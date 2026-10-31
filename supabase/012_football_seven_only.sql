-- Run after 010/011. All new or edited lineups must be football 7.
-- NOT VALID preserves historical rows; it still enforces these checks on writes.
-- No existing players are removed or automatically chosen as starters.
begin;
alter table public.lineups drop constraint if exists lineups_formation_check;
alter table public.lineups add constraint lineups_formation_check
 check(formation in ('3-1-2','3-2-1','3-1-1-1','2-3-1','2-2-2','2-1-2-1')) not valid;
alter table public.lineups drop constraint if exists lineups_seven_players;
alter table public.lineups add constraint lineups_seven_players
 check(cardinality(player_ids)=7) not valid;

create or replace function public.validate_lineup() returns trigger
language plpgsql security definer set search_path=public as $$
declare m public.matches; n integer;
begin
 select * into m from public.matches where id=new.match_id for update;
 if m.id is null or not (new.team_id is not distinct from m.home_id or new.team_id is not distinct from m.away_id) then
  raise exception 'El equipo no participa en este partido';
 end if;
 if m.status<>'scheduled' then raise exception 'La alineación está bloqueada: el partido ya comenzó'; end if;
 if new.formation not in ('3-1-2','3-2-1','3-1-1-1','2-3-1','2-2-2','2-1-2-1') then
  raise exception 'Todos los partidos son de fútbol 7. Elige una formación válida';
 end if;
 select count(distinct p.id) into n from public.players p where p.id=any(new.player_ids) and p.team_id=new.team_id;
 if n<>7 or cardinality(new.player_ids)<>7 then
  raise exception 'Selecciona exactamente 7 jugadores distintos del equipo';
 end if;
 if new.slot_player_ids is null or cardinality(new.slot_player_ids)<>7
    or array_position(new.slot_player_ids,null) is not null
    or new.slot_player_ids is distinct from new.player_ids then
  raise exception 'Asigna un jugador distinto a cada una de las siete posiciones';
 end if;
 return new;
end $$;
commit;
