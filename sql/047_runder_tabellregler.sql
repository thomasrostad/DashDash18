-- 047: tabellregler på runden og playoff-runden (gjennomføringsplanen steg 6). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–045 (044_roller: private.has_club_right; 042: competition_auto_count_round;
-- 043: tv_competition_data).
--
-- Motoren er merget (#69, se Packages/GolfgutuCore/REGELSETT.md, «Tabellregler og playoff»):
-- Round.counts, Round.pointsTable, Round.hideLastHoles og Playoff.decide. Playoff regnes
-- netto med fullt spillehandicap i playoff-runden (Thomas 11.10.2026).
--
-- Hva fila gjør:
--   1. rounds får
--        counts          boolean  not null default true   (false = kvelden teller ikke, vekt 0)
--        points_table    text     null                    (navnet på en poengtabell i
--                                                          table.pointsTables, f.eks. «finale»;
--                                                          1–40 tegn, ikke blankt. Motoren godtar
--                                                          alle navn som ikke er blanke, og et
--                                                          ukjent navn gir multiplikator 1)
--        hide_last_holes smallint not null default 0      (0–9; «skjul de tre siste» = 3)
--        kind            text     not null default 'normal'  ('normal' eller 'playoff')
--        playoff_for     uuid     null → competitions(id) on delete cascade
--        playoff_holes   smallint[] null                  (hullene i playoffen i valgt rekkefølge)
--      Alle runder som finnes, får standardverdiene og er altså uendret (counts = true,
--      kind = normal, ingen tabell, ingen skjulte hull).
--      Regler (check): kind = playoff ⇔ playoff_for og playoff_holes er satt; en playoff
--      teller aldri (counts = false); playoff_holes har 1–hole_count elementer, hvert
--      0 ≤ h < hole_count, ingen null.
--   2. Hvem setter counts, points_table og hide_last_holes: som de andre oppsettkolonnene
--      på runden, med vanlig update (rounds_update: rettigheten rounds, eller eieren av en
--      løs runde). Ingen ny policy. kind, playoff_for og playoff_holes kan ikke endres med
--      update (trigger rounds_guard_kind); de settes bare av RPC-ene under.
--   3. Playoff-hullene. Motoren tar rundens 0-baserte hullindekser i rekkefølgen de spilles,
--      og samme hull kan stå flere ganger (forslaget er siste, første, siste). Derfor:
--        * rounds.playoff_holes[i] er rundehullet (0-basert, som ld_hole_index og
--          hole_scores.hole_index) som spilles som playoff-hull nummer i;
--        * scoren for playoff-hull nummer i (1-basert i lista) lagres i hole_scores med
--          hole_index = i − 1, altså POSISJONEN, ikke banehullet. Da kan samme hull spilles
--          to ganger uten å endre hole_scores, og save_hole/kanFore virker som før.
--          Klienten slår opp par og indeks via playoff_holes[i];
--        * runden har samme hole_count som turneringens runder (18, eller 9 når de var
--          9-hullsrunder), så Playoff.decide får samme slag på hullet som i en vanlig runde.
--          Derfor høyst hole_count playoff-hull.
--      Oppgaven foreslo «hull 1–18, unike». Unike hull ville stoppe motorens forslag
--      (siste, første, siste), så gjentak er lov.
--   4. create_playoff_round(turnering, kveld, spillere, hull, bane default null) lager en
--      aktiv playoff-runde:
--        * rett: is_competition_admin (tournaments, eier eller stab), og for klubbens
--          turneringer også rettigheten rounds;
--        * bare sesong, liga og morro med table.tieRule = playoff;
--        * klubbturnering: på kvelden som er gitt (må høre til turneringen) eller den
--          siste kvelden i turneringen. Spillerne er aktive medlemmer i klubben (medlems-
--          eller profil-id) som er med i turneringen. Runden får neste ledige round_no på
--          kvelden;
--        * turnering uten klubb: en løs runde (club_id og event_id tomme) med spillerne som
--          round_participants (profil-id, eller medlems-id med innlogging);
--        * «med i turneringen»: klubbens tropp når entry = club, en aktiv påmelding
--          (competition_participants), eller spilt i en runde som teller i turneringen;
--        * bane, antall hull, første hull, form, andel, ekstern handicap, sted og tee hentes
--          fra den siste runden som teller i turneringen. Banen kan gis (p_course_id), og
--          må gis når turneringen ikke har runder med bane;
--        * counts = false, LD og KP av, navn «Playoff», kind = playoff, playoff_for = turneringen.
--      Databasen sjekker ikke at spillerne faktisk står likt; det regner motoren ut.
--      playoff_set_holes(runde, hull) bytter eller forlenger hullene (arrangøren legger til
--      hull når det fortsatt står likt). Hull som har score, kan ikke byttes.
--   5. En playoff er ikke en vanlig runde:
--        * den kobles aldri i competition_rounds: competition_auto_count_round (042) hopper
--          over playoffer, competition_rounds_before_insert hopper over raden når den kommer
--          fra en trigger (sesongkoblingen fra 031/034 når runden ligger på turneringens
--          kveld), og avviser den (22023) fra set_round_competitions eller direkte insert;
--        * den unike indeksen «én aktiv runde per kveld og bølge» gjelder bare kind = normal,
--          så en playoff kan starte mens kveldens runde fortsatt går, og den stopper ikke en
--          ny runde. Høyst én aktiv playoff per turnering (ny unik indeks). Valgt fordi
--          playoffen ofte spilles rett etter siste runde, før den er låst, og fordi den
--          ikke er en bølge i terminlista;
--        * veddemål kan ikke knyttes til en playoff-runde (hullene er posisjoner);
--        * påminnelser og purring leser kvelder og påmeldinger, ikke runder, og er urørt.
--          Tipping (tips_open) stenger når kvelden har score; playoffen kommer etter.
--   6. Lesing: round_in_readable_competition gjelder også runder med playoff_for, så de som
--      kan lese turneringen, ser en løs playoff (den er ikke i competition_rounds).
--   7. tavla_data (036), tv_board_data (041/043) og tv_competition_data (043) sender de seks
--      nye feltene. tv_competition_data tar også med playoff-rundene til turneringen.
--      TV-funksjonene sender fortsatt ingen bruker-id. TV-en får ikke scorene på de skjulte
--      hullene (hide_last_holes) før runden er låst, siden TV-en er «alle andre». tavla_data
--      sender alt, som før: hvem som ser hva bestemmer appen (Round.hidingLastHoles).
--
-- Mønsteret fra 001–045: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.
--
-- Appen, web-admin og TV-en må (ikke i denne fila):
--   * lese counts, points_table og hide_last_holes inn i Round (motoren har feltene);
--   * runde-oppsett: «Teller ikke», poengtabell (fra table.pointsTables) og «Skjul de tre
--     siste hullene», skrevet med vanlig update på rounds;
--   * holde runder med kind = playoff utenfor alt som teller (Tavla, tabeller, statistikk,
--     tips, «Mine runder» som vanlig runde, hole_stats) og vise dem som playoff;
--   * starte playoffen med create_playoff_round når tabellen viser playoffPending, med
--     Playoff.suggestedHoles som forslag, og føre score per posisjon (hole_index = posisjon);
--   * regne vinneren med Playoff.decide (holes = playoff_holes, scores per posisjon) og gi
--     den til Season.standings(playoffWinner:);
--   * TV: samme for kind = playoff i tv_board_data og tv_competition_data.

begin;


-- ===========================================================================
-- 1. ROUNDS: NYE KOLONNER
-- ===========================================================================
alter table public.rounds
  add column if not exists counts          boolean  not null default true,
  add column if not exists points_table    text,
  add column if not exists hide_last_holes smallint not null default 0,
  add column if not exists kind            text     not null default 'normal',
  add column if not exists playoff_for     uuid,
  add column if not exists playoff_holes   smallint[];

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rounds_playoff_for_fkey') then
    alter table public.rounds add constraint rounds_playoff_for_fkey
      foreign key (playoff_for) references public.competitions(id) on delete cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_kind_check') then
    alter table public.rounds add constraint rounds_kind_check
      check (kind in ('normal', 'playoff'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_points_table_check') then
    alter table public.rounds add constraint rounds_points_table_check
      check (points_table is null or (char_length(points_table) between 1 and 40 and btrim(points_table) <> ''));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_hide_last_holes_check') then
    alter table public.rounds add constraint rounds_hide_last_holes_check
      check (hide_last_holes between 0 and 9);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_playoff_for_kind') then
    alter table public.rounds add constraint rounds_playoff_for_kind
      check ((kind = 'playoff') = (playoff_for is not null));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_playoff_never_counts') then
    alter table public.rounds add constraint rounds_playoff_never_counts
      check (kind = 'normal' or not counts);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_playoff_holes_check') then
    alter table public.rounds add constraint rounds_playoff_holes_check
      check ((kind = 'playoff') = (playoff_holes is not null)
             and (playoff_holes is null
                  or (array_ndims(playoff_holes) = 1
                      and cardinality(playoff_holes) between 1 and hole_count
                      and array_position(playoff_holes, null) is null
                      and 0 <= all (playoff_holes)
                      and hole_count > all (playoff_holes))));
  end if;
end $$;

comment on column public.rounds.counts is
  'false = runden teller ikke i tabellen (Round.counts, vekt 0). Standard true. En playoff teller aldri.';
comment on column public.rounds.points_table is
  'Navnet på en poengtabell i regelsettet (table.pointsTables). null = ingen (multiplikator 1).';
comment on column public.rounds.hide_last_holes is
  'Antall hull til slutt som skjules for andre til runden er låst (Round.hideLastHoles). 0 = av.';
comment on column public.rounds.kind is
  'normal eller playoff. En playoff lages med create_playoff_round, teller aldri og kobles ikke i competition_rounds.';
comment on column public.rounds.playoff_for is
  'Turneringen playoffen avgjør (bare når kind = playoff).';
comment on column public.rounds.playoff_holes is
  'Playoff-hullene i rekkefølge (0-baserte rundehull, kan gjentas). Score for nummer i lagres med hole_index = i − 1.';

-- Én aktiv runde per kveld og bølge gjelder bare vanlige runder. Høyst én aktiv playoff per turnering.
drop index if exists public.rounds_one_active_per_event_wave;
create unique index rounds_one_active_per_event_wave
  on public.rounds (event_id, wave_no)
  where status = 'active' and event_id is not null and kind = 'normal';
create unique index if not exists rounds_one_active_playoff
  on public.rounds (playoff_for) where status = 'active' and kind = 'playoff';
create index if not exists rounds_playoff_for_idx
  on public.rounds (playoff_for) where playoff_for is not null;


-- ===========================================================================
-- 2. VAKTER: RUNDETYPEN, KOBLINGEN OG VEDDEMÅL
-- ===========================================================================
-- kind, playoff_for og playoff_holes skrives bare av RPC-ene (dd18.playoff_write = on).
-- Uten innlogging (SQL Editor, service_role) er det lov, som i de andre vaktene.
create or replace function private.rounds_guard_kind()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rpc boolean := coalesce(current_setting('dd18.playoff_write', true), '') = 'on';
begin
  if auth.uid() is null or v_rpc then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.kind = 'playoff' then
      raise exception 'En playoff lages med create_playoff_round' using errcode = '42501';
    end if;
  else
    if new.kind is distinct from old.kind or new.playoff_for is distinct from old.playoff_for then
      raise exception 'Rundetypen kan ikke endres' using errcode = '22023';
    end if;
    if new.playoff_holes is distinct from old.playoff_holes then
      raise exception 'Playoff-hullene endres med playoff_set_holes' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.rounds_guard_kind() from public, anon, authenticated;

drop trigger if exists rounds_guard_kind on public.rounds;
create trigger rounds_guard_kind
  before insert or update on public.rounds
  for each row execute function private.rounds_guard_kind();

-- En playoff teller aldri som runde i turneringen. Fra triggerne (sesongkoblingen og
-- auto_count) hoppes raden over; fra set_round_competitions eller direkte insert avvises den.
create or replace function public.competition_rounds_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.rounds r where r.id = new.round_id and r.kind = 'playoff') then
    if pg_trigger_depth() > 1 then
      return null;
    end if;
    raise exception 'En playoff-runde teller ikke som runde i turneringen' using errcode = '22023';
  end if;
  if auth.uid() is not null and pg_trigger_depth() = 1 then
    new.added_by := auth.uid();
  end if;
  return new;
end;
$$;
revoke all on function public.competition_rounds_before_insert() from public, anon, authenticated;

-- auto_count (042) som før, men en playoff kobles aldri (linja med kind).
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
  if v_round.id is null or v_round.status not in ('active', 'locked') or v_round.kind = 'playoff' then
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

create or replace function private.bets_guard_playoff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.round_id is not null
     and exists (select 1 from public.rounds r where r.id = new.round_id and r.kind = 'playoff') then
    raise exception 'Veddemål på en playoff-runde er ikke støttet' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function private.bets_guard_playoff() from public, anon, authenticated;

drop trigger if exists bets_guard_playoff on public.bets;
create trigger bets_guard_playoff
  before insert or update of round_id on public.bets
  for each row execute function private.bets_guard_playoff();

-- De som kan lese turneringen, kan lese playoffen (en løs playoff er ikke i competition_rounds).
create or replace function public.round_in_readable_competition(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competition_rounds cr
    where cr.round_id = p_round_id and public.can_read_competition(cr.competition_id)
  ) or exists (
    select 1 from public.rounds r
    where r.id = p_round_id and r.playoff_for is not null and public.can_read_competition(r.playoff_for)
  );
$$;
revoke all on function public.round_in_readable_competition(uuid) from public, anon;
grant execute on function public.round_in_readable_competition(uuid) to authenticated;


-- ===========================================================================
-- 3. PLAYOFF-RUNDEN
-- ===========================================================================
-- Hvem kan starte og endre en playoff i turneringen.
create or replace function private.playoff_can_manage(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_competition_admin(p_competition_id)
      or exists (select 1 from public.competitions c
                  where c.id = p_competition_id and c.club_id is not null
                    and private.has_club_right(c.club_id, 'rounds'));
$$;
revoke all on function private.playoff_can_manage(uuid) from public, anon, authenticated;

-- Er personen (medlem og/eller profil) med i turneringen: tropp (entry = club), påmeldt,
-- eller spilt i en runde som teller.
create or replace function private.playoff_entrant(p_competition_id uuid, p_member_id uuid, p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.competitions c
                  join public.club_members m on m.club_id = c.club_id
                 where c.id = p_competition_id and c.entry = 'club'
                   and m.id = p_member_id and m.status = 'active')
      or exists (select 1 from public.competition_participants cp
                  where cp.competition_id = p_competition_id and cp.status = 'active'
                    and (   cp.member_id = p_member_id
                         or cp.profile_id = p_profile_id
                         or cp.member_id in (select m.id from public.club_members m where m.user_id = p_profile_id)))
      or exists (select 1 from public.competition_rounds cr
                  join public.rounds r on r.id = cr.round_id
                 where cr.competition_id = p_competition_id
                   and r.kind = 'normal' and r.status in ('active', 'locked')
                   and (   exists (select 1 from public.round_players rp
                                    where rp.round_id = r.id
                                      and (   rp.member_id = p_member_id
                                           or rp.member_id in (select m.id from public.club_members m
                                                                where m.user_id = p_profile_id)))
                        or exists (select 1 from public.round_participants pa
                                    where pa.round_id = r.id and pa.profile_id = p_profile_id)));
$$;
revoke all on function private.playoff_entrant(uuid, uuid, uuid) from public, anon, authenticated;

-- Sjekker hullene (0-baserte rundehull, i rekkefølge, gjentak lov).
create or replace function private.playoff_check_holes(p_holes smallint[], p_hole_count smallint)
returns void
language plpgsql
immutable
security definer
set search_path = ''
as $$
begin
  if p_holes is null or cardinality(p_holes) = 0 then
    raise exception 'Velg minst ett hull til playoffen' using errcode = '22023';
  end if;
  if array_ndims(p_holes) <> 1 then
    raise exception 'Hullene må være en enkel liste' using errcode = '22023';
  end if;
  if cardinality(p_holes) > p_hole_count then
    raise exception 'Høyst % playoff-hull', p_hole_count using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_holes) h where h is null or h < 0 or h >= p_hole_count) then
    raise exception 'Playoff-hullene må være blant rundens % hull', p_hole_count using errcode = '22023';
  end if;
end;
$$;
revoke all on function private.playoff_check_holes(smallint[], smallint) from public, anon, authenticated;

create or replace function public.create_playoff_round(
  p_competition_id uuid,
  p_event_id       uuid,
  p_member_ids     uuid[],
  p_holes          smallint[],
  p_course_id      uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_comp      public.competitions%rowtype;
  v_event     public.events%rowtype;
  v_tpl       public.rounds%rowtype;
  v_course    uuid;
  v_count     smallint;
  v_round_no  smallint := 1;
  v_round     uuid;
  v_people    uuid[] := '{}';
  v_x         uuid;
  v_m         uuid;
  v_p         uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.* into v_comp from public.competitions c where c.id = p_competition_id for update;
  if v_comp.id is null or not public.can_read_competition(v_comp.id) then
    raise exception 'Fant ikke turneringen' using errcode = 'P0002';
  end if;
  if not private.playoff_can_manage(v_comp.id) then
    raise exception 'Bare arrangøren kan starte en playoff' using errcode = '42501';
  end if;
  if v_comp.kind not in ('season', 'league', 'fun') then
    raise exception 'Playoff finnes bare i sesong, liga og morroturnering' using errcode = '22023';
  end if;
  if coalesce(v_comp.rules #>> '{table,tieRule}', '') <> 'playoff' then
    raise exception 'Turneringen avgjør likhet uten playoff' using errcode = '55000';
  end if;
  if exists (select 1 from public.rounds r
              where r.playoff_for = v_comp.id and r.kind = 'playoff' and r.status = 'active') then
    raise exception 'En playoff går allerede i turneringen' using errcode = '23505';
  end if;

  -- Kvelden (bare klubbturneringer).
  if v_comp.club_id is not null then
    if p_event_id is not null then
      select e.* into v_event from public.events e
       where e.id = p_event_id and e.competition_id = v_comp.id;
      if v_event.id is null then
        raise exception 'Kvelden hører ikke til turneringen' using errcode = '22023';
      end if;
    else
      select e.* into v_event from public.events e
       where e.competition_id = v_comp.id
       order by e.event_date desc, e.start_time desc nulls last, e.created_at desc
       limit 1;
      if v_event.id is null then
        raise exception 'Turneringen har ingen kveld å legge playoffen på' using errcode = '55000';
      end if;
    end if;
  elsif p_event_id is not null then
    raise exception 'En turnering uten klubb har ingen kvelder' using errcode = '22023';
  end if;

  -- Oppsettet fra den siste runden som teller (bane, hull, form, handicapmodell).
  select r.* into v_tpl
    from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
   where cr.competition_id = v_comp.id and r.kind = 'normal' and r.status in ('active', 'locked')
   order by (r.course_id is not null) desc, coalesce(r.started_at, r.created_at) desc, r.id
   limit 1;
  v_course := coalesce(p_course_id, v_tpl.course_id);
  if v_course is null then
    raise exception 'Velg banen for playoffen' using errcode = '22023';
  end if;
  v_count := coalesce(v_tpl.hole_count, 18);
  perform private.playoff_check_holes(p_holes, v_count);

  -- Spillerne.
  foreach v_x in array (select coalesce(array_agg(distinct x), '{}') from unnest(coalesce(p_member_ids, '{}')) x
                         where x is not null) loop
    if v_comp.club_id is not null then
      select m.id into v_m from public.club_members m
       where m.club_id = v_comp.club_id and m.status = 'active' and (m.id = v_x or m.user_id = v_x)
       order by (m.id = v_x) desc limit 1;
      if v_m is null then
        raise exception 'En av spillerne er ikke aktivt medlem i klubben' using errcode = '22023';
      end if;
      if not private.playoff_entrant(v_comp.id, v_m,
                                     (select m.user_id from public.club_members m where m.id = v_m)) then
        raise exception 'En av spillerne er ikke med i turneringen' using errcode = '22023';
      end if;
      if not v_m = any (v_people) then
        v_people := v_people || v_m;
      end if;
    else
      v_p := coalesce((select p.id from public.profiles p where p.id = v_x),
                      (select m.user_id from public.club_members m where m.id = v_x));
      if v_p is null then
        raise exception 'En av spillerne har ingen profil' using errcode = '22023';
      end if;
      if not private.playoff_entrant(v_comp.id, null, v_p) then
        raise exception 'En av spillerne er ikke med i turneringen' using errcode = '22023';
      end if;
      if not v_p = any (v_people) then
        v_people := v_people || v_p;
      end if;
    end if;
  end loop;
  if cardinality(v_people) < 2 then
    raise exception 'En playoff trenger minst to spillere' using errcode = '22023';
  end if;
  if cardinality(v_people) > 47 then
    raise exception 'For mange spillere i én playoff' using errcode = '22023';
  end if;

  if v_event.id is not null then
    select coalesce(max(r.round_no), 0) + 1 into v_round_no from public.rounds r where r.event_id = v_event.id;
    if v_round_no > 9 then
      raise exception 'Kvelden har ikke plass til flere runder (høyst 9)' using errcode = '55000';
    end if;
  end if;

  perform set_config('dd18.playoff_write', 'on', true);
  insert into public.rounds (club_id, event_id, course_id, round_no, name, status, hole_count, first_hole,
                             format, handicap_allowance, external_handicap, weight, ld_enabled, kp_enabled,
                             venue, tee_id, counts, kind, playoff_for, playoff_holes)
  values (v_comp.club_id, v_event.id, v_course, v_round_no, 'Playoff', 'draft', v_count,
          case when v_count = 9 then coalesce(v_tpl.first_hole, 1) else 1 end,
          coalesce(v_tpl.format, 'stableford'), coalesce(v_tpl.handicap_allowance, 1),
          coalesce(v_tpl.external_handicap, false), 1, false, false,
          coalesce(v_tpl.venue, v_comp.venue, 'simulator'),
          case when v_course = v_tpl.course_id then v_tpl.tee_id end,
          false, 'playoff', v_comp.id, p_holes)
  returning id into v_round;
  perform set_config('dd18.playoff_write', '', true);

  if v_comp.club_id is not null then
    insert into public.round_players (round_id, member_id, club_id)
    select v_round, x, v_comp.club_id from unnest(v_people) x;
  else
    insert into public.round_participants (round_id, profile_id, display_name)
    select v_round, p.id,
           left(coalesce(nullif(btrim(p.display_name), ''),
                         (select m.display_name from public.club_members m
                           where m.user_id = p.id order by m.created_at limit 1),
                         'Spiller'), 40)
      from public.profiles p where p.id = any (v_people);
  end if;

  -- Start: handicapet fryses (rounds_after_update / rounds_freeze_participants).
  update public.rounds set status = 'active' where id = v_round;

  return jsonb_build_object(
    'round_id', v_round,
    'status', 'active',
    'event_id', v_event.id,
    'round_no', v_round_no,
    'hole_count', v_count,
    'playoff_holes', to_jsonb(p_holes),
    'players', (select coalesce(jsonb_agg(rp.member_id order by rp.member_id), '[]')
                  from public.round_players rp where rp.round_id = v_round));
end;
$$;
revoke all on function public.create_playoff_round(uuid, uuid, uuid[], smallint[], uuid) from public, anon;
grant execute on function public.create_playoff_round(uuid, uuid, uuid[], smallint[], uuid) to authenticated;

-- Bytter eller forlenger hullene. Hull med score (hole_index = posisjon) kan ikke byttes.
create or replace function public.playoff_set_holes(p_round_id uuid, p_holes smallint[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round public.rounds%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select r.* into v_round from public.rounds r where r.id = p_round_id for update;
  if v_round.id is null or not public.can_read_round(v_round.id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_round.kind <> 'playoff' then
    raise exception 'Runden er ikke en playoff' using errcode = '22023';
  end if;
  if not (private.playoff_can_manage(v_round.playoff_for) or public.is_round_organizer(v_round.id)) then
    raise exception 'Bare arrangøren kan endre playoff-hullene' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Playoffen er låst' using errcode = '55000';
  end if;
  perform private.playoff_check_holes(p_holes, v_round.hole_count);
  if exists (select 1 from public.hole_scores s
              where s.round_id = v_round.id
                and (s.hole_index >= cardinality(p_holes)
                     or p_holes[s.hole_index + 1] is distinct from v_round.playoff_holes[s.hole_index + 1])) then
    raise exception 'Et playoff-hull som har score, kan ikke byttes' using errcode = '55000';
  end if;

  perform set_config('dd18.playoff_write', 'on', true);
  update public.rounds set playoff_holes = p_holes where id = v_round.id;
  perform set_config('dd18.playoff_write', '', true);

  return jsonb_build_object('round_id', v_round.id, 'playoff_holes', to_jsonb(p_holes));
end;
$$;
revoke all on function public.playoff_set_holes(uuid, smallint[]) from public, anon;
grant execute on function public.playoff_set_holes(uuid, smallint[]) to authenticated;


-- ===========================================================================
-- 4. TAVLA OG TV: DE NYE FELTENE
-- ===========================================================================
-- tavla_data som i 036, med counts, points_table, hide_last_holes, kind, playoff_for og
-- playoff_holes på rundene. Playoff-runder på sesongens kvelder kommer med som før (kind skiller).
create or replace function public.tavla_data(p_season_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club uuid;
  v_events uuid[];
  v_rounds uuid[];
  v_courses uuid[];
begin
  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke sesongen' using errcode = 'P0002';
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = p_season_id;

  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r
   where r.event_id = any (v_events)
     and r.status in ('active', 'locked')
     and public.can_read_round(r.id);

  select coalesce(array_agg(c.id), '{}') into v_courses
    from public.courses c
   where c.id in (select r.course_id from public.rounds r where r.id = any (v_rounds))
     and (c.club_id is null or public.is_club_member(c.club_id));

  return jsonb_build_object(
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue, e.note
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, m.user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, m.avatar_path
          from public.club_members m where m.club_id = v_club) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               r.par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               c.confirmed_by, c.confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes, s.recorded_at, s.updated_by, s.updated_at
          from public.hole_scores s where s.round_id = any (v_rounds)) x)
  );
end;
$$;
revoke all on function public.tavla_data(uuid) from public, anon;
grant execute on function public.tavla_data(uuid) to authenticated;

-- tv_competition_data som i 043, med de nye feltene, playoff-rundene til turneringen, og uten
-- scorene på skjulte hull før runden er låst. Fortsatt ingen ekte bruker-id.
create or replace function public.tv_competition_data(p_competition_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_rounds  uuid[];
  v_courses uuid[];
  v_profiles uuid[];
begin
  select * into v_comp from public.competitions c where c.id = p_competition_id;
  select coalesce(array_agg(x.id), '{}') into v_rounds from (
    select r.id
      from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
     where cr.competition_id = p_competition_id and r.status in ('active', 'locked')
    union
    select r.id from public.rounds r
     where r.playoff_for = p_competition_id and r.kind = 'playoff' and r.status in ('active', 'locked')) x;
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;
  select coalesce(array_agg(distinct x.id), '{}') into v_profiles from (
    select p.profile_id as id from public.competition_participants p where p.competition_id = p_competition_id and p.profile_id is not null
    union select rp.profile_id from public.round_participants rp where rp.round_id = any (v_rounds) and rp.profile_id is not null
    union select rr.profile_id from public.round_roster rr where rr.round_id = any (v_rounds) and rr.profile_id is not null) x;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind, 'status', v_comp.status,
                                      'season_id', null, 'club_id', v_comp.club_id, 'owner_id', null,
                                      'entry', v_comp.entry, 'rules', v_comp.rules, 'starts_on', v_comp.starts_on,
                                      'ends_on', v_comp.ends_on, 'is_main', v_comp.is_main,
                                      'requires_purchase', v_comp.requires_purchase, 'entitlement_id', null,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'participants', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.id, p.competition_id, p.member_id, md5(p_competition_id::text || p.profile_id::text)::uuid as profile_id, p.status
          from public.competition_participants p where p.competition_id = p_competition_id) x),
    'links', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select cr.competition_id, cr.round_id, cr.source
          from public.competition_rounds cr where cr.competition_id = p_competition_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               null::uuid as par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue, null::uuid as owner_id,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               (select e.event_date from public.events e where e.id = r.event_id) as event_date,
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s join public.rounds r on r.id = s.round_id
         where s.round_id = any (v_rounds)
           and (r.status = 'locked' or r.hide_last_holes = 0
                or s.hole_index < r.hole_count - least(r.hide_last_holes, r.hole_count))) x),
    'roster', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select rr.round_id, rr.player_id, rr.club_id, rr.display_name, md5(p_competition_id::text || rr.profile_id::text)::uuid as profile_id, rr.is_guest
          from public.round_roster rr where rr.round_id = any (v_rounds)) x),
    'round_participants', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select rp.id, rp.round_id, md5(p_competition_id::text || rp.profile_id::text)::uuid as profile_id, rp.display_name, rp.handicap_index
          from public.round_participants rp where rp.round_id = any (v_rounds)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, md5(p_competition_id::text || m.user_id::text)::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'profiles', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select md5(p_competition_id::text || p.id::text)::uuid as id, p.display_name, p.handicap_index, null::text as avatar_path
          from public.profiles p where p.id = any (v_profiles)) x),
    'cup_matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.competition_id, m.round_no, m.slot, m.player_a, m.player_b, m.winner, m.walkover, m.result, m.round_id
          from public.competition_matches m where m.competition_id = p_competition_id and v_comp.kind = 'cup') x)
  );
