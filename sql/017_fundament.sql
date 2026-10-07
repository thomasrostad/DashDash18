-- ===========================================================================
-- 017 – FUNDAMENT FOR EN ÅPEN APP (FASE 12) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt mot Supabase, verken
-- test eller prod. Prøvd lokalt (se sql/README.md). Krever 001–016.
--
-- Hvorfor (docs/visjon-apen-app.md, «Grepet: runden er kjernen», og
-- docs/datamodell-v2.md): runden skal kunne stå alene, uten klubb og kveld.
-- Spilleren er en profil. En runde kan telle i null, én eller flere
-- konkurranser. Klubb er valgfritt. Golfgutu-klubben blir én klubb med
-- jakkeracet som hovedkonkurranse.
--
-- Veien er ADDITIV: nye tabeller, nye kolonner som kan være tomme, nye
-- hjelpefunksjoner og noen utvidede policyer. Ingen tabell skrives om, ingen
-- kolonne bytter navn, og alle RPC-ene fra 001–016 virker som før. Det som
-- endres for dagens data:
--   * rounds.club_id og rounds.event_id kan være tomme, men en CHECK krever at
--     de enten begge er satt (klubbrunde, som i dag) eller begge er tomme (løs
--     runde). Alle runder som finnes, er klubbrunder.
--   * round_players.club_id kan være tom: da er deltakeren en profil eller en
--     gjest i en løs runde (round_participants), ikke et klubbmedlem.
--   * courses.club_id kan være tom: banen ligger i det felles biblioteket.
--   * Hver sesong får en konkurranse (kind = season, is_main), og rundene i
--     sesongens kvelder kobles til den. Nye sesonger og runder kobles av
--     triggere, så appen og importen trenger ikke å vite om det ennå.
--   * Alle innlogginger får en profil, fylt fra klubbmedlemskapet.
--
-- Hjelpefunksjonene can_read_round, is_round_organizer og can_score byttes ut
-- (create or replace) med utgaver som har en ekstra gren for løse runder og
-- konkurranser. For klubbrunder gir de nøyaktig samme svar som før (kontroll
-- 9 nederst sammenligner med 001-utgavene for hver bruker og runde).
--
-- Tilgang ved deltakelse (RLS):
--   * du ser runder i klubber der du er aktivt medlem (som før),
--   * løse runder du eier eller er med i,
--   * startede runder som teller i en konkurranse du kan se,
--   * konkurranser i klubbene dine, konkurranser du eier og konkurranser du
--     deltar i,
--   * profiler til folk du deler en klubb, en runde eller en konkurranse med.
-- En fremmed bruker ser ingenting av dette, og kan ikke koble seg på andres
-- runder eller konkurranser (se trusselmodellen i docs/datamodell-v2.md).
--
-- Mønsteret fra 001–016 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, og
-- triggerfunksjoner tas fra authenticated også.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. PROFILER: én person per innlogging
-- ===========================================================================
create table if not exists public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  -- Tom til personen har sagt hva hen heter (onboarding), eller fylt fra
  -- klubbmedlemskapet av ensure_profile().
  display_name    text check (display_name is null or char_length(btrim(display_name)) between 1 and 40),
  -- Personens egen WHS-indeks, brukt i løse runder. Klubbrunder bruker fortsatt
  -- club_members.handicap_index (pariteten).
  handicap_index  numeric(3,1) check (handicap_index between -10 and 54),
  avatar_path     text check (avatar_path is null or char_length(avatar_path) <= 200),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
