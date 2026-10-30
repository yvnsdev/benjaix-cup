-- Ejecutar una vez en Supabase > SQL Editor, sobre un proyecto vacío.
begin;
create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, role text not null check(role in ('admin','captain')) default 'captain');
create table public.teams (id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 1 and 60), short_name text not null check(length(short_name) between 1 and 3), color text not null default '#699b44' check(color ~ '^#[0-9A-Fa-f]{6}$'), captain_id uuid references public.profiles(id) on delete set null);
create table public.players (id uuid primary key default gen_random_uuid(), team_id uuid not null references public.teams(id) on delete cascade, name text not null check(length(name) between 1 and 80), number integer not null check(number between 1 and 99), position text not null check(position in ('POR','DEF','MED','DEL')), unique(team_id,number));
create table public.matches (id uuid primary key default gen_random_uuid(), home_id uuid not null references public.teams(id), away_id uuid not null references public.teams(id), home_score integer not null default 0 check(home_score between 0 and 99), away_score integer not null default 0 check(away_score between 0 and 99), status text not null default 'scheduled' check(status in ('scheduled','live','finished')), minute integer not null default 0 check(minute between 0 and 150), round integer not null check(round between 1 and 100), kickoff timestamptz not null, venue text not null check(length(venue) between 1 and 100), check(home_id<>away_id));
create table public.events (id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade, team_id uuid not null references public.teams(id), player_id uuid not null references public.players(id), minute integer not null check(minute between 0 and 150), type text not null check(type in ('goal','yellow','red')));
create table public.lineups (id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade, team_id uuid not null references public.teams(id), formation text not null check(formation in ('4-3-3','4-4-2','3-5-2','4-2-3-1')), player_ids uuid[] not null default '{}', unique(match_id,team_id));
create index on public.teams(captain_id);
create index on public.players(team_id);
create index on public.events(match_id);
create index on public.matches(kickoff);
create function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin'); $$;
create function public.owns_team(target uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.teams where id=target and captain_id=auth.uid()); $$;
create function public.protect_team() returns trigger language plpgsql set search_path=public as $$ begin
 if current_user in ('anon','authenticated') and not public.is_admin() and (new.captain_id is distinct from old.captain_id or new.id<>old.id) then raise exception 'Solo el administrador puede asignar capitanes'; end if;
 return new; end $$;
create trigger protect_team before update on public.teams for each row execute function public.protect_team();
create function public.validate_lineup() returns trigger language plpgsql set search_path=public as $$ declare m public.matches; n integer; begin
 select * into m from public.matches where id=new.match_id for update;
 if m.id is null or new.team_id not in (m.home_id,m.away_id) then raise exception 'El equipo no participa en este partido'; end if;
 if m.status<>'scheduled' then raise exception 'La alineación está bloqueada: el partido ya comenzó'; end if;
 select count(distinct p.id) into n from public.players p where p.id=any(new.player_ids) and p.team_id=new.team_id;
 if n<>cardinality(new.player_ids) or n<1 or n>11 then raise exception 'Selecciona entre 1 y 11 jugadores distintos del equipo'; end if;
 return new; end $$;
create trigger validate_lineup before insert or update on public.lineups for each row execute function public.validate_lineup();
create function public.validate_event() returns trigger language plpgsql set search_path=public as $$ begin
 if not exists(select 1 from public.matches where id=new.match_id and new.team_id in (home_id,away_id)) or not exists(select 1 from public.players where id=new.player_id and team_id=new.team_id) then raise exception 'Jugador o equipo no corresponde al partido'; end if;
 return new; end $$;
create trigger validate_event before insert or update on public.events for each row execute function public.validate_event();
create function public.protect_player() returns trigger language plpgsql set search_path=public as $$ begin
 if exists(select 1 from public.lineups where old.id=any(player_ids)) then raise exception 'Retira al jugador de las alineaciones antes de eliminarlo o cambiar su equipo'; end if;
 if tg_op='DELETE' then return old; end if; return new; end $$;
create trigger protect_player_delete before delete on public.players for each row execute function public.protect_player();
create trigger protect_player_move before update of team_id on public.players for each row when(old.team_id is distinct from new.team_id) execute function public.protect_player();
alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.players enable row level security;
alter table public.matches enable row level security;
alter table public.events enable row level security;
alter table public.lineups enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy profile_admin on public.profiles for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy team_read on public.teams for select to anon,authenticated using(true);
create policy team_admin on public.teams for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy team_captain on public.teams for update to authenticated using(captain_id=auth.uid()) with check(captain_id=auth.uid());
create policy player_read on public.players for select to anon,authenticated using(true);
create policy player_write on public.players for all to authenticated using(public.is_admin() or public.owns_team(team_id)) with check(public.is_admin() or public.owns_team(team_id));
create policy match_read on public.matches for select to anon,authenticated using(true);
create policy match_write on public.matches for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy event_read on public.events for select to anon,authenticated using(true);
create policy event_write on public.events for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy lineup_read on public.lineups for select to anon,authenticated using(true);
create policy lineup_write on public.lineups for all to authenticated using((public.is_admin() or public.owns_team(team_id)) and exists(select 1 from public.matches where id=match_id and status='scheduled')) with check((public.is_admin() or public.owns_team(team_id)) and exists(select 1 from public.matches where id=match_id and status='scheduled'));
grant select on public.teams,public.players,public.matches,public.events,public.lineups to anon;
grant select,insert,update,delete on public.profiles,public.teams,public.players,public.matches,public.events,public.lineups to authenticated;
revoke all on function public.is_admin(),public.owns_team(uuid) from public;
grant execute on function public.is_admin(),public.owns_team(uuid) to authenticated;
do $$ declare t text; begin foreach t in array array['teams','players','matches','events','lineups'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then execute format('alter publication supabase_realtime add table public.%I',t); end if;
end loop; end $$;
commit;
