-- 048: formater, flere konkurranser på samme runde og øyeblikksbildet ved start
-- (gjennomføringsplanen steg 7). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–047 og 049–051 (044_roller: private.has_club_right; 047: rounds.kind, playoff_for,
-- tavla_data og TV-funksjonene slik de er nå; 049: previous_round_setup). Prøvd lokalt
-- (sql/lokal/048_prove.sql).
--
-- Motoren er merget (#74, se Packages/GolfgutuCore/REGELSETT.md, «Formene fra steg 7»): to akser
-- (TeamForm og ScoringMethod), Amerikaner og Københavner, skins som form, lag mot lag (RyderCup),
-- flere konkurranser på samme runde (RoundCompetitions) og øyeblikksbildet ved start (FrozenRound).
-- Denne fila er lagringen.
--
-- Hva fila gjør:
--   1. Ny tabell round_competitions (id, round_id, name, is_main, format_version, config,
--      sort_order, created_by, created_at, updated_at): flere konkurranser på samme runde.
--      Hvorfor ikke round_games (020): et spill der er et nullsumspill om poeng med egne deltakere
--      (seat 1–8, side), markeringer og oppgjør (round_game_results), og kind er låst til fem
--      spill. En konkurranse er et resultat regnet fra de samme hullscorene (stableford,
--      bestball, skins, Amerikaner …), uten oppgjør og ofte med alle i runden. Å blande dem ville
--      gitt kolonner som bare gjelder den ene sorten og endret 020-reglene (kind, seat, settle).
--      config er motorens RoundCompetition uten id (id er radens id):
--        form        katalogens form-id (Round.gameType, samme mønster som rounds.format)
--        teamForm    {"type": "individual"} / {"type": "pairs", "pairs": "fourball"} / …
--        scoring     {"type": "stableford", "net": true} / {"type": "skins"} / …
--        entrants    [[spiller-id, …], …]  (lag eller grupper; utelatt: hver for seg / alle)
--        holes       {"first": 0, "last": 8}  (0-basert, inkludert; utelatt: alle)
--        allowance   0–1 (utelatt: 1; ikke lov på hovedkonkurransen, se under)
--      format_version 1 godtar bare disse nøklene (ingen fritekst, så TV-en ikke kan få
--      personopplysninger via config). Spiller-id-ene er rundens spillere (round_players.member_id),
--      som Tavla og TV allerede har. Høyst 16 kB per config og 10 konkurranser per runde.
--      Hovedkonkurransen (is_main, høyst én per runde, unik indeks) speiler rounds.format begge veier:
--        * rounds.format endres (også fra gamle bygg) → hovedkonkurransens config.form blir den nye
--          formen, og teamForm/scoring tas bort (de ville vært feil; appen leser aksene fra formen,
--          CompetitionForm.axes);
--        * hovedkonkurransen lagres eller blir hoved → rounds.format = config.form;
--        * mangler config.form på hovedkonkurransen, fylles den med rounds.format.
--      Hovedkonkurransen bruker rundens andel (rounds.handicap_allowance), så allowance er ikke lov
--      der. En runde uten rader har rounds.format som eneste (underforståtte) hovedkonkurranse,
--      slik alle runder er i dag. Ingen rader lages for rundene som finnes.
--      Skriving bare via round_competitions_set(runde, liste) (hele lista i én transaksjon, rader
--      med id beholdes, rader som mangler slettes): den som kan sette opp runden
--      (is_round_organizer: rettigheten rounds, eieren av en løs runde eller arrangør i staben),
--      ikke i en låst runde. Lesing: som round_games (can_read_round). Realtime som round_games, og
--      kringkasting på round:<id> (040).
--   2. Øyeblikksbildet ved start. rounds får
--        rules_snapshot  jsonb  regelsettet slik det var da runden startet: turneringen bak
--                               playoffen, ellers kveldens turnering (events.competition_id), ellers
--                               kveldens sesong (seasons.rules), ellers den ene turneringen runden er
--                               koblet til (competition_rounds; ingen eller flere gir null)
--        holes_snapshot  jsonb  {"holes": [{hole, par, cardIndex, meters, strokeIndex}, …],
--                                "from": "tee"|"course"|null, course_id, tee_id, first_hole}
--                               for alle hullene i runden, også egne baner og simulator uten bane.
--                               Nøklene i hvert hull er motorens PlayedHole (Round.courseHoles()):
--                               rundens egne hull (round_holes) går foran, så teens hull (når teen
--                               har hull, som 030), så banens hull (hentede baner som 030; egne
--                               baner bare med 9 eller 18 sammenhengende hull, som appen),
--                               cardIndex = indeksen (mangler: hullnummeret i runden), strokeIndex
--                               = rangen blant hullene som spilles. par er null når ingen kilde har
--                               par; da bruker appen Course.defaultPar som i dag. hole er nummeret på
--                               kortet (first_hole + i)
--        snapshot_at     timestamptz
--        snapshot_source text   'start' | 'refresh' | 'backfill'
--      Trigger rounds_snapshot (before insert/update): fryses når runden går fra kladd til aktiv
--      (alle veier: start_round, playoffen, vanlig update, løse runder) og er tom i kladd. Etterpå
--      beholdes verdiene uansett hva en update setter, så endringer i regelsettet, banen, teen
--      eller rundens hull ikke endrer en startet runde. Eneste unntak er
--      round_snapshot_refresh(runde) («Oppdater øyeblikksbildet»): den som kan sette opp runden,
--      bare i en aktiv (ikke låst) runde, f.eks. når par eller indeks var feil på banen eller
--      regelsettet ble rettet etter start. Trengs fordi rundens egne hull (round_holes) og
--      regelsettet kan rettes mens runden går. En låst runde endres aldri.
--      Resten av FrozenRound ligger der fra før: spillehandicapet (round_players.playing_handicap,
--      frosset ved start), formen (rounds.format) og lagene (round_players.team_no).
--   3. Etterfylling: aktive og låste runder uten øyeblikksbilde får det fra dagens data
--      (snapshot_source = 'backfill'). De er REKONSTRUERT: regelsettet og banen slik de er da 048
--      kjøres, ikke slik de var da runden ble spilt. updated_at og kringkastingen røres ikke.
--   4. Lag mot lag (Ryder Cup): round_players.side smallint null (1 eller 2). team_no er fortsatt
--      laget/paret i runden (1–20); motoren (RyderCup.evaluate(rounds:sides:…), RyderCup.pairings)
--      tar sidene som eget kart (spiller → 1/2) ved siden av lagene, så team_no kan ikke bære
--      begge (å kode side i lagnummeret, f.eks. oddetall/partall, ville gjort MatchPlanner og
--      Tavla feil for dagens runder). set_round_setup skriver side bare for spillere der elementet
--      har nøkkelen "side", så et gammelt bygg ikke visker den ut, og avviser to sider på samme
--      lag. Løse runder setter side som team_no (update på round_players). Sidene for en hel
--      Ryder Cup er sidene i hver runde (appen slår dem sammen).
--   5. tavla_data, tv_board_data og tv_competition_data sender rules_snapshot, holes_snapshot,
--      snapshot_at og snapshot_source på rundene, side på spillerne og round_competitions
--      (id, round_id, name, is_main, format_version, config, sort_order; ikke created_by).
--      previous_round_setup («Samme som sist») sender side på spillerne og competitions (navn,
--      hoved, versjon, config, rekkefølge), så appen kan kopiere konkurransene.
--
-- Mønsteret fra 001–051: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst. start_round er ikke endret (triggeren gjør
-- jobben).
--
-- Appen, web-admin og TV-en må (ikke i denne fila):
--   * runde-oppsett: lista over konkurranser (navn, form eller akser, lag/grupper, hull, andel)
--     lagret med round_competitions_set; hovedkonkurransen er formen som før (rounds.format);
--   * Tavla, føring og TV: regne konkurransene med RoundCompetitions.evaluate fra
--     FrozenRound (rules_snapshot → ruleset, holes_snapshot.holes → holes, playing_handicap,
--     format, team_no), og falle tilbake til dagens oppslag når snapshot_source er null (kladd)
--     eller rules_snapshot er null (runde uten turnering);
--   * vise at et øyeblikksbilde er rekonstruert (snapshot_source = 'backfill') der det betyr noe,
--     og «Oppdater øyeblikksbildet» for arrangøren i en aktiv runde (round_snapshot_refresh);
--     kalle den etter at rundens hull (par/indeks) er rettet mens runden går;
--   * lag mot lag: side i set_round_setup (nøkkelen "side" per spiller), RyderCup med sidene;
--   * «Samme som sist»: kopiere competitions (spiller-id-ene i entrants er fra forrige runde) og
--     side; rundemaler (049) kan ta med competitions i payload (ingen SQL-endring);
--   * web-admin: det samme.

begin;


-- ===========================================================================
-- 1. ROUNDS: ØYEBLIKKSBILDET
-- ===========================================================================
alter table public.rounds
  add column if not exists rules_snapshot  jsonb,
  add column if not exists holes_snapshot  jsonb,
  add column if not exists snapshot_at     timestamptz,
  add column if not exists snapshot_source text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'rounds_rules_snapshot_shape') then
    alter table public.rounds add constraint rounds_rules_snapshot_shape
      check (rules_snapshot is null
             or (jsonb_typeof(rules_snapshot) = 'object' and octet_length(rules_snapshot::text) <= 65536));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_holes_snapshot_shape') then
    alter table public.rounds add constraint rounds_holes_snapshot_shape
      check (holes_snapshot is null
             or (jsonb_typeof(holes_snapshot) = 'object'
                 and jsonb_typeof(holes_snapshot -> 'holes') = 'array'
                 and octet_length(holes_snapshot::text) <= 16384));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_snapshot_source_check') then
    alter table public.rounds add constraint rounds_snapshot_source_check
      check (snapshot_source is null or snapshot_source in ('start', 'refresh', 'backfill'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rounds_snapshot_when') then
    alter table public.rounds add constraint rounds_snapshot_when
      check ((snapshot_source is null) = (snapshot_at is null)
             and (snapshot_source is not null or (rules_snapshot is null and holes_snapshot is null)));
  end if;
end $$;

comment on column public.rounds.rules_snapshot is
  'Regelsettet da runden startet (048). Endres bare av round_snapshot_refresh i en aktiv runde.';
comment on column public.rounds.holes_snapshot is
  'Hullene da runden startet, som motorens PlayedHole (048): {"holes": [{hole, par, cardIndex, meters, strokeIndex}], "from", course_id, tee_id, first_hole}.';
comment on column public.rounds.snapshot_source is
  'start (frosset ved start), refresh (round_snapshot_refresh) eller backfill (rekonstruert fra data da 048 ble kjørt).';


-- ===========================================================================
-- 2. ROUND_PLAYERS: SIDE (LAG MOT LAG)
-- ===========================================================================
alter table public.round_players add column if not exists side smallint;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'round_players_side_check') then
    alter table public.round_players add constraint round_players_side_check
      check (side is null or side in (1, 2));
  end if;
end $$;
comment on column public.round_players.side is
  'Lag mot lag (048): side 1 eller 2. team_no er laget/paret i runden.';


-- ===========================================================================
-- 3. ROUND_COMPETITIONS
-- ===========================================================================
create table if not exists public.round_competitions (
  id              uuid primary key default gen_random_uuid(),
  round_id        uuid not null references public.rounds(id) on delete cascade,
  name            text not null,
  is_main         boolean not null default false,
  format_version  integer not null default 1,
  config          jsonb not null default '{}'::jsonb,
  sort_order      smallint not null default 0,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint round_competitions_name_check
    check (char_length(name) between 1 and 60 and btrim(name) <> ''),
  constraint round_competitions_format_version_check check (format_version between 1 and 1000),
  constraint round_competitions_sort_order_check check (sort_order between 0 and 99),
  constraint round_competitions_config_shape
    check (jsonb_typeof(config) = 'object' and octet_length(config::text) <= 16384),
  constraint round_competitions_form_check
    check (config -> 'form' is null
           or (jsonb_typeof(config -> 'form') = 'string' and (config ->> 'form') ~ '^[a-z0-9-]{1,40}$')),
  constraint round_competitions_main_form
    check (not is_main or (config ->> 'form') is not null),
  constraint round_competitions_main_allowance
    check (not is_main or config -> 'allowance' is null)
);
comment on table public.round_competitions is
  'Konkurranser på samme runde (048), motorens RoundCompetition i config. Hovedkonkurransen speiler '
  'rounds.format. Skrives bare via round_competitions_set.';
create index if not exists round_competitions_round_idx on public.round_competitions (round_id, sort_order);
create unique index if not exists round_competitions_one_main on public.round_competitions (round_id) where is_main;

drop trigger if exists round_competitions_set_updated_at on public.round_competitions;
create trigger round_competitions_set_updated_at before update on public.round_competitions
  for each row execute function public.set_updated_at();

alter table public.round_competitions enable row level security;
drop policy if exists round_competitions_select on public.round_competitions;
create policy round_competitions_select on public.round_competitions
  for select to authenticated using (public.can_read_round(round_id));
revoke all on table public.round_competitions from public, anon, authenticated;
grant select on table public.round_competitions to authenticated;

-- Sanntid som round_games (Realtime-publikasjonen) og kringkasting som hole_scores (040).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public'
                        and tablename = 'round_competitions') then
    alter publication supabase_realtime add table public.round_competitions;
  end if;