comment on table public.profiles is
  'Én rad per innlogging (id = auth.users.id). Klubbmedlemskap (club_members.user_id) og '
  'deltakelse i løse runder (round_participants.profile_id) peker hit. Slettes med kontoen.';

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- Navnet fra innloggingen (Apple/Google gir full_name eller name), ellers tomt.
-- Tar hele raden som jsonb, så den tåler at auth.users mangler kolonnen.
create or replace function public.profile_name_from_auth(p_user jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(left(btrim(coalesce(p_user -> 'raw_user_meta_data' ->> 'full_name',
                                    p_user -> 'raw_user_meta_data' ->> 'name', '')), 40), '');
$$;
revoke all on function public.profile_name_from_auth(jsonb) from public, anon, authenticated;

-- Ny innlogging → tom profil. Feiler den, logges det, men innloggingen stopper
-- ikke (ensure_profile() lager den da ved første kall fra appen).
create or replace function public.profiles_on_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    insert into public.profiles (id, display_name)
    values (new.id, public.profile_name_from_auth(to_jsonb(new)))
    on conflict (id) do nothing;
  exception when others then
    raise warning 'Fikk ikke laget profil for %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;
revoke all on function public.profiles_on_new_user() from public, anon, authenticated;

drop trigger if exists profiles_on_new_user on auth.users;
create trigger profiles_on_new_user
  after insert on auth.users
  for each row execute function public.profiles_on_new_user();

-- Kolonnevakt: id kan ikke byttes, og du lager bare din egen profil.
-- Unntak: profilen som lages av triggeren på auth.users (pg_trigger_depth() > 1).
create or replace function public.guard_profiles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or pg_trigger_depth() > 1 then
    return new;
  end if;
  if new.id is distinct from auth.uid() or (tg_op = 'UPDATE' and new.id is distinct from old.id) then
    raise exception 'Du kan bare endre din egen profil' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_profiles() from public, anon, authenticated;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before insert or update on public.profiles
  for each row execute function public.guard_profiles();


-- ===========================================================================
-- 2. KONTOKJØP (StoreKit): plass til abonnement eller kjøp per klubb/turnering
-- ===========================================================================
-- Bare serveren skriver (service_role i en Edge Function som har sjekket
-- kvitteringen mot App Store Server API). Appen leser sine egne.
create table if not exists public.entitlements (
  id                       uuid primary key default gen_random_uuid(),
  profile_id               uuid references public.profiles(id) on delete set null,   -- kjøperen
  club_id                  uuid references public.clubs(id) on delete cascade,      -- kjøpt for en klubb
  product_id               text not null check (product_id ~ '^[A-Za-z0-9._-]{1,100}$'),
  original_transaction_id  text unique check (char_length(original_transaction_id) <= 64),
  environment              text not null default 'production'
                           check (environment in ('sandbox', 'production')),
  status                   text not null default 'active'
                           check (status in ('active', 'expired', 'revoked', 'refunded')),
  purchased_at             timestamptz,
  expires_at               timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
comment on table public.entitlements is
  'Kjøp i appen (StoreKit). Skrives bare av serveren etter kvitteringssjekk. '
  'En konkurranse som krever kjøp, peker hit (competitions.entitlement_id).';
create index if not exists entitlements_profile_idx on public.entitlements (profile_id);
create index if not exists entitlements_club_idx on public.entitlements (club_id);

drop trigger if exists entitlements_set_updated_at on public.entitlements;
create trigger entitlements_set_updated_at before update on public.entitlements
  for each row execute function public.set_updated_at();


-- ===========================================================================
-- 3. RUNDER UTEN KLUBB OG KVELD
-- ===========================================================================
alter table public.rounds alter column club_id drop not null;
alter table public.rounds alter column event_id drop not null;
alter table public.rounds
  add column if not exists owner_id uuid references public.profiles(id) on delete set null;
comment on column public.rounds.owner_id is
  'Eieren av en løs runde (club_id tom). Settes av serveren. Tom på klubbrunder, og når eieren har slettet kontoen.';

do $$
begin
  -- Klubbrunde: klubb og kveld, som før. Løs runde: ingen av dem.
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.rounds'::regclass and conname = 'rounds_home_check') then
    alter table public.rounds add constraint rounds_home_check
      check ((club_id is null) = (event_id is null));
  end if;
  -- Den sammensatte nøkkelen (course_id, club_id) sjekkes ikke når club_id er
  -- tom. Denne holder banen ekte også i løse runder.
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.rounds'::regclass and conname = 'rounds_course_id_fk') then
    alter table public.rounds add constraint rounds_course_id_fk
      foreign key (course_id) references public.courses(id) on delete restrict;
  end if;
end $$;
create index if not exists rounds_owner_idx on public.rounds (owner_id) where owner_id is not null;

-- Vakt for løse runder (egen trigger, rounds_before_write fra 001 er urørt):
--   * eieren settes av serveren (auth.uid()), og kan ikke flyttes fra appen,
--   * en runde kan ikke flyttes mellom løs og klubb,
--   * en løs runde bruker bare baner fra det felles biblioteket.
create or replace function public.rounds_guard_home()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is not null then
    if tg_op = 'INSERT' then
      new.owner_id := case when new.club_id is null then v_uid end;
    else
      if (old.club_id is null or new.club_id is null)
         and new.club_id is distinct from old.club_id then
        raise exception 'En runde kan ikke flyttes mellom klubb og løs runde' using errcode = '42501';
      end if;
      -- Unntak: eieren har slettet kontoen (fremmednøkkelen setter null).
      if new.owner_id is distinct from old.owner_id
         and not (new.owner_id is null
                  and not exists (select 1 from public.profiles p where p.id = old.owner_id)) then
        raise exception 'Eieren av runden kan ikke endres her' using errcode = '42501';
      end if;
    end if;
  end if;

  if new.club_id is null and new.course_id is not null
     and (tg_op = 'INSERT' or new.course_id is distinct from old.course_id)
     and not exists (select 1 from public.courses c where c.id = new.course_id and c.club_id is null) then
    raise exception 'En løs runde må bruke en bane fra det felles biblioteket' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.rounds_guard_home() from public, anon, authenticated;

drop trigger if exists rounds_guard_home on public.rounds;
create trigger rounds_guard_home
  before insert or update on public.rounds
  for each row execute function public.rounds_guard_home();


-- ===========================================================================
-- 4. DELTAKERE I LØSE RUNDER: profil eller gjest
-- ===========================================================================
-- I en løs runde er deltakeren en rad her. round_players.member_id får samme
-- id, så hole_scores, round_matches og side_claims (som peker på
-- round_players) virker uendret. I klubbrunder er deltakeren klubbmedlemmet,
-- som før. Gjest = profile_id tom. En gjest kan senere kobles til en profil.
create table if not exists public.round_participants (
  id              uuid primary key default gen_random_uuid(),
  round_id        uuid not null references public.rounds(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete set null,
  -- Navnet slik det ble skrevet inn (gjest), eller profilens navn da personen
  -- ble lagt til. Står igjen hvis kontoen slettes.
  display_name    text not null check (char_length(btrim(display_name)) between 1 and 40),
  handicap_index  numeric(3,1) check (handicap_index between -10 and 54),
  added_by        uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint round_participants_id_round_key unique (id, round_id)
);
comment on table public.round_participants is
  'Deltaker i en løs runde: profil eller gjest (profile_id tom). round_players.member_id = id.';
create unique index if not exists round_participants_one_per_profile
  on public.round_participants (round_id, profile_id) where profile_id is not null;
create index if not exists round_participants_profile_idx
  on public.round_participants (profile_id) where profile_id is not null;

drop trigger if exists round_participants_set_updated_at on public.round_participants;
create trigger round_participants_set_updated_at before update on public.round_participants
  for each row execute function public.set_updated_at();

-- round_players: club_id kan være tom for deltakere i løse runder.
alter table public.round_players alter column club_id drop not null;
alter table public.round_players
  add column if not exists participant_round_id uuid
  generated always as (case when club_id is null then round_id end) stored;
comment on column public.round_players.participant_round_id is
  'Satt (= round_id) når deltakeren ikke er klubbmedlem. Brukes bare i nøkkelen til round_participants.';

do $$
begin
  -- Den sammensatte nøkkelen (round_id, club_id) sjekkes ikke når club_id er tom.
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.round_players'::regclass and conname = 'round_players_round_id_fk') then
    alter table public.round_players add constraint round_players_round_id_fk
      foreign key (round_id) references public.rounds(id) on delete cascade;
  end if;
  -- Uten klubb: deltakeren må finnes i round_participants for samme runde.
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.round_players'::regclass and conname = 'round_players_participant_fk') then
    alter table public.round_players add constraint round_players_participant_fk
      foreign key (member_id, participant_round_id)
      references public.round_participants (id, round_id) on delete cascade;
  end if;
end $$;


-- ===========================================================================
-- 5. FELLES BANEBIBLIOTEK OG EKSTERN KILDE
-- ===========================================================================
alter table public.courses alter column club_id drop not null;
alter table public.courses
  add column if not exists source text check (source is null or source ~ '^[a-z0-9_-]{1,30}$'),
  add column if not exists external_id text check (external_id is null or char_length(external_id) <= 100),
  add column if not exists fetched_at timestamptz,
  add column if not exists created_by_profile uuid references public.profiles(id) on delete set null;
comment on column public.courses.club_id is
  'Klubbens egen bane, eller tom = det felles biblioteket som alle innloggede leser.';
comment on column public.courses.source is
  'Hvor banen er hentet fra (f.eks. golfapi). Tom = lagt inn av en bruker eller klubb.';
comment on column public.courses.external_id is
  'Banens id hos kilden. (source, external_id) er unik, så en ny henting oppdaterer samme rad.';
comment on column public.courses.fetched_at is 'Sist hentet fra kilden.';

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.courses'::regclass and conname = 'courses_external_whole') then
    alter table public.courses add constraint courses_external_whole
      check (external_id is null or source is not null);
  end if;
end $$;
create unique index if not exists courses_external_key
  on public.courses (source, external_id) where external_id is not null;
create index if not exists courses_shared_idx on public.courses (lower(btrim(name))) where club_id is null;

-- Vakt: en bane flyttes ikke mellom klubb og bibliotek fra appen, og hvem som
-- la inn en felles bane, settes av serveren.
create or replace function public.courses_guard_library()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.created_by_profile := case when new.club_id is null then auth.uid() end;
    if new.source is not null or new.external_id is not null or new.fetched_at is not null then
      raise exception 'Hentede baner legges inn av serveren' using errcode = '42501';
    end if;
  else
    if new.club_id is distinct from old.club_id then
      raise exception 'En bane kan ikke flyttes mellom klubb og bibliotek' using errcode = '42501';
    end if;
    if (new.created_by_profile is distinct from old.created_by_profile
        and not (new.created_by_profile is null
                 and not exists (select 1 from public.profiles p where p.id = old.created_by_profile)))
       or new.source is distinct from old.source
       or new.external_id is distinct from old.external_id
       or new.fetched_at is distinct from old.fetched_at then
      raise exception 'Kilden til banen endres bare av serveren' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.courses_guard_library() from public, anon, authenticated;

drop trigger if exists courses_guard_library on public.courses;
create trigger courses_guard_library
  before insert or update on public.courses
  for each row execute function public.courses_guard_library();


-- ===========================================================================
-- 6. KONKURRANSER: eget lag over rundene
-- ===========================================================================
create table if not exists public.competitions (
  id                 uuid primary key default gen_random_uuid(),
  -- season = turnering/sesong (jakkeracet), league = liga, cup = utslag,
  -- fun = morroturnering, game = spill på runden (skins, Nassau …).
  kind               text not null check (kind in ('season', 'league', 'cup', 'fun', 'game')),
  name               text not null check (char_length(btrim(name)) between 1 and 60),
  -- Eier: en klubb (arrangørene styrer), eller en profil (club_id tom).
  club_id            uuid references public.clubs(id) on delete cascade,
  owner_id           uuid references public.profiles(id) on delete set null,
  -- Satt for sesongens konkurranse. Navn, status og regler speiles da fra
  -- sesongen av en trigger (sesongen er kilden i overgangen).
  season_id          uuid unique,
  status             text not null default 'planned'
                     check (status in ('planned', 'active', 'finished')),
  -- Hvem som er med: club = klubbens tropp (aktive + de som har spilt, som
  -- Tavla), listed = bare competition_participants, open = alle som spiller en
  -- tellende runde.
  entry              text not null default 'listed' check (entry in ('club', 'listed', 'open')),
  rules              jsonb not null default '{"version": 1}'::jsonb,
  starts_on          date,
  ends_on            date,
  -- Klubbens hovedturnering (jakkeracet). Høyst én aktiv per klubb.
  is_main            boolean not null default false,
  -- StoreKit: krever kjøp, og kjøpet som låser opp. Settes bare av serveren.
  requires_purchase  boolean not null default false,
  entitlement_id     uuid references public.entitlements(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint competitions_id_club_key unique (id, club_id),
  constraint competitions_season_fk foreign key (season_id, club_id)
    references public.seasons (id, club_id) on delete cascade,
  constraint competitions_season_kind check (season_id is null or kind = 'season'),
  constraint competitions_main_needs_club check (not is_main or club_id is not null),
  constraint competitions_entry_club check (entry <> 'club' or club_id is not null),
  constraint competitions_period check (starts_on is null or ends_on is null or ends_on >= starts_on),
  constraint competitions_rules_shape check (
    jsonb_typeof(rules) = 'object'
    and case when jsonb_typeof(rules -> 'version') = 'number'
             then (rules -> 'version')::numeric >= 1
             else false end
    and pg_column_size(rules) <= 65536
  )
);
comment on table public.competitions is
  'En konkurranse: sesong, liga, cup, morroturnering eller spill på runden. Rundene som teller, '
  'står i competition_rounds. Eies av en klubb eller en profil.';
create unique index if not exists competitions_one_main_active
  on public.competitions (club_id) where is_main and status = 'active';
create index if not exists competitions_club_idx on public.competitions (club_id);
create index if not exists competitions_owner_idx on public.competitions (owner_id) where owner_id is not null;

drop trigger if exists competitions_set_updated_at on public.competitions;
create trigger competitions_set_updated_at before update on public.competitions
  for each row execute function public.set_updated_at();


create table if not exists public.competition_participants (
  id              uuid primary key default gen_random_uuid(),
  competition_id  uuid not null references public.competitions(id) on delete cascade,
  -- Enten et klubbmedlem (klubbkonkurranse) eller en profil.
  member_id       uuid references public.club_members(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete cascade,
  status          text not null default 'active' check (status in ('active', 'withdrawn')),
  created_at      timestamptz not null default now(),
  constraint competition_participants_one_kind check (num_nonnulls(member_id, profile_id) = 1)
);
comment on table public.competition_participants is
  'Påmeldte i en konkurranse (entry = listed). Klubbmedlem eller profil. Gjester er med via rundene (entry = open).';
create unique index if not exists competition_participants_member
  on public.competition_participants (competition_id, member_id) where member_id is not null;
create unique index if not exists competition_participants_profile
  on public.competition_participants (competition_id, profile_id) where profile_id is not null;
create index if not exists competition_participants_profile_idx
  on public.competition_participants (profile_id) where profile_id is not null;
create index if not exists competition_participants_member_idx
  on public.competition_participants (member_id) where member_id is not null;


create table if not exists public.competition_rounds (
  competition_id  uuid not null references public.competitions(id) on delete cascade,
  round_id        uuid not null references public.rounds(id) on delete cascade,
  -- season = koblet av triggeren (runden er i en kveld i sesongen),
  -- manual = lagt til av en arrangør/eier.
  source          text not null default 'manual' check (source in ('season', 'manual')),
  added_by        uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (competition_id, round_id)
);
comment on table public.competition_rounds is
  'Rundene som teller i en konkurranse. En runde kan telle i flere.';
create index if not exists competition_rounds_round_idx on public.competition_rounds (round_id);


-- ===========================================================================
-- 7. HJELPEFUNKSJONER FOR RLS
-- ===========================================================================
-- Som i 001: SECURITY DEFINER, kalles av policyene som den innloggede, så
-- authenticated har EXECUTE og anon har det ikke.

-- Er jeg med i den løse runden (som profil)?
create or replace function public.is_round_participant(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.round_participants p
    where p.round_id = p_round_id and p.profile_id = auth.uid()
  );
$$;
revoke all on function public.is_round_participant(uuid) from public, anon;
grant execute on function public.is_round_participant(uuid) to authenticated;

-- Er deltakeren i runden meg? Klubbmedlem (owns_member, som før) eller
-- deltaker i en løs runde.
create or replace function public.owns_round_player(p_round_id uuid, p_player_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.owns_member(p_player_id)
      or exists (select 1 from public.round_participants p
                 where p.id = p_player_id and p.round_id = p_round_id
                   and p.profile_id = auth.uid());
$$;
revoke all on function public.owns_round_player(uuid, uuid) from public, anon;
grant execute on function public.owns_round_player(uuid, uuid) to authenticated;

-- Deltar jeg i konkurransen (som profil, eller som klubbmedlem på lista)?
create or replace function public.is_competition_participant(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competition_participants p
    where p.competition_id = p_competition_id
      and p.status = 'active'
      and (p.profile_id = auth.uid() or public.owns_member(p.member_id))
  );
$$;
revoke all on function public.is_competition_participant(uuid) from public, anon;
grant execute on function public.is_competition_participant(uuid) to authenticated;

-- Kan jeg se konkurransen? Klubbens: medlemmer. Profilens: eieren. Alle: de
-- som deltar.
create or replace function public.can_read_competition(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is not null and public.is_club_member(c.club_id))
           or (c.club_id is null and c.owner_id = auth.uid())
           or public.is_competition_participant(c.id))
  );
$$;
revoke all on function public.can_read_competition(uuid) from public, anon;
grant execute on function public.can_read_competition(uuid) to authenticated;

-- Styrer jeg konkurransen? Klubbens: arrangør. Profilens: eieren.
create or replace function public.is_competition_admin(p_competition_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competitions c
    where c.id = p_competition_id
      and (   (c.club_id is not null and public.is_club_organizer(c.club_id))
           or (c.club_id is null and c.owner_id = auth.uid()))
  );
$$;
revoke all on function public.is_competition_admin(uuid) from public, anon;
grant execute on function public.is_competition_admin(uuid) to authenticated;

-- Teller runden i en konkurranse jeg kan se?
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
  );
$$;
revoke all on function public.round_in_readable_competition(uuid) from public, anon;
grant execute on function public.round_in_readable_competition(uuid) to authenticated;

-- Kan jeg gi runden til en konkurranse? Det er rundens «eier» som samtykker:
-- arrangøren i klubben, eller eieren av den løse runden.
create or replace function public.can_link_round(p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.rounds r
    where r.id = p_round_id
      and (   (r.club_id is not null and public.is_club_organizer(r.club_id))
           or (r.club_id is null and r.owner_id = auth.uid()))
  );
$$;
revoke all on function public.can_link_round(uuid) from public, anon;
grant execute on function public.can_link_round(uuid) to authenticated;

-- Kan jeg se profilen? Meg selv, folk i samme klubb, i samme løse runde
-- (også eieren) og i samme konkurranse (også eieren). Ingen søk etter
-- fremmede: en ny forbindelse lages med invitasjon (fase 13/15).
create or replace function public.can_see_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
       p_profile_id = auth.uid()
    or exists (select 1 from public.club_members a
               join public.club_members b on b.club_id = a.club_id
               where a.user_id = auth.uid() and a.status = 'active'
                 and b.user_id = p_profile_id)
    or exists (select 1 from public.round_participants a
               join public.round_participants b on b.round_id = a.round_id
               where a.profile_id = auth.uid() and b.profile_id = p_profile_id)
    or exists (select 1 from public.rounds r
               join public.round_participants b on b.round_id = r.id
               where r.club_id is null
                 and (   (r.owner_id = auth.uid() and b.profile_id = p_profile_id)
                      or (r.owner_id = p_profile_id and b.profile_id = auth.uid())))
    or exists (select 1 from public.competition_participants a
               join public.competition_participants b on b.competition_id = a.competition_id
               where a.profile_id = auth.uid() and b.profile_id = p_profile_id
                 and a.status = 'active' and b.status = 'active')
    or exists (select 1 from public.competitions c
               join public.competition_participants b on b.competition_id = c.id
               where c.club_id is null and b.status = 'active'
                 and (   (c.owner_id = auth.uid() and b.profile_id = p_profile_id)
                      or (c.owner_id = p_profile_id and b.profile_id = auth.uid())))
  );
$$;
revoke all on function public.can_see_profile(uuid) from public, anon;
grant execute on function public.can_see_profile(uuid) to authenticated;


-- --- Utvidet fra 001: samme svar for klubbrunder, pluss løse runder -------
-- Kan jeg se runden? Klubb: som før. Løs: eieren og deltakerne (også kladd).
-- Startet runde i en konkurranse jeg kan se: ja.
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
           or public.is_club_organizer(r.club_id)
           or (r.club_id is null
               and (r.owner_id = auth.uid() or public.is_round_participant(r.id)))
           or (r.status <> 'draft' and public.round_in_readable_competition(r.id)))
  );
