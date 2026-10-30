-- Los jugadores normales no necesitan una cuenta. Solo el capitán administra sus perfiles.
begin;
drop function if exists public.add_team_player(uuid,text,text,integer,text);
drop function if exists public.add_team_player(uuid,text,integer,text);

create function public.add_team_player(
 target_team uuid,
 player_name text,
 shirt_number integer,
 player_position text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare pid uuid;
begin
 if not (public.is_admin() or public.owns_team(target_team)) then
  raise exception 'No tienes permisos sobre este equipo';
 end if;
 insert into public.players(team_id,name,number,position)
 values(target_team,trim(player_name),shirt_number,player_position)
 returning id into pid;
 return pid;
end
$$;

revoke all on function public.add_team_player(uuid,text,integer,text) from public;
grant execute on function public.add_team_player(uuid,text,integer,text) to authenticated;
commit;