end $$;
drop trigger if exists round_competitions_broadcast on public.round_competitions;
create trigger round_competitions_broadcast after insert or update or delete on public.round_competitions
  for each row execute function public.broadcast_round_change();


-- ===========================================================================
-- 4. HJELPERE
-- ===========================================================================

-- Regelsettet for runden nå: playoffens turnering, kveldens turnering, kveldens sesong, eller den
-- ene turneringen runden er koblet til.
create or replace function private.round_rules_now(p_round public.rounds)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select c.rules from public.competitions c where c.id = p_round.playoff_for),
    (select c.rules from public.events e join public.competitions c on c.id = e.competition_id
      where e.id = p_round.event_id),
    (select s.rules from public.events e join public.seasons s on s.id = e.season_id
      where e.id = p_round.event_id),
    (select case when count(*) = 1 then (array_agg(c.rules))[1] end
       from public.competition_rounds cr join public.competitions c on c.id = cr.competition_id
      where cr.round_id = p_round.id));
$$;
revoke all on function private.round_rules_now(public.rounds) from public, anon, authenticated;

-- Hullene for runden nå, som motorens Round.courseHoles().
create or replace function private.round_holes_now(p_round public.rounds)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fetched boolean := false;
  v_from    text;
  v_count   integer := 0;
  v_max     integer;
  v_offset  integer;
  v_holes   jsonb;
