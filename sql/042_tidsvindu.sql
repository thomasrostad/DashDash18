-- 042: Turneringer med tidsvindu (Thomas 10.10.2026: «Turneringer med tidsvindu bør være
-- tilgjengelig som en mulighet å velge», valgt: «beste N teller»). IKKE KJØRT. Krever godkjenning.
--
-- En liga eller morroturnering kan ha «Spill når det passer»: hver påmeldt spiller spiller når det
-- passer i perioden (starts_on–ends_on), så mange runder hun vil, og de beste N teller (N står i
-- regelsettet som før: competitionRules.league.bestRounds / fun.bestRounds). Nytt her er at rundene
-- teller AV SEG SELV: når en påmeldt starter eller låser en runde i perioden (løs runde eller
-- klubbrunde), kobles runden til turneringen (competition_rounds, source = 'manual', added_by null).
-- Før måtte hver runde kobles med «Teller også i …» når den ble satt opp.
--
-- Nytt felt: competitions.auto_count (av som standard). Ingen eksisterende turnering endres, og
-- Golfgutu og sesongene berøres ikke (bare liga og morro, og bare med auto_count).
-- Gamle bygg ser ikke feltet; de ser bare rundene som teller.
--
-- Én transaksjon, idempotent. Kontroll og rullebakke nederst.

begin;

alter table public.competitions add column if not exists auto_count boolean not null default false;
comment on column public.competitions.auto_count is
  '«Spill når det passer» (sql/042): runder påmeldte spiller i perioden, teller av seg selv. Bare liga og morro.';

-- Kobler runden til alle aktive liga- og morroturneringer med auto_count der minst én av spillerne
-- er påmeldt og runden er spilt i perioden. Gir antall nye koblinger.
create or replace function public.competition_auto_count_round(p_round_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds%rowtype;
  v_day   date;
  n       integer;
begin
  select * into v_round from public.rounds r where r.id = p_round_id;
  if v_round.id is null or v_round.status not in ('active', 'locked') then
    return 0;
  end if;
  v_day := coalesce((select e.event_date from public.events e where e.id = v_round.event_id),
                    (coalesce(v_round.started_at, v_round.created_at) at time zone 'Europe/Oslo')::date);

  insert into public.competition_rounds (competition_id, round_id, source, added_by)
  select c.id, v_round.id, 'manual', null
    from public.competitions c
   where c.auto_count
     and c.kind in ('league', 'fun')
     and c.status = 'active'
     and (c.starts_on is null or v_day >= c.starts_on)
     and (c.ends_on is null or v_day <= c.ends_on)
     and exists (
       select 1 from public.competition_participants cp
        where cp.competition_id = c.id and cp.status = 'active'
          -- Samme person, uansett om hen er påmeldt som profil eller medlem, og om runden er løs
          -- (round_participants) eller en klubbrunde (round_players).
          and (   cp.profile_id in (select rp.profile_id from public.round_participants rp
                                     where rp.round_id = v_round.id and rp.profile_id is not null)
               or cp.profile_id in (select m.user_id from public.round_players p
                                     join public.club_members m on m.id = p.member_id
                                    where p.round_id = v_round.id and m.user_id is not null)
               or cp.member_id in (select p.member_id from public.round_players p where p.round_id = v_round.id)
               or cp.member_id in (select m.id from public.club_members m
                                    join public.round_participants rp on rp.profile_id = m.user_id
                                   where rp.round_id = v_round.id)))
  on conflict (competition_id, round_id) do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.competition_auto_count_round(uuid) from public, anon, authenticated;

create or replace function public.rounds_auto_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.competition_auto_count_round(new.id);
  return null;
end;
$$;
revoke all on function public.rounds_auto_count() from public, anon, authenticated;

-- Når runden startes eller låses (og når en ferdig runde legges inn).
drop trigger if exists rounds_auto_count on public.rounds;
create trigger rounds_auto_count
  after insert or update of status on public.rounds
  for each row when (new.status in ('active', 'locked'))
  execute function public.rounds_auto_count();

-- Når en spiller legges til i en runde som allerede går.
create or replace function public.round_people_auto_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.competition_auto_count_round(new.round_id);
  return null;
end;
$$;
revoke all on function public.round_people_auto_count() from public, anon, authenticated;

drop trigger if exists round_participants_auto_count on public.round_participants;
create trigger round_participants_auto_count
  after insert on public.round_participants
  for each row execute function public.round_people_auto_count();

drop trigger if exists round_players_auto_count on public.round_players;
create trigger round_players_auto_count
  after insert on public.round_players
  for each row execute function public.round_people_auto_count();

commit;

-- Kontroll (les):
-- select count(*) from pg_trigger where tgname like '%auto_count';   -- 3
-- select count(*) from public.competitions where auto_count;          -- 0 rett etter kjøring
--
-- Rull tilbake:
-- begin;
-- drop trigger if exists round_players_auto_count on public.round_players;
-- drop trigger if exists round_participants_auto_count on public.round_participants;
-- drop trigger if exists rounds_auto_count on public.rounds;
-- drop function if exists public.round_people_auto_count();
-- drop function if exists public.rounds_auto_count();
-- drop function if exists public.competition_auto_count_round(uuid);
-- alter table public.competitions drop column if exists auto_count;
-- commit;
