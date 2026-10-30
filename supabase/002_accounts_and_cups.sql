-- Ejecutar después de schema.sql. Conserva equipos, jugadores y resultados.
begin;
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('admin','captain','member'));
alter table public.profiles alter column role set default 'member';
create function public.handle_signup() returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into public.profiles(id,role) values(new.id,'member') on conflict(id) do nothing;
 return new;
end $$;
create trigger benjaix_signup after insert on auth.users for each row execute function public.handle_signup();
insert into public.profiles(id,role) select id,'member' from auth.users on conflict(id) do nothing;

create table public.team_members (
 id uuid primary key default gen_random_uuid(),
 team_id uuid not null references public.teams(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 player_id uuid not null unique references public.players(id) on delete cascade,
 unique(team_id,user_id)
);
alter table public.team_members enable row level security;
create policy member_read on public.team_members for select to authenticated using(user_id=auth.uid() or public.is_admin() or public.owns_team(team_id));
grant select on public.team_members to authenticated;
revoke insert,update,delete on public.team_members from anon,authenticated;

create function public.create_my_team(team_name text, abbreviation text, team_color text) returns uuid language plpgsql security definer set search_path=public as $$ declare tid uuid; begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Confirma tu correo antes de crear un equipo'; end if;
 -- El perfil es el cerrojo para solicitudes simultáneas de la misma cuenta.
 perform 1 from public.profiles where id=auth.uid() for update;
 if exists(select 1 from public.teams where captain_id=auth.uid()) then raise exception 'Ya gestionas un equipo propio'; end if;
 insert into public.teams(name,short_name,color,captain_id) values(trim(team_name),upper(trim(abbreviation)),team_color,auth.uid()) returning id into tid;
 return tid;
end $$;

create function public.add_team_player(target_team uuid, player_name text, shirt_number integer, player_position text) returns uuid language plpgsql security definer set search_path=public as $$ declare pid uuid; begin
 if not (public.is_admin() or public.owns_team(target_team)) then raise exception 'No tienes permisos sobre este equipo'; end if;
 insert into public.players(team_id,name,number,position) values(target_team,trim(player_name),shirt_number,player_position) returning id into pid;
 return pid;
end $$;
-- Un capitán nunca puede convertir a un jugador en gestor mediante la API.
revoke all on function public.create_my_team(text,text,text),public.add_team_player(uuid,text,integer,text) from public;
grant execute on function public.create_my_team(text,text,text),public.add_team_player(uuid,text,integer,text) to authenticated;

create table public.competitions(id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 80), format text not null check(format in ('league','cup')), size integer check(size in (4,8,16)), created_at timestamptz not null default now(), check((format='league' and size is null) or (format='cup' and size is not null)));
insert into public.competitions(name,format) values('Liga Benjaix 2026','league');
alter table public.matches add column competition_id uuid references public.competitions(id);
update public.matches set competition_id=(select id from public.competitions where format='league' limit 1);
alter table public.matches alter column competition_id set not null;
alter table public.matches alter column home_id drop not null;
alter table public.matches alter column away_id drop not null;
alter table public.matches add column slot integer check(slot between 1 and 8);
alter table public.matches add column penalty_home integer check(penalty_home between 0 and 99);
alter table public.matches add column penalty_away integer check(penalty_away between 0 and 99);
create unique index cup_slots on public.matches(competition_id,round,slot) where slot is not null;
alter table public.competitions enable row level security;
create policy competition_read on public.competitions for select to anon,authenticated using(true);
grant select on public.competitions to anon,authenticated;
revoke insert,update,delete on public.competitions from anon,authenticated;

create function public.create_cup(cup_name text, team_ids uuid[], first_kickoff timestamptz, cup_venue text) returns uuid language plpgsql security definer set search_path=public as $$ declare cid uuid; n integer:=cardinality(team_ids); r integer:=1; slots integer; i integer; begin
 if not public.is_admin() then raise exception 'Solo la administración puede crear copas'; end if;
 if n is null or n not in (4,8,16) or (select count(distinct id) from public.teams where id=any(team_ids))<>n then raise exception 'Selecciona 4, 8 o 16 equipos distintos'; end if;
 insert into public.competitions(name,format,size) values(trim(cup_name),'cup',n) returning id into cid;
 slots:=n/2;
 while slots>=1 loop
  for i in 1..slots loop
   insert into public.matches(competition_id,home_id,away_id,round,slot,kickoff,venue)
   values(cid,case when r=1 then team_ids[2*i-1] end,case when r=1 then team_ids[2*i] end,r,i,first_kickoff+make_interval(days=7*(r-1)),cup_venue);
  end loop;
  slots:=slots/2; r:=r+1;
 end loop;
 return cid;