begin
  if p_round.course_id is not null then
    select c.source is not null into v_fetched from public.courses c where c.id = p_round.course_id;
    v_fetched := coalesce(v_fetched, false);
    if p_round.tee_id is not null
       and exists (select 1 from public.course_tee_holes h where h.tee_id = p_round.tee_id) then
      v_from := 'tee';
      select count(*) into v_count from public.course_tee_holes h where h.tee_id = p_round.tee_id;
    else
      select count(*), max(h.hole_number) into v_count, v_max
        from public.course_holes h where h.course_id = p_round.course_id;
      -- Hentede baner som 030 (alle radene); egne baner bare med et helt sett (appen).
      if v_count > 0 and (v_fetched or (v_count in (9, 18) and v_max = v_count)) then
        v_from := 'course';
      else
        v_count := 0;
      end if;
    end if;
  end if;
  v_offset := case when p_round.first_hole = 10 and v_count = 18 then 9 else 0 end;

  with idx as (
    select i from generate_series(0, p_round.hole_count - 1) i
  ), src as (
    select h.hole_number - 1 - v_offset as i, h.par, h.stroke_index, h.length_m
      from public.course_tee_holes h where v_from = 'tee' and h.tee_id = p_round.tee_id
    union all
    select h.hole_number - 1 - v_offset, h.par, h.stroke_index, h.length_m
      from public.course_holes h where v_from = 'course' and h.course_id = p_round.course_id
  ), merged as (
    select idx.i,
           coalesce(rh.par, src.par)::int as par,
           coalesce(rh.stroke_index, src.stroke_index, idx.i + 1)::int as card,
           coalesce(rh.length_m, src.length_m)::int as meters
      from idx
      left join src on src.i = idx.i
      left join public.round_holes rh on rh.round_id = p_round.id and rh.hole_index = idx.i
  ), ranked as (
    select m.*, row_number() over (order by m.card, m.i) as si from merged m
  )
  select coalesce(jsonb_agg(jsonb_build_object('hole', p_round.first_hole + r.i, 'par', r.par,
                                               'cardIndex', r.card, 'meters', r.meters,
                                               'strokeIndex', r.si) order by r.i), '[]'::jsonb)
    into v_holes
    from ranked r;

  return jsonb_build_object('holes', v_holes, 'from', v_from, 'course_id', p_round.course_id,
                            'tee_id', p_round.tee_id, 'first_hole', p_round.first_hole);
end;
$$;
revoke all on function private.round_holes_now(public.rounds) from public, anon, authenticated;

