-- Ejecutar después de 017. No elimina equipos ni resultados existentes.
begin;
create table public.site_settings (
 id text primary key default 'main' check(id='main'),
 title text not null default 'Benjaix Cup' check(length(title) between 1 and 80),
 description text not null default 'Fútbol 7, comunidad y una copa por conquistar.' check(length(description)<=3000),
 venue text not null default '' check(length(venue)<=200),
 dates text not null default '' check(length(dates)<=200),
 prizes text not null default '' check(length(prizes)<=5000),
 payment_instructions text not null default '' check(length(payment_instructions)<=3000),
 registration_fee integer check(registration_fee between 1 and 10000000),
 registration_open boolean not null default false,
 featured_cup_id uuid references public.competitions(id) on delete set null,
 check(not registration_open or (registration_fee is not null and length(trim(payment_instructions))>0))
);
insert into public.site_settings(id) values('main');
alter table public.site_settings enable row level security;
create policy settings_read on public.site_settings for select to anon,authenticated using(true);
create policy settings_update on public.site_settings for update to authenticated using(public.is_admin()) with check(public.is_admin());
grant select on public.site_settings to anon,authenticated;
grant update on public.site_settings to authenticated;

create table public.championship_news (
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(trim(title)) between 1 and 160),
 body text not null check(length(trim(body)) between 1 and 10000),
 category text not null default 'general' check(category in ('general','reschedule','suspension','registration')),
 match_id uuid references public.matches(id) on delete set null,
 published boolean not null default false,
 pinned boolean not null default false,
 created_at timestamptz not null default now()
);
alter table public.championship_news enable row level security;
create policy news_read on public.championship_news for select to anon,authenticated using(published or public.is_admin());
create policy news_admin on public.championship_news for all to authenticated using(public.is_admin()) with check(public.is_admin());
grant select on public.championship_news to anon,authenticated;
grant insert,update,delete on public.championship_news to authenticated;

create table public.captain_registrations (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references public.profiles(id) on delete cascade,
 captain_name text not null check(length(trim(captain_name)) between 1 and 100),
 team_name text not null check(length(trim(team_name)) between 1 and 60),
 contact text not null check(length(trim(contact)) between 1 and 200),
 payment_reference text not null check(length(trim(payment_reference)) between 1 and 300),
 amount integer not null check(amount>0),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 review_note text not null default '' check(length(review_note)<=1000),
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references public.profiles(id) on delete set null
);
alter table public.captain_registrations enable row level security;
create policy registration_read on public.captain_registrations for select to authenticated using(user_id=auth.uid() or public.is_admin());
grant select on public.captain_registrations to authenticated;
revoke insert,update,delete on public.captain_registrations from anon,authenticated;

create function public.submit_captain_registration(captain_name text,team_name text,contact text,payment_reference text) returns uuid
language plpgsql security definer set search_path=public as $$
declare s public.site_settings; existing public.captain_registrations; rid uuid;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Confirma tu correo antes de inscribirte'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into s from public.site_settings where id='main' for share;
 if not coalesce(s.registration_open,false) then raise exception 'Las inscripciones están cerradas'; end if;
 if exists(select 1 from public.teams where captain_id=auth.uid()) then raise exception 'Ya eres capitán de un equipo'; end if;
 select * into existing from public.captain_registrations where user_id=auth.uid() for update;
 if existing.status in ('pending','approved') then raise exception 'Ya tienes una solicitud pendiente o aprobada'; end if;
 insert into public.captain_registrations(user_id,captain_name,team_name,contact,payment_reference,amount)
 values(auth.uid(),trim(captain_name),trim(team_name),trim(contact),trim(payment_reference),s.registration_fee)
 on conflict(user_id) do update set captain_name=excluded.captain_name,team_name=excluded.team_name,contact=excluded.contact,payment_reference=excluded.payment_reference,amount=excluded.amount,status='pending',review_note='',created_at=now(),reviewed_at=null,reviewed_by=null
 returning id into rid;
 return rid;
end $$;

create function public.review_captain_registration(registration_id uuid,decision text,note text default '') returns void
language plpgsql security definer set search_path=public as $$
declare r public.captain_registrations;
begin
 if not public.is_admin() then raise exception 'Solo la administración puede revisar pagos'; end if;
 if decision not in ('approved','rejected') or decision is null then raise exception 'Decisión no válida'; end if;
 select * into r from public.captain_registrations where id=registration_id for update;
 if r.id is null or r.status<>'pending' then raise exception 'Esta solicitud ya fue revisada o no existe'; end if;
 update public.captain_registrations set status=decision,review_note=trim(note),reviewed_at=now(),reviewed_by=auth.uid() where id=r.id;
 if decision='approved' then update public.profiles set role='captain' where id=r.user_id and role<>'admin'; end if;
end $$;

-- Validación en servidor: ocultar un formulario no basta para exigir el pago.
create or replace function public.create_my_team(team_name text, abbreviation text, team_color text) returns uuid
language plpgsql security definer set search_path=public as $$
declare tid uuid;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null) then raise exception 'Confirma tu correo antes de crear un equipo'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 if exists(select 1 from public.teams where captain_id=auth.uid()) then raise exception 'Ya gestionas un equipo propio'; end if;
 if not public.is_admin() and not exists(select 1 from public.captain_registrations where user_id=auth.uid() and status='approved') then raise exception 'La administración debe confirmar tu pago de inscripción antes de crear el equipo'; end if;
 insert into public.teams(name,short_name,color,captain_id) values(trim(team_name),upper(trim(abbreviation)),team_color,auth.uid()) returning id into tid;
 return tid;
end $$;
revoke all on function public.submit_captain_registration(text,text,text,text),public.review_captain_registration(uuid,text,text) from public;
grant execute on function public.submit_captain_registration(text,text,text,text),public.review_captain_registration(uuid,text,text) to authenticated;
alter publication supabase_realtime add table public.site_settings,public.championship_news;
-- Solicitudes privadas se consultan al entrar al panel y con Actualizar solicitudes.
commit;
