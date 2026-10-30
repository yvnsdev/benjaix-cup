-- Ejecutar una vez, después de 003_stats_and_expert.sql.
begin;
-- Los resultados históricos conservan sus candidatos; las nuevas votaciones son automáticas.
alter table public.expert_polls add column automatic boolean not null default false;
alter table public.expert_polls alter column automatic set default true;

create function public.expert_eligible_players(target_match uuid) returns table(player_id uuid)
language sql stable set search_path=public as $$
 select distinct p.id from public.players p join public.matches m on m.id=target_match
 where p.team_id in (m.home_id,m.away_id) and (
  exists(select 1 from public.lineups l where l.match_id=m.id and l.team_id=p.team_id and p.id=any(l.player_ids))
  or exists(select 1 from public.events e where e.match_id=m.id and e.player_id=p.id and e.team_id=p.team_id)
 );
$$;

create function public.sync_live_expert_poll(target_match uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m public.matches;
begin
 select * into m from public.matches where id=target_match for update;
 if m.id is null then return; end if;
 if m.status='live' then
  insert into public.expert_polls(match_id,status,automatic) values(m.id,'open',true)
  on conflict(match_id) do update set status='open',automatic=true,closed_at=null;
  insert into public.expert_candidates(match_id,player_id)
   select m.id,p.player_id from public.expert_eligible_players(m.id) p where true on conflict do nothing;
  insert into public.expert_totals(match_id,player_id,votes)
   select c.match_id,c.player_id,0 from public.expert_candidates c where c.match_id=m.id on conflict do nothing;
 elsif m.status='finished' then
  update public.expert_polls set status='closed',closed_at=coalesce(closed_at,now()) where match_id=m.id;
 else
  update public.expert_polls set status='closed',closed_at=null where match_id=m.id;
 end if;
end $$;

create function public.expert_match_lifecycle() returns trigger language plpgsql security definer set search_path=public as $$
begin
 perform public.sync_live_expert_poll(new.id);
 return new;
end $$;
create trigger expert_match_lifecycle after insert or update of status on public.matches for each row execute function public.expert_match_lifecycle();

create function public.expert_participants_changed() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then
  if exists(select 1 from public.matches where id=old.match_id and status='live') then perform public.sync_live_expert_poll(old.match_id); end if;
  return old;
 end if;
 if exists(select 1 from public.matches where id=new.match_id and status='live') then perform public.sync_live_expert_poll(new.match_id); end if;
 if tg_op='UPDATE' and old.match_id is distinct from new.match_id then
  if exists(select 1 from public.matches where id=old.match_id and status='live') then perform public.sync_live_expert_poll(old.match_id); end if;
 end if;
 return new;
end $$;
create trigger expert_lineup_changes after insert or update or delete on public.lineups for each row execute function public.expert_participants_changed();
create trigger expert_event_changes after insert or update or delete on public.events for each row execute function public.expert_participants_changed();

create or replace function public.cast_expert_vote(target_match uuid, chosen_player uuid)
returns void language plpgsql security definer set search_path=public as $$
declare m public.matches; poll public.expert_polls;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Inicia sesión con una cuenta de correo confirmado'; end if;
 select * into m from public.matches where id=target_match for update;
 select * into poll from public.expert_polls where match_id=target_match for update;
 if m.id is null or m.status<>'live' or poll.match_id is null or poll.status<>'open' then raise exception 'Solo se puede votar mientras el partido está en vivo'; end if;
 if not exists(select 1 from public.expert_eligible_players(target_match) where player_id=chosen_player)
 or not exists(select 1 from public.expert_candidates where match_id=target_match and player_id=chosen_player) then raise exception 'El jugador no participa en este partido'; end if;
 insert into public.expert_votes(match_id,voter_id,player_id) values(target_match,auth.uid(),chosen_player)
 on conflict(match_id,voter_id) do update set player_id=excluded.player_id,updated_at=now();
end $$;

-- Retirar el flujo manual anterior: ni el cliente ni un capitán eligen candidatos.
drop function public.manage_expert_poll(uuid,text,uuid[]);
revoke all on function public.sync_live_expert_poll(uuid),public.expert_match_lifecycle(),public.expert_participants_changed() from public;
revoke all on function public.cast_expert_vote(uuid,uuid) from public;
grant execute on function public.cast_expert_vote(uuid,uuid) to authenticated;
grant execute on function public.expert_eligible_players(uuid) to anon,authenticated;

-- Mantener votos históricos y poner al día los estados existentes.
do $$ declare m record; begin
 for m in select id from public.matches loop perform public.sync_live_expert_poll(m.id); end loop;
end $$;
commit;