-- Sjekker config for en konkurranse. Gir en norsk melding, eller null når den er i orden.
create or replace function private.round_competition_problem(
  p_config jsonb, p_version integer, p_hole_count integer, p_main boolean)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key   text;
  v_e     jsonb;
  v_x     jsonb;
  v_first numeric;
  v_last  numeric;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    return 'Oppsettet må være et objekt';
  end if;
  if octet_length(p_config::text) > 16384 then
    return 'Oppsettet er for stort (høyst 16 kB)';
  end if;
  if p_version is distinct from 1 then
    return 'Ukjent versjon av oppsettet. Oppdater appen.';
  end if;
  for v_key in select jsonb_object_keys(p_config) loop
    if v_key not in ('form', 'teamForm', 'scoring', 'entrants', 'holes', 'allowance') then
      return format('Ukjent felt i oppsettet: %s', left(v_key, 40));
    end if;
  end loop;
  if p_config ? 'form' and (jsonb_typeof(p_config -> 'form') <> 'string'
                            or (p_config ->> 'form') !~ '^[a-z0-9-]{1,40}$') then
    return 'Ugyldig form';
  end if;
  foreach v_key in array array['teamForm', 'scoring'] loop
    if p_config ? v_key and (jsonb_typeof(p_config -> v_key) <> 'object'
                             or jsonb_typeof(p_config -> v_key -> 'type') is distinct from 'string') then
      return format('%s må være et objekt med type', v_key);
    end if;
  end loop;
  if not p_main and not (p_config ? 'form' or (p_config ? 'teamForm' and p_config ? 'scoring')) then
    return 'Konkurransen mangler form (form, eller teamForm og scoring)';
  end if;
  if p_config ? 'entrants' then
    if jsonb_typeof(p_config -> 'entrants') <> 'array' or jsonb_array_length(p_config -> 'entrants') > 200 then
      return 'entrants må være en liste med høyst 200 lag eller grupper';
    end if;
    for v_e in select jsonb_array_elements(p_config -> 'entrants') loop
      if jsonb_typeof(v_e) <> 'array' or jsonb_array_length(v_e) not between 1 and 100 then
        return 'Hvert lag eller hver gruppe må være en liste med 1–100 spillere';
      end if;
      for v_x in select jsonb_array_elements(v_e) loop
        if jsonb_typeof(v_x) <> 'string'
           or (v_x #>> '{}') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
          return 'Spillerne i entrants må være spiller-id-er';
        end if;
      end loop;
    end loop;
  end if;
  if p_config ? 'holes' then
    if jsonb_typeof(p_config -> 'holes') <> 'object'
       or jsonb_typeof(p_config -> 'holes' -> 'first') is distinct from 'number'
       or jsonb_typeof(p_config -> 'holes' -> 'last') is distinct from 'number' then
      return 'holes må være {"first": n, "last": n}';
    end if;
    v_first := (p_config -> 'holes' ->> 'first')::numeric;
    v_last := (p_config -> 'holes' ->> 'last')::numeric;
    if v_first <> trunc(v_first) or v_last <> trunc(v_last)
       or v_first < 0 or v_first > v_last or v_last >= p_hole_count then
      return format('Hullene må være mellom 0 og %s, første før siste', p_hole_count - 1);
    end if;
  end if;
  if p_config ? 'allowance' then
    if p_main then
      return 'Hovedkonkurransen bruker rundens andel (handicap_allowance)';
    end if;
    if jsonb_typeof(p_config -> 'allowance') <> 'number'
       or (p_config ->> 'allowance')::numeric not between 0 and 1 then
      return 'Andelen må være mellom 0 og 1';
    end if;
  end if;
  return null;
end;
$$;
revoke all on function private.round_competition_problem(jsonb, integer, integer, boolean) from public, anon, authenticated;


-- ===========================================================================
-- 5. TRIGGERE
-- ===========================================================================

-- Øyeblikksbildet: fryses ved start, tomt i kladd, uendret ellers (unntak: refresh og etterfylling).
create or replace function private.rounds_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mode text := coalesce(current_setting('dd18.snapshot_write', true), '');
begin
  if new.status = 'draft' then
    new.rules_snapshot := null;
    new.holes_snapshot := null;
    new.snapshot_at := null;
    new.snapshot_source := null;
    return new;
  end if;

  if tg_op = 'INSERT' or old.status = 'draft' then
    new.rules_snapshot := private.round_rules_now(new);
    new.holes_snapshot := private.round_holes_now(new);
    new.snapshot_at := now();
    new.snapshot_source := 'start';
  elsif v_mode = 'refresh:' || new.id::text and old.status = 'active' then
    new.rules_snapshot := private.round_rules_now(new);
    new.holes_snapshot := private.round_holes_now(new);
    new.snapshot_at := now();
    new.snapshot_source := 'refresh';
  elsif v_mode = 'backfill' and old.snapshot_source is null then
    new.rules_snapshot := private.round_rules_now(new);
    new.holes_snapshot := private.round_holes_now(new);
    new.snapshot_at := now();
    new.snapshot_source := 'backfill';
  else
    new.rules_snapshot := old.rules_snapshot;
    new.holes_snapshot := old.holes_snapshot;
    new.snapshot_at := old.snapshot_at;
    new.snapshot_source := old.snapshot_source;
  end if;
  return new;
end;
$$;
revoke all on function private.rounds_snapshot() from public, anon, authenticated;

drop trigger if exists rounds_snapshot on public.rounds;
create trigger rounds_snapshot before insert or update on public.rounds
  for each row execute function private.rounds_snapshot();

-- rounds.format → hovedkonkurransen (gamle bygg endrer formen med update på rounds).
create or replace function private.rounds_format_to_main()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.round_competitions c
     set config = (c.config - 'teamForm' - 'scoring') || jsonb_build_object('form', new.format)
   where c.round_id = new.id and c.is_main
     and (c.config ->> 'form') is distinct from new.format;
  return null;
end;
$$;
revoke all on function private.rounds_format_to_main() from public, anon, authenticated;

drop trigger if exists rounds_format_to_main on public.rounds;
create trigger rounds_format_to_main after update of format on public.rounds
  for each row when (old.format is distinct from new.format)
  execute function private.rounds_format_to_main();

-- Hovedkonkurransen uten form får rundens form; runden kan ikke byttes.
create or replace function private.round_competitions_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.round_id is distinct from old.round_id then
    raise exception 'En konkurranse kan ikke flyttes til en annen runde' using errcode = '22023';
  end if;
  if new.is_main and (new.config ->> 'form') is null then
    new.config := new.config || jsonb_build_object(
      'form', (select r.format from public.rounds r where r.id = new.round_id));
  end if;
  return new;
end;
$$;
revoke all on function private.round_competitions_before_write() from public, anon, authenticated;

drop trigger if exists round_competitions_before_write on public.round_competitions;
create trigger round_competitions_before_write before insert or update on public.round_competitions
  for each row execute function private.round_competitions_before_write();

-- Hovedkonkurransen → rounds.format.
create or replace function private.round_competitions_main_to_round()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.rounds r
     set format = new.config ->> 'form'
   where r.id = new.round_id
     and r.format is distinct from (new.config ->> 'form');
  return null;
end;
$$;
revoke all on function private.round_competitions_main_to_round() from public, anon, authenticated;

drop trigger if exists round_competitions_main_to_round on public.round_competitions;
create trigger round_competitions_main_to_round after insert or update of is_main, config on public.round_competitions
  for each row when (new.is_main)
  execute function private.round_competitions_main_to_round();


-- ===========================================================================
-- 6. RPC-ER
-- ===========================================================================

-- Hele lista med konkurranser for runden. p_competitions:
--   [{"id": uuid|null, "name": "…", "is_main": bool, "format_version": 1, "config": {…},
--     "sort_order": 0–99 (utelatt: plassen i lista)}, …]
-- Rader med id beholdes og oppdateres, rader som ikke er med slettes, rader uten id lages.
create or replace function public.round_competitions_set(p_round_id uuid, p_competitions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   public.rounds%rowtype;
  v_e       jsonb;
  v_i       bigint;
  v_id      uuid;
  v_ids     uuid[] := '{}';
  v_name    text;
  v_main    boolean;
  v_mains   integer := 0;
  v_version integer;
  v_sort    integer;
  v_problem text;
  v_me      uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if v_round.id is null or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not public.is_round_organizer(p_round_id) then
    raise exception 'Bare den som setter opp runden, kan endre konkurransene' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er låst' using errcode = '55000';
  end if;
  if jsonb_typeof(p_competitions) is distinct from 'array' or jsonb_array_length(p_competitions) > 10 then
    raise exception 'Konkurransene må være en liste med høyst 10' using errcode = '22023';
  end if;

  -- Sjekk alt først.
  for v_e, v_i in select e, i from jsonb_array_elements(p_competitions) with ordinality t(e, i) loop
    if jsonb_typeof(v_e) <> 'object' then
      raise exception 'Konkurranse % er ikke et objekt', v_i using errcode = '22023';
    end if;
    begin
      v_id := nullif(v_e ->> 'id', '')::uuid;
      v_main := coalesce((v_e ->> 'is_main')::boolean, false);
      v_version := coalesce((v_e ->> 'format_version')::integer, 1);
      v_sort := coalesce((v_e ->> 'sort_order')::integer, v_i - 1);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Konkurranse % har en ugyldig verdi', v_i using errcode = '22023';
    end;
    if v_id is not null then
      if v_id = any (v_ids) then
        raise exception 'Samme konkurranse to ganger' using errcode = '22023';
      end if;
      if not exists (select 1 from public.round_competitions c where c.id = v_id and c.round_id = p_round_id) then
        raise exception 'Fant ikke konkurransen på runden' using errcode = '22023';
      end if;
      v_ids := v_ids || v_id;
    end if;
    v_name := btrim(coalesce(v_e ->> 'name', ''));
    if char_length(v_name) not between 1 and 60 then
      raise exception 'Navnet må ha 1–60 tegn' using errcode = '22023';
    end if;
    if v_sort not between 0 and 99 then
      raise exception 'sort_order må være 0–99' using errcode = '22023';
    end if;
    if v_main then
      v_mains := v_mains + 1;
    end if;
    v_problem := private.round_competition_problem(coalesce(v_e -> 'config', '{}'::jsonb), v_version,
                                                   v_round.hole_count, v_main);
    if v_problem is not null then
      raise exception '%', v_problem using errcode = '22023';
    end if;
  end loop;
  if v_mains > 1 then
    raise exception 'Bare én hovedkonkurranse per runde' using errcode = '22023';
  end if;

  delete from public.round_competitions c
   where c.round_id = p_round_id and not (c.id = any (v_ids));
  -- Hovedmerket tas av først, så den unike indeksen ikke stopper et bytte.
  update public.round_competitions c set is_main = false
   where c.round_id = p_round_id and c.is_main;

  for v_e, v_i in select e, i from jsonb_array_elements(p_competitions) with ordinality t(e, i) loop
    insert into public.round_competitions as c
           (id, round_id, name, is_main, format_version, config, sort_order, created_by)
    values (coalesce(nullif(v_e ->> 'id', '')::uuid, gen_random_uuid()), p_round_id, btrim(v_e ->> 'name'),
            coalesce((v_e ->> 'is_main')::boolean, false), coalesce((v_e ->> 'format_version')::integer, 1),
            coalesce(v_e -> 'config', '{}'::jsonb), coalesce((v_e ->> 'sort_order')::integer, v_i - 1), v_me)
    on conflict (id) do update
      set name = excluded.name,
          is_main = excluded.is_main,
          format_version = excluded.format_version,
          config = excluded.config,
          sort_order = excluded.sort_order;
  end loop;

  return coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'round_id', c.round_id, 'name', c.name,
                                        'is_main', c.is_main, 'format_version', c.format_version,
                                        'config', c.config, 'sort_order', c.sort_order)
                     order by c.sort_order, c.created_at, c.id)
      from public.round_competitions c where c.round_id = p_round_id), '[]'::jsonb);
