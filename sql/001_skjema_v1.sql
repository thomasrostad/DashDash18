-- ===========================================================================
-- 001 – SKJEMA V1 (UTKAST, IKKE KJØRT)
-- ===========================================================================
-- Kjernen for fase 1–5 i den NYE, egne Supabase-databasen (Postgres 17):
-- klubb, medlemmer og roller, sesong med regelsett, kveld, påmelding, bane og
-- hull, runde med deltakere/bås/markør/lag/match, score og sidepremier.
--
-- Status: UTKAST til godkjenning (ROADMAP B5). Kjør ingenting før brukeren har
-- godkjent fila. Deretter: TEST først, kontrollspørringene nederst, så appen
-- mot test. Prod først etter ny godkjenning.
--
-- Navnestil: tabeller og kolonner på ENGELSK (snake_case), kommentarer på
-- norsk. Begrunnelse: CLAUDE.md sier at kodeidentifikatorer er engelske, og
-- supabase-swift mapper snake_case → camelCase rett inn i Swift-typene. Det
-- holder også æøå unna identifikatorer, og gjør at ingen forveksler det nye
-- skjemaet med PWA-ens (importen i fase 9 mapper eksplisitt). Verdier i
-- CHECK-lister er også engelske (se ordlista i sql/README.md).
--
-- Det som IKKE er med (kommer i senere migreringer, og er ikke designet bort):
-- penger, veddemål, bøter, tråd, tippekupong, aktivitetslogg, push-tokens,
-- Storage-bøtter. Alle henger naturlig på club_id / event_id / round_id /
-- club_members.id, som finnes her.
--
-- Rettighetsgrunnregler (detaljer ved hver tabell):
--   * anon får INGENTING: ingen tabellrettigheter og ingen funksjonsrettigheter.
--     (PWA-en lot anon beholde SELECT for å få tom liste i stedet for feil.
--     For native er en tydelig 401/42501 bedre enn en stille tom liste – det
--     var nettopp den stille tomme lista som ga 23505-feilen 17.09.2026.)
--   * innloggede leser bare data i klubber der de er AKTIVT medlem.
--   * kladdrunder (status = 'draft') og alt under dem ser bare arrangøren.
--   * skriving etter rolle: arrangøren skriver oppsett; spilleren skriver sin
--     egen påmelding, sine egne sidepremier og (etter kanFore) score.
--   * SECURITY DEFINER-funksjoner har `set search_path = ''` og fullt
--     kvalifiserte navn. `revoke … from public, anon` står ETTER hver
--     `create or replace` (replace gir standardrettighetene på nytt – PWA-ens
--     anon-felle, lært tre ganger).
--   * triggerfunksjoner: revoke fra public, anon OG authenticated (Postgres
--     sjekker EXECUTE når triggeren opprettes, ikke når den fyrer).
--
-- Alt kjøres i én transaksjon. Fila er idempotent der det er naturlig
-- (if not exists, create or replace, drop … if exists før create). Endres en
-- tabelldefinisjon etter første kjøring, må det skje i en ny migrering –
-- `create table if not exists` endrer ikke en tabell som finnes.
-- ===========================================================================

begin;


-- ===========================================================================
-- 0. FELLES
-- ===========================================================================

-- updated_at settes av serveren, aldri av klientens klokke (SPEC 5.2).
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;


-- ===========================================================================
-- 1. TABELLER
-- ===========================================================================
-- Klubb-id ligger på de «store» tabellene (club_members, seasons, events,
-- courses, rounds, round_players, signups, event_committee). Sammensatte
-- fremmednøkler (x_id, club_id) → parent(id, club_id) gjør det UMULIG å
-- blande klubber, uansett om skrivingen kommer fra appen, en RPC eller SQL
-- Editor. Tabellene under en runde (hull, score, match, sidepremie) arver
-- klubben via runden og via round_players.

