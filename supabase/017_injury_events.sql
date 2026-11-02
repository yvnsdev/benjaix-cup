-- Apply after 016. Adds player injuries to the match timeline.
begin;
alter table public.events drop constraint if exists events_type_check;
alter table public.events add constraint events_type_check
 check(type in ('goal','assist','yellow','red','substitution','injury'));
commit;