end;
$$;
revoke all on function public.round_competitions_set(uuid, jsonb) from public, anon;
grant execute on function public.round_competitions_set(uuid, jsonb) to authenticated;

-- «Oppdater øyeblikksbildet»: regelsettet og hullene på nytt fra dagens data, bare i en aktiv runde.
create or replace function public.round_snapshot_refresh(p_round_id uuid)
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
  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if v_round.id is null or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not public.is_round_organizer(p_round_id) then
    raise exception 'Bare den som setter opp runden, kan oppdatere øyeblikksbildet' using errcode = '42501';
  end if;
  if v_round.status <> 'active' then
    raise exception 'Øyeblikksbildet kan bare oppdateres mens runden går' using errcode = '55000';
  end if;

  perform set_config('dd18.snapshot_write', 'refresh:' || p_round_id::text, true);
  update public.rounds r set snapshot_at = r.snapshot_at where r.id = p_round_id
  returning * into v_round;
  perform set_config('dd18.snapshot_write', '', true);

  return jsonb_build_object('rules_snapshot', v_round.rules_snapshot, 'holes_snapshot', v_round.holes_snapshot,
                            'snapshot_at', v_round.snapshot_at, 'snapshot_source', v_round.snapshot_source);
end;
$$;
revoke all on function public.round_snapshot_refresh(uuid) from public, anon;
grant execute on function public.round_snapshot_refresh(uuid) to authenticated;


