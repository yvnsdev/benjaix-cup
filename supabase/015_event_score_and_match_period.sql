-- Apply after 014. The score comes from goal events; match progress uses named periods.
begin;

alter table public.matches add column if not exists period text not null default 'first_half';
alter table public.matches drop constraint if exists matches_period_check;
alter table public.matches add constraint matches_period_check
 check(period in ('first_half','second_half','extra_first','extra_second','penalties'));
alter table public.matches add column if not exists score_from_events boolean not null default false;
alter table public.matches alter column score_from_events set default true;

-- Preserve finished historical results without goal detail. Active matches and
-- matches with recorded goals switch immediately to event-calculated scores.
update public.matches match_row set
 home_score=(select count(*) from public.events event_row where event_row.match_id=match_row.id and event_row.type='goal' and event_row.team_id=match_row.home_id),
 away_score=(select count(*) from public.events event_row where event_row.match_id=match_row.id and event_row.type='goal' and event_row.team_id=match_row.away_id),
 score_from_events=true
where match_row.status<>'finished'
 or exists(select 1 from public.events event_row where event_row.match_id=match_row.id and event_row.type='goal');

create or replace function public.sync_match_score_from_events(target_match uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.matches match_row set
  home_score=(select count(*) from public.events event_row where event_row.match_id=match_row.id and event_row.type='goal' and event_row.team_id=match_row.home_id),
  away_score=(select count(*) from public.events event_row where event_row.match_id=match_row.id and event_row.type='goal' and event_row.team_id=match_row.away_id),
  score_from_events=true
 where match_row.id=target_match;
end $$;

create or replace function public.event_score_changed()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then
  if old.type='goal' then perform public.sync_match_score_from_events(old.match_id); end if;
  return old;
 end if;
 if tg_op='INSERT' then
  if new.type='goal' then perform public.sync_match_score_from_events(new.match_id); end if;
  return new;
 end if;
 if old.type='goal' or new.type='goal' then
  perform public.sync_match_score_from_events(new.match_id);
  if old.match_id is distinct from new.match_id then perform public.sync_match_score_from_events(old.match_id); end if;
 end if;
 return new;
end $$;
drop trigger if exists event_score_changed on public.events;
create trigger event_score_changed after insert or update or delete on public.events
for each row execute function public.event_score_changed();

create or replace function public.protect_event_calculated_score()
returns trigger language plpgsql set search_path=public as $$
declare expected_home integer; expected_away integer;
begin
 if old.score_from_events and (new.home_score is distinct from old.home_score or new.away_score is distinct from old.away_score) then
  select count(*) into expected_home from public.events where match_id=new.id and type='goal' and team_id=new.home_id;
  select count(*) into expected_away from public.events where match_id=new.id and type='goal' and team_id=new.away_id;
  if new.home_score<>expected_home or new.away_score<>expected_away then
   raise exception 'El marcador se calcula desde los goles registrados';
  end if;
 end if;
 return new;
end $$;
drop trigger if exists protect_event_calculated_score on public.matches;
create trigger protect_event_calculated_score before update of home_score,away_score on public.matches
for each row execute function public.protect_event_calculated_score();

revoke all on function public.sync_match_score_from_events(uuid),public.event_score_changed(),public.protect_event_calculated_score() from public;
commit;
