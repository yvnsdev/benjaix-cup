-- Ejecutar una vez después de schema.sql y 002_accounts_and_cups.sql.
begin;
alter table public.events drop constraint events_type_check;
alter table public.events add constraint events_type_check check(type in ('goal','assist','yellow','red'));

create table public.expert_polls (
 match_id uuid primary key references public.matches(id) on delete cascade,
 status text not null check(status in ('open','closed')),
 opened_at timestamptz not null default now(),
 closed_at timestamptz
);
create table public.expert_candidates (
 match_id uuid not null references public.expert_polls(match_id) on delete cascade,
 player_id uuid not null references public.players(id),
 primary key(match_id,player_id)
);
create table public.expert_votes (
 match_id uuid not null,
 voter_id uuid not null references auth.users(id) on delete cascade,
 player_id uuid not null,
 updated_at timestamptz not null default now(),
 primary key(match_id,voter_id),
 foreign key(match_id,player_id) references public.expert_candidates(match_id,player_id)
);
create table public.expert_totals (
 match_id uuid not null,
 player_id uuid not null,
 votes integer not null default 0 check(votes>=0),
 primary key(match_id,player_id),
 foreign key(match_id,player_id) references public.expert_candidates(match_id,player_id) on delete cascade
);
alter table public.expert_polls enable row level security;
alter table public.expert_candidates enable row level security;
alter table public.expert_votes enable row level security;
alter table public.expert_totals enable row level security;
create policy polls_read on public.expert_polls for select to anon,authenticated using(true);
create policy candidates_read on public.expert_candidates for select to anon,authenticated using(true);
create policy totals_read on public.expert_totals for select to anon,authenticated using(true);
create policy own_vote_read on public.expert_votes for select to authenticated using(voter_id=auth.uid());
revoke all on public.expert_polls,public.expert_candidates,public.expert_votes,public.expert_totals from anon,authenticated;
grant select on public.expert_polls,public.expert_candidates,public.expert_totals to anon,authenticated;
grant select on public.expert_votes to authenticated;

create function public.manage_expert_poll(target_match uuid, action text, candidate_ids uuid[] default null)
returns void language plpgsql security definer set search_path=public as $$
declare m public.matches; existing public.expert_polls; n integer;
begin
 if not public.is_admin() then raise exception 'Solo la administración puede gestionar la votación'; end if;
 select * into m from public.matches where id=target_match for update;
 if m.id is null or m.status<>'finished' then raise exception 'La votación requiere un partido finalizado'; end if;
 if action not in ('open','close') or action is null then raise exception 'Acción no válida'; end if;
 select * into existing from public.expert_polls where match_id=target_match for update;
 if existing.match_id is not null then
  -- Candidatos congelados desde la apertura; se conservan los votos al reabrir.
  update public.expert_polls set status=case when action='open' then 'open' else 'closed' end,closed_at=case when action='close' then now() else null end where match_id=target_match;
  return;
 end if;
 if action='close' then raise exception 'Primero abre la votación'; end if;
 n:=cardinality(candidate_ids);
 if n is null or n<2 or n>32 or (select count(distinct p.id) from public.players p where p.id=any(candidate_ids) and p.team_id in (m.home_id,m.away_id))<>n then raise exception 'Elige entre 2 y 32 candidatos distintos de los equipos del partido'; end if;
 insert into public.expert_polls(match_id,status) values(target_match,'open');
 insert into public.expert_candidates(match_id,player_id) select target_match,unnest(candidate_ids);
 insert into public.expert_totals(match_id,player_id,votes) select target_match,unnest(candidate_ids),0;
end $$;

create function public.cast_expert_vote(target_match uuid, chosen_player uuid)
returns void language plpgsql security definer set search_path=public as $$
declare m public.matches; poll public.expert_polls;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Inicia sesión con una cuenta de correo confirmado'; end if;
 -- Orden de bloqueo consistente con manage_expert_poll; cierre y voto son atómicos.
 select * into m from public.matches where id=target_match for update;
 select * into poll from public.expert_polls where match_id=target_match for update;
 if m.id is null or m.status<>'finished' or poll.match_id is null or poll.status<>'open' then raise exception 'La votación no está abierta'; end if;
 if not exists(select 1 from public.expert_candidates c join public.players p on p.id=c.player_id where c.match_id=target_match and c.player_id=chosen_player and p.team_id in (m.home_id,m.away_id)) then raise exception 'El jugador no es candidato de este partido'; end if;
 insert into public.expert_votes(match_id,voter_id,player_id) values(target_match,auth.uid(),chosen_player)
 on conflict(match_id,voter_id) do update set player_id=excluded.player_id,updated_at=now();
end $$;

create function public.update_expert_totals() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='UPDATE' and old.player_id=new.player_id then return new; end if;
 if tg_op in ('UPDATE','DELETE') then update public.expert_totals set votes=votes-1 where match_id=old.match_id and player_id=old.player_id; end if;
 if tg_op in ('INSERT','UPDATE') then update public.expert_totals set votes=votes+1 where match_id=new.match_id and player_id=new.player_id; end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
create trigger expert_vote_totals after insert or update or delete on public.expert_votes for each row execute function public.update_expert_totals();
-- Mantener la pertenencia deportiva de los candidatos ya publicados.
create function public.protect_expert_candidate_team() returns trigger language plpgsql set search_path=public as $$
begin
 if new.team_id is distinct from old.team_id and exists(select 1 from public.expert_candidates where player_id=old.id) then raise exception 'No se puede cambiar de equipo a un candidato con votaciones publicadas'; end if;
 return new;
end $$;
create trigger protect_expert_candidate_team before update of team_id on public.players for each row execute function public.protect_expert_candidate_team();
revoke all on function public.manage_expert_poll(uuid,text,uuid[]),public.cast_expert_vote(uuid,uuid),public.update_expert_totals() from public;
grant execute on function public.manage_expert_poll(uuid,text,uuid[]),public.cast_expert_vote(uuid,uuid) to authenticated;
-- Solo se publican conteos: jamás identidades ni elecciones de otros votantes.
alter publication supabase_realtime add table public.expert_polls,public.expert_candidates,public.expert_totals;
commit;