-- ===========================================================================
-- 7. SET_ROUND_SETUP MED SIDE
-- ===========================================================================
-- Som i 044, med steg 4b (side). Alt annet er likt.
create or replace function public.set_round_setup(p_round_id uuid, p_players jsonb, p_matches jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_ids    uuid[];
  v_names  text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not private.has_club_right(v_round.club_id, 'rounds') then
    raise exception 'Bare en arrangør kan sette opp runden' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er låst' using errcode = '55000';
  end if;
  if jsonb_typeof(p_players) is distinct from 'array' then
    raise exception 'Spillerlista mangler' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_matches, '[]'::jsonb)) <> 'array' then
    raise exception 'Matchlista må være en liste' using errcode = '22023';
  end if;

  select coalesce(array_agg(x.member_id), '{}') into v_ids
  from jsonb_to_recordset(p_players) as x(member_id uuid);

  if exists (select 1 from unnest(v_ids) i where i is null) then
    raise exception 'member_id mangler' using errcode = '22023';
  end if;
  if cardinality(v_ids) <> (select count(distinct i) from unnest(v_ids) i) then
    raise exception 'Samme spiller to ganger' using errcode = '22023';
  end if;

  -- Ingen fjerning av spillere som har ført noe.
  select string_agg(m.display_name, ', ' order by m.display_name) into v_names
  from public.round_players rp
  join public.club_members m on m.id = rp.member_id
  where rp.round_id = p_round_id
    and not (rp.member_id = any(v_ids))
    and (   exists (select 1 from public.hole_scores s
                    where s.round_id = rp.round_id and s.member_id = rp.member_id)
         or exists (select 1 from public.side_claims c
                    where c.round_id = rp.round_id and c.member_id = rp.member_id));
  if v_names is not null then
    raise exception 'Kan ikke ta ut % – det er ført scorer eller sidepremier. Slett dem først.', v_names
      using errcode = '55000';
  end if;

  -- 1. Matchene peker på deltakere, så de går først.
  delete from public.round_matches where round_id = p_round_id;

  -- 2. Ta ut dem som ikke er med lenger.
  delete from public.round_players rp
   where rp.round_id = p_round_id and not (rp.member_id = any(v_ids));

  -- 3. Nullstill markørene først: den unike indeksen (én markør per bås)
  --    kan ikke utsettes, og et markørbytte i samme bås ville ellers kollidere.
  update public.round_players set is_marker = false
   where round_id = p_round_id and is_marker;

  -- 4. Skriv deltakerne.
  insert into public.round_players as rp
         (round_id, member_id, club_id, bay_no, is_marker, team_no, playing_handicap)
  select p_round_id, x.member_id, v_round.club_id, x.bay_no,
         coalesce(x.is_marker, false), x.team_no, x.playing_handicap
  from jsonb_to_recordset(p_players)
       as x(member_id uuid, bay_no smallint, is_marker boolean, team_no smallint,
            playing_handicap smallint)
  on conflict (round_id, member_id) do update
    set bay_no           = excluded.bay_no,
        is_marker        = excluded.is_marker,
        team_no          = excluded.team_no,
        playing_handicap = excluded.playing_handicap;


  -- 4b. Side for lag mot lag (048). Bare for elementer med nøkkelen "side", så et gammelt bygg
  --     (uten nøkkelen) ikke visker ut sidene. Spillerne på samme lag må være på samme side.
  if exists (select 1 from jsonb_array_elements(p_players) e where e ? 'side') then
    if exists (select 1 from jsonb_array_elements(p_players) e
                where e ? 'side' and jsonb_typeof(e -> 'side') <> 'null'
                  and (e ->> 'side') not in ('1', '2')) then
      raise exception 'Siden må være 1 eller 2' using errcode = '22023';
    end if;
    update public.round_players rp
       set side = (e ->> 'side')::smallint
      from jsonb_array_elements(p_players) e
     where rp.round_id = p_round_id
       and rp.member_id = (e ->> 'member_id')::uuid
       and e ? 'side';
    if exists (select 1 from public.round_players rp
                where rp.round_id = p_round_id and rp.team_no is not null
                group by rp.team_no
               having count(distinct rp.side) > 1 or count(rp.side) not in (0, count(*))) then
      raise exception 'Spillerne på samme lag må være på samme side' using errcode = '22023';
    end if;
  end if;

  -- 5. Matchene.
  insert into public.round_matches
         (round_id, match_no, player_a, player_b, player_c, team_a, team_b, result)
  select p_round_id, x.match_no, x.player_a, x.player_b, x.player_c, x.team_a, x.team_b, x.result
  from jsonb_to_recordset(coalesce(p_matches, '[]'::jsonb))
       as x(match_no smallint, player_a uuid, player_b uuid, player_c uuid,
            team_a smallint, team_b smallint, result text);

  return jsonb_build_object(
    'players', (select count(*) from public.round_players where round_id = p_round_id),
    'matches', (select count(*) from public.round_matches where round_id = p_round_id)
  );