end;
$$;
revoke all on function public.tv_competition_data(uuid) from public, anon, authenticated;

-- tv_board_data som i 043, med de nye feltene og uten scorene på skjulte hull før runden er låst.
-- Den eneste funksjonen anon kan kalle (som før).
create or replace function public.tv_board_data(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  v_rounds  uuid[];
  v_courses uuid[];
begin
  select c.* into v_comp
    from public.tv_codes t join public.competitions c on c.id = t.competition_id
   where t.code = upper(btrim(coalesce(p_code, ''))) and t.revoked_at is null and t.expires_at > now();
  if v_comp.id is null then
    raise exception 'Fant ingen TV-visning for koden' using errcode = 'P0002';
  end if;
  if v_comp.season_id is null then
    return public.tv_competition_data(v_comp.id);
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = v_comp.season_id;
  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r where r.event_id = any (v_events) and r.status in ('active', 'locked');
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind,
                                      'status', v_comp.status, 'season_id', v_comp.season_id,
                                      'club_id', v_comp.club_id, 'rules', v_comp.rules,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, null::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               null::uuid as par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s join public.rounds r on r.id = s.round_id
         where s.round_id = any (v_rounds)
           and (r.status = 'locked' or r.hide_last_holes = 0
                or s.hole_index < r.hole_count - least(r.hide_last_holes, r.hole_count))) x)
  );