$$;
revoke all on function public.can_read_round(uuid) from public, anon;
grant execute on function public.can_read_round(uuid) to authenticated;

-- Styrer jeg runden? Klubb: arrangøren (som før). Løs: eieren.
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
      and (   public.is_club_organizer(r.club_id)
           or (r.club_id is null and r.owner_id = auth.uid()))
  );
$$;
revoke all on function public.is_round_organizer(uuid) from public, anon;
grant execute on function public.is_round_organizer(uuid) to authenticated;

-- kanFore, som i 001. Eieren av en løs runde har arrangørens rett. «Spilleren
-- selv» og «markøren» er klubbmedlemmet (som før) eller profilen bak
-- deltakeren i den løse runden. En gjest uten profil føres av markøren eller
-- eieren.
create or replace function public.can_score(p_round_id uuid, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_found   boolean;
  v_club    uuid;
  v_status  text;
  v_owner   uuid;
  v_bay     smallint;
  v_marker  uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select true, r.club_id, r.status, r.owner_id into v_found, v_club, v_status, v_owner
  from public.rounds r where r.id = p_round_id;
  if v_found is null then
    return false;
  end if;

  if v_club is not null then
    if public.is_club_organizer(v_club) then
      return true;
    end if;
  elsif v_owner = auth.uid() then
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
    return public.owns_round_player(p_round_id, v_marker);
  end if;

  return public.owns_round_player(p_round_id, p_member_id);
end;
$$;
revoke all on function public.can_score(uuid, uuid) from public, anon;
grant execute on function public.can_score(uuid, uuid) to authenticated;

-- Navn og profil for en deltaker i en runde du kan se. Klubbmedlem: navnet i
-- troppen. Løs runde: profilens navn, ellers navnet som ble skrevet inn.
-- Brukes av viewet round_roster, så de som ser en runde via en konkurranse
-- får navnene uten å kunne lese troppen.
create or replace function public.round_player_identity(p_round_id uuid, p_player_id uuid)
returns table (display_name text, profile_id uuid, is_guest boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(m.display_name, pf.display_name, pa.display_name),
         coalesce(m.user_id, pa.profile_id),
         (m.id is null and pa.profile_id is null)
  from public.round_players rp
  left join public.club_members m
    on m.id = rp.member_id and rp.club_id is not null
  left join public.round_participants pa
    on pa.id = rp.member_id and pa.round_id = rp.round_id and rp.club_id is null
  left join public.profiles pf on pf.id = pa.profile_id
  where rp.round_id = p_round_id and rp.member_id = p_player_id
    and public.can_read_round(p_round_id);
$$;
revoke all on function public.round_player_identity(uuid, uuid) from public, anon;
grant execute on function public.round_player_identity(uuid, uuid) to authenticated;


-- ===========================================================================
-- 8. TRIGGERE FOR DELTAKERE, KONKURRANSER OG SPEILING
-- ===========================================================================

-- --- round_participants: bare i løse runder, profil du kan se, og ikke ut
--     når det er ført noe -----------------------------------------------------
create or replace function public.round_participants_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  if tg_op = 'UPDATE' and new.round_id is distinct from old.round_id then
    raise exception 'En deltaker kan ikke flyttes til en annen runde' using errcode = '42501';
  end if;

  -- Klubbrunder har klubbmedlemmer som deltakere (set_round_setup). Bare den
  -- som styrer runden, får vite hvorfor; andre får samme svar som RLS gir.
  select r.club_id into v_club from public.rounds r where r.id = new.round_id;
  if v_club is not null then
    if auth.uid() is null or public.is_round_organizer(new.round_id) then
      raise exception 'Klubbrunder har klubbmedlemmer som deltakere (set_round_setup)' using errcode = '22023';
    end if;
    raise exception 'Du kan ikke legge til deltakere i denne runden' using errcode = '42501';
  end if;

  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.added_by := auth.uid();
    elsif new.added_by is distinct from old.added_by
          and not (new.added_by is null
                   and not exists (select 1 from public.profiles p where p.id = old.added_by)) then
      raise exception 'Hvem som la til deltakeren, endres ikke' using errcode = '42501';
    end if;
    -- En profil legges bare til (eller kobles til en gjest) av noen som kan se
    -- den. Ellers kunne hvem som helst fylle andres «Mine runder».
    if new.profile_id is not null
       and (tg_op = 'INSERT' or new.profile_id is distinct from old.profile_id)
       and not public.can_see_profile(new.profile_id) then
      raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller konkurranse'
        using errcode = '42501';
    end if;
  end if;

  -- Handicap fra profilen når det ikke er gitt.
  if tg_op = 'INSERT' and new.handicap_index is null and new.profile_id is not null then
    select p.handicap_index into new.handicap_index from public.profiles p where p.id = new.profile_id;
  end if;
  return new;
end;
$$;
revoke all on function public.round_participants_before_write() from public, anon, authenticated;

drop trigger if exists round_participants_before_write on public.round_participants;
create trigger round_participants_before_write
  before insert or update on public.round_participants
  for each row execute function public.round_participants_before_write();

-- Ny deltaker → rad i round_players (samme id), så føring, bås og match virker.
create or replace function public.round_participants_after_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.round_players (round_id, member_id, club_id, handicap_index)
  values (new.round_id, new.id, null, new.handicap_index)
  on conflict (round_id, member_id) do nothing;
  return null;
end;
$$;
revoke all on function public.round_participants_after_insert() from public, anon, authenticated;

drop trigger if exists round_participants_after_insert on public.round_participants;
create trigger round_participants_after_insert
  after insert on public.round_participants
  for each row execute function public.round_participants_after_insert();

-- Den som har scorer eller sidepremier, tas ikke ut (som set_round_setup).
-- Slettes hele runden, går alt med.
create or replace function public.round_participants_before_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.rounds r where r.id = old.round_id)
     and (   exists (select 1 from public.hole_scores s
                     where s.round_id = old.round_id and s.member_id = old.id)
          or exists (select 1 from public.side_claims c
                     where c.round_id = old.round_id and c.member_id = old.id)) then
    raise exception 'Kan ikke ta ut % – det er ført scorer eller sidepremier', old.display_name
      using errcode = '55000';
  end if;
  return old;
end;
$$;
revoke all on function public.round_participants_before_delete() from public, anon, authenticated;

drop trigger if exists round_participants_before_delete on public.round_participants;
create trigger round_participants_before_delete
  before delete on public.round_participants
  for each row execute function public.round_participants_before_delete();

-- Når en løs runde startes, fryses handicapet: profilens indeks nå, ellers
-- det som ble gitt for gjesten. (Klubbrunder fryses av rounds_after_update.)
create or replace function public.rounds_freeze_participants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is null and old.status = 'draft' and new.status = 'active' then
    update public.round_players rp
       set handicap_index = coalesce(pf.handicap_index, pa.handicap_index)
      from public.round_participants pa
      left join public.profiles pf on pf.id = pa.profile_id
     where rp.round_id = new.id
       and pa.id = rp.member_id
       and pa.round_id = new.id;
  end if;
  return null;
end;
$$;
revoke all on function public.rounds_freeze_participants() from public, anon, authenticated;

drop trigger if exists rounds_freeze_participants on public.rounds;
create trigger rounds_freeze_participants
  after update of status on public.rounds
  for each row execute function public.rounds_freeze_participants();

-- side_claims (001): hvem meldte inn. I en løs runde finnes ikke noe
-- medlems-id, og et innsendt created_by godtas ikke.
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
  if v_club is null then
    new.created_by := null;
  else
    new.created_by := coalesce(public.my_member_id(v_club), new.created_by);
  end if;
  return new;
end;
$$;
revoke all on function public.side_claims_before_write() from public, anon, authenticated;


-- --- competitions: kolonnevakt -----------------------------------------------
-- Fra appen (pg_trigger_depth() = 1): eieren settes av serveren, sesongens
-- konkurranse og hovedturneringen lages bare av speilingen, kjøp settes bare
-- av serveren, og sesongens navn, status og regler endres i sesongen.
create or replace function public.guard_competitions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := case when new.club_id is null then auth.uid() end;
    if new.kind = 'season' or new.season_id is not null or new.is_main then
      raise exception 'Sesongens konkurranse lages av sesongen' using errcode = '22023';
    end if;
    if new.requires_purchase or new.entitlement_id is not null then
      raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.kind is distinct from old.kind or new.club_id is distinct from old.club_id
     or (new.owner_id is distinct from old.owner_id
         and not (new.owner_id is null
                  and not exists (select 1 from public.profiles p where p.id = old.owner_id)))
     or new.season_id is distinct from old.season_id
     or new.is_main is distinct from old.is_main then
    raise exception 'Type, eier og hovedturnering kan ikke endres her' using errcode = '42501';
  end if;
  if new.requires_purchase is distinct from old.requires_purchase
     or new.entitlement_id is distinct from old.entitlement_id then
    raise exception 'Kjøp settes bare av serveren' using errcode = '42501';
  end if;
  if old.season_id is not null
     and (new.name is distinct from old.name or new.status is distinct from old.status
          or new.rules is distinct from old.rules or new.entry is distinct from old.entry) then
    raise exception 'Endre sesongen i stedet' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competitions() from public, anon, authenticated;

drop trigger if exists competitions_guard on public.competitions;
create trigger competitions_guard
  before insert or update on public.competitions
  for each row execute function public.guard_competitions();

-- --- competition_participants: riktig klubb, og bare folk du kan se ---------
create or replace function public.guard_competition_participants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  if tg_op = 'UPDATE'
     and (new.competition_id is distinct from old.competition_id
          or new.member_id is distinct from old.member_id
          or new.profile_id is distinct from old.profile_id) then
    raise exception 'Bare status kan endres på en påmelding' using errcode = '42501';
  end if;

  select c.club_id into v_club from public.competitions c where c.id = new.competition_id;
  if new.member_id is not null
     and not exists (select 1 from public.club_members m
                     where m.id = new.member_id and m.club_id = v_club) then
    raise exception 'Medlemmet er ikke i konkurransens klubb' using errcode = '22023';
  end if;

  if tg_op = 'INSERT' and auth.uid() is not null and new.profile_id is not null
     and not public.can_see_profile(new.profile_id) then
    raise exception 'Du kan bare melde på folk du kjenner fra en klubb, runde eller konkurranse'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competition_participants() from public, anon, authenticated;

drop trigger if exists competition_participants_guard on public.competition_participants;
create trigger competition_participants_guard
  before insert or update on public.competition_participants
  for each row execute function public.guard_competition_participants();

-- --- competition_rounds: hvem la til ----------------------------------------
create or replace function public.competition_rounds_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and pg_trigger_depth() = 1 then
    new.added_by := auth.uid();
  end if;
  return new;
end;
$$;
revoke all on function public.competition_rounds_before_insert() from public, anon, authenticated;

drop trigger if exists competition_rounds_before_insert on public.competition_rounds;
create trigger competition_rounds_before_insert
  before insert on public.competition_rounds
  for each row execute function public.competition_rounds_before_insert();


-- --- Speiling: sesong → konkurranse, kveld/runde → kobling -------------------
-- I overgangen er seasons kilden for sesongens navn, status og regler. Den
-- som lager eller endrer en sesong (appen, activate_season, importen), får
-- konkurransen oppdatert i samme transaksjon.
create or replace function public.competitions_sync_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.competitions (kind, name, club_id, season_id, status, entry, rules, is_main)
  values ('season', new.name, new.club_id, new.id, new.status, 'club', new.rules, true)
  on conflict (season_id) do update
    set name   = excluded.name,
        status = excluded.status,
        rules  = excluded.rules;
  return null;
end;
$$;
revoke all on function public.competitions_sync_season() from public, anon, authenticated;

drop trigger if exists competitions_sync_season on public.seasons;
create trigger competitions_sync_season
  after insert or update of name, status, rules on public.seasons
  for each row execute function public.competitions_sync_season();

-- En runde i en kveld i en sesong teller i sesongens konkurranse.
create or replace function public.competition_rounds_sync_round()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.event_id is not distinct from old.event_id then
      return null;
    end if;
    delete from public.competition_rounds cr
     where cr.round_id = new.id and cr.source = 'season';
  end if;

  insert into public.competition_rounds (competition_id, round_id, source)
  select c.id, new.id, 'season'
    from public.events e
    join public.competitions c on c.season_id = e.season_id
   where e.id = new.event_id
  on conflict (competition_id, round_id) do nothing;
  return null;
end;
$$;
revoke all on function public.competition_rounds_sync_round() from public, anon, authenticated;

drop trigger if exists competition_rounds_sync_round on public.rounds;
create trigger competition_rounds_sync_round
  after insert or update of event_id on public.rounds
  for each row execute function public.competition_rounds_sync_round();

-- En kveld som flyttes til en annen sesong, tar rundene med seg.
create or replace function public.competition_rounds_sync_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.season_id is not distinct from old.season_id then
    return null;
  end if;
  delete from public.competition_rounds cr
   using public.rounds r
   where r.event_id = new.id and cr.round_id = r.id and cr.source = 'season';
  insert into public.competition_rounds (competition_id, round_id, source)
  select c.id, r.id, 'season'
    from public.rounds r
    join public.competitions c on c.season_id = new.season_id
   where r.event_id = new.id
  on conflict (competition_id, round_id) do nothing;
  return null;
end;
$$;
revoke all on function public.competition_rounds_sync_event() from public, anon, authenticated;

drop trigger if exists competition_rounds_sync_event on public.events;
create trigger competition_rounds_sync_event
  after update of season_id on public.events
  for each row execute function public.competition_rounds_sync_event();


-- ===========================================================================
-- 9. RLS-POLICYER
-- ===========================================================================
alter table public.profiles                 enable row level security;
alter table public.entitlements             enable row level security;
alter table public.round_participants       enable row level security;
alter table public.competitions             enable row level security;
alter table public.competition_participants enable row level security;
alter table public.competition_rounds       enable row level security;

-- Rydd policyene på de nye tabellene, så fila kan kjøres om igjen.
do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles', 'entitlements', 'round_participants', 'competitions',
                        'competition_participants', 'competition_rounds')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- --- profiles ---------------------------------------------------------------
