-- Apply after 012. Admin-only, atomic cup management.
begin;
create or replace function public.edit_cup_pairings(cup_id uuid, team_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare c public.competitions; cup_match public.matches; participants uuid[];
begin
 if not public.is_admin() then raise exception 'Solo la administración puede editar cruces'; end if;
 select * into c from public.competitions where id=cup_id and format='cup' for update;
 if c.id is null then raise exception 'Copa no encontrada'; end if;
 perform id from public.matches where competition_id=cup_id order by id for update;
 if exists(select 1 from public.matches where competition_id=cup_id and
   (status<>'scheduled' or home_score<>0 or away_score<>0 or minute<>0 or penalty_home is not null or penalty_away is not null))
 or exists(select 1 from public.events e join public.matches event_match on event_match.id=e.match_id where event_match.competition_id=cup_id)
 or exists(select 1 from public.expert_polls p join public.matches poll_match on poll_match.id=p.match_id where poll_match.competition_id=cup_id)
 then raise exception 'La copa ya tiene actividad registrada'; end if;
 select array_agg(pairing.team_id) into participants from public.matches first_round
 cross join lateral (values(first_round.home_id),(first_round.away_id)) pairing(team_id)
 where first_round.competition_id=cup_id and first_round.round=1;
 if cardinality(team_ids) is distinct from c.size or cardinality(participants) is distinct from c.size
 or array_position(team_ids,null) is not null
 or (select count(distinct selected.team_id) from unnest(team_ids) selected(team_id))<>c.size
 or not (team_ids @> participants and team_ids <@ participants)
 then raise exception 'Selecciona todos los participantes una sola vez'; end if;
 for cup_match in select * from public.matches where competition_id=cup_id and round=1 order by slot loop
  if cup_match.home_id is distinct from team_ids[2*cup_match.slot-1] or cup_match.away_id is distinct from team_ids[2*cup_match.slot] then
   delete from public.lineups where match_id=cup_match.id;
   update public.matches target set home_id=team_ids[2*cup_match.slot-1],away_id=team_ids[2*cup_match.slot] where target.id=cup_match.id;
  end if;
 end loop;
end $$;

create or replace function public.delete_cup(cup_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Solo la administración puede borrar copas'; end if;
 perform id from public.competitions where id=cup_id and format='cup' for update;
 if not found then raise exception 'Copa no encontrada'; end if;
 perform id from public.matches where competition_id=cup_id order by id for update;
 -- Votes deliberately have no cascading candidate FK: remove them first.
 delete from public.expert_votes where match_id in (select id from public.matches where competition_id=cup_id);
 -- Match foreign keys cascade to events, lineups and polls, then candidates/totals.
 delete from public.matches where competition_id=cup_id;
 delete from public.competitions where id=cup_id;
end $$;
revoke all on function public.edit_cup_pairings(uuid,uuid[]) from public,anon;
revoke all on function public.delete_cup(uuid) from public,anon;
grant execute on function public.edit_cup_pairings(uuid,uuid[]) to authenticated;
grant execute on function public.delete_cup(uuid) to authenticated;
commit;
