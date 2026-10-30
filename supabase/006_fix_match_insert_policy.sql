-- Deja una única política de inserción para partidos de liga.
begin;

insert into public.competitions(name, format, size)
select 'Liga Benjaix 2026', 'league', null
where not exists (
 select 1 from public.competitions where format = 'league'
);

drop policy if exists match_write on public.matches;
drop policy if exists match_insert on public.matches;
drop policy if exists match_update on public.matches;

create policy match_insert on public.matches
for insert
to authenticated
with check (
 public.is_admin()
 and exists (
  select 1
  from public.competitions c
  where c.id = competition_id
    and c.format = 'league'
 )
);

create policy match_update on public.matches
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

commit;
