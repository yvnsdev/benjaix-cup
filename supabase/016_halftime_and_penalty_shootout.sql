-- Apply after 015. Adds halftime and a public five-kick penalty shootout.
begin;

alter table public.matches drop constraint if exists matches_period_check;
alter table public.matches add constraint matches_period_check
 check(period in ('first_half','halftime','second_half','extra_first','extra_second','penalties'));

create table if not exists public.penalty_kicks (
 match_id uuid not null references public.matches(id) on delete cascade,
 team_id uuid not null references public.teams(id),
 kick_number integer not null check(kick_number between 1 and 5),
 outcome text not null default 'pending' check(outcome in ('pending','goal','miss')),
 updated_at timestamptz not null default now(),
 primary key(match_id,team_id,kick_number)
);
alter table public.penalty_kicks enable row level security;
drop policy if exists penalty_kicks_read on public.penalty_kicks;
create policy penalty_kicks_read on public.penalty_kicks for select to anon,authenticated using(true);
revoke all on public.penalty_kicks from anon,authenticated;
grant select on public.penalty_kicks to anon,authenticated;

-- Preserve existing shootout totals as successful kicks when possible.
insert into public.penalty_kicks(match_id,team_id,kick_number,outcome)
select match_row.id,match_row.home_id,kick_number,'goal'
from public.matches match_row
cross join lateral generate_series(1,least(coalesce(match_row.penalty_home,0),5)) kick_number
on conflict do nothing;
insert into public.penalty_kicks(match_id,team_id,kick_number,outcome)
select match_row.id,match_row.away_id,kick_number,'goal'
from public.matches match_row
cross join lateral generate_series(1,least(coalesce(match_row.penalty_away,0),5)) kick_number
on conflict do nothing;

create or replace function public.set_penalty_kick(
 target_match uuid,
 target_team uuid,
 target_kick integer,
 target_outcome text
) returns void
language plpgsql security definer set search_path=public as $$
declare match_row public.matches;
begin
 if not public.is_admin() then raise exception 'Solo la administración puede registrar penales'; end if;
 select * into match_row from public.matches where id=target_match for update;
 if match_row.id is null then raise exception 'Partido no encontrado'; end if;
 if match_row.period<>'penalties' then raise exception 'Activa la fase PEN antes de registrar la tanda'; end if;
 if target_team is distinct from match_row.home_id and target_team is distinct from match_row.away_id then raise exception 'El equipo no participa en este partido'; end if;
 if target_kick not between 1 and 5 or target_outcome not in ('pending','goal','miss') then raise exception 'Penal no válido'; end if;

 insert into public.penalty_kicks(match_id,team_id,kick_number,outcome,updated_at)
 values(target_match,target_team,target_kick,target_outcome,now())
 on conflict(match_id,team_id,kick_number) do update
 set outcome=excluded.outcome,updated_at=excluded.updated_at;

 update public.matches current_match set
  penalty_home=(select count(*) from public.penalty_kicks kick where kick.match_id=target_match and kick.team_id=current_match.home_id and kick.outcome='goal'),
  penalty_away=(select count(*) from public.penalty_kicks kick where kick.match_id=target_match and kick.team_id=current_match.away_id and kick.outcome='goal')
 where current_match.id=target_match;
end $$;
revoke all on function public.set_penalty_kick(uuid,uuid,integer,text) from public,anon;
grant execute on function public.set_penalty_kick(uuid,uuid,integer,text) to authenticated;

do $$ begin
 alter publication supabase_realtime add table public.penalty_kicks;
exception when duplicate_object then null;
end $$;
commit;