-- Lese: deg selv og folk du deler noe med. Lage/endre: bare din egen.
-- Slette: ingen (kontoen slettes, og profilen følger med).
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.can_see_profile(id));
create policy profiles_insert on public.profiles
  for insert to authenticated with check (id = auth.uid());
create policy profiles_update on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- --- entitlements: lese egne, eller klubbens som arrangør. Skrive: serveren.
create policy entitlements_select on public.entitlements
  for select to authenticated
  using (profile_id = auth.uid() or public.is_club_organizer(club_id));

-- --- round_participants: lese via runden, skrive som eier ---------------------
create policy round_participants_select on public.round_participants
  for select to authenticated using (public.can_read_round(round_id));
create policy round_participants_insert on public.round_participants
  for insert to authenticated with check (public.is_round_organizer(round_id));
create policy round_participants_update on public.round_participants
  for update to authenticated
  using (public.is_round_organizer(round_id)) with check (public.is_round_organizer(round_id));
create policy round_participants_delete on public.round_participants
  for delete to authenticated using (public.is_round_organizer(round_id));

-- --- competitions -----------------------------------------------------------
-- Uttrykket står i policyen (ikke bare i can_read_competition), så en ny rad
-- kan leses tilbake i samme forespørsel (insert … returning).
create policy competitions_select on public.competitions
  for select to authenticated
  using (   (club_id is not null and public.is_club_member(club_id))
         or (club_id is null and owner_id = auth.uid())
         or public.is_competition_participant(id));
