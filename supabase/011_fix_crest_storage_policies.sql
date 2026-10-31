-- Run after 010 in Supabase SQL Editor. Safe to rerun.
-- In a correlated subquery, unqualified "name" resolved to teams.name,
-- not storage.objects.name. It must refer to the uploaded object's path.
-- Keeps existing files and the captain/admin permission boundary.
begin;
drop policy if exists team_crest_insert on storage.objects;
drop policy if exists team_crest_delete on storage.objects;
drop policy if exists team_crest_owner_read on storage.objects;

create policy team_crest_insert on storage.objects for insert to authenticated
with check (
 bucket_id = 'team-crests'
 and storage.objects.name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
 and exists (
  select 1 from public.teams t
  where t.id::text = (storage.foldername(storage.objects.name))[1]
   and (t.captain_id = auth.uid() or public.is_admin())
 )
);

create policy team_crest_delete on storage.objects for delete to authenticated
using (
 bucket_id = 'team-crests'
 and exists (
  select 1 from public.teams t
  where t.id::text = (storage.foldername(storage.objects.name))[1]
   and (t.captain_id = auth.uid() or public.is_admin())
 )
);

create policy team_crest_owner_read on storage.objects for select to authenticated
using (
 bucket_id = 'team-crests'
 and exists (
  select 1 from public.teams t
  where t.id::text = (storage.foldername(storage.objects.name))[1]
   and (t.captain_id = auth.uid() or public.is_admin())
 )
);
commit;