-- --- clubs: klubben/gjengen -------------------------------------------------
create table if not exists public.clubs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  -- Invitasjonskoden. Den som har koden, kan se ledige navn i troppen og be
  -- om å bli med. 10 heksadesimale tegn fra gen_random_uuid() (40 tilfeldige
  -- bit). Arrangøren kan bytte den.
  join_code   text not null unique
              default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))
              check (join_code ~ '^[A-Z0-9]{6,16}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on table public.clubs is
  'En klubb/gjeng. Alt annet henger på en klubb. Opprettes via create_club().';


-- --- club_members: troppen ---------------------------------------------------
-- Én rad per spiller i klubben. user_id null = ledig tropprad som arrangøren
-- har lagt inn, og som kan «tas» med join_club(). Roller er flagg: alle er
-- spillere; arrangør og kasserer kommer i tillegg.
create table if not exists public.club_members (
  id              uuid primary key default gen_random_uuid(),
  club_id         uuid not null references public.clubs(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete set null,
  display_name    text not null check (char_length(btrim(display_name)) between 1 and 40),
  -- WHS-indeks. Pluss-handicap lagres negativt. null = ikke oppgitt.
  handicap_index  numeric(3,1) check (handicap_index between -10 and 54),
  -- Seedet gruppe. Hvilket tall gruppa gir, står i sesongens regelsett.
  seed_group      smallint check (seed_group between 1 and 9),
  is_organizer    boolean not null default false,
  is_treasurer    boolean not null default false,
  -- active: fullt medlem. pending: har bedt om å bli med, venter på
  -- arrangøren. archived: har sluttet (raden beholdes for historikken).
  status          text not null default 'active'
                  check (status in ('active', 'pending', 'archived')),
  -- Sti i en senere Storage-bøtte. Formatet låses når bøtta kommer.
  avatar_path     text check (avatar_path is null or char_length(avatar_path) <= 200),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint club_members_id_club_key unique (id, club_id),
  constraint club_members_roles_need_active
    check (status = 'active' or not (is_organizer or is_treasurer)),
  constraint club_members_pending_has_user
    check (status <> 'pending' or user_id is not null)
);
comment on table public.club_members is
  'Troppen. user_id null = ledig navn som kan tas. Roller som flagg. '
  'Slettes ikke når spilleren har runder (fremmednøkler), arkiveres i stedet.';

-- Én innlogging kan være med i flere klubber, men bare én gang per klubb.
create unique index if not exists club_members_one_row_per_user
  on public.club_members (club_id, user_id) where user_id is not null;
-- Navn er unike i troppen (det er navnet folk velger ved første innlogging).
create unique index if not exists club_members_unique_name
  on public.club_members (club_id, lower(btrim(display_name))) where status <> 'archived';
create index if not exists club_members_user_idx on public.club_members (user_id);
create index if not exists club_members_club_idx on public.club_members (club_id);


-- --- seasons: sesong med regelsett (B12) -----------------------------------
create table if not exists public.seasons (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  status      text not null default 'planned'
              check (status in ('planned', 'active', 'finished')),
  -- Regelsettet som jsonb med versjonsfelt. Innholdet eies av regelmotoren
  -- (Packages/GolfgutuCore) og valideres der; databasen sjekker bare at det
  -- er et objekt med et versjonsnummer ≥ 1 og at det ikke er absurd stort.
  -- Se README for begrunnelse og et eksempel.
  rules       jsonb not null default '{"version": 1}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint seasons_id_club_key unique (id, club_id),
  constraint seasons_rules_shape check (
    jsonb_typeof(rules) = 'object'
    and case when jsonb_typeof(rules -> 'version') = 'number'
             then (rules -> 'version')::numeric >= 1
             else false end
    and pg_column_size(rules) <= 65536
  )
);
comment on column public.seasons.rules is
  'Regelsettet (B12) som jsonb. Må ha "version" (tall ≥ 1). Resten tolkes av '
  'regelmotoren i appen, som også validerer. Golfgutu-oppsettet er en mal i appen.';

-- Høyst én aktiv sesong per klubb.
create unique index if not exists seasons_one_active_per_club
  on public.seasons (club_id) where status = 'active';
create index if not exists seasons_club_idx on public.seasons (club_id);


-- --- events: kveld i terminlista -------------------------------------------
create table if not exists public.events (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  season_id   uuid,
  event_date  date not null,
  start_time  time,                    -- lokal tid (Europe/Oslo), null = ikke satt
  venue       text check (venue is null or char_length(venue) <= 80),
  note        text check (note  is null or char_length(note)  <= 200),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint events_id_club_key unique (id, club_id),
  constraint events_one_per_date unique (club_id, event_date),
  constraint events_season_fk foreign key (season_id, club_id)
    references public.seasons (id, club_id) on delete restrict
);
comment on table public.events is
  'En kveld i terminlista. Kan ha flere runder. Påmelding gjelder kvelden. '
  '«Kvelden er ferdig» regnes ut (alle runder låst), lagres ikke.';
create index if not exists events_season_idx on public.events (season_id);


-- --- event_committee: sosialkomiteen for en kveld --------------------------
-- Egen tabell, ikke social_1/social_2: antallet er ikke låst.
create table if not exists public.event_committee (
  event_id    uuid not null,
  member_id   uuid not null,
  club_id     uuid not null,
  primary key (event_id, member_id),
  constraint event_committee_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint event_committee_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
create index if not exists event_committee_member_idx on public.event_committee (member_id);


-- --- signups: påmelding til en kveld ---------------------------------------
-- Ingen rad = ikke svart. yes = kommer, maybe = usikker, no = kommer ikke.
create table if not exists public.signups (
  event_id    uuid not null,
  member_id   uuid not null,
  club_id     uuid not null,
  status      text not null check (status in ('yes', 'maybe', 'no')),
  comment     text check (comment is null or char_length(comment) <= 80),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (event_id, member_id),
  constraint signups_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint signups_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
create index if not exists signups_member_idx on public.signups (member_id);


-- --- courses: banebiblioteket (per klubb) ----------------------------------
create table if not exists public.courses (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid not null references public.clubs(id) on delete cascade,
  name           text not null check (char_length(btrim(name)) between 1 and 80),
  external_name  text check (external_name is null or char_length(external_name) <= 80), -- navnet i simulatoren (Trackman)
  course_rating  numeric(4,1) check (course_rating between 20 and 90),
  slope_rating   smallint     check (slope_rating between 55 and 155),
  in_use         boolean not null default true,
  image_path     text check (image_path is null or char_length(image_path) <= 200),
  -- Sist bekreftet mot simulatorskjermen. null = aldri sjekket.
  confirmed_by   uuid references public.club_members(id) on delete set null,
  confirmed_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint courses_id_club_key unique (id, club_id)
);
comment on table public.courses is
  'Banebiblioteket. Banens par regnes fra course_holes, lagres ikke.';
create unique index if not exists courses_unique_name
  on public.courses (club_id, lower(btrim(name)));


-- --- course_holes: hullene på en bane --------------------------------------
create table if not exists public.course_holes (
  course_id     uuid not null references public.courses(id) on delete cascade,
  hole_number   smallint not null check (hole_number between 1 and 18),
  par           smallint not null check (par between 3 and 6),
  -- Indeksen på scorekortet (1–18). null = ukjent.
  stroke_index  smallint check (stroke_index between 1 and 18),
  length_m      smallint check (length_m between 50 and 700),
  primary key (course_id, hole_number),
  -- Utsatt til commit, så to hull kan bytte indeks i samme forespørsel
  -- (PWA-ens indeks-bytte.sql). Flere null er lov.
  constraint course_holes_unique_stroke_index unique (course_id, stroke_index)
    deferrable initially deferred
);


-- --- rounds: en runde på en kveld ------------------------------------------
create table if not exists public.rounds (
  id                  uuid primary key default gen_random_uuid(),
  club_id             uuid not null,
  event_id            uuid not null,
  course_id           uuid,
  round_no            smallint not null default 1 check (round_no between 1 and 9),
  name                text check (name is null or char_length(name) <= 60),
  -- draft = kladd (bare arrangøren ser den), active = pågår, locked = låst.
  status              text not null default 'draft'
                      check (status in ('draft', 'active', 'locked')),
  hole_count          smallint not null default 18 check (hole_count in (9, 18)),
  -- Første hull på banen: 1, eller 10 for «siste ni» på en 18-hullsbane.
  -- (PWA: hole_start 0/9.) Rundens egne hull er alltid 0..hole_count-1.
  first_hole          smallint not null default 1,
  tee_time            time,
  -- Konkurranseform (id fra KONKURRANSEFORMER i appen, f.eks. 'stableford').
  format              text not null default 'stableford'
                      check (format ~ '^[a-z0-9-]{1,40}$'),
  -- Handicapandel 0–1. 0 er gyldig (brutto).
  handicap_allowance  numeric(4,3) not null default 1
                      check (handicap_allowance between 0 and 1),
  -- true = simulatoren har allerede delt ut slagene (Trackman); scorene er netto.
  external_handicap   boolean not null default false,
  -- Rundevekt (PWA: multiplier). 0 = teller ikke.
  weight              numeric(4,2) not null default 1 check (weight between 0 and 5),
  ld_enabled          boolean not null default true,
  ld_hole_index       smallint check (ld_hole_index between 0 and 17),
  kp_enabled          boolean not null default true,
  kp_hole_index       smallint check (kp_hole_index between 0 and 17),
  -- Avkorting: regel + etter hvor mange hull + hvem/når.
  --   common  = bare hullene alle rakk teller (PWA: 'felles')
  --   net_par = uspilte hull gir netto par (PWA: 'nettopar')
  --   zero    = uspilte hull gir 0 poeng (PWA: strengen 'null')
  cut_rule            text check (cut_rule in ('common', 'net_par', 'zero')),
  cut_after           smallint,
  cut_by              uuid references public.club_members(id) on delete set null,
  cut_at              timestamptz,
  -- Par/indeks bekreftet mot simulatorskjermen før føring.
  par_confirmed_by    uuid references public.club_members(id) on delete set null,
  par_confirmed_at    timestamptz,
  started_at          timestamptz,
  locked_at           timestamptz,
  created_by          uuid references public.club_members(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint rounds_id_club_key unique (id, club_id),
  constraint rounds_unique_no_per_event unique (event_id, round_no),
  constraint rounds_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete restrict,
  constraint rounds_course_fk foreign key (course_id, club_id)
    references public.courses (id, club_id) on delete restrict,
  constraint rounds_first_hole_check
    check (first_hole = 1 or (first_hole = 10 and hole_count = 9)),
  constraint rounds_ld_hole_in_round check (ld_hole_index is null or ld_hole_index < hole_count),
  constraint rounds_kp_hole_in_round check (kp_hole_index is null or kp_hole_index < hole_count),
  -- En regel uten hulltall, eller et hulltall uten regel, er en halv beslutning.
  constraint rounds_cut_whole check (
    (cut_rule is null and cut_after is null)
    or (cut_rule is not null and cut_after between 1 and hole_count)
  )
);
comment on table public.rounds is
  'En runde. Rådata for oppsett; poeng regnes i appen fra hole_scores.';

-- Høyst én pågående runde per klubb (fase 4: «nummer to nektes mens første
-- går»). Brudd gir 23505 – appen må oversette den til en forståelig melding.
create unique index if not exists rounds_one_active_per_club
  on public.rounds (club_id) where status = 'active';
create index if not exists rounds_club_status_idx on public.rounds (club_id, status);
create index if not exists rounds_course_idx on public.rounds (course_id);


-- --- round_holes: overstyring av par/indeks/lengde for én runde -----------
-- Tom = banens hull gjelder. hole_index er rundens 0-baserte hull.
create table if not exists public.round_holes (
  round_id      uuid not null references public.rounds(id) on delete cascade,
  hole_index    smallint not null check (hole_index between 0 and 17),
  par           smallint check (par between 3 and 6),
  stroke_index  smallint check (stroke_index between 1 and 18),   -- kortets tall, ikke rang
  length_m      smallint check (length_m between 50 and 700),
  primary key (round_id, hole_index)
);


-- --- round_players: deltakere, bås, markør og lag --------------------------
-- Én rad per spiller i runden. Erstatter PWA-ens round_bays og round_teams:
-- bås og lag er egenskaper ved deltakelsen, og da kan hele oppsettet skrives
-- i én operasjon og aldri bli halvt.
create table if not exists public.round_players (
  round_id          uuid not null,
  member_id         uuid not null,
  club_id           uuid not null,
  -- Frosset ved start (se trigger rounds_after_update): indeks og seedet
  -- gruppe slik de var da runden startet. Senere endringer i troppen
  -- flytter ikke poeng i gamle runder.
  handicap_index    numeric(3,1) check (handicap_index between -10 and 54),
  seed_group        smallint check (seed_group between 1 and 9),
  -- Spillehandicapet appen regnet ut ved start, lagret bevisst som fasit for
  -- runden (se README «valg»). null = regnes fra feltene over.
  playing_handicap  smallint check (playing_handicap between -20 and 80),
  bay_no            smallint check (bay_no between 1 and 12),
  is_marker         boolean not null default false,
  team_no           smallint check (team_no between 1 and 20),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (round_id, member_id),
  constraint round_players_round_fk foreign key (round_id, club_id)
    references public.rounds (id, club_id) on delete cascade,
  constraint round_players_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete restrict,
  constraint round_players_marker_needs_bay check (not is_marker or bay_no is not null)
);
-- Nøyaktig én markør per bås.
create unique index if not exists round_players_one_marker_per_bay
  on public.round_players (round_id, bay_no) where is_marker;
create index if not exists round_players_member_idx on public.round_players (member_id);
create index if not exists round_players_bay_idx on public.round_players (round_id, bay_no);


-- --- round_matches: matcher (spillere eller lag, trekant) ------------------
create table if not exists public.round_matches (
  round_id   uuid not null references public.rounds(id) on delete cascade,
  match_no   smallint not null check (match_no between 1 and 40),
  player_a   uuid,
  player_b   uuid,
  player_c   uuid,           -- satt = trekant (avgjøres på poengsum)
  team_a     smallint check (team_a between 1 and 20),
  team_b     smallint check (team_b between 1 and 20),
  -- Manuelt resultat: a, b eller halved (PWA: A/B/H). null = regnes fra hull.
  result     text check (result in ('a', 'b', 'halved')),
  primary key (round_id, match_no),
  constraint round_matches_a_fk foreign key (round_id, player_a)
    references public.round_players (round_id, member_id) on delete cascade,
  constraint round_matches_b_fk foreign key (round_id, player_b)
    references public.round_players (round_id, member_id) on delete cascade,
  constraint round_matches_c_fk foreign key (round_id, player_c)
    references public.round_players (round_id, member_id) on delete cascade,
  constraint round_matches_sides check (
    (player_a is not null and player_b is not null and team_a is null and team_b is null
       and player_a <> player_b
       and (player_c is null or (player_c <> player_a and player_c <> player_b)))
    or
    (team_a is not null and team_b is not null and player_a is null and player_b is null
       and player_c is null and team_a <> team_b)
  ),
  constraint round_matches_no_manual_result_for_triangle
    check (player_c is null or result is null)
);


-- --- hole_scores: rådata, brutto per spiller per hull -----------------------
-- Ingen poengtabell: poeng regnes i appen fra disse radene (B2, CLAUDE.md).
-- Ingen rad = hullet er ikke ført.
create table if not exists public.hole_scores (
  round_id     uuid not null,
  member_id    uuid not null,
  hole_index   smallint not null check (hole_index between 0 and 17),
  strokes      smallint not null check (strokes between 1 and 20),
  -- Når slaget ble tastet på telefonen (klientens tid, for utboksen).
  -- Eldre innsendinger overskriver ikke nyere (se save_hole). Klemmes til
  -- serverens tid hvis den ligger i framtida.
  recorded_at  timestamptz not null default now(),
  -- Settes av trigger: hvem og når på serveren.
  updated_by   uuid references public.club_members(id) on delete set null,
  updated_at   timestamptz not null default now(),
  primary key (round_id, member_id, hole_index),
  -- Bare deltakere kan ha score.
  constraint hole_scores_player_fk foreign key (round_id, member_id)
    references public.round_players (round_id, member_id) on delete cascade
);


-- --- side_claims: longest drive og nærmest pinnen --------------------------
create table if not exists public.side_claims (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null,
  member_id   uuid not null,
  kind        text not null check (kind in ('drive', 'kp')),
  meters      numeric(5,1) not null check (meters > 0 and meters <= 500),
  hole_index  smallint check (hole_index between 0 and 17),
  created_by  uuid references public.club_members(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint side_claims_one_per_kind unique (round_id, member_id, kind),
  constraint side_claims_player_fk foreign key (round_id, member_id)
    references public.round_players (round_id, member_id) on delete cascade
);


-- --- updated_at-triggere ----------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['clubs', 'club_members', 'seasons', 'events', 'signups',
                           'courses', 'rounds', 'round_players', 'side_claims'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format('create trigger %I before update on public.%I '
                   'for each row execute function public.set_updated_at()',
                   t || '_set_updated_at', t);
  end loop;
end $$;


-- ===========================================================================
-- 2. HJELPEFUNKSJONER FOR RLS
-- ===========================================================================
-- SECURITY DEFINER: kjører som eieren og omgår RLS internt, ellers ville et
-- oppslag mot club_members inne i en policy PÅ club_members gå i løkke.
-- Policyene kaller dem som den som SPØR, så authenticated MÅ ha EXECUTE.
-- anon skal ikke ha det (revoke etter hver create or replace).

-- Min medlemsrad i klubben (bare aktiv), eller null.
create or replace function public.my_member_id(p_club_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.id
  from public.club_members m
  where m.club_id = p_club_id
    and m.user_id = auth.uid()
    and m.status = 'active';
$$;
revoke all on function public.my_member_id(uuid) from public, anon;
grant execute on function public.my_member_id(uuid) to authenticated;

-- Er jeg aktivt medlem av klubben?
create or replace function public.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.club_id = p_club_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;
revoke all on function public.is_club_member(uuid) from public, anon;
grant execute on function public.is_club_member(uuid) to authenticated;

-- Har jeg en rad i klubben i det hele tatt (også pending)? Brukes bare for å
-- la en som venter på godkjenning se klubbnavnet og sin egen rad.
create or replace function public.has_membership(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.club_id = p_club_id
      and m.user_id = auth.uid()
      and m.status in ('active', 'pending')
  );
$$;
revoke all on function public.has_membership(uuid) from public, anon;
grant execute on function public.has_membership(uuid) to authenticated;

-- Er jeg arrangør i klubben?
create or replace function public.is_club_organizer(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.club_id = p_club_id
      and m.user_id = auth.uid()
      and m.status = 'active'
      and m.is_organizer
  );
$$;
revoke all on function public.is_club_organizer(uuid) from public, anon;
grant execute on function public.is_club_organizer(uuid) to authenticated;

-- Er medlemsraden min (og aktiv)?
create or replace function public.owns_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.id = p_member_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  );
$$;
revoke all on function public.owns_member(uuid) from public, anon;
grant execute on function public.owns_member(uuid) to authenticated;

-- Kan jeg se runden? Medlem av klubben, og runden er ikke kladd – eller jeg
-- er arrangør. Gjelder også alt under runden.
create or replace function public.can_read_round(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   (r.status <> 'draft' and public.is_club_member(r.club_id))
           or public.is_club_organizer(r.club_id))
  );
$$;
revoke all on function public.can_read_round(uuid) from public, anon;
grant execute on function public.can_read_round(uuid) to authenticated;

-- Er jeg arrangør i rundens klubb?
create or replace function public.is_round_organizer(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and public.is_club_organizer(r.club_id)
  );
$$;
revoke all on function public.is_round_organizer(uuid) from public, anon;
grant execute on function public.is_round_organizer(uuid) to authenticated;

-- Pågår runden (status active)?
create or replace function public.round_is_active(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id and r.status = 'active'
  );
$$;
revoke all on function public.round_is_active(uuid) from public, anon;
grant execute on function public.round_is_active(uuid) to authenticated;

-- kanFore: kan JEG skrive score for spilleren p_member_id i runden?
--   arrangør                         : alltid, også i kladd og låst runde
--   runden pågår ikke (kladd/låst)   : ingen andre
--   spillerens bås har markør        : bare markøren (også for seg selv)
--   ellers (ingen bås / ingen markør): spilleren selv
-- Samme regel som kanFore() i PWA-en og hole_scores-policyen i
-- markor-og-avkorting.sql, med én innstramming: PWA-en tillot føring i en
-- ulåst kladd; her må runden være startet.
create or replace function public.can_score(p_round_id uuid, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_status  text;
  v_bay     smallint;
  v_marker  uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select r.club_id, r.status into v_club, v_status
  from public.rounds r where r.id = p_round_id;
  if v_club is null then
    return false;
  end if;

  if public.is_club_organizer(v_club) then
    return true;
  end if;

  if v_status <> 'active' then
    return false;
  end if;

  select rp.bay_no into v_bay
  from public.round_players rp
  where rp.round_id = p_round_id and rp.member_id = p_member_id;

  if v_bay is not null then
    select rp.member_id into v_marker
    from public.round_players rp
    where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
  end if;

  if v_marker is not null then
    return public.owns_member(v_marker);
  end if;

  return public.owns_member(p_member_id);
end;
$$;
revoke all on function public.can_score(uuid, uuid) from public, anon;
grant execute on function public.can_score(uuid, uuid) to authenticated;


-- ===========================================================================
-- 3. KOLONNEVAKTER OG ANDRE TRIGGERE
-- ===========================================================================
-- RLS virker på rader, ikke kolonner. Triggerne under vokter kolonnene en
-- spiller ikke skal kunne endre på sin egen rad.
--
-- auth.uid() is null slipper gjennom: det er SQL Editor og service_role
-- (import, nødutgang). anon kommer aldri hit, fordi anon ikke har noen
-- tabellrettigheter i det hele tatt (se avsnitt 5). NB: dette unntaket gjelder
-- bare triggere på tabeller. RPC-ene under har INGEN slik bakvei (PWA-ens
-- slett_runde-lærdom).

-- --- club_members ------------------------------------------------------------
create or replace function public.guard_club_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_organizer  boolean;
begin
  if v_uid is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.club_id is distinct from old.club_id then
    raise exception 'Et medlem kan ikke flyttes til en annen klubb'
      using errcode = '42501';
  end if;

  v_organizer := public.is_club_organizer(new.club_id);

  if tg_op = 'INSERT' then
    if v_organizer then
      return new;
    end if;
    -- Oppstart: den første arrangøren i en ny klubb (create_club).
    if new.is_organizer
       and new.user_id = v_uid
       and new.status = 'active'
       and not exists (select 1 from public.club_members m
                       where m.club_id = new.club_id and m.is_organizer) then
      return new;
    end if;
    -- Ellers: bare deg selv, som ventende, uten roller (join_club).
    if new.user_id is distinct from v_uid
       or new.status <> 'pending'
       or new.is_organizer or new.is_treasurer
       or new.seed_group is not null then
      raise exception 'Bare en arrangør kan legge til spillere eller gi roller'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- UPDATE
  if not v_organizer then
    if new.is_organizer is distinct from old.is_organizer
       or new.is_treasurer is distinct from old.is_treasurer then
      raise exception 'Bare en arrangør kan endre roller' using errcode = '42501';
    end if;
    if new.seed_group is distinct from old.seed_group then
      raise exception 'Bare en arrangør kan endre seedet gruppe' using errcode = '42501';
    end if;
    if new.status is distinct from old.status then
      raise exception 'Bare en arrangør kan godkjenne eller arkivere' using errcode = '42501';
    end if;
    -- user_id: uendret, eller en ledig rad som tas av deg selv (join_club).
    if new.user_id is distinct from old.user_id
       and not (old.user_id is null and new.user_id = v_uid) then
      raise exception 'Bare en arrangør kan koble en innlogging til eller fra et navn'
        using errcode = '42501';
    end if;
  end if;

  -- Siste arrangør kan ikke fjerne seg selv (eller bli fjernet), ellers er
  -- klubben låst ute. Nødutgang: SQL Editor.
  if old.is_organizer and old.status = 'active' and old.user_id is not null
     and (not new.is_organizer or new.status <> 'active' or new.user_id is null)
     and not exists (select 1 from public.club_members m
                     where m.club_id = old.club_id and m.id <> old.id
                       and m.is_organizer and m.status = 'active'
                       and m.user_id is not null) then
    raise exception 'Klubben må ha minst én arrangør' using errcode = '42501';
  end if;

  return new;
end;
$$;
revoke all on function public.guard_club_members() from public, anon, authenticated;

drop trigger if exists club_members_guard on public.club_members;
create trigger club_members_guard
  before insert or update on public.club_members
  for each row execute function public.guard_club_members();


-- --- rounds: tidsstempler, oppretter og statusoverganger -------------------
create or replace function public.rounds_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by is null then
      new.created_by := public.my_member_id(new.club_id);
    end if;
  else
    if old.status = 'locked' and new.status = 'draft' then
      raise exception 'En låst runde kan ikke bli kladd igjen' using errcode = '22023';
    end if;
  end if;

  if new.status = 'active' and new.started_at is null then
    new.started_at := now();
  end if;
  if new.status = 'locked' and new.locked_at is null then
    new.locked_at := now();
  elsif new.status <> 'locked' then
    new.locked_at := null;
  end if;

  return new;
end;
$$;
revoke all on function public.rounds_before_write() from public, anon, authenticated;

drop trigger if exists rounds_before_write on public.rounds;
create trigger rounds_before_write
  before insert or update on public.rounds
  for each row execute function public.rounds_before_write();

-- Når en kladd startes, fryses handicapene: indeks og seedet gruppe kopieres
-- fra troppen slik de er NÅ. (En kladd kan være laget dager før.)
create or replace function public.rounds_after_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'draft' and new.status = 'active' then
    update public.round_players rp
       set handicap_index = m.handicap_index,
           seed_group     = m.seed_group
      from public.club_members m
     where rp.round_id = new.id
       and m.id = rp.member_id;
  end if;
  return null;
end;
$$;
revoke all on function public.rounds_after_update() from public, anon, authenticated;

drop trigger if exists rounds_after_update on public.rounds;
create trigger rounds_after_update
  after update of status on public.rounds
  for each row execute function public.rounds_after_update();


-- --- round_players: handicap fra troppen når det ikke er gitt --------------
create or replace function public.round_players_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.handicap_index is null and new.seed_group is null then
    select m.handicap_index, m.seed_group
      into new.handicap_index, new.seed_group
      from public.club_members m
     where m.id = new.member_id;
  end if;
  return new;
end;
$$;
revoke all on function public.round_players_before_insert() from public, anon, authenticated;

drop trigger if exists round_players_before_insert on public.round_players;
create trigger round_players_before_insert
  before insert on public.round_players
  for each row execute function public.round_players_before_insert();


-- --- hole_scores: hull innenfor runden, hvem/når settes av serveren --------
create or replace function public.hole_scores_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club        uuid;
  v_hole_count  smallint;
begin
  select r.club_id, r.hole_count into v_club, v_hole_count
  from public.rounds r where r.id = new.round_id;

  if new.hole_index >= v_hole_count then
    raise exception 'Hull % finnes ikke i en runde på % hull', new.hole_index + 1, v_hole_count
      using errcode = '22023';
  end if;

  -- En klokke som går foran skal ikke kunne sperre senere rettinger.
  if new.recorded_at > now() then
    new.recorded_at := now();
  end if;

  new.updated_at := now();
  new.updated_by := public.my_member_id(v_club);   -- null fra SQL Editor
  return new;
end;
$$;
revoke all on function public.hole_scores_before_write() from public, anon, authenticated;

drop trigger if exists hole_scores_before_write on public.hole_scores;
create trigger hole_scores_before_write
  before insert or update on public.hole_scores
  for each row execute function public.hole_scores_before_write();


-- --- side_claims: hvem meldte inn -----------------------------------------
create or replace function public.side_claims_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  select r.club_id into v_club from public.rounds r where r.id = new.round_id;
  new.created_by := coalesce(public.my_member_id(v_club), new.created_by);
  return new;
end;
$$;
revoke all on function public.side_claims_before_write() from public, anon, authenticated;

drop trigger if exists side_claims_before_write on public.side_claims;
create trigger side_claims_before_write
  before insert or update on public.side_claims
  for each row execute function public.side_claims_before_write();


-- ===========================================================================
-- 4. RLS-POLICYER
-- ===========================================================================
-- Alle policyer gjelder bare rollen authenticated. Én policy per kommando,
-- og samme uttrykk i USING og WITH CHECK der begge finnes. (PWA-fella i
-- uinnloeste-rader.sql: flere permissive policyer ORes hver for seg på USING
-- og WITH CHECK, så en `with check (true)` i én policy åpner alle.)

alter table public.clubs            enable row level security;
alter table public.club_members     enable row level security;
alter table public.seasons          enable row level security;
alter table public.events           enable row level security;
alter table public.event_committee  enable row level security;
alter table public.signups          enable row level security;
alter table public.courses          enable row level security;
alter table public.course_holes     enable row level security;
alter table public.rounds           enable row level security;
alter table public.round_holes      enable row level security;
alter table public.round_players    enable row level security;
alter table public.round_matches    enable row level security;
alter table public.hole_scores      enable row level security;
alter table public.side_claims      enable row level security;

-- Rydd bort alle eksisterende policyer på disse tabellene, så fila kan
-- kjøres om igjen uten at gamle policyer blir stående og ORes inn.
do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('clubs', 'club_members', 'seasons', 'events', 'event_committee',
                        'signups', 'courses', 'course_holes', 'rounds', 'round_holes',
                        'round_players', 'round_matches', 'hole_scores', 'side_claims')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- --- clubs --------------------------------------------------------------
-- Lese: medlem (også ventende, så de ser hvilken klubb de venter på).
-- Opprette: bare via create_club(). Endre: arrangør. Slette: ingen (SQL Editor).
create policy clubs_select on public.clubs
  for select to authenticated
  using (public.has_membership(id));
create policy clubs_update on public.clubs
  for update to authenticated
  using (public.is_club_organizer(id))
  with check (public.is_club_organizer(id));

-- --- club_members ---------------------------------------------------------
-- Lese: aktive medlemmer ser hele troppen; alle ser sin egen rad.
-- Legge til: arrangør (ledige navn). Selvinnmelding går via join_club().
-- Endre: arrangør, eller egen rad (kolonnevakten stopper roller, seeding,
-- status og innloggingskobling). Slette: arrangør, bare ledige rader
-- (fremmednøklene stopper sletting av spillere med runder).
create policy club_members_select on public.club_members
  for select to authenticated
  using (public.is_club_member(club_id) or user_id = auth.uid());
create policy club_members_insert on public.club_members
  for insert to authenticated
  with check (public.is_club_organizer(club_id));
create policy club_members_update on public.club_members
  for update to authenticated
  using (public.is_club_organizer(club_id) or user_id = auth.uid())
  with check (public.is_club_organizer(club_id) or user_id = auth.uid());
create policy club_members_delete on public.club_members
  for delete to authenticated
  using (public.is_club_organizer(club_id) and user_id is null);

-- --- seasons, events, event_committee, courses: les medlem, skriv arrangør -
create policy seasons_select on public.seasons
  for select to authenticated using (public.is_club_member(club_id));
create policy seasons_insert on public.seasons
  for insert to authenticated with check (public.is_club_organizer(club_id));
create policy seasons_update on public.seasons
  for update to authenticated
  using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
create policy seasons_delete on public.seasons
  for delete to authenticated using (public.is_club_organizer(club_id));

create policy events_select on public.events
  for select to authenticated using (public.is_club_member(club_id));
create policy events_insert on public.events
  for insert to authenticated with check (public.is_club_organizer(club_id));
create policy events_update on public.events
  for update to authenticated
  using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
create policy events_delete on public.events
  for delete to authenticated using (public.is_club_organizer(club_id));

create policy event_committee_select on public.event_committee
  for select to authenticated using (public.is_club_member(club_id));
create policy event_committee_insert on public.event_committee
  for insert to authenticated with check (public.is_club_organizer(club_id));
create policy event_committee_update on public.event_committee
  for update to authenticated
  using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
create policy event_committee_delete on public.event_committee
  for delete to authenticated using (public.is_club_organizer(club_id));

create policy courses_select on public.courses
  for select to authenticated using (public.is_club_member(club_id));
create policy courses_insert on public.courses
  for insert to authenticated with check (public.is_club_organizer(club_id));
create policy courses_update on public.courses
  for update to authenticated
  using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
create policy courses_delete on public.courses
  for delete to authenticated using (public.is_club_organizer(club_id));

-- --- course_holes: via banens klubb ---------------------------------------
create policy course_holes_select on public.course_holes
  for select to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id and public.is_club_member(c.club_id)));
create policy course_holes_insert on public.course_holes
  for insert to authenticated
  with check (exists (select 1 from public.courses c
                      where c.id = course_id and public.is_club_organizer(c.club_id)));
create policy course_holes_update on public.course_holes
  for update to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id and public.is_club_organizer(c.club_id)))
  with check (exists (select 1 from public.courses c
                      where c.id = course_id and public.is_club_organizer(c.club_id)));
create policy course_holes_delete on public.course_holes
  for delete to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id and public.is_club_organizer(c.club_id)));

-- --- signups: egen rad, eller arrangør ------------------------------------
-- Upsert krever både INSERT og UPDATE. onConflict: event_id,member_id.
create policy signups_select on public.signups
  for select to authenticated using (public.is_club_member(club_id));
create policy signups_insert on public.signups
  for insert to authenticated
  with check (public.owns_member(member_id) or public.is_club_organizer(club_id));
create policy signups_update on public.signups
  for update to authenticated
  using (public.owns_member(member_id) or public.is_club_organizer(club_id))
  with check (public.owns_member(member_id) or public.is_club_organizer(club_id));
create policy signups_delete on public.signups
  for delete to authenticated
  using (public.owns_member(member_id) or public.is_club_organizer(club_id));

-- --- rounds ------------------------------------------------------------
-- Lese: medlemmer ser startede runder; kladder bare arrangør.
-- Skrive: arrangør. Slette: arrangør, aldri låst (delete_round() teller opp).
create policy rounds_select on public.rounds
  for select to authenticated
  using (   (status <> 'draft' and public.is_club_member(club_id))
         or public.is_club_organizer(club_id));
create policy rounds_insert on public.rounds
  for insert to authenticated with check (public.is_club_organizer(club_id));
create policy rounds_update on public.rounds
  for update to authenticated
  using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
create policy rounds_delete on public.rounds
  for delete to authenticated
  using (public.is_club_organizer(club_id) and status <> 'locked');

-- --- round_holes, round_players, round_matches: les via runden, skriv arrangør
create policy round_holes_select on public.round_holes
  for select to authenticated using (public.can_read_round(round_id));
create policy round_holes_insert on public.round_holes
  for insert to authenticated with check (public.is_round_organizer(round_id));
create policy round_holes_update on public.round_holes
  for update to authenticated
  using (public.is_round_organizer(round_id)) with check (public.is_round_organizer(round_id));
create policy round_holes_delete on public.round_holes
  for delete to authenticated using (public.is_round_organizer(round_id));

create policy round_players_select on public.round_players
  for select to authenticated using (public.can_read_round(round_id));
create policy round_players_insert on public.round_players
  for insert to authenticated with check (public.is_round_organizer(round_id));
create policy round_players_update on public.round_players
  for update to authenticated
  using (public.is_round_organizer(round_id)) with check (public.is_round_organizer(round_id));
create policy round_players_delete on public.round_players
  for delete to authenticated using (public.is_round_organizer(round_id));

create policy round_matches_select on public.round_matches
  for select to authenticated using (public.can_read_round(round_id));
create policy round_matches_insert on public.round_matches
  for insert to authenticated with check (public.is_round_organizer(round_id));
create policy round_matches_update on public.round_matches
  for update to authenticated
  using (public.is_round_organizer(round_id)) with check (public.is_round_organizer(round_id));
create policy round_matches_delete on public.round_matches
  for delete to authenticated using (public.is_round_organizer(round_id));

-- --- hole_scores: kanFore ---------------------------------------------------
create policy hole_scores_select on public.hole_scores
  for select to authenticated using (public.can_read_round(round_id));
create policy hole_scores_insert on public.hole_scores
  for insert to authenticated with check (public.can_score(round_id, member_id));
create policy hole_scores_update on public.hole_scores
  for update to authenticated
  using (public.can_score(round_id, member_id))
  with check (public.can_score(round_id, member_id));
create policy hole_scores_delete on public.hole_scores
  for delete to authenticated using (public.can_score(round_id, member_id));

-- --- side_claims: egen innmelding i pågående runde, eller arrangør ---------
create policy side_claims_select on public.side_claims
  for select to authenticated using (public.can_read_round(round_id));
create policy side_claims_insert on public.side_claims
  for insert to authenticated
  with check (public.is_round_organizer(round_id)
              or (public.owns_member(member_id) and public.round_is_active(round_id)));
create policy side_claims_update on public.side_claims
  for update to authenticated
  using (public.is_round_organizer(round_id)
         or (public.owns_member(member_id) and public.round_is_active(round_id)))
  with check (public.is_round_organizer(round_id)
              or (public.owns_member(member_id) and public.round_is_active(round_id)));
create policy side_claims_delete on public.side_claims
  for delete to authenticated
  using (public.is_round_organizer(round_id)
         or (public.owns_member(member_id) and public.round_is_active(round_id)));


-- ===========================================================================
-- 5. TABELLRETTIGHETER
-- ===========================================================================
-- Supabase gir anon og authenticated ALL på nye tabeller i public. Vi tar
-- alt fra begge, og gir authenticated bare de fire kommandoene. RLS avgjør
-- resten. anon får ingenting: et kall uten innlogging gir en feil (42501),
-- ikke en stille tom liste.
do $$
declare
  t text;
begin
  foreach t in array array['clubs', 'club_members', 'seasons', 'events', 'event_committee',
                           'signups', 'courses', 'course_holes', 'rounds', 'round_holes',
                           'round_players', 'round_matches', 'hole_scores', 'side_claims'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', t);
  end loop;
end $$;


-- ===========================================================================
-- 6. RPC-ER
-- ===========================================================================
-- Alle er SECURITY DEFINER og kjører i én transaksjon (et funksjonskall er
-- én setning). De omgår RLS, og bærer derfor sine egne sperrer, som bruker de
-- SAMME hjelpefunksjonene som policyene. Ingen bakvei for auth.uid() is null:
-- uten innlogging nektes alt (også fra SQL Editor – nødutgangen der er vanlig
-- SQL, se nederst).
-- Feilkoder: 42501 = ikke lov, P0002 = finnes ikke, 22023 = ugyldig input,
-- 55000 = feil tilstand (f.eks. låst runde).

-- --- create_club: ny klubb med deg som første arrangør ---------------------
create or replace function public.create_club(
  p_name            text,
  p_display_name    text,
  p_handicap_index  numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  insert into public.clubs (name) values (btrim(p_name))
  returning id into v_club;

  insert into public.club_members (club_id, user_id, display_name, handicap_index,
                                   is_organizer, status)
  values (v_club, auth.uid(), btrim(p_display_name), p_handicap_index, true, 'active');

  return v_club;
end;
$$;
revoke all on function public.create_club(text, text, numeric) from public, anon;
grant execute on function public.create_club(text, text, numeric) to authenticated;


-- --- club_preview: hva skjuler seg bak en invitasjonskode? ------------------
-- For en som ikke er medlem ennå: klubbnavnet og de LEDIGE navnene i troppen
-- (aldri handicap, roller eller tatte navn). null hvis koden ikke finnes.
create or replace function public.club_preview(p_join_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club  public.clubs%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_club from public.clubs c where c.join_code = upper(btrim(p_join_code));
  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'club_id', v_club.id,
    'name', v_club.name,
    'my_status', (select m.status from public.club_members m
                  where m.club_id = v_club.id and m.user_id = auth.uid()),
    'open_members', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'display_name', m.display_name)
                       order by m.display_name)
      from public.club_members m
      where m.club_id = v_club.id and m.user_id is null and m.status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;
revoke all on function public.club_preview(text) from public, anon;
grant execute on function public.club_preview(text) to authenticated;


-- --- join_club: ta et ledig navn, eller be om å bli med som ny -------------
-- Med p_member_id: tar den ledige raden (user_id null → deg). Aktiv med én gang.
-- Uten: lager en ny rad med status pending, som arrangøren godkjenner.
-- Idempotent: har du alt en rad i klubben, returneres den.
-- Returnerer {member_id, status}.
create or replace function public.join_club(
  p_join_code       text,
  p_member_id       uuid    default null,
  p_display_name    text    default null,
  p_handicap_index  numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_member  uuid;
  v_status  text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select c.id into v_club from public.clubs c where c.join_code = upper(btrim(p_join_code));
  if v_club is null then
    raise exception 'Fant ingen klubb med den koden' using errcode = 'P0002';
  end if;

  select m.id, m.status into v_member, v_status
  from public.club_members m
  where m.club_id = v_club and m.user_id = auth.uid();
  if v_member is not null then
    return jsonb_build_object('member_id', v_member, 'status', v_status);
  end if;

  if p_member_id is not null then
    update public.club_members m
       set user_id = auth.uid()
     where m.id = p_member_id
       and m.club_id = v_club
       and m.user_id is null
       and m.status = 'active'
    returning m.id, m.status into v_member, v_status;
    if v_member is null then
      raise exception 'Navnet er tatt eller finnes ikke lenger' using errcode = '55000';
    end if;
  else
    if p_display_name is null or btrim(p_display_name) = '' then
      raise exception 'Skriv inn et navn' using errcode = '22023';
    end if;
    insert into public.club_members (club_id, user_id, display_name, handicap_index, status)
    values (v_club, auth.uid(), btrim(p_display_name), p_handicap_index, 'pending')
    returning id, status into v_member, v_status;
  end if;

  return jsonb_build_object('member_id', v_member, 'status', v_status);
end;
$$;
revoke all on function public.join_club(text, uuid, text, numeric) from public, anon;
grant execute on function public.join_club(text, uuid, text, numeric) to authenticated;


-- --- save_hole: lagre ett hull for hele båsen, atomisk og idempotent -------
-- p_scores: [{"member_id": "<uuid>", "strokes": 5}, …]. strokes null = tøm hullet.
-- Lagform «per lag»: appen sender én rad per lagmedlem med samme slag.
-- p_recorded_at: når hullet ble tastet (utboksens tidsstempel). En innsending
-- som er ELDRE enn det som ligger lagret, hoppes over for den spilleren, så en
-- gammel melding fra utboksen ikke overskriver en nyere retting.
-- Alt eller ingenting: mangler retten for én spiller, lagres ingen.
-- Returnerer serverens rader for hullet etterpå (sjekk tilbake, SPEC 3.2).
create or replace function public.save_hole(
  p_round_id     uuid,
  p_hole_index   integer,
  p_scores       jsonb,
  p_recorded_at  timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round     public.rounds%rowtype;
  v_rec       timestamptz := least(coalesce(p_recorded_at, now()), now());
  v_entry     jsonb;
  v_member    uuid;
  v_members   uuid[] := '{}';
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id;
  if not found or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;

  if p_hole_index is null or p_hole_index < 0 or p_hole_index >= v_round.hole_count then
    raise exception 'Ugyldig hull' using errcode = '22023';
  end if;

  if jsonb_typeof(p_scores) is distinct from 'array' or jsonb_array_length(p_scores) = 0 then
    raise exception 'Ingen scorer å lagre' using errcode = '22023';
  end if;

  -- Sjekk alt før noe skrives.
  for v_entry in select value from jsonb_array_elements(p_scores) loop
    v_member := (v_entry ->> 'member_id')::uuid;
    if v_member is null then
      raise exception 'member_id mangler' using errcode = '22023';
    end if;
    if v_member = any(v_members) then
      raise exception 'Samme spiller to ganger i samme hull' using errcode = '22023';
    end if;
    v_members := v_members || v_member;

    if not exists (select 1 from public.round_players rp
                   where rp.round_id = p_round_id and rp.member_id = v_member) then
      raise exception 'Spilleren er ikke med i runden' using errcode = '22023';
    end if;
    if not public.can_score(p_round_id, v_member) then
      raise exception 'Du kan ikke føre for denne spilleren' using errcode = '42501';
    end if;
  end loop;

  -- Skriv.
  for v_entry in select value from jsonb_array_elements(p_scores) loop
    v_member := (v_entry ->> 'member_id')::uuid;

    if jsonb_typeof(v_entry -> 'strokes') is distinct from 'number' then
      delete from public.hole_scores s
       where s.round_id = p_round_id and s.member_id = v_member
         and s.hole_index = p_hole_index
         and s.recorded_at <= v_rec;
    else
      insert into public.hole_scores as s (round_id, member_id, hole_index, strokes, recorded_at)
      values (p_round_id, v_member, p_hole_index, (v_entry ->> 'strokes')::smallint, v_rec)
      on conflict (round_id, member_id, hole_index) do update
        set strokes = excluded.strokes,
            recorded_at = excluded.recorded_at
        where s.recorded_at <= excluded.recorded_at;
    end if;
  end loop;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'member_id', s.member_id, 'hole_index', s.hole_index, 'strokes', s.strokes,
             'recorded_at', s.recorded_at, 'updated_by', s.updated_by, 'updated_at', s.updated_at)
           order by s.member_id)
    from public.hole_scores s
    where s.round_id = p_round_id and s.hole_index = p_hole_index
      and s.member_id = any(v_members)
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.save_hole(uuid, integer, jsonb, timestamptz) from public, anon;
grant execute on function public.save_hole(uuid, integer, jsonb, timestamptz) to authenticated;


-- --- set_round_setup: deltakere, båser, markører, lag og matcher i ett -----
-- Erstatter PWA-ens slett-så-sett-inn i tre omganger (saveBaaser, saveLag,
-- saveMatcher). Kun arrangør, ikke låst runde.
-- p_players: [{"member_id", "bay_no", "is_marker", "team_no", "playing_handicap"}]
--   Hele lista: spillere som ikke er med, fjernes – men ALDRI en spiller som
--   har scorer eller sidepremier i runden (da feiler hele kallet).
--   Nye spillere får handicap fra troppen (trigger). Eksisterende beholder
--   sitt frosne handicap.
-- p_matches: [{"match_no", "player_a", "player_b", "player_c", "team_a", "team_b", "result"}]
--   Hele lista: matchene skrives på nytt.
-- Returnerer {players, matches} (antall rader etterpå).
create or replace function public.set_round_setup(
  p_round_id  uuid,
  p_players   jsonb,
  p_matches   jsonb default '[]'::jsonb
)
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
  if not public.is_club_organizer(v_round.club_id) then
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
grant execute on function public.set_round_setup(uuid, jsonb, jsonb) to authenticated;


-- --- delete_round: slett en ulåst runde med alt under ---------------------
-- Kun arrangør, aldri låst. Alt under runden har ON DELETE CASCADE, så det
-- kan ikke bli foreldreløse rader – slettingene her er for å telle opp hva
-- som forsvant, slik at appen kan si det. Veddemål (senere migrering) MÅ få
-- en ekte fremmednøkkel til rounds, ikke en id i jsonb (PWA-fella).
create or replace function public.delete_round(p_round_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round    public.rounds%rowtype;
  n_scores   integer;
  n_claims   integer;
  n_matches  integer;
  n_players  integer;
  n_holes    integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ingen runde å slette. Er den alt borte?' using errcode = 'P0002';
  end if;
  if not public.is_club_organizer(v_round.club_id) then
    raise exception 'Bare en arrangør kan slette en runde' using errcode = '42501';
  end if;
  if v_round.status = 'locked' then
    raise exception 'Runden er låst. En låst runde slettes ikke herfra.' using errcode = '55000';
  end if;

  delete from public.hole_scores   where round_id = p_round_id; get diagnostics n_scores  = row_count;
  delete from public.side_claims   where round_id = p_round_id; get diagnostics n_claims  = row_count;
  delete from public.round_matches where round_id = p_round_id; get diagnostics n_matches = row_count;
  delete from public.round_players where round_id = p_round_id; get diagnostics n_players = row_count;
  delete from public.round_holes   where round_id = p_round_id; get diagnostics n_holes   = row_count;
  delete from public.rounds        where id = p_round_id;

  return jsonb_build_object(
    'round_no', v_round.round_no,
    'name', v_round.name,
    'hole_scores', n_scores,
    'side_claims', n_claims,
    'matches', n_matches,
    'players', n_players,
    'round_holes', n_holes
  );
end;
$$;
revoke all on function public.delete_round(uuid) from public, anon;
grant execute on function public.delete_round(uuid) to authenticated;


-- ===========================================================================
-- 7. REALTIME
-- ===========================================================================
-- Tabellene appen lytter på under en kveld og i troppen. Realtime følger
-- SELECT-policyene, så kladder og andre klubber lekker ikke.
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  foreach t in array array['club_members', 'events', 'event_committee', 'signups',
                           'rounds', 'round_holes', 'round_players', 'round_matches',
                           'hole_scores', 'side_claims'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

commit;


-- ===========================================================================
-- KONTROLL (kjør etterpå, én blokk om gangen, i SQL Editor)
-- ===========================================================================
-- 1. Alle 14 tabellene finnes og har RLS på. Forventet: 14 rader, rls = true.
--
-- select c.relname as tabell, c.relrowsecurity as rls
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
--   and c.relname in ('clubs','club_members','seasons','events','event_committee',
--                     'signups','courses','course_holes','rounds','round_holes',
--                     'round_players','round_matches','hole_scores','side_claims')
-- order by 1;
--
-- 2. anon har INGEN tabellrettigheter. Forventet: 0 rader.
--
-- select table_name, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public' and grantee = 'anon'
--   and table_name in ('clubs','club_members','seasons','events','event_committee',
--                      'signups','courses','course_holes','rounds','round_holes',
--                      'round_players','round_matches','hole_scores','side_claims');
--
-- 3. Ingen policy gjelder anon eller public. Forventet: 0 rader.
--
-- select tablename, policyname, roles from pg_policies
-- where schemaname = 'public' and not (roles = '{authenticated}');
--
-- 4. Funksjonsrettigheter. Forventet: anon_kan = false på ALLE.
--    auth_kan = true på hjelpere og RPC-er, false på triggerfunksjonene.
--    definer = true på alt unntatt set_updated_at.
--
-- select p.proname as funksjon,
--        p.prosecdef as definer,
--        has_function_privilege('anon',          p.oid, 'execute') as anon_kan,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--        p.proconfig as innstillinger
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('set_updated_at','my_member_id','is_club_member','has_membership',
--                     'is_club_organizer','owns_member','can_read_round','is_round_organizer',
--                     'round_is_active','can_score','guard_club_members','rounds_before_write',
--                     'rounds_after_update','round_players_before_insert',
--                     'hole_scores_before_write','side_claims_before_write','create_club',
--                     'club_preview','join_club','save_hole','set_round_setup','delete_round')
-- order by anon_kan desc, p.proname;
--
-- 5. Realtime. Forventet: 10 rader.
--
-- select tablename from pg_publication_tables
-- where pubname = 'supabase_realtime' and schemaname = 'public' order by 1;
--
-- 6. Policyoversikt (for øyet).
--
-- select tablename, cmd, policyname from pg_policies
-- where schemaname = 'public' order by tablename, cmd;
--
-- Rolleprøven sql/lokal/001_prove.sql er KUN for lokal Postgres. På test
-- prøves rollene med to ekte kontoer fra appen (ROADMAP fase 1, «ferdig når»).


-- ===========================================================================
-- RULLEBAKKE (fjerner ALT fra denne migreringen, inkludert data)
-- ===========================================================================
-- Bare på test, og bare hvis ingen data skal beholdes.
--
-- begin;
-- do $$
-- declare t text;
-- begin
--   if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
--     foreach t in array array['club_members','events','event_committee','signups','rounds',
--                              'round_holes','round_players','round_matches','hole_scores',
--                              'side_claims'] loop
--       if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = t) then
--         execute format('alter publication supabase_realtime drop table public.%I', t);
--       end if;
--     end loop;
--   end if;
-- end $$;
-- drop function if exists public.delete_round(uuid);
-- drop function if exists public.set_round_setup(uuid, jsonb, jsonb);
-- drop function if exists public.save_hole(uuid, integer, jsonb, timestamptz);
-- drop function if exists public.join_club(text, uuid, text, numeric);
-- drop function if exists public.club_preview(text);
-- drop function if exists public.create_club(text, text, numeric);
-- drop table if exists public.side_claims, public.hole_scores, public.round_matches,
--   public.round_players, public.round_holes, public.rounds, public.course_holes,
--   public.courses, public.signups, public.event_committee, public.events,
--   public.seasons, public.club_members, public.clubs cascade;
-- drop function if exists public.side_claims_before_write();
-- drop function if exists public.hole_scores_before_write();
-- drop function if exists public.round_players_before_insert();
-- drop function if exists public.rounds_after_update();
-- drop function if exists public.rounds_before_write();
-- drop function if exists public.guard_club_members();
-- drop function if exists public.can_score(uuid, uuid);
-- drop function if exists public.round_is_active(uuid);
-- drop function if exists public.is_round_organizer(uuid);
-- drop function if exists public.can_read_round(uuid);
-- drop function if exists public.owns_member(uuid);
-- drop function if exists public.is_club_organizer(uuid);
-- drop function if exists public.has_membership(uuid);
-- drop function if exists public.is_club_member(uuid);
-- drop function if exists public.my_member_id(uuid);
-- drop function if exists public.set_updated_at();
-- commit;


-- ===========================================================================
-- NØDUTGANG (SQL Editor, kjører som postgres og omgår RLS og vaktene)
-- ===========================================================================
-- Klubben har mistet alle arrangører:
--   update public.club_members set is_organizer = true, status = 'active'
--    where id = '<medlem-uuid>';
--
-- Slette en låst runde (sesongtavla endrer seg!):
--   update public.rounds set status = 'active' where id = '<runde-uuid>';
--   delete from public.rounds where id = '<runde-uuid>';   -- barna følger med (cascade)
--
-- Markøren har gått hjem: arrangøren fører alltid. Eller fjern markøren:
--   update public.round_players set is_marker = false where round_id = '<runde-uuid>';