end;
$$;
revoke all on function public.set_round_setup(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.set_round_setup(uuid, jsonb, jsonb) to authenticated, service_role;


-- ===========================================================================
-- 8. TAVLA OG TV: DE NYE FELTENE
-- ===========================================================================
-- Som i 047, med rules_snapshot, holes_snapshot, snapshot_at og snapshot_source på rundene, side
-- på spillerne og round_competitions (uten created_by). TV-funksjonene sender fortsatt ingen
-- bruker-id: config har bare form, akser, hull, andel og rundens spiller-id-er (som 'players').
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
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
               r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'round_competitions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.name, c.is_main, c.format_version, c.config, c.sort_order
          from public.round_competitions c where c.round_id = any (v_rounds)
         order by c.round_id, c.sort_order, c.created_at, c.id) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no, p.side
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
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
               r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'round_competitions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.name, c.is_main, c.format_version, c.config, c.sort_order
          from public.round_competitions c where c.round_id = any (v_rounds)
         order by c.round_id, c.sort_order, c.created_at, c.id) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no, p.side
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
               r.counts, r.points_table, r.hide_last_holes, r.kind, r.playoff_for, r.playoff_holes,
               r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'round_competitions', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.name, c.is_main, c.format_version, c.config, c.sort_order
          from public.round_competitions c where c.round_id = any (v_rounds)
         order by c.round_id, c.sort_order, c.created_at, c.id) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no, p.side
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
-- 9. «SAMME SOM SIST»
-- ===========================================================================
-- Som i 049, med side på spillerne og konkurransene (uten id; spiller-id-ene i entrants er fra
-- forrige runde, og appen kopierer dem som forslag).
create or replace function public.previous_round_setup(p_event_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_event public.events%rowtype;
  v_r     public.rounds%rowtype;
  v_date  date;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select e.* into v_event from public.events e where e.id = p_event_id;
  if v_event.id is null
     or not (public.is_club_member(v_event.club_id)
             or (v_event.competition_id is not null and public.can_read_competition(v_event.competition_id))) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if not (private.has_club_right(v_event.club_id, 'rounds')
          or (v_event.competition_id is not null
              and exists (select 1 from public.competition_staff s
                           where s.competition_id = v_event.competition_id
                             and s.profile_id = auth.uid() and s.role = 'organizer'))) then
    raise exception 'Bare den som setter opp runder, kan hente forrige oppsett' using errcode = '42501';
  end if;

  select r.* into v_r
    from public.rounds r
    join public.events e on e.id = r.event_id
   where e.club_id = v_event.club_id
     and e.competition_id is not distinct from v_event.competition_id
     and e.event_date <= v_event.event_date
     and r.kind = 'normal'
     and r.status in ('active', 'locked')
   order by e.event_date desc, r.round_no desc, coalesce(r.started_at, r.created_at) desc, r.id
   limit 1;
  if v_r.id is null then
    return null;
  end if;
  select e.event_date into v_date from public.events e where e.id = v_r.event_id;

  return jsonb_build_object(
    'round_id', v_r.id,
    'event_id', v_r.event_id,
    'event_date', v_date,
    'round_no', v_r.round_no,
    'name', v_r.name,
    'status', v_r.status,
    'course_id', v_r.course_id,
    'tee_id', v_r.tee_id,
    'hole_count', v_r.hole_count,
    'first_hole', v_r.first_hole,
    'format', v_r.format,
    'handicap_allowance', v_r.handicap_allowance,
    'external_handicap', v_r.external_handicap,
    'venue', v_r.venue,
    'ld_enabled', v_r.ld_enabled,
    'ld_hole_index', v_r.ld_hole_index,
    'kp_enabled', v_r.kp_enabled,
    'kp_hole_index', v_r.kp_hole_index,
    'weight', v_r.weight,
    'counts', v_r.counts,
    'points_table', v_r.points_table,
    'hide_last_holes', v_r.hide_last_holes,
    'wave_no', v_r.wave_no,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object('member_id', rp.member_id, 'bay_no', rp.bay_no,
                                          'is_marker', rp.is_marker, 'team_no', rp.team_no, 'side', rp.side,
                                          'seed_group', rp.seed_group)
                       order by rp.bay_no nulls last, rp.is_marker desc, m.display_name)
        from public.round_players rp
        join public.club_members m on m.id = rp.member_id
       where rp.round_id = v_r.id and m.status = 'active'), '[]'::jsonb),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object('match_no', rm.match_no, 'player_a', rm.player_a,
                                          'player_b', rm.player_b, 'player_c', rm.player_c,
                                          'team_a', rm.team_a, 'team_b', rm.team_b)
                       order by rm.match_no)
        from public.round_matches rm where rm.round_id = v_r.id), '[]'::jsonb),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object('kind', g.kind, 'settings', g.settings) order by g.created_at, g.id)
        from public.round_games g where g.round_id = v_r.id), '[]'::jsonb),
    'competitions', coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'is_main', c.is_main,
                                          'format_version', c.format_version, 'config', c.config,
                                          'sort_order', c.sort_order)
                       order by c.sort_order, c.created_at, c.id)
        from public.round_competitions c where c.round_id = v_r.id), '[]'::jsonb));
end;
$$;
revoke all on function public.previous_round_setup(uuid) from public, anon;
grant execute on function public.previous_round_setup(uuid) to authenticated;


-- ===========================================================================
-- 10. ETTERFYLLING (REKONSTRUERT)
-- ===========================================================================
-- Aktive og låste runder uten øyeblikksbilde får det fra dagens regelsett og bane
-- (snapshot_source = 'backfill'). updated_at og kringkastingen røres ikke. Idempotent: runder som
-- alt har et øyeblikksbilde, hoppes over.
alter table public.rounds disable trigger rounds_set_updated_at;
alter table public.rounds disable trigger rounds_broadcast;
do $$
begin
  perform set_config('dd18.snapshot_write', 'backfill', true);
  update public.rounds r set snapshot_source = r.snapshot_source
   where r.status <> 'draft' and r.snapshot_source is null;
  perform set_config('dd18.snapshot_write', '', true);
end $$;
alter table public.rounds enable trigger rounds_broadcast;
alter table public.rounds enable trigger rounds_set_updated_at;


