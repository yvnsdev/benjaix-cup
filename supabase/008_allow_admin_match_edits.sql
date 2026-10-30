-- El administrador puede editar partidos de liga y copa.
begin;

drop policy if exists match_update on public.matches;

create policy match_update on public.matches
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

commit;