create policy competitions_insert on public.competitions
  for insert to authenticated
  with check (   (club_id is not null and public.is_club_organizer(club_id))
              or (club_id is null and owner_id = auth.uid()));
create policy competitions_update on public.competitions
  for update to authenticated
  using (   (club_id is not null and public.is_club_organizer(club_id))
         or (club_id is null and owner_id = auth.uid()))
  with check (   (club_id is not null and public.is_club_organizer(club_id))
              or (club_id is null and owner_id = auth.uid()));
-- Sesongens konkurranse slettes med sesongen.
create policy competitions_delete on public.competitions
  for delete to authenticated
  using (season_id is null
         and (   (club_id is not null and public.is_club_organizer(club_id))
              or (club_id is null and owner_id = auth.uid())));

-- --- competition_participants -----------------------------------------------
create policy competition_participants_select on public.competition_participants
  for select to authenticated using (public.can_read_competition(competition_id));
create policy competition_participants_insert on public.competition_participants
  for insert to authenticated with check (public.is_competition_admin(competition_id));
create policy competition_participants_update on public.competition_participants
  for update to authenticated
  using (public.is_competition_admin(competition_id))
  with check (public.is_competition_admin(competition_id));
-- Arrangøren tar ut; du kan melde deg av selv.
create policy competition_participants_delete on public.competition_participants
  for delete to authenticated
  using (public.is_competition_admin(competition_id)
         or profile_id = auth.uid() or public.owns_member(member_id));

-- --- competition_rounds -----------------------------------------------------
-- Lese: konkurransen og runden må være synlige (kladder vises ikke).
-- Legge til: arrangøren av konkurransen, og rundens eier samtykker (det er
-- samme person, eller eieren gjør det selv). Ta bort: arrangøren eller
-- rundens eier. Sesongens koblinger styres av triggeren.
create policy competition_rounds_select on public.competition_rounds
  for select to authenticated
  using (public.can_read_competition(competition_id) and public.can_read_round(round_id));
create policy competition_rounds_insert on public.competition_rounds
  for insert to authenticated
  with check (source = 'manual'
              and public.is_competition_admin(competition_id)
              and public.can_link_round(round_id));
create policy competition_rounds_delete on public.competition_rounds
  for delete to authenticated
  using (source = 'manual'
         and (public.is_competition_admin(competition_id) or public.can_link_round(round_id)));

-- --- rounds (erstatter 001): klubbuttrykket er uendret, løs runde i tillegg --
drop policy if exists rounds_select on public.rounds;
drop policy if exists rounds_insert on public.rounds;
drop policy if exists rounds_update on public.rounds;
drop policy if exists rounds_delete on public.rounds;
create policy rounds_select on public.rounds
  for select to authenticated
  using (   (status <> 'draft' and public.is_club_member(club_id))
         or public.is_club_organizer(club_id)
         or (club_id is null and (owner_id = auth.uid() or public.is_round_participant(id)))
         or (status <> 'draft' and public.round_in_readable_competition(id)));
create policy rounds_insert on public.rounds
  for insert to authenticated
  with check (public.is_club_organizer(club_id) or (club_id is null and owner_id = auth.uid()));
create policy rounds_update on public.rounds
  for update to authenticated
  using (public.is_club_organizer(club_id) or (club_id is null and owner_id = auth.uid()))
  with check (public.is_club_organizer(club_id) or (club_id is null and owner_id = auth.uid()));
create policy rounds_delete on public.rounds
  for delete to authenticated
  using ((public.is_club_organizer(club_id) or (club_id is null and owner_id = auth.uid()))
         and status <> 'locked');

-- --- side_claims (erstatter 001): «egen» er også deltakeren i en løs runde --
drop policy if exists side_claims_insert on public.side_claims;
drop policy if exists side_claims_update on public.side_claims;
drop policy if exists side_claims_delete on public.side_claims;
create policy side_claims_insert on public.side_claims
  for insert to authenticated
  with check (public.is_round_organizer(round_id)
              or (public.owns_round_player(round_id, member_id) and public.round_is_active(round_id)));
create policy side_claims_update on public.side_claims
  for update to authenticated
  using (public.is_round_organizer(round_id)
         or (public.owns_round_player(round_id, member_id) and public.round_is_active(round_id)))
  with check (public.is_round_organizer(round_id)
              or (public.owns_round_player(round_id, member_id) and public.round_is_active(round_id)));
create policy side_claims_delete on public.side_claims
  for delete to authenticated
  using (public.is_round_organizer(round_id)
         or (public.owns_round_player(round_id, member_id) and public.round_is_active(round_id)));

-- --- courses og course_holes (erstatter 001): klubbens som før, pluss det
--     felles biblioteket. Alle innloggede leser det. Den som la inn en felles
--     bane, retter den så lenge den ikke er hentet fra en kilde. -------------
drop policy if exists courses_select on public.courses;
drop policy if exists courses_insert on public.courses;
drop policy if exists courses_update on public.courses;
drop policy if exists courses_delete on public.courses;
create policy courses_select on public.courses
  for select to authenticated
  using (public.is_club_member(club_id) or club_id is null);
create policy courses_insert on public.courses
  for insert to authenticated
  with check (public.is_club_organizer(club_id)
              or (club_id is null and source is null and created_by_profile = auth.uid()));
create policy courses_update on public.courses
  for update to authenticated
  using (public.is_club_organizer(club_id)
         or (club_id is null and source is null and created_by_profile = auth.uid()))
  with check (public.is_club_organizer(club_id)
              or (club_id is null and source is null and created_by_profile = auth.uid()));
create policy courses_delete on public.courses
  for delete to authenticated
  using (public.is_club_organizer(club_id)
         or (club_id is null and source is null and created_by_profile = auth.uid()));

drop policy if exists course_holes_select on public.course_holes;
drop policy if exists course_holes_insert on public.course_holes;
drop policy if exists course_holes_update on public.course_holes;
drop policy if exists course_holes_delete on public.course_holes;
create policy course_holes_select on public.course_holes
  for select to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id
                   and (public.is_club_member(c.club_id) or c.club_id is null)));
create policy course_holes_insert on public.course_holes
  for insert to authenticated
  with check (exists (select 1 from public.courses c
                      where c.id = course_id
                        and (public.is_club_organizer(c.club_id)
                             or (c.club_id is null and c.source is null
                                 and c.created_by_profile = auth.uid()))));
create policy course_holes_update on public.course_holes
  for update to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id
                   and (public.is_club_organizer(c.club_id)
                        or (c.club_id is null and c.source is null
                            and c.created_by_profile = auth.uid()))))
  with check (exists (select 1 from public.courses c
                      where c.id = course_id
                        and (public.is_club_organizer(c.club_id)
                             or (c.club_id is null and c.source is null
                                 and c.created_by_profile = auth.uid()))));
create policy course_holes_delete on public.course_holes
  for delete to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id
                   and (public.is_club_organizer(c.club_id)
                        or (c.club_id is null and c.source is null
                            and c.created_by_profile = auth.uid()))));