-- ===========================================================================
-- KONTROLL (10 sjekker; feiler hele transaksjonen ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
begin
  -- 1. Kolonnene og tabellen finnes.
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'rounds'
         and column_name in ('rules_snapshot', 'holes_snapshot', 'snapshot_at', 'snapshot_source')) <> 4
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'round_players' and column_name = 'side')
     or to_regclass('public.round_competitions') is null then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Reglene: formen på øyeblikksbildet, side 1/2, konkurransene og én hoved per runde.
  if (select count(*) from pg_constraint where conrelid = 'public.rounds'::regclass
        and conname in ('rounds_rules_snapshot_shape', 'rounds_holes_snapshot_shape',
                        'rounds_snapshot_source_check', 'rounds_snapshot_when')) <> 4
     or not exists (select 1 from pg_constraint where conname = 'round_players_side_check')
     or (select count(*) from pg_constraint where conrelid = 'public.round_competitions'::regclass
          and conname in ('round_competitions_name_check', 'round_competitions_format_version_check',
                          'round_competitions_sort_order_check', 'round_competitions_config_shape',
                          'round_competitions_form_check', 'round_competitions_main_form',
                          'round_competitions_main_allowance')) <> 7
     or not exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
                     where c.relname = 'round_competitions_one_main' and i.indisunique) then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. RLS på, bare lesepolicy, authenticated har bare select, anon ingenting.
  if not (select relrowsecurity from pg_class where oid = 'public.round_competitions'::regclass)
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'round_competitions') <> 1
     or exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'round_competitions'
                 and cmd <> 'SELECT')
     or has_table_privilege('authenticated', 'public.round_competitions', 'insert, update, delete')
     or not has_table_privilege('authenticated', 'public.round_competitions', 'select')
     or has_table_privilege('anon', 'public.round_competitions', 'select') then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. RPC-ene: authenticated kan, anon kan ikke. Hjelperne kan ingen kalle.
  if has_function_privilege('anon', 'public.round_competitions_set(uuid, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.round_snapshot_refresh(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.round_competitions_set(uuid, jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.round_snapshot_refresh(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.round_rules_now(public.rounds)', 'execute')
     or has_function_privilege('authenticated', 'private.round_holes_now(public.rounds)', 'execute')
     or has_function_privilege('authenticated', 'private.round_competition_problem(jsonb, integer, integer, boolean)', 'execute')
     or has_function_privilege('authenticated', 'private.rounds_snapshot()', 'execute')
     or has_function_privilege('authenticated', 'private.rounds_format_to_main()', 'execute')
     or has_function_privilege('authenticated', 'private.round_competitions_before_write()', 'execute')
     or has_function_privilege('authenticated', 'private.round_competitions_main_to_round()', 'execute')
     or has_function_privilege('anon', 'public.previous_round_setup(uuid)', 'execute')
     or has_function_privilege('anon', 'public.tavla_data(uuid)', 'execute')
     or has_function_privilege('anon', 'public.tv_competition_data(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.tv_competition_data(uuid)', 'execute')
     or not has_function_privilege('anon', 'public.tv_board_data(text)', 'execute') then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Tom search_path overalt, security definer unntatt den rene sjekken.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'round_competitions_set'), ('public', 'round_snapshot_refresh'),
                                               ('public', 'set_round_setup'), ('public', 'tavla_data'),
                                               ('public', 'tv_competition_data'), ('public', 'tv_board_data'),
                                               ('public', 'previous_round_setup'),
                                               ('private', 'round_rules_now'), ('private', 'round_holes_now'),
                                               ('private', 'rounds_snapshot'), ('private', 'rounds_format_to_main'),
                                               ('private', 'round_competitions_before_write'),
                                               ('private', 'round_competitions_main_to_round'))
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig))))
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'private' and p.proname = 'round_competition_problem'
                       and 'search_path=""' = any (p.proconfig)) then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Triggerne.
  if (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O'
        and ((tgrelid = 'public.rounds'::regclass and tgname in ('rounds_snapshot', 'rounds_format_to_main',
                                                                  'rounds_set_updated_at', 'rounds_broadcast'))
          or (tgrelid = 'public.round_competitions'::regclass
              and tgname in ('round_competitions_before_write', 'round_competitions_main_to_round',
                             'round_competitions_broadcast', 'round_competitions_set_updated_at')))) <> 8 then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Hver startet runde har øyeblikksbildet med alle hullene; ingen kladd har det.
  if exists (select 1 from public.rounds r
              where (r.status = 'draft') <> (r.snapshot_source is null)
                 or (r.status <> 'draft' and jsonb_array_length(r.holes_snapshot -> 'holes') <> r.hole_count)) then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Hovedkonkurransen har samme form som runden.
  if exists (select 1 from public.round_competitions c join public.rounds r on r.id = c.round_id
              where c.is_main and (c.config ->> 'form') is distinct from r.format) then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Hver konkurranse har et gyldig oppsett.
  if exists (select 1 from public.round_competitions c join public.rounds r on r.id = c.round_id
              where private.round_competition_problem(c.config, c.format_version, r.hole_count, c.is_main) is not null) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Klientene får feltene: Tavla, TV, «Samme som sist» og side i set_round_setup.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('tavla_data', 'tv_competition_data', 'tv_board_data')
         and p.prosrc like '%round_competitions%' and p.prosrc like '%rules_snapshot%'
         and p.prosrc like '%p.side%') <> 3
     or (select prosrc from pg_proc where oid = 'public.previous_round_setup(uuid)'::regprocedure)
          not like '%''competitions''%'
     or (select prosrc from pg_proc where oid = 'public.set_round_setup(uuid, jsonb, jsonb)'::regprocedure)
          not like '%set side%' then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '048 kontroll feilet:%', v_fail;
  end if;
  raise notice '048 kontroll: 10 av 10 (startede runder: %, med regelsett: %, etterfylt: %, konkurranser: %)',
    (select count(*) from public.rounds where status <> 'draft'),
    (select count(*) from public.rounds where rules_snapshot is not null),
    (select count(*) from public.rounds where snapshot_source = 'backfill'),
    (select count(*) from public.round_competitions);
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (sletter konkurransene, sidene og øyeblikksbildene; rounds.format står)
-- ===========================================================================
-- begin;
-- -- previous_round_setup, tavla_data, tv_competition_data, tv_board_data og set_round_setup:
-- -- kjør definisjonene fra 049 (previous_round_setup), 047 (tavla og TV) og 044 (set_round_setup)
-- -- på nytt, i den rekkefølgen, før kolonnene under slettes.
-- drop function if exists public.round_snapshot_refresh(uuid);
-- drop function if exists public.round_competitions_set(uuid, jsonb);
-- drop trigger if exists rounds_format_to_main on public.rounds;
-- drop function if exists private.rounds_format_to_main();
-- drop trigger if exists rounds_snapshot on public.rounds;
-- drop function if exists private.rounds_snapshot();
-- drop table if exists public.round_competitions;
-- drop function if exists private.round_competitions_main_to_round();
-- drop function if exists private.round_competitions_before_write();
-- drop function if exists private.round_competition_problem(jsonb, integer, integer, boolean);
-- drop function if exists private.round_holes_now(public.rounds);
-- drop function if exists private.round_rules_now(public.rounds);
-- alter table public.round_players drop constraint if exists round_players_side_check;
-- alter table public.round_players drop column if exists side;
-- alter table public.rounds
--   drop constraint if exists rounds_snapshot_when,
--   drop constraint if exists rounds_snapshot_source_check,
--   drop constraint if exists rounds_holes_snapshot_shape,
--   drop constraint if exists rounds_rules_snapshot_shape;
-- alter table public.rounds
--   drop column if exists snapshot_source,
--   drop column if exists snapshot_at,
--   drop column if exists holes_snapshot,
--   drop column if exists rules_snapshot;
-- commit;