end $$;
revoke all on function public.create_cup(text,uuid[],timestamptz,text) from public;
grant execute on function public.create_cup(text,uuid[],timestamptz,text) to authenticated;

create function public.match_winner(m public.matches) returns uuid language sql immutable as $$
 select case when m.status<>'finished' then null when m.home_score>m.away_score then m.home_id when m.away_score>m.home_score then m.away_id when m.penalty_home>m.penalty_away then m.home_id when m.penalty_away>m.penalty_home then m.away_id end;
$$;
create function public.validate_competition_match() returns trigger language plpgsql set search_path=public as $$ declare c public.competitions; begin
 select * into c from public.competitions where id=new.competition_id;
 if tg_op='UPDATE' and (new.competition_id<>old.competition_id or new.round<>old.round or new.slot is distinct from old.slot) then raise exception 'No se puede mover un partido entre fases'; end if;
 if c.format='league' and (new.home_id is null or new.away_id is null or new.slot is not null) then raise exception 'Partido de liga no válido'; end if;
 if (new.home_id is null or new.away_id is null) and new.status<>'scheduled' then raise exception 'Espera a que se definan ambos equipos'; end if;
 if c.format='cup' and new.status='finished' and public.match_winner(new) is null then raise exception 'Un empate de copa necesita un ganador por penales'; end if;
 if c.format='cup' and (new.slot is null or new.round>log(2,c.size)::integer or new.slot>c.size/power(2,new.round)) then raise exception 'Fase de copa no válida'; end if;
 return new;
end $$;
create trigger validate_competition_match before insert or update on public.matches for each row execute function public.validate_competition_match();
-- SECURITY DEFINER para que el avance sea atómico y no dependa de la interfaz.
create function public.advance_cup_winner() returns trigger language plpgsql security definer set search_path=public as $$ declare w uuid; next_match public.matches; previous uuid; begin
 if not exists(select 1 from public.competitions where id=new.competition_id and format='cup') then return new; end if;
 w:=public.match_winner(new); previous:=public.match_winner(old);
 if w is not distinct from previous then return new; end if;
 select * into next_match from public.matches where competition_id=new.competition_id and round=new.round+1 and slot=(new.slot+1)/2 for update;
 if next_match.id is null then return new; end if;
 if next_match.status<>'scheduled' then raise exception 'Primero reabre la siguiente fase: ya comenzó o terminó'; end if;
 if exists(select 1 from public.events where match_id=next_match.id) then raise exception 'Retira los eventos de la siguiente fase antes de cambiar el ganador'; end if;
 delete from public.lineups where match_id=next_match.id;
 update public.matches set home_id=case when new.slot%2=1 then w else home_id end,away_id=case when new.slot%2=0 then w else away_id end,home_score=0,away_score=0,minute=0,penalty_home=null,penalty_away=null where id=next_match.id;
 return new;
end $$;
create trigger advance_cup_winner after update on public.matches for each row execute function public.advance_cup_winner();
-- Los partidos de copa se crean exclusivamente mediante create_cup.
drop policy match_write on public.matches;
create policy match_insert on public.matches for insert to authenticated with check(public.is_admin() and exists(select 1 from public.competitions where id=competition_id and format='league'));
create policy match_update on public.matches for update to authenticated using(public.is_admin()) with check(public.is_admin());
create function public.protect_cup_structure() returns trigger language plpgsql set search_path=public as $$ begin
 if current_user='authenticated' and exists(select 1 from public.competitions where id=old.competition_id and format='cup') and (new.home_id is distinct from old.home_id or new.away_id is distinct from old.away_id) then raise exception 'Los participantes de copa se definen por el cuadro'; end if;
 return new;
end $$;
create trigger protect_cup_structure before update on public.matches for each row execute function public.protect_cup_structure();
-- El bloqueo de la fila del partido no debe requerir permiso de editar marcadores.
create or replace function public.validate_lineup() returns trigger language plpgsql security definer set search_path=public as $$ declare m public.matches; n integer; begin
 select * into m from public.matches where id=new.match_id for update;
 if m.id is null or not (new.team_id is not distinct from m.home_id or new.team_id is not distinct from m.away_id) then raise exception 'El equipo no participa en este partido'; end if;
 if m.status<>'scheduled' then raise exception 'La alineación está bloqueada: el partido ya comenzó'; end if;
 select count(distinct p.id) into n from public.players p where p.id=any(new.player_ids) and p.team_id=new.team_id;
 if n<>cardinality(new.player_ids) or n<1 or n>11 then raise exception 'Selecciona entre 1 y 11 jugadores distintos del equipo'; end if;
 return new;
end $$;
revoke all on function public.handle_signup(),public.advance_cup_winner() from public;
alter publication supabase_realtime add table public.competitions,public.team_members;
commit;