end;
$$;
revoke all on function public.tv_board_data(text) from public;
grant execute on function public.tv_board_data(text) to anon, authenticated;


-- ===========================================================================
-- KONTROLL (kjøres i transaksjonen; feiler hele fila hvis noe er galt)
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. De seks kolonnene med riktige standardverdier.
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'rounds'
         and ((column_name = 'counts' and column_default = 'true' and is_nullable = 'NO')
           or (column_name = 'points_table' and column_default is null and is_nullable = 'YES')
           or (column_name = 'hide_last_holes' and column_default = '0' and is_nullable = 'NO')
           or (column_name = 'kind' and column_default = '''normal''::text' and is_nullable = 'NO')
           or (column_name = 'playoff_for' and is_nullable = 'YES')
           or (column_name = 'playoff_holes' and is_nullable = 'YES'))) <> 6 then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Reglene på tabellen.
  if (select count(*) from pg_constraint where conrelid = 'public.rounds'::regclass and conname in
        ('rounds_playoff_for_fkey', 'rounds_kind_check', 'rounds_points_table_check',
         'rounds_hide_last_holes_check', 'rounds_playoff_for_kind', 'rounds_playoff_never_counts',
         'rounds_playoff_holes_check')) <> 7 then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. Indeksene: én aktiv per kveld og bølge gjelder bare vanlige runder; én aktiv playoff per turnering.
  if coalesce((select pg_get_indexdef(i.indexrelid) from pg_index i
                where i.indexrelid = 'public.rounds_one_active_per_event_wave'::regclass), '')
       not like '%kind = ''normal''%'
     or not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                     where c.relname = 'rounds_one_active_playoff' and i.indisunique) then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. Triggerne, koblingen og lesingen.
  if (select count(*) from pg_trigger where not tgisinternal
        and ((tgname = 'rounds_guard_kind' and tgrelid = 'public.rounds'::regclass)
          or (tgname = 'bets_guard_playoff' and tgrelid = 'public.bets'::regclass)
          or (tgname = 'competition_rounds_before_insert' and tgrelid = 'public.competition_rounds'::regclass))) <> 3
     or (select prosrc from pg_proc where oid = 'public.competition_rounds_before_insert()'::regprocedure)
          not like '%playoff%'
     or (select prosrc from pg_proc where oid = 'public.round_in_readable_competition(uuid)'::regprocedure)
          not like '%playoff_for%'
     or (select prosrc from pg_proc where oid = 'public.competition_auto_count_round(uuid)'::regprocedure)
          not like '%v_round.kind = ''playoff''%' then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. RPC-ene: authenticated kan, anon kan ikke. Hjelperne kan ingen kalle.
  if has_function_privilege('anon', 'public.create_playoff_round(uuid, uuid, uuid[], smallint[], uuid)', 'execute')
     or has_function_privilege('anon', 'public.playoff_set_holes(uuid, smallint[])', 'execute')
     or not has_function_privilege('authenticated', 'public.create_playoff_round(uuid, uuid, uuid[], smallint[], uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.playoff_set_holes(uuid, smallint[])', 'execute')
     or has_function_privilege('authenticated', 'private.playoff_can_manage(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.playoff_entrant(uuid, uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.playoff_check_holes(smallint[], smallint)', 'execute') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Alle funksjonene her er security definer med tom search_path.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'create_playoff_round'), ('public', 'playoff_set_holes'),
                                               ('public', 'tavla_data'), ('public', 'tv_board_data'),
                                               ('public', 'tv_competition_data'), ('public', 'round_in_readable_competition'),
                                               ('public', 'competition_rounds_before_insert'),
                                               ('public', 'competition_auto_count_round'),
                                               ('private', 'rounds_guard_kind'), ('private', 'bets_guard_playoff'),
                                               ('private', 'playoff_can_manage'), ('private', 'playoff_entrant'),
                                               ('private', 'playoff_check_holes'))
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig)))) then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Tavla og TV sender de nye feltene.
  if (select count(*) from pg_proc where oid in ('public.tavla_data(uuid)'::regprocedure,
                                                 'public.tv_board_data(text)'::regprocedure,
                                                 'public.tv_competition_data(uuid)'::regprocedure)
        and prosrc like '%r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes%') <> 3 then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. TV-rettighetene som i 043: tv_board_data for anon, tv_competition_data for ingen.
  if not has_function_privilege('anon', 'public.tv_board_data(text)', 'execute')
     or has_function_privilege('anon', 'public.tv_competition_data(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.tv_competition_data(uuid)', 'execute')
     or has_function_privilege('anon', 'public.tavla_data(uuid)', 'execute') then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Ingen playoff er koblet som runde i en turnering.
  if exists (select 1 from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
              where r.kind = 'playoff') then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Hver playoff hører til en turnering og teller ikke (reglene holder for alle rader).
  if exists (select 1 from public.rounds r
              where (r.kind = 'playoff' and (r.playoff_for is null or r.counts or r.playoff_holes is null))
                 or (r.kind = 'normal' and (r.playoff_for is not null or r.playoff_holes is not null))) then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '047 kontroll feilet:%', v_fail;
  end if;
  raise notice '047 kontroll: 10 av 10 (runder: %, som ikke teller: %, med poengtabell: %, playoff: %)',
    (select count(*) from public.rounds), (select count(*) from public.rounds where not counts),
    (select count(*) from public.rounds where points_table is not null),
    (select count(*) from public.rounds where kind = 'playoff');
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (før appen har laget playoff-runder eller satt feltene; sletter playoffene)
-- ===========================================================================
-- begin;
-- delete from public.rounds where kind = 'playoff';
-- drop function if exists public.create_playoff_round(uuid, uuid, uuid[], smallint[], uuid);
-- drop function if exists public.playoff_set_holes(uuid, smallint[]);
-- drop function if exists private.playoff_can_manage(uuid);
-- drop function if exists private.playoff_entrant(uuid, uuid, uuid);
-- drop function if exists private.playoff_check_holes(smallint[], smallint);
-- drop trigger if exists rounds_guard_kind on public.rounds;
-- drop function if exists private.rounds_guard_kind();
-- drop trigger if exists bets_guard_playoff on public.bets;
-- drop function if exists private.bets_guard_playoff();
-- -- competition_rounds_before_insert som i 017 (uten playoff-linjene):
-- create or replace function public.competition_rounds_before_insert()
-- returns trigger language plpgsql security definer set search_path = '' as $$
-- begin
--   if auth.uid() is not null and pg_trigger_depth() = 1 then
--     new.added_by := auth.uid();
--   end if;
--   return new;
-- end;
-- $$;
-- revoke all on function public.competition_rounds_before_insert() from public, anon, authenticated;
-- -- round_in_readable_competition som før (bare competition_rounds):
-- create or replace function public.round_in_readable_competition(p_round_id uuid)
-- returns boolean language sql stable security definer set search_path = '' as $$
--   select exists (select 1 from public.competition_rounds cr
--                   where cr.round_id = p_round_id and public.can_read_competition(cr.competition_id));
-- $$;
-- revoke all on function public.round_in_readable_competition(uuid) from public, anon;
-- grant execute on function public.round_in_readable_competition(uuid) to authenticated;
-- -- tavla_data: kjør 036 på nytt. tv_competition_data og tv_board_data: kjør 043 på nytt.
-- -- competition_auto_count_round: kjør funksjonen fra 042 på nytt.
-- drop index if exists public.rounds_one_active_playoff;
-- drop index if exists public.rounds_playoff_for_idx;
-- drop index if exists public.rounds_one_active_per_event_wave;
-- create unique index rounds_one_active_per_event_wave on public.rounds (event_id, wave_no)
--   where status = 'active' and event_id is not null;
-- alter table public.rounds
--   drop constraint if exists rounds_playoff_holes_check,
--   drop constraint if exists rounds_playoff_never_counts,
--   drop constraint if exists rounds_playoff_for_kind,
--   drop constraint if exists rounds_hide_last_holes_check,
--   drop constraint if exists rounds_points_table_check,
--   drop constraint if exists rounds_kind_check,
--   drop constraint if exists rounds_playoff_for_fkey;
-- alter table public.rounds
--   drop column if exists playoff_holes, drop column if exists playoff_for, drop column if exists kind,
--   drop column if exists hide_last_holes, drop column if exists points_table, drop column if exists counts;
-- commit;
