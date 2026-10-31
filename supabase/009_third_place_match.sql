-- Añade y actualiza automáticamente el partido por el tercer lugar.
begin;

create or replace function public.validate_competition_match()
returns trigger language plpgsql set search_path=public
as $$
declare c public.competitions;
begin
 select * into c from public.competitions where id=new.competition_id;
 if tg_op='UPDATE' and (new.competition_id<>old.competition_id or new.round<>old.round or new.slot is distinct from old.slot) then
  raise exception 'No se puede mover un partido entre fases';
 end if;
 if c.format='league' and (new.home_id is null or new.away_id is null or new.slot is not null) then
  raise exception 'Partido de liga no válido';
 end if;
 if (new.home_id is null or new.away_id is null) and new.status<>'scheduled' then
  raise exception 'Espera a que se definan ambos equipos';
 end if;
 if c.format='cup' and new.status='finished' and public.match_winner(new) is null then
  raise exception 'Un empate de copa necesita un ganador por penales';
 end if;
 if c.format='cup' and (new.slot is null or new.round>log(2,c.size)::integer
    or (new.slot>c.size/power(2,new.round)
    and not (new.round=log(2,c.size)::integer and new.slot=2))) then
  raise exception 'Fase de copa no válida';
 end if;
 return new;
end
$$;

create or replace function public.create_cup(
 cup_name text, team_ids uuid[], first_kickoff timestamptz, cup_venue text
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare cid uuid; n integer:=cardinality(team_ids); r integer:=1; slots integer; i integer;
begin
 if not public.is_admin() then raise exception 'Solo la administración puede crear copas'; end if;
 if n is null or n not in (4,8,16)
    or (select count(distinct id) from public.teams where id=any(team_ids))<>n then
  raise exception 'Selecciona 4, 8 o 16 equipos distintos';
 end if;
 insert into public.competitions(name,format,size)
 values(trim(cup_name),'cup',n) returning id into cid;
 slots:=n/2;
 while slots>=1 loop
  for i in 1..slots loop
   insert into public.matches(competition_id,home_id,away_id,round,slot,kickoff,venue)
   values(cid,case when r=1 then team_ids[2*i-1] end,
     case when r=1 then team_ids[2*i] end,r,i,
     first_kickoff+make_interval(days => 7*(r-1)),cup_venue);
   if r=log(2,n)::integer and i=1 then
    insert into public.matches(competition_id,home_id,away_id,round,slot,kickoff,venue)
    values(cid,null,null,r,2,
      first_kickoff+make_interval(days => 7*(r-1)),cup_venue);
   end if;
  end loop;
  slots:=slots/2; r:=r+1;
 end loop;
 return cid;
end
$$;

create or replace function public.advance_cup_winner()
returns trigger language plpgsql security definer set search_path=public
as $$
declare
 w uuid; next_match public.matches; previous uuid; cup_size integer;
begin
 if not exists(select 1 from public.competitions where id=new.competition_id and format='cup') then return new; end if;
 w:=public.match_winner(new); previous:=public.match_winner(old);
 if w is not distinct from previous then return new; end if;
 select size into cup_size from public.competitions where id=new.competition_id;
 select * into next_match from public.matches
  where competition_id=new.competition_id and round=new.round+1
    and slot=(new.slot+1)/2 for update;
 if next_match.id is null then return new; end if;
 if next_match.status<>'scheduled' then raise exception 'Primero reabre la siguiente fase: ya comenzó o terminó'; end if;
 if exists(select 1 from public.events where match_id=next_match.id) then raise exception 'Retira los eventos de la siguiente fase antes de cambiar el ganador'; end if;
 delete from public.lineups where match_id=next_match.id;
 update public.matches set home_id=case when new.slot%2=1 then w else home_id end,
  away_id=case when new.slot%2=0 then w else away_id end,
  home_score=0,away_score=0,minute=0,penalty_home=null,penalty_away=null
  where id=next_match.id;
 if new.round=log(2,cup_size)::integer-1 then
  update public.matches set
   home_id=case when new.slot=1 then case when new.home_id=w then new.away_id else new.home_id end else home_id end,
   away_id=case when new.slot=2 then case when new.home_id=w then new.away_id else new.home_id end else away_id end,
   home_score=0,away_score=0,minute=0,penalty_home=null,penalty_away=null
  where competition_id=new.competition_id and round=new.round+1 and slot=2;
 end if;
 return new;
end
$$;

do $$
declare c record; final_match public.matches;
begin
 for c in select id, size from public.competitions where format='cup' loop
  if not exists(select 1 from public.matches where competition_id=c.id and round=log(2,c.size)::integer and slot=2) then
   select * into final_match from public.matches
   where competition_id=c.id and round=log(2,c.size)::integer and slot=1;
   if final_match.id is not null then
    insert into public.matches(
     competition_id,home_id,away_id,round,slot,kickoff,venue
    ) values(
     c.id,null,null,final_match.round,2,final_match.kickoff,final_match.venue
    );
   end if;
  end if;
 end loop;
end
$$;

do $$
declare
 c record;
 semifinal_one public.matches;
 semifinal_two public.matches;
 loser_one uuid;
 loser_two uuid;
begin
 for c in
  select id, size
  from public.competitions
  where format='cup'
 loop
  select * into semifinal_one
  from public.matches
  where competition_id=c.id
    and round=log(2,c.size)::integer-1
    and slot=1;

  select * into semifinal_two
  from public.matches
  where competition_id=c.id
    and round=log(2,c.size)::integer-1
    and slot=2;

  loser_one:=case
   when public.match_winner(semifinal_one)=semifinal_one.home_id then semifinal_one.away_id
   when public.match_winner(semifinal_one)=semifinal_one.away_id then semifinal_one.home_id
  end;
  loser_two:=case
   when public.match_winner(semifinal_two)=semifinal_two.home_id then semifinal_two.away_id
   when public.match_winner(semifinal_two)=semifinal_two.away_id then semifinal_two.home_id
  end;

  if loser_one is not null and loser_two is not null then
   update public.matches
   set home_id=loser_one,
       away_id=loser_two
   where competition_id=c.id
     and round=log(2,c.size)::integer
     and slot=2
     and status='scheduled';
  end if;
 end loop;
end
$$;

commit;
