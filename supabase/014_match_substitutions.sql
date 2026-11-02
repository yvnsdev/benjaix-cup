-- Apply after 013. Records football-seven substitutions from published lineups.
begin;

alter table public.events add column if not exists related_player_id uuid references public.players(id);
alter table public.events add column if not exists created_at timestamptz not null default now();
alter table public.events drop constraint if exists events_type_check;
alter table public.events add constraint events_type_check
 check(type in ('goal','assist','yellow','red','substitution'));
alter table public.events drop constraint if exists events_substitution_players_check;
alter table public.events add constraint events_substitution_players_check check(
 (type='substitution' and related_player_id is not null and related_player_id<>player_id)
 or (type<>'substitution' and related_player_id is null)
);

create or replace function public.expert_eligible_players(target_match uuid)
returns table(player_id uuid)
language sql stable set search_path=public as $$
 select distinct player_row.id
 from public.players player_row
 join public.matches match_row on match_row.id=target_match
 where player_row.team_id in (match_row.home_id,match_row.away_id) and (
  exists(select 1 from public.lineups lineup_row where lineup_row.match_id=match_row.id and lineup_row.team_id=player_row.team_id and player_row.id=any(lineup_row.player_ids))
  or exists(select 1 from public.events event_row where event_row.match_id=match_row.id and event_row.team_id=player_row.team_id and (event_row.player_id=player_row.id or event_row.related_player_id=player_row.id))
 );
$$;

create or replace function public.register_substitution(
 target_match uuid,
 target_team uuid,
 outgoing_player uuid,
 incoming_player uuid,
 change_minute integer
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
 match_row public.matches;
 lineup_row public.lineups;
 change_row record;
 current_players uuid[];
 outgoing_position integer;
 inserted_id uuid;
 last_change integer;
begin
 if not public.is_admin() then raise exception 'Solo la administración puede registrar cambios'; end if;
 if change_minute is null or change_minute<0 or change_minute>150 then raise exception 'Minuto no válido'; end if;
 select * into match_row from public.matches where id=target_match for update;
 if match_row.id is null then raise exception 'Partido no encontrado'; end if;
 if match_row.status='scheduled' then raise exception 'El partido todavía no ha comenzado'; end if;
 if target_team is distinct from match_row.home_id and target_team is distinct from match_row.away_id then raise exception 'El equipo no participa en este partido'; end if;
 select * into lineup_row from public.lineups where match_id=target_match and team_id=target_team for update;
 if lineup_row.id is null or cardinality(lineup_row.player_ids)<>7 then raise exception 'Publica una alineación válida antes de registrar cambios'; end if;
 if outgoing_player=incoming_player
 or not exists(select 1 from public.players where id=outgoing_player and team_id=target_team)
 or not exists(select 1 from public.players where id=incoming_player and team_id=target_team)
 then raise exception 'Los jugadores del cambio deben pertenecer al equipo'; end if;

 perform event_row.id from public.events event_row where event_row.match_id=target_match for update;
 select max(event_row.minute) into last_change from public.events event_row
 where event_row.match_id=target_match and event_row.team_id=target_team and event_row.type='substitution';
 if last_change is not null and change_minute<last_change then raise exception 'Registra los cambios en orden cronológico'; end if;

 current_players:=lineup_row.player_ids;
 for change_row in
  select event_row.player_id,event_row.related_player_id
  from public.events event_row
  where event_row.match_id=target_match and event_row.team_id=target_team
    and event_row.type='substitution' and event_row.minute<=change_minute
  order by event_row.minute,event_row.created_at,event_row.id
 loop
  outgoing_position:=array_position(current_players,change_row.player_id);
  if outgoing_position is not null and array_position(current_players,change_row.related_player_id) is null then
   current_players[outgoing_position]:=change_row.related_player_id;
  end if;
 end loop;
 outgoing_position:=array_position(current_players,outgoing_player);
 if outgoing_position is null then raise exception 'El jugador que sale no está en cancha'; end if;
 if array_position(current_players,incoming_player) is not null then raise exception 'El jugador que entra ya está en cancha'; end if;

 insert into public.events(match_id,team_id,player_id,related_player_id,minute,type)
 values(target_match,target_team,outgoing_player,incoming_player,change_minute,'substitution')
 returning id into inserted_id;
 return inserted_id;
end $$;

create or replace function public.protect_substitution_history()
returns trigger language plpgsql set search_path=public as $$
begin
 if old.type='substitution'
 and exists(select 1 from public.matches where id=old.match_id)
 and exists(
  select 1 from public.events later
  where later.match_id=old.match_id and later.team_id=old.team_id and later.type='substitution'
   and (later.minute>old.minute or (later.minute=old.minute and (later.created_at>old.created_at or (later.created_at=old.created_at and later.id>old.id))))
 ) then raise exception 'Elimina primero los cambios posteriores de este equipo'; end if;
 return old;
end $$;
drop trigger if exists protect_substitution_history on public.events;
create trigger protect_substitution_history before delete on public.events
for each row execute function public.protect_substitution_history();

revoke all on function public.register_substitution(uuid,uuid,uuid,uuid,integer) from public,anon;
grant execute on function public.register_substitution(uuid,uuid,uuid,uuid,integer) to authenticated;
revoke all on function public.protect_substitution_history() from public;
commit;
