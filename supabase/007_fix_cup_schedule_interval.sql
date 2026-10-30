-- Corrige la programación de fases de copa en instalaciones existentes.
begin;

create or replace function public.create_cup(
 cup_name text,
 team_ids uuid[],
 first_kickoff timestamptz,
 cup_venue text
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
 cid uuid;
 n integer:=cardinality(team_ids);
 r integer:=1;
 slots integer;
 i integer;
begin
 if not public.is_admin() then
  raise exception 'Solo la administración puede crear copas';
 end if;
 if n is null or n not in (4,8,16)
    or (select count(distinct id) from public.teams where id=any(team_ids))<>n then
  raise exception 'Selecciona 4, 8 o 16 equipos distintos';
 end if;
 insert into public.competitions(name,format,size)
 values(trim(cup_name),'cup',n)
 returning id into cid;
 slots:=n/2;
 while slots>=1 loop
  for i in 1..slots loop
   insert into public.matches(
    competition_id,home_id,away_id,round,slot,kickoff,venue
   )
   values(
    cid,
    case when r=1 then team_ids[2*i-1] end,
    case when r=1 then team_ids[2*i] end,
    r,
    i,
    first_kickoff+make_interval(days => 7*(r-1)),
    cup_venue
   );
  end loop;
  slots:=slots/2;
  r:=r+1;
 end loop;
 return cid;
end
$$;

revoke all on function public.create_cup(text,uuid[],timestamptz,text) from public;
grant execute on function public.create_cup(text,uuid[],timestamptz,text) to authenticated;

commit;