-- ===========================================================================
-- 10. TABELLRETTIGHETER
-- ===========================================================================
-- Som i 001: alt tas fra public, anon og authenticated, og authenticated får
-- bare det policyene trenger. service_role beholder standardrettighetene.
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'entitlements', 'round_participants', 'competitions',
                           'competition_participants', 'competition_rounds'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;
grant select, insert, update          on table public.profiles                 to authenticated;
grant select                          on table public.entitlements             to authenticated;
grant select, insert, update, delete  on table public.round_participants       to authenticated;
grant select, insert, update, delete  on table public.competitions             to authenticated;
grant select, insert, update, delete  on table public.competition_participants to authenticated;
grant select, insert, delete          on table public.competition_rounds       to authenticated;


-- ===========================================================================
-- 11. VIEW: deltakerne i en runde, uansett hvor de kommer fra
-- ===========================================================================
-- security_invoker: RLS på round_players gjelder (du ser bare runder du kan
-- lese). Navn og profil hentes av round_player_identity.
create or replace view public.round_roster
with (security_invoker = true) as
select rp.round_id,
       rp.member_id as player_id,
       rp.club_id,
       i.display_name,
       i.profile_id,
       i.is_guest,
       rp.bay_no,
       rp.is_marker,
       rp.team_no
from public.round_players rp
cross join lateral public.round_player_identity(rp.round_id, rp.member_id) i;
comment on view public.round_roster is
  'Deltakerne i en runde med navn og profil: klubbmedlem, profil eller gjest. player_id = round_players.member_id.';
revoke all on table public.round_roster from public, anon, authenticated;
grant select on table public.round_roster to authenticated;


-- ===========================================================================
-- 12. RPC-ER (én transaksjon hver)
-- ===========================================================================

-- --- ensure_profile: profilen ved første innlogging ---------------------------
-- Lager profilen om den mangler, og fyller tomme felt fra klubbmedlemskapet
-- (navn, handicap, portrett). Overskriver aldri det personen har satt selv.
-- Idempotent. Returnerer profilen.
create or replace function public.ensure_profile()
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text;
  v_hcp  numeric;
  v_img  text;
  v_row  public.profiles;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select m.display_name, m.handicap_index, m.avatar_path into v_name, v_hcp, v_img
  from public.club_members m
  where m.user_id = v_uid and m.status = 'active'
  order by m.created_at, m.id
  limit 1;

  insert into public.profiles (id, display_name, handicap_index, avatar_path)
  select v_uid, coalesce(v_name, public.profile_name_from_auth(to_jsonb(u))), v_hcp, v_img
    from auth.users u where u.id = v_uid
  on conflict (id) do update
    set display_name   = coalesce(public.profiles.display_name, excluded.display_name),
        handicap_index = coalesce(public.profiles.handicap_index, excluded.handicap_index),
        avatar_path    = coalesce(public.profiles.avatar_path, excluded.avatar_path)
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Fant ikke innloggingen' using errcode = 'P0002';
  end if;
  return v_row;
end;
$$;
revoke all on function public.ensure_profile() from public, anon;
grant execute on function public.ensure_profile() to authenticated;


-- --- create_loose_round: løs runde med deltakere i ett kall -------------------
-- Du blir eier og første deltaker. p_players: [{"profile_id": "<uuid>"} eller
-- {"guest_name": "Per", "handicap_index": 12.4}, …]. Profiler må være folk du
-- kan se (samme klubb, runde eller konkurranse). Banen må ligge i det felles
-- biblioteket. p_start = true starter runden med én gang (handicapet fryses).
-- Returnerer {round_id, status, participants: [{id, profile_id, display_name}]}.
create or replace function public.create_loose_round(
  p_course_id   uuid,
  p_hole_count  integer default 18,
  p_first_hole  integer default 1,
  p_format      text    default 'stableford',
  p_venue       text    default null,
  p_players     jsonb   default '[]'::jsonb,
  p_start       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     public.profiles;
  v_round  uuid;
  v_entry  jsonb;
  v_prof   uuid;
  v_name   text;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_players, '[]'::jsonb)) <> 'array' then
    raise exception 'Spillerlista må være en liste' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_players, '[]'::jsonb)) > 47 then
    raise exception 'For mange spillere i én runde' using errcode = '22023';
  end if;

  v_me := public.ensure_profile();

  insert into public.rounds (club_id, event_id, course_id, hole_count, first_hole, format, venue, status)
  values (null, null, p_course_id, p_hole_count, p_first_hole, coalesce(p_format, 'stableford'),
          coalesce(p_venue, 'simulator'), 'draft')
  returning id into v_round;

  insert into public.round_participants (round_id, profile_id, display_name)
  values (v_round, v_me.id, coalesce(v_me.display_name, 'Meg'));

  for v_entry in select value from jsonb_array_elements(coalesce(p_players, '[]'::jsonb)) loop
    v_prof := nullif(v_entry ->> 'profile_id', '')::uuid;
    if v_prof is not null then
      if v_prof = v_me.id then
        continue;
      end if;
      select p.display_name into v_name from public.profiles p where p.id = v_prof;
      if not public.can_see_profile(v_prof) then
        raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller konkurranse'
          using errcode = '42501';
      end if;
      insert into public.round_participants (round_id, profile_id, display_name)
      values (v_round, v_prof, coalesce(v_name, 'Spiller'));
    else
      v_name := btrim(coalesce(v_entry ->> 'guest_name', ''));
      if v_name = '' then
        raise exception 'En gjest må ha et navn' using errcode = '22023';
      end if;
      insert into public.round_participants (round_id, display_name, handicap_index)
      values (v_round, v_name, (v_entry ->> 'handicap_index')::numeric);
    end if;
  end loop;

  if coalesce(p_start, true) then
    update public.rounds set status = 'active' where id = v_round;
  end if;

  return jsonb_build_object(
    'round_id', v_round,
    'status', (select r.status from public.rounds r where r.id = v_round),
    'participants', (select jsonb_agg(jsonb_build_object('id', p.id, 'profile_id', p.profile_id,
                                                         'display_name', p.display_name)
                                      order by p.created_at, p.id)
                     from public.round_participants p where p.round_id = v_round)
  );
end;
$$;
revoke all on function public.create_loose_round(uuid, integer, integer, text, text, jsonb, boolean) from public, anon;
grant execute on function public.create_loose_round(uuid, integer, integer, text, text, jsonb, boolean) to authenticated;


-- --- create_competition: ny konkurranse (ikke sesong) -----------------------
-- Med klubb: bare arrangøren. Uten: du blir eier og første deltaker.
-- Regelsettet er jsonb med versjon, som seasons.rules (tomt = Golfgutu-malen).
create or replace function public.create_competition(
  p_kind       text,
  p_name       text,
  p_club_id    uuid  default null,
  p_entry      text  default 'listed',
  p_rules      jsonb default null,
  p_starts_on  date  default null,
  p_ends_on    date  default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_me public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind = 'season' then
    raise exception 'Sesongens konkurranse lages av sesongen' using errcode = '22023';
  end if;
  if p_club_id is not null and not public.is_club_organizer(p_club_id) then
    raise exception 'Bare en arrangør kan lage en konkurranse i klubben' using errcode = '42501';
  end if;

  v_me := public.ensure_profile();

  insert into public.competitions (kind, name, club_id, owner_id, status, entry, rules, starts_on, ends_on)
  values (p_kind, btrim(p_name), p_club_id, case when p_club_id is null then v_me.id end,
          'active', coalesce(p_entry, 'listed'), coalesce(p_rules, '{"version": 1}'::jsonb),
          p_starts_on, p_ends_on)
  returning id into v_id;

  if p_club_id is null then
    insert into public.competition_participants (competition_id, profile_id) values (v_id, v_me.id);
  end if;
  return v_id;
end;
$$;
revoke all on function public.create_competition(text, text, uuid, text, jsonb, date, date) from public, anon;
grant execute on function public.create_competition(text, text, uuid, text, jsonb, date, date) to authenticated;


-- ===========================================================================
-- 13. DAGENS DATA INN I DEN NYE MODELLEN
-- ===========================================================================
-- 13a. En profil per innlogging, fylt fra første aktive klubbmedlemskap.
insert into public.profiles (id, display_name, handicap_index, avatar_path)
select u.id,
       coalesce(m.display_name, public.profile_name_from_auth(to_jsonb(u))),
       m.handicap_index,
       m.avatar_path
from auth.users u
left join lateral (
  select cm.display_name, cm.handicap_index, cm.avatar_path
  from public.club_members cm
  where cm.user_id = u.id and cm.status = 'active'
  order by cm.created_at, cm.id
  limit 1
) m on true
on conflict (id) do nothing;

-- 13b. En konkurranse per sesong: type season, hovedturnering, klubbens tropp.
insert into public.competitions (kind, name, club_id, season_id, status, entry, rules, is_main)
select 'season', s.name, s.club_id, s.id, s.status, 'club', s.rules, true
from public.seasons s
on conflict (season_id) do nothing;

-- 13c. Rundene i sesongens kvelder teller i sesongens konkurranse.
insert into public.competition_rounds (competition_id, round_id, source)
select c.id, r.id, 'season'
from public.rounds r
join public.events e on e.id = r.event_id
join public.competitions c on c.season_id = e.season_id
on conflict (competition_id, round_id) do nothing;


-- ===========================================================================
-- 14. REALTIME
-- ===========================================================================
-- Deltakerlista i en løs runde. Konkurransene hentes ved behov (ikke live).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public'
                   and tablename = 'round_participants') then
    alter publication supabase_realtime add table public.round_participants;
  end if;
