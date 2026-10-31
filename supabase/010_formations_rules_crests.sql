-- Apply after 009. Preserves existing matches, lineups and cup participants.
begin;
alter table public.competitions add column if not exists rules text not null default '' check(length(rules)<=20000);
grant update(name,rules) on public.competitions to authenticated;
create policy competition_admin_edit on public.competitions for update to authenticated using(public.is_admin()) with check(public.is_admin());

create function public.create_cup_with_rules(cup_name text,team_ids uuid[],first_kickoff timestamptz,cup_venue text,cup_rules text) returns uuid
language plpgsql security definer set search_path=public as $$ declare cid uuid; begin
 if not public.is_admin() then raise exception 'Solo la administración puede crear copas'; end if;
 cid:=public.create_cup(cup_name,team_ids,first_kickoff,cup_venue);
 update public.competitions set rules=coalesce(cup_rules,'') where id=cid;
 return cid;
end $$;
revoke all on function public.create_cup_with_rules(text,uuid[],timestamptz,text,text) from public;
grant execute on function public.create_cup_with_rules(text,uuid[],timestamptz,text,text) to authenticated;

alter table public.lineups drop constraint if exists lineups_formation_check;
alter table public.lineups add constraint lineups_formation_check check(formation in ('3-1-2','3-2-1','3-1-1-1','2-3-1','2-2-2','2-1-2-1','4-3-3','4-4-2','4-2-3-1','4-1-4-1','4-3-1-2','3-5-2','3-4-3','5-3-2','5-4-1'));
alter table public.lineups add column if not exists slot_player_ids uuid[];
create or replace function public.validate_lineup() returns trigger language plpgsql security definer set search_path=public as $$
declare m public.matches; n integer; expected integer;
begin
 select * into m from public.matches where id=new.match_id for update;
 if m.id is null or not (new.team_id is not distinct from m.home_id or new.team_id is not distinct from m.away_id) then raise exception 'El equipo no participa en este partido'; end if;
 if m.status<>'scheduled' then raise exception 'La alineación está bloqueada: el partido ya comenzó'; end if;
 select count(distinct p.id) into n from public.players p where p.id=any(new.player_ids) and p.team_id=new.team_id;
 if n<>cardinality(new.player_ids) or n<1 or n>11 then raise exception 'Selecciona entre 1 y 11 jugadores distintos del equipo'; end if;
 -- Old lineups stay readable. New positional lineups must fill every fixed slot.
 if new.slot_player_ids is not null then
  select 1+sum(x::integer) into expected from unnest(string_to_array(new.formation,'-')) x;
  if cardinality(new.slot_player_ids)<>expected or array_position(new.slot_player_ids,null) is not null or new.slot_player_ids is distinct from new.player_ids then raise exception 'Asigna un jugador distinto por posición, respetando el orden de la formación'; end if;
 end if;
 return new;
end $$;

alter table public.teams add column if not exists crest_path text;
alter table public.teams add constraint team_crest_path check(crest_path is null or crest_path ~ ('^'||id::text||'/[0-9a-f-]{36}\.webp$'));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('team-crests','team-crests',true,65536,array['image/webp'])
on conflict(id) do update set public=true,file_size_limit=65536,allowed_mime_types=array['image/webp'];
-- Public retrieval for CDN caching. Writes are restricted to the owning captain/admin.
create policy team_crest_insert on storage.objects for insert to authenticated with check(
 bucket_id='team-crests' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.webp$'
 and exists(select 1 from public.teams t where t.id::text=(storage.foldername(name))[1] and (t.captain_id=auth.uid() or public.is_admin())));
create policy team_crest_delete on storage.objects for delete to authenticated using(
 bucket_id='team-crests' and exists(select 1 from public.teams t where t.id::text=(storage.foldername(name))[1] and (t.captain_id=auth.uid() or public.is_admin())));
create policy team_crest_owner_read on storage.objects for select to authenticated using(
 bucket_id='team-crests' and exists(select 1 from public.teams t where t.id::text=(storage.foldername(name))[1] and (t.captain_id=auth.uid() or public.is_admin())));
commit;