end $$;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- Sjekk 9 sammenligner, for hver innlogging med et aktivt klubbmedlemskap, det
-- den ser, styrer og kan føre i klubbrundene med 001-utgavene av hjelperne
-- (kopiert ordrett inn som pg_temp-funksjoner under), og rundepolicyens
-- uttrykk med 001-uttrykket. Den setter request.jwt.claims lokalt i
-- transaksjonen og endrer ingenting.
--
-- create or replace function pg_temp.as_user(u uuid) returns void language sql as $f$
--   select set_config('request.jwt.claim.sub', coalesce(u::text, ''), true),
--          set_config('request.jwt.claims',
--                     case when u is null then '' else json_build_object('sub', u, 'role', 'authenticated')::text end,
--                     true);
-- $f$;
-- -- 001: can_read_round, is_round_organizer og can_score, ordrett.
-- create or replace function pg_temp.old_can_read_round(p_round_id uuid) returns boolean language sql stable as $f$
--   select exists (select 1 from public.rounds r where r.id = p_round_id
--     and ((r.status <> 'draft' and public.is_club_member(r.club_id)) or public.is_club_organizer(r.club_id)));
-- $f$;
-- create or replace function pg_temp.old_is_round_organizer(p_round_id uuid) returns boolean language sql stable as $f$
--   select exists (select 1 from public.rounds r where r.id = p_round_id and public.is_club_organizer(r.club_id));
-- $f$;
-- create or replace function pg_temp.old_can_score(p_round_id uuid, p_member_id uuid) returns boolean
--   language plpgsql stable as $f$
-- declare v_club uuid; v_status text; v_bay smallint; v_marker uuid;
-- begin
--   if auth.uid() is null then return false; end if;
--   select r.club_id, r.status into v_club, v_status from public.rounds r where r.id = p_round_id;
--   if v_club is null then return false; end if;
--   if public.is_club_organizer(v_club) then return true; end if;
--   if v_status <> 'active' then return false; end if;
--   select rp.bay_no into v_bay from public.round_players rp where rp.round_id = p_round_id and rp.member_id = p_member_id;
--   if v_bay is not null then
--     select rp.member_id into v_marker from public.round_players rp
--      where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
--   end if;
--   if v_marker is not null then return public.owns_member(v_marker); end if;
--   return public.owns_member(p_member_id);
-- end $f$;
-- create or replace function pg_temp.diff_for(u uuid) returns bigint language plpgsql as $f$
-- declare n bigint := 0; k bigint;
-- begin
--   perform pg_temp.as_user(u);
--   -- Hjelperne som alle policyene under en runde bruker.
--   select count(*) into k from public.rounds r where r.club_id is not null
--     and (pg_temp.old_can_read_round(r.id) is distinct from public.can_read_round(r.id)
--          or pg_temp.old_is_round_organizer(r.id) is distinct from public.is_round_organizer(r.id));
--   n := n + k;
--   select count(*) into k from public.round_players rp join public.rounds r on r.id = rp.round_id
--    where r.club_id is not null
--      and pg_temp.old_can_score(r.id, rp.member_id) is distinct from public.can_score(r.id, rp.member_id);
--   n := n + k;
--   -- rounds_select: 001-uttrykket mot det nye.
--   select count(*) into k from public.rounds r where r.club_id is not null
--     and ((r.status <> 'draft' and public.is_club_member(r.club_id)) or public.is_club_organizer(r.club_id))
--         is distinct from
--         ((r.status <> 'draft' and public.is_club_member(r.club_id)) or public.is_club_organizer(r.club_id)
--          or (r.club_id is null and (r.owner_id = auth.uid() or public.is_round_participant(r.id)))
--          or (r.status <> 'draft' and public.round_in_readable_competition(r.id)));
--   n := n + k;
--   perform pg_temp.as_user(null);
--   return n;
-- end $f$;
--
-- with
-- nye as (select unnest(array['profiles','entitlements','round_participants','competitions',
--                             'competition_participants','competition_rounds']) as t),
-- f as (select p.proname, p.prosecdef,
--              has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--              has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('profile_name_from_auth','profiles_on_new_user','guard_profiles','rounds_guard_home',
--                           'courses_guard_library','is_round_participant','owns_round_player',
--                           'is_competition_participant','can_read_competition','is_competition_admin',
--                           'round_in_readable_competition','can_link_round','can_see_profile','can_read_round',
--                           'is_round_organizer','can_score','round_player_identity',
--                           'round_participants_before_write','round_participants_after_insert',
--                           'round_participants_before_delete','rounds_freeze_participants',
--                           'side_claims_before_write','guard_competitions','guard_competition_participants',
--                           'competition_rounds_before_insert','competitions_sync_season',
--                           'competition_rounds_sync_round','competition_rounds_sync_event',
--                           'ensure_profile','create_loose_round','create_competition')),
-- brukere as (select distinct m.user_id from public.club_members m where m.user_id is not null and m.status = 'active')
-- select 1 as nr, 'De seks nye tabellene finnes med RLS' as sjekk,
--        (select count(*) = 6 and bool_and(c.relrowsecurity) from nye join pg_class c on c.oid = ('public.' || nye.t)::regclass) as ok
-- union all
-- select 2, 'anon har ingen rettigheter på nye tabeller eller round_roster',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
--                      and table_name in (select t from nye union all select 'round_roster'))
-- union all
-- select 3, 'anon kan ikke kjøre noen ny eller endret funksjon', not exists (select 1 from f where anon_kan)
-- union all
-- select 4, 'authenticated kan kjøre de 3 RPC-ene og 12 hjelperne, ikke de 15 triggerfunksjonene og navnehjelperen',
--        (select count(*) filter (where auth_kan) = 15
--            and count(*) filter (where not auth_kan) = 16 from f)
-- union all
-- select 5, 'Alle innlogginger har en profil',
--        not exists (select 1 from auth.users u where not exists (select 1 from public.profiles p where p.id = u.id))
-- union all
-- select 6, 'Hver sesong har én konkurranse (season, is_main, club) med samme navn, status og regler',
--        not exists (select 1 from public.seasons s
--                    where not exists (select 1 from public.competitions c
--                                      where c.season_id = s.id and c.kind = 'season' and c.is_main
--                                        and c.entry = 'club' and c.club_id = s.club_id and c.name = s.name
--                                        and c.status = s.status and c.rules = s.rules))
-- union all
-- select 7, 'Rundene i sesongens kvelder teller i sesongens konkurranse, og ingen andre er koblet av sesongen',
--        not exists (select 1 from public.rounds r join public.events e on e.id = r.event_id
--                    join public.competitions c on c.season_id = e.season_id
--                    where not exists (select 1 from public.competition_rounds cr
--                                      where cr.competition_id = c.id and cr.round_id = r.id))
--        and not exists (select 1 from public.competition_rounds cr
--                        join public.competitions c on c.id = cr.competition_id
--                        join public.rounds r on r.id = cr.round_id
--                        left join public.events e on e.id = r.event_id
--                        where cr.source = 'season' and c.season_id is distinct from e.season_id)
-- union all
-- select 8, 'Høyst én aktiv hovedkonkurranse per klubb',
--        not exists (select club_id from public.competitions where is_main and status = 'active'
--                    group by club_id having count(*) > 1)
-- union all
-- select 9, 'Klubbmedlemmene ser, styrer og fører de samme klubbrundene som før (001-reglene)',
--        coalesce((select sum(pg_temp.diff_for(b.user_id)) = 0 from brukere b), true)
-- union all
-- select 10, 'Alle klubbrunder har klubb og kveld, alle løse har ingen',
--        not exists (select 1 from public.rounds where (club_id is null) <> (event_id is null))
-- union all
-- select 11, 'Alle deltakere i klubbrunder er klubbmedlemmer i rundens klubb',
--        not exists (select 1 from public.round_players rp join public.rounds r on r.id = rp.round_id
--                    where r.club_id is not null and (rp.club_id is distinct from r.club_id
--                      or not exists (select 1 from public.club_members m where m.id = rp.member_id and m.club_id = r.club_id)))
-- union all
-- select 12, 'Triggerne for speiling og vakter finnes',
--        (select count(*) = 10 from pg_trigger
--         where not tgisinternal
--           and tgname in ('profiles_on_new_user','rounds_guard_home','courses_guard_library',
--                          'round_participants_before_write','round_participants_after_insert',
--                          'competitions_guard','competitions_sync_season','competition_rounds_sync_round',
--                          'competition_rounds_sync_event','rounds_freeze_participants'))
-- union all
-- select 13, 'RLS står fortsatt på rounds, round_players, hole_scores og courses',
--        (select bool_and(relrowsecurity) from pg_class
--         where oid in ('public.rounds'::regclass, 'public.round_players'::regclass,
--                       'public.hole_scores'::regclass, 'public.courses'::regclass))
-- union all
-- select 14, 'round_participants er med i realtime',
--        exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = 'round_participants')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner alt fra 017, også løse runder, felles baner,
-- profiler og konkurranser. Klubbrunder, sesonger og baner i klubbene står.
-- Slå av FoundationFeature i appen først (den er av fra start).
-- ===========================================================================
-- begin;
-- -- Data som ikke passer i 001-skjemaet.
-- delete from public.rounds where club_id is null;
-- delete from public.course_holes h using public.courses c where c.id = h.course_id and c.club_id is null;
-- delete from public.courses where club_id is null;
-- -- Realtime og view.
-- do $$ begin
--   if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--              and schemaname = 'public' and tablename = 'round_participants') then
--     alter publication supabase_realtime drop table public.round_participants;
--   end if;
-- end $$;
-- drop view if exists public.round_roster;
-- -- RPC-er.
-- drop function if exists public.create_competition(text, text, uuid, text, jsonb, date, date);
-- drop function if exists public.create_loose_round(uuid, integer, integer, text, text, jsonb, boolean);
-- drop function if exists public.ensure_profile();
-- -- Triggere på gamle tabeller.
-- drop trigger if exists profiles_on_new_user on auth.users;
-- drop trigger if exists rounds_guard_home on public.rounds;
-- drop trigger if exists rounds_freeze_participants on public.rounds;
-- drop trigger if exists competition_rounds_sync_round on public.rounds;
-- drop trigger if exists competition_rounds_sync_event on public.events;
-- drop trigger if exists competitions_sync_season on public.seasons;
-- drop trigger if exists courses_guard_library on public.courses;
-- -- Policyene fra 001 tilbake.
-- drop policy if exists rounds_select on public.rounds;
-- drop policy if exists rounds_insert on public.rounds;
-- drop policy if exists rounds_update on public.rounds;
-- drop policy if exists rounds_delete on public.rounds;
-- create policy rounds_select on public.rounds for select to authenticated
--   using ((status <> 'draft' and public.is_club_member(club_id)) or public.is_club_organizer(club_id));
-- create policy rounds_insert on public.rounds for insert to authenticated with check (public.is_club_organizer(club_id));
-- create policy rounds_update on public.rounds for update to authenticated
--   using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
-- create policy rounds_delete on public.rounds for delete to authenticated
--   using (public.is_club_organizer(club_id) and status <> 'locked');
-- drop policy if exists side_claims_insert on public.side_claims;
-- drop policy if exists side_claims_update on public.side_claims;
-- drop policy if exists side_claims_delete on public.side_claims;
-- create policy side_claims_insert on public.side_claims for insert to authenticated
--   with check (public.is_round_organizer(round_id) or (public.owns_member(member_id) and public.round_is_active(round_id)));
-- create policy side_claims_update on public.side_claims for update to authenticated
--   using (public.is_round_organizer(round_id) or (public.owns_member(member_id) and public.round_is_active(round_id)))
--   with check (public.is_round_organizer(round_id) or (public.owns_member(member_id) and public.round_is_active(round_id)));
-- create policy side_claims_delete on public.side_claims for delete to authenticated
--   using (public.is_round_organizer(round_id) or (public.owns_member(member_id) and public.round_is_active(round_id)));
-- drop policy if exists courses_select on public.courses;
-- drop policy if exists courses_insert on public.courses;
-- drop policy if exists courses_update on public.courses;
-- drop policy if exists courses_delete on public.courses;
-- create policy courses_select on public.courses for select to authenticated using (public.is_club_member(club_id));
-- create policy courses_insert on public.courses for insert to authenticated with check (public.is_club_organizer(club_id));
-- create policy courses_update on public.courses for update to authenticated
--   using (public.is_club_organizer(club_id)) with check (public.is_club_organizer(club_id));
-- create policy courses_delete on public.courses for delete to authenticated using (public.is_club_organizer(club_id));
-- drop policy if exists course_holes_select on public.course_holes;
-- drop policy if exists course_holes_insert on public.course_holes;
-- drop policy if exists course_holes_update on public.course_holes;
-- drop policy if exists course_holes_delete on public.course_holes;
-- create policy course_holes_select on public.course_holes for select to authenticated
--   using (exists (select 1 from public.courses c where c.id = course_id and public.is_club_member(c.club_id)));
-- create policy course_holes_insert on public.course_holes for insert to authenticated
--   with check (exists (select 1 from public.courses c where c.id = course_id and public.is_club_organizer(c.club_id)));
-- create policy course_holes_update on public.course_holes for update to authenticated
--   using (exists (select 1 from public.courses c where c.id = course_id and public.is_club_organizer(c.club_id)))
--   with check (exists (select 1 from public.courses c where c.id = course_id and public.is_club_organizer(c.club_id)));
-- create policy course_holes_delete on public.course_holes for delete to authenticated
--   using (exists (select 1 from public.courses c where c.id = course_id and public.is_club_organizer(c.club_id)));
-- -- Hjelperne fra 001 tilbake (kroppene er kopiert fra 001_skjema_v1.sql).
-- create or replace function public.can_read_round(p_round_id uuid) returns boolean language sql stable
--   security definer set search_path = '' as $f$
--   select exists (select 1 from public.rounds r where r.id = p_round_id
--     and ((r.status <> 'draft' and public.is_club_member(r.club_id)) or public.is_club_organizer(r.club_id)));
-- $f$;
-- revoke all on function public.can_read_round(uuid) from public, anon;
-- grant execute on function public.can_read_round(uuid) to authenticated;
-- create or replace function public.is_round_organizer(p_round_id uuid) returns boolean language sql stable
--   security definer set search_path = '' as $f$
--   select exists (select 1 from public.rounds r where r.id = p_round_id and public.is_club_organizer(r.club_id));
-- $f$;
-- revoke all on function public.is_round_organizer(uuid) from public, anon;
-- grant execute on function public.is_round_organizer(uuid) to authenticated;
-- create or replace function public.can_score(p_round_id uuid, p_member_id uuid) returns boolean
--   language plpgsql stable security definer set search_path = '' as $f$
-- declare v_club uuid; v_status text; v_bay smallint; v_marker uuid;
-- begin
--   if auth.uid() is null then return false; end if;
--   select r.club_id, r.status into v_club, v_status from public.rounds r where r.id = p_round_id;
--   if v_club is null then return false; end if;
--   if public.is_club_organizer(v_club) then return true; end if;
--   if v_status <> 'active' then return false; end if;
--   select rp.bay_no into v_bay from public.round_players rp where rp.round_id = p_round_id and rp.member_id = p_member_id;
--   if v_bay is not null then
--     select rp.member_id into v_marker from public.round_players rp
--      where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
--   end if;
--   if v_marker is not null then return public.owns_member(v_marker); end if;
--   return public.owns_member(p_member_id);
-- end $f$;
-- revoke all on function public.can_score(uuid, uuid) from public, anon;
-- grant execute on function public.can_score(uuid, uuid) to authenticated;
-- create or replace function public.side_claims_before_write() returns trigger language plpgsql
--   security definer set search_path = '' as $f$
-- declare v_club uuid;
-- begin
--   select r.club_id into v_club from public.rounds r where r.id = new.round_id;
--   new.created_by := coalesce(public.my_member_id(v_club), new.created_by);
--   return new;
-- end $f$;
-- revoke all on function public.side_claims_before_write() from public, anon, authenticated;
-- -- Nye tabeller og hjelpere.
-- drop table if exists public.competition_rounds, public.competition_participants, public.competitions,
--   public.round_participants, public.entitlements cascade;
-- -- Kolonner og nøkler på gamle tabeller.
-- alter table public.round_players drop constraint if exists round_players_participant_fk;
-- alter table public.round_players drop constraint if exists round_players_round_id_fk;
-- alter table public.round_players drop column if exists participant_round_id;
-- alter table public.round_players alter column club_id set not null;
-- alter table public.rounds drop constraint if exists rounds_home_check;
-- alter table public.rounds drop constraint if exists rounds_course_id_fk;
-- drop index if exists public.rounds_owner_idx;
-- alter table public.rounds drop column if exists owner_id;
-- alter table public.rounds alter column club_id set not null;
-- alter table public.rounds alter column event_id set not null;
-- drop index if exists public.courses_external_key;
-- drop index if exists public.courses_shared_idx;
-- alter table public.courses drop constraint if exists courses_external_whole;
-- alter table public.courses drop column if exists created_by_profile;
-- alter table public.courses drop column if exists fetched_at;
-- alter table public.courses drop column if exists external_id;
-- alter table public.courses drop column if exists source;
-- alter table public.courses alter column club_id set not null;
-- -- Profilene sist (rounds.owner_id og courses.created_by_profile pekte hit).
-- drop table if exists public.profiles cascade;
-- drop function if exists public.guard_profiles();
-- drop function if exists public.profiles_on_new_user();
-- drop function if exists public.profile_name_from_auth(jsonb);
-- -- Hjelperne og triggerfunksjonene til slutt (policyene på profiles brukte dem).
-- drop function if exists public.round_player_identity(uuid, uuid);
-- drop function if exists public.can_see_profile(uuid);
-- drop function if exists public.can_link_round(uuid);
-- drop function if exists public.round_in_readable_competition(uuid);
-- drop function if exists public.is_competition_admin(uuid);
-- drop function if exists public.can_read_competition(uuid);
-- drop function if exists public.is_competition_participant(uuid);
-- drop function if exists public.owns_round_player(uuid, uuid);
-- drop function if exists public.is_round_participant(uuid);
-- drop function if exists public.competition_rounds_sync_event();
-- drop function if exists public.competition_rounds_sync_round();
-- drop function if exists public.competitions_sync_season();
-- drop function if exists public.competition_rounds_before_insert();
-- drop function if exists public.guard_competition_participants();
-- drop function if exists public.guard_competitions();
-- drop function if exists public.rounds_freeze_participants();
-- drop function if exists public.round_participants_before_delete();
-- drop function if exists public.round_participants_after_insert();
-- drop function if exists public.round_participants_before_write();
-- drop function if exists public.courses_guard_library();
-- drop function if exists public.rounds_guard_home();
-- commit;
