-- ===========================================================================
-- 031 – TURNERINGEN SOM KJERNE, TRINN 1 (FASE 22) – KJØRT PÅ TEST 09.10.2026
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). IKKE KJØRT mot Supabase,
-- verken test eller prod. Prøvd lokalt (sql/lokal/031_prove.sql, to kjøringer
-- på rad). Krever 001–030 (028 finnes ikke).
--
-- Hvorfor (docs/fase-22-turnering-som-kjerne.md): appen skal kunne brukes av
-- golfklubber og simulatorsentre som kjører mange turneringer samtidig. I dag
-- er reglene bygget rundt klubben: én aktiv runde per klubb, én aktiv sesong
-- per klubb, én kveld per dato per klubb, og kveldene hører til klubbens
-- sesong. Målbildet er at turneringen (competitions) er kjernen: spilledager
-- og runder hører til en turnering, og en klubb eller arena kan ha mange
-- turneringer i gang samtidig.
--
-- Dette er TRINN 1 av fem, og det er bare ADDITIVT. Dagens app merker ingen
-- forskjell, fordi den henter navngitte kolonner (ikke select *), og fordi
-- alle reglene den bygger på, står:
--   * rounds_one_active_per_club, seasons_one_active_per_club,
--     events_one_per_date og competitions_one_main_active står urørt;
--   * ingen policy og ingen hjelpefunksjon fra 001–030 endres;
--   * ingen ny verdi i en kolonne appen dekoder strengt (status, kind, entry,
--     source), derfor er ventelista en egen tabell og ikke en ny status.
--
-- Hva fila gjør:
--   1. app_config: nøkkel/verdi som appen leser etter innlogging. Første
--      nøkkel er min_ios_build (0 nå). Når appen fra fase 23 leser den, kan
--      vi senere stenge ute gamle bygg før trinn 4 (ikke-additivt).
--   2. clubs.kind: group (gjeng, standard), golf_club, simulator_center.
--   3. competitions: hvem som kan melde seg på (signup_audience: members |
--      anyone), om turneringen vises i arenaens offentlige liste (listed),
--      tak (max_entrants), venteliste (waitlist_enabled), påmeldingsvindu
--      (signup_opens_at, signup_closes_at) og sted (venue: simulator | course).
--      Alt er av eller tomt som standard, så alle turneringer er som før.
--   4. competition_staff: flere arrangører (og funksjonærer) per turnering,
--      som profiler. Lesing: den som ser turneringen. Skriving: den som styrer
--      turneringen i dag (is_competition_admin, uendret). Rettighetene staben
--      får, kobles på i trinn 2 (fase 23), ikke her.
--   5. competition_waitlist: ventelista når turneringen er full. Bare lesing
--      (egen rad og arrangøren). RPC-ene som skriver, kommer i trinn 2.
--   6. events.competition_id: spilledagen hører til en turnering. Fylles fra
--      sesongen for alle kvelder i dag, og holdes i takt med season_id av en
--      trigger i begge retninger. Ny unik indeks: én spilledag per dato per
--      turnering (ved siden av den gamle per klubb).
--   7. rounds.wave_no (pulje, 1 som standard) og en ny unik indeks: høyst én
--      aktiv runde per spilledag og pulje (ved siden av den gamle per klubb).
--   8. round_start_groups: startlista for en runde (gruppe/flight, starttid,
--      starthull for kanonstart, bås eller simulator). Les som runden, skriv
--      som rundens arrangør (can_read_round og is_round_organizer, uendret).
--   9. activity.competition_id: hvilken turnering en hendelse gjelder, fylt
--      av en trigger (fra spilledagen, runden, eller data->>'competition' for
--      plassbytte), og fylt for det som finnes. Ny indeks for feeden per
--      turnering. activity.club_id er fortsatt påkrevd (push_queue bygger på
--      klubben); det endres i trinn 4.
--  10. is_competition_staff(): ny hjelpefunksjon. Brukes ikke av noen policy
--      i 031.
--  11. To indekser fra lasttesten (docs/fase-22-turnering-som-kjerne.md,
--      kap. 9): rounds (club_id, locked_at desc) for låste runder i Hjem, og
--      competition_participants (competition_id) for RLS-oppslaget i
--      is_competition_participant.
--
-- Hva fila IKKE gjør (kommer i trinn 2–5, se dokumentet):
--   * utvider ikke is_competition_admin, can_read_competition, can_read_round
--     eller can_score med staben, åpen påmelding eller offentlige turneringer;
--   * fjerner ingen av de gamle unike indeksene;
--   * snur ikke speilingen sesong → turnering;
--   * lar ikke deltakere uten klubbmedlemskap spille klubbrunder;
--   * gjør ikke activity.club_id eller push_queue.club_id valgfri.
--
-- Låser og varighet: ADD COLUMN med konstant standardverdi er bare metadata.
-- Indeksene og fremmednøklene bygges i transaksjonen og holder skrivelås på
-- tabellene i noen millisekunder med dagens datamengde (Golfgutu: hundrevis
-- av rader). I en stor database bør indeksene lages med CONCURRENTLY utenfor
-- transaksjonen (se rullebakken og dokumentet).
--
-- Mønsteret fra 001–030 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace,
-- triggerfunksjoner tas fra authenticated også, kontroll og rullebakke
-- nederst.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. APP_CONFIG: minste appversjon og andre brytere appen leser
-- ===========================================================================
create table if not exists public.app_config (
  key         text primary key check (key ~ '^[a-z][a-z0-9_]{0,39}$'),
  value       jsonb not null check (pg_column_size(value) <= 4096),
  updated_at  timestamptz not null default now()
);
comment on table public.app_config is
  'Brytere appen leser etter innlogging. min_ios_build = laveste bygg som får bruke databasen '
  '(appen ber om oppdatering under det). Skrives bare i SQL Editor / service_role.';

insert into public.app_config (key, value)
values ('min_ios_build', '{"build": 0}'::jsonb)
on conflict (key) do nothing;

drop trigger if exists app_config_set_updated_at on public.app_config;
create trigger app_config_set_updated_at before update on public.app_config
  for each row execute function public.set_updated_at();


-- ===========================================================================
-- 2. CLUBS.KIND: gjeng, golfklubb eller simulatorsenter
-- ===========================================================================
alter table public.clubs
  add column if not exists kind text not null default 'group';
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.clubs'::regclass and conname = 'clubs_kind_check') then
    alter table public.clubs add constraint clubs_kind_check
      check (kind in ('group', 'golf_club', 'simulator_center'));
  end if;
end $$;
comment on column public.clubs.kind is
  'group = gjeng (Golfgutu), golf_club = golfklubb, simulator_center = simulatorsenter. '
  'Styrer bare tekster og standardvalg i appen, ikke tilgang.';


-- ===========================================================================
-- 3. COMPETITIONS: påmelding, tak, venteliste og sted
-- ===========================================================================
alter table public.competitions
  add column if not exists signup_audience  text not null default 'members',
  add column if not exists listed           boolean not null default false,
  add column if not exists max_entrants     integer,
  add column if not exists waitlist_enabled boolean not null default false,
  add column if not exists signup_opens_at  timestamptz,
  add column if not exists signup_closes_at timestamptz,
  add column if not exists venue            text;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_signup_audience_check') then
    alter table public.competitions add constraint competitions_signup_audience_check
      check (signup_audience in ('members', 'anyone'));
  end if;
  -- Klubbens tropp (entry = club) er bare medlemmer. Åpen påmelding er en liste.
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_anyone_listed') then
    alter table public.competitions add constraint competitions_anyone_listed
      check (signup_audience = 'members' or entry <> 'club');
  end if;
  -- Den offentlige lista er arenaens (klubbens).
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_listed_needs_club') then
    alter table public.competitions add constraint competitions_listed_needs_club
      check (not listed or club_id is not null);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_max_entrants_check') then
    alter table public.competitions add constraint competitions_max_entrants_check
      check (max_entrants is null or max_entrants between 2 and 5000);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_waitlist_needs_cap') then
    alter table public.competitions add constraint competitions_waitlist_needs_cap
      check (not waitlist_enabled or max_entrants is not null);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_signup_window') then
    alter table public.competitions add constraint competitions_signup_window
      check (signup_opens_at is null or signup_closes_at is null or signup_closes_at >= signup_opens_at);
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.competitions'::regclass
                   and conname = 'competitions_venue_check') then
    alter table public.competitions add constraint competitions_venue_check
      check (venue is null or venue in ('simulator', 'course'));
  end if;
end $$;

comment on column public.competitions.signup_audience is
  'members = bare klubbens medlemmer (eller de med invitasjon, uten klubb). anyone = alle innloggede '
  'som finner turneringen. Tas i bruk av RLS i trinn 2 (fase 23).';
comment on column public.competitions.listed is
  'Vises i arenaens offentlige liste over turneringer. Krever klubb. Tas i bruk i trinn 2.';
comment on column public.competitions.max_entrants is
  'Tak på antall påmeldte (status active). Tom = ingen grense.';
comment on column public.competitions.waitlist_enabled is
  'Når taket er nådd, havner nye på venteliste (competition_waitlist) i stedet for å avvises.';
comment on column public.competitions.venue is
  'Standard sted for turneringens runder: simulator (båser) eller course (ekte bane, startliste). '
  'Tom = som rundene sier (rounds.venue).';


-- ===========================================================================
-- 4. COMPETITION_STAFF: flere arrangører per turnering
-- ===========================================================================
create table if not exists public.competition_staff (
  competition_id  uuid not null references public.competitions(id) on delete cascade,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  -- organizer = styrer turneringen (spilledager, runder, påmelding, stab).
  -- scorer    = funksjonær: kan føre for alle i turneringens runder.
  role            text not null default 'organizer' check (role in ('organizer', 'scorer')),
  added_by        uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (competition_id, profile_id)
);
comment on table public.competition_staff is
  'Arrangører og funksjonærer per turnering (profiler, også uten klubbmedlemskap). '
  'I 031 er tabellen bare data; rettighetene kobles på i trinn 2.';
create index if not exists competition_staff_profile_idx on public.competition_staff (profile_id);

create or replace function public.guard_competition_staff()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (new.competition_id is distinct from old.competition_id
          or new.profile_id is distinct from old.profile_id) then
    raise exception 'Bare rollen kan endres' using errcode = '42501';
  end if;
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.added_by := auth.uid();
    if not public.can_see_profile(new.profile_id) then
      raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller turnering'
        using errcode = '42501';
    end if;
  elsif new.added_by is distinct from old.added_by
        and not (new.added_by is null
                 and not exists (select 1 from public.profiles p where p.id = old.added_by)) then
    raise exception 'Hvem som la til, endres ikke' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_competition_staff() from public, anon, authenticated;

drop trigger if exists competition_staff_guard on public.competition_staff;
create trigger competition_staff_guard
  before insert or update on public.competition_staff
  for each row execute function public.guard_competition_staff();


-- ===========================================================================
-- 5. COMPETITION_WAITLIST: venteliste når turneringen er full
-- ===========================================================================
-- Egen tabell, ikke en ny status i competition_participants: dagens app
-- dekoder status strengt (active | withdrawn), og en ukjent verdi ville gjort
-- hele påmeldingslista ulesbar for gamle bygg.
create table if not exists public.competition_waitlist (
  id                uuid primary key default gen_random_uuid(),
  competition_id    uuid not null references public.competitions(id) on delete cascade,
  profile_id        uuid not null references public.profiles(id) on delete cascade,
  -- Satt når personen er medlem i turneringens klubb (meldes på som medlemmet).
  member_id         uuid references public.club_members(id) on delete cascade,
  created_at        timestamptz not null default now(),
  -- Plassen er tilbudt (en plass ble ledig) og må tas innen fristen.
  offered_at        timestamptz,
  offer_expires_at  timestamptz,
  constraint competition_waitlist_one_per_profile unique (competition_id, profile_id),
  constraint competition_waitlist_offer_whole
    check ((offered_at is null) = (offer_expires_at is null))
);
comment on table public.competition_waitlist is
  'Ventelista. Rekkefølgen er created_at. Skrives bare av RPC-ene i trinn 2 (fase 23).';
create index if not exists competition_waitlist_queue_idx
  on public.competition_waitlist (competition_id, created_at);
create index if not exists competition_waitlist_profile_idx
  on public.competition_waitlist (profile_id);


-- ===========================================================================
-- 6. EVENTS.COMPETITION_ID: spilledagen hører til en turnering
-- ===========================================================================
alter table public.events add column if not exists competition_id uuid;
comment on column public.events.competition_id is
  'Turneringen spilledagen hører til. For kvelder i en sesong er det sesongens turnering '
  '(holdes i takt med season_id av events_sync_competition). Tom = klubbens egen terminliste.';

-- Fylles for det som finnes, uten å flytte updated_at (appen bruker den til
-- å se endringer).
alter table public.events disable trigger events_set_updated_at;
update public.events e
   set competition_id = c.id
  from public.competitions c
 where c.season_id = e.season_id
   and e.competition_id is distinct from c.id;
alter table public.events enable trigger events_set_updated_at;

do $$
begin
  -- Samme klubb som turneringen (den sammensatte nøkkelen fra 017).
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.events'::regclass and conname = 'events_competition_fk') then
    alter table public.events add constraint events_competition_fk
      foreign key (competition_id, club_id) references public.competitions (id, club_id);
  end if;
end $$;

-- Én spilledag per dato per turnering. Den gamle (én per dato per klubb)
-- står til trinn 4.
create unique index if not exists events_one_per_date_per_competition
  on public.events (competition_id, event_date) where competition_id is not null;

-- I takt med sesongen, begge veier:
--   * season_id satt eller endret → sesongens turnering (sesongen vinner),
--   * tatt ut av sesongen → ut av sesongens turnering,
--   * competition_id satt eller endret (ny app) → season_id fra turneringen
--     (tom for andre turneringer enn sesonger), så Tavla i dagens app ser
--     kvelden når den legges i jakkeracet,
--   * tatt ut av turneringen → ut av sesongen.
create or replace function public.events_sync_competition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.season_id is not null
     and (tg_op = 'INSERT' or new.season_id is distinct from old.season_id) then
    select c.id into new.competition_id
      from public.competitions c where c.season_id = new.season_id;
  elsif tg_op = 'UPDATE' and new.season_id is null and old.season_id is not null
        and new.competition_id is not distinct from old.competition_id then
    new.competition_id := null;
  elsif new.competition_id is not null
        and (tg_op = 'INSERT' or new.competition_id is distinct from old.competition_id) then
    select c.season_id into new.season_id
      from public.competitions c where c.id = new.competition_id;
  elsif tg_op = 'UPDATE' and new.competition_id is null and old.competition_id is not null
        and new.season_id is not distinct from old.season_id then
    new.season_id := null;
  end if;
  return new;
end;
$$;
revoke all on function public.events_sync_competition() from public, anon, authenticated;

drop trigger if exists events_sync_competition on public.events;
create trigger events_sync_competition
  before insert or update of season_id, competition_id on public.events
  for each row execute function public.events_sync_competition();

-- Rundene følger kvelden også når den flyttes med competition_id (triggeren
-- over endrer da season_id, og en «update of season_id»-trigger fyrer bare
-- for kolonner i SET). Funksjonen fra 017 er uendret.
drop trigger if exists competition_rounds_sync_event on public.events;
create trigger competition_rounds_sync_event
  after update of season_id, competition_id on public.events
  for each row execute function public.competition_rounds_sync_event();


-- ===========================================================================
-- 7. ROUNDS.WAVE_NO: én aktiv runde per spilledag og pulje
-- ===========================================================================
alter table public.rounds
  add column if not exists wave_no smallint not null default 1;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.rounds'::regclass and conname = 'rounds_wave_no_check') then
    alter table public.rounds add constraint rounds_wave_no_check check (wave_no between 1 and 20);
  end if;
end $$;
comment on column public.rounds.wave_no is
  'Pulje på spilledagen (1 = standard). To puljer kan gå samtidig, f.eks. formiddag og kveld, '
  'eller to båsrekker. Regelen «én aktiv runde» gjelder per spilledag og pulje (fra trinn 4).';

-- Ny regel ved siden av den gamle. Med dagens data er den alltid oppfylt:
-- én aktiv per klubb gir høyst én per kveld.
create unique index if not exists rounds_one_active_per_event_wave
  on public.rounds (event_id, wave_no) where status = 'active' and event_id is not null;


-- ===========================================================================
-- 8. ROUND_START_GROUPS: startliste (flight, starttid, starthull, bås)
-- ===========================================================================
-- Gruppenummeret er round_players.bay_no (bås i simulator, flight på bane,
-- sql/015). Tabellen gir gruppen tid, starthull og ressurs. Ingen rad = som i
-- dag (rundens tee_time, hull 1).
create table if not exists public.round_start_groups (
  round_id        uuid not null references public.rounds(id) on delete cascade,
  group_no        smallint not null check (group_no between 1 and 99),
  starts_at       time,
  -- Kanonstart: hullet gruppen starter på (banens nummer). Tom = rundens første hull.
  start_hole      smallint check (start_hole between 1 and 18),
  -- Bås eller simulator («Bås 3», «Trackman 2»), eller tee («Tee 10»).
  resource_label  text check (resource_label is null or char_length(btrim(resource_label)) between 1 and 40),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (round_id, group_no)
);
comment on table public.round_start_groups is
  'Startlista: tid, starthull og bås/simulator per gruppe (= round_players.bay_no).';

drop trigger if exists round_start_groups_set_updated_at on public.round_start_groups;
create trigger round_start_groups_set_updated_at before update on public.round_start_groups
  for each row execute function public.set_updated_at();


-- ===========================================================================
-- 9. ACTIVITY.COMPETITION_ID: hvilken turnering hendelsen gjelder
-- ===========================================================================
alter table public.activity add column if not exists competition_id uuid;
comment on column public.activity.competition_id is
  'Turneringen hendelsen gjelder. Fylles av activity_fill_competition (spilledagen, runden, '
  'eller data->>competition for plassbytte). Brukes av Hjem-feeden per turnering (trinn 2).';

-- Fylles for det som finnes (activity har ingen update-triggere).
update public.activity a
   set competition_id = c.id
  from public.competitions c
 where a.competition_id is null
   and a.kind = 'table_changed'
   and (a.data ->> 'competition') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and c.id = (a.data ->> 'competition')::uuid
   and c.club_id = a.club_id;
update public.activity a
   set competition_id = e.competition_id
  from public.events e
 where a.competition_id is null
   and a.event_id = e.id
   and e.competition_id is not null;
update public.activity a
   set competition_id = e.competition_id
  from public.rounds r
  join public.events e on e.id = r.event_id
 where a.competition_id is null
   and a.event_id is null
   and a.round_id = r.id
   and e.competition_id is not null;

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.activity'::regclass and conname = 'activity_competition_fk') then
    alter table public.activity add constraint activity_competition_fk
      foreign key (competition_id, club_id) references public.competitions (id, club_id)
      on delete set null (competition_id);
  end if;
end $$;

create index if not exists activity_competition_time_idx
  on public.activity (competition_id, created_at desc) where competition_id is not null;

create or replace function public.activity_fill_competition()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.competition_id is not null then
    return new;
  end if;
  if new.kind = 'table_changed'
     and (new.data ->> 'competition') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select c.id into new.competition_id
      from public.competitions c
     where c.id = (new.data ->> 'competition')::uuid and c.club_id = new.club_id;
  end if;
  if new.competition_id is null and new.event_id is not null then
    select e.competition_id into new.competition_id
      from public.events e where e.id = new.event_id;
  end if;
  if new.competition_id is null and new.round_id is not null then
    select e.competition_id into new.competition_id
      from public.rounds r join public.events e on e.id = r.event_id
     where r.id = new.round_id;
  end if;
  return new;
end;
$$;
revoke all on function public.activity_fill_competition() from public, anon, authenticated;

-- Navnet sorteres etter activity_before_insert og før zz_quota.
drop trigger if exists activity_fill_competition on public.activity;
create trigger activity_fill_competition
  before insert on public.activity
  for each row execute function public.activity_fill_competition();


-- ===========================================================================
-- 10. HJELPEFUNKSJON (brukes ikke av noen policy i 031)
-- ===========================================================================
-- Er jeg i staben til turneringen (valgfritt: med denne rollen)?
create or replace function public.is_competition_staff(p_competition_id uuid, p_role text default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.competition_staff s
    where s.competition_id = p_competition_id
      and s.profile_id = auth.uid()
      and (p_role is null or s.role = p_role)
  );
$$;
revoke all on function public.is_competition_staff(uuid, text) from public, anon;
grant execute on function public.is_competition_staff(uuid, text) to authenticated;


-- ===========================================================================
-- 11. INDEKSER FRA LASTTESTEN (dokumentet, kap. 9)
-- ===========================================================================
-- Hjem: klubbrundene som er låst de siste 30 dagene, nyeste først.
create index if not exists rounds_club_locked_idx
  on public.rounds (club_id, locked_at desc) where status = 'locked';
-- RLS: is_competition_participant (017) slår opp påmeldte per turnering for
-- hver turnering du kan se. De unike indeksene fra 017 er delindekser (bare
-- medlem / bare profil) og kan ikke brukes til «alle påmeldte i turneringen»,
-- så oppslaget ble en full gjennomgang av tabellen per turnering.
create index if not exists competition_participants_competition_idx
  on public.competition_participants (competition_id);


-- ===========================================================================
-- 12. RLS OG RETTIGHETER FOR DE NYE TABELLENE
-- ===========================================================================
alter table public.app_config           enable row level security;
alter table public.competition_staff    enable row level security;
alter table public.competition_waitlist enable row level security;
alter table public.round_start_groups   enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- app_config: alle innloggede leser. Ingen skriver fra appen.
create policy app_config_select on public.app_config
  for select to authenticated using (true);

-- competition_staff: den som ser turneringen, ser staben (og du ser deg selv).
-- Den som styrer turneringen i dag (klubbens arrangør eller eieren), legger
-- til, endrer og tar ut. Du kan gå ut selv.
create policy competition_staff_select on public.competition_staff
  for select to authenticated
  using (profile_id = auth.uid() or public.can_read_competition(competition_id));
create policy competition_staff_insert on public.competition_staff
  for insert to authenticated with check (public.is_competition_admin(competition_id));
create policy competition_staff_update on public.competition_staff
  for update to authenticated
  using (public.is_competition_admin(competition_id))
  with check (public.is_competition_admin(competition_id));
create policy competition_staff_delete on public.competition_staff
  for delete to authenticated
  using (public.is_competition_admin(competition_id) or profile_id = auth.uid());

-- competition_waitlist: din egen plass, og arrangøren ser hele lista.
create policy competition_waitlist_select on public.competition_waitlist
  for select to authenticated
  using (profile_id = auth.uid() or public.is_competition_admin(competition_id));

-- round_start_groups: som round_holes (001).
create policy round_start_groups_select on public.round_start_groups
  for select to authenticated using (public.can_read_round(round_id));
create policy round_start_groups_insert on public.round_start_groups
  for insert to authenticated with check (public.is_round_organizer(round_id));
create policy round_start_groups_update on public.round_start_groups
  for update to authenticated
  using (public.is_round_organizer(round_id)) with check (public.is_round_organizer(round_id));
create policy round_start_groups_delete on public.round_start_groups
  for delete to authenticated using (public.is_round_organizer(round_id));

do $$
declare
  t text;
begin
  foreach t in array array['app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;
grant select                          on table public.app_config           to authenticated;
grant select, insert, update, delete  on table public.competition_staff    to authenticated;
grant select                          on table public.competition_waitlist to authenticated;
grant select, insert, update, delete  on table public.round_start_groups   to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          p.proconfig
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('guard_competition_staff', 'events_sync_competition',
--                       'activity_fill_competition', 'is_competition_staff')
-- ), t as (
--   select unnest(array['app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups']) as tabell
-- )
-- select 1 as nr, 'De nye kolonnene finnes (clubs, competitions, events, rounds, activity)' as sjekk,
--        (select count(*) = 11 from information_schema.columns
--          where table_schema = 'public'
--            and (table_name, column_name) in (('clubs', 'kind'),
--                 ('competitions', 'signup_audience'), ('competitions', 'listed'),
--                 ('competitions', 'max_entrants'), ('competitions', 'waitlist_enabled'),
--                 ('competitions', 'signup_opens_at'), ('competitions', 'signup_closes_at'),
--                 ('competitions', 'venue'), ('events', 'competition_id'),
--                 ('rounds', 'wave_no'), ('activity', 'competition_id'))) as ok
-- union all
-- select 2, 'De fire nye tabellene har RLS på, og anon har ingenting',
--        (select bool_and(c.relrowsecurity) from t join pg_class c on c.oid = ('public.' || t.tabell)::regclass)
--        and not exists (select 1 from information_schema.role_table_grants g join t on g.table_name = t.tabell
--                         where g.table_schema = 'public' and g.grantee in ('anon', 'PUBLIC'))
-- union all
-- select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
--        (select count(*) = 3 from pg_indexes where schemaname = 'public'
--          and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club', 'competitions_one_main_active'))
--        and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
--                     and conrelid = 'public.events'::regclass)
-- union all
-- select 4, 'De nye indeksene finnes',
--        (select count(*) = 5 from pg_indexes where schemaname = 'public'
--          and indexname in ('events_one_per_date_per_competition', 'rounds_one_active_per_event_wave',
--                            'activity_competition_time_idx', 'rounds_club_locked_idx',
--                            'competition_participants_competition_idx'))
-- union all
-- select 5, 'Paritet: hver kveld i en sesong hører til sesongens turnering, og ingen andre har en sesong',
--        not exists (select 1 from public.events e
--                    left join public.competitions c on c.season_id = e.season_id
--                    where e.season_id is not null and e.competition_id is distinct from c.id)
--        and not exists (select 1 from public.events e join public.competitions c on c.id = e.competition_id
--                        where c.season_id is distinct from e.season_id)
-- union all
-- select 6, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
--        not exists (
--          (select e.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--            where e.season_id is not null
--           except
--           select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--             join public.competitions c on c.id = e.competition_id where c.season_id is not null)
--          union all
--          (select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
--             join public.competitions c on c.id = e.competition_id where c.season_id is not null
--           except
--           select c.season_id, cr.round_id from public.competition_rounds cr
--             join public.competitions c on c.id = cr.competition_id
--            where cr.source = 'season' and c.season_id is not null))
-- union all
-- select 7, 'Ingen policy fra 001–030 bruker staben eller de nye kolonnene',
--        not exists (select 1 from pg_policies where schemaname = 'public'
--                     and tablename not in ('app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups')
--                     and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(competition_staff|is_competition_staff|signup_audience|listed|wave_no)')
-- union all
-- select 8, 'Triggerfunksjonene kan ikke kalles av appen; is_competition_staff av innloggede, ikke anon',
--        (select bool_and(not auth_kan and not anon_kan) from f
--          where proname in ('guard_competition_staff', 'events_sync_competition', 'activity_fill_competition'))
--        and (select auth_kan and not anon_kan from f where proname = 'is_competition_staff')
-- union all
-- select 9, 'Alle fire funksjonene har tom search_path',
--        (select count(*) = 4 and bool_and('search_path=""' = any(proconfig)) from f)
-- union all
-- select 10, 'Triggerne finnes (events begge veier, rundene følger kvelden, aktivitet, stab)',
--        (select count(*) = 4 from pg_trigger where not tgisinternal and tgname in
--          ('events_sync_competition', 'competition_rounds_sync_event', 'activity_fill_competition',
--           'competition_staff_guard'))
-- union all
-- select 11, 'app_config har min_ios_build',
--        exists (select 1 from public.app_config where key = 'min_ios_build' and value ? 'build')
-- union all
-- select 12, 'Plassbytte-linjer er koblet til turneringen sin',
--        not exists (select 1 from public.activity a join public.competitions c
--                      on c.id::text = a.data ->> 'competition' and c.club_id = a.club_id
--                    where a.kind = 'table_changed' and a.competition_id is distinct from c.id)
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test; data i de nye tabellene og kolonnene går tapt)
-- ===========================================================================
-- Ingen app bruker de nye kolonnene før fase 23, så rullebakken er trygg så
-- lenge appen fra fase 23 ikke er slått på mot databasen.
--
-- begin;
-- drop index if exists public.competition_participants_competition_idx;
-- drop index if exists public.rounds_club_locked_idx;
-- drop function if exists public.is_competition_staff(uuid, text);
-- drop trigger if exists activity_fill_competition on public.activity;
-- drop function if exists public.activity_fill_competition();
-- drop index if exists public.activity_competition_time_idx;
-- alter table public.activity drop constraint if exists activity_competition_fk;
-- alter table public.activity drop column if exists competition_id;
-- drop table if exists public.round_start_groups;
-- drop index if exists public.rounds_one_active_per_event_wave;
-- alter table public.rounds drop constraint if exists rounds_wave_no_check;
-- alter table public.rounds drop column if exists wave_no;
-- drop trigger if exists competition_rounds_sync_event on public.events;
-- create trigger competition_rounds_sync_event
--   after update of season_id on public.events
--   for each row execute function public.competition_rounds_sync_event();
-- drop trigger if exists events_sync_competition on public.events;
-- drop function if exists public.events_sync_competition();
-- drop index if exists public.events_one_per_date_per_competition;
-- alter table public.events drop constraint if exists events_competition_fk;
-- alter table public.events drop column if exists competition_id;
-- drop table if exists public.competition_waitlist;
-- drop table if exists public.competition_staff;
-- drop function if exists public.guard_competition_staff();
-- alter table public.competitions
--   drop constraint if exists competitions_signup_audience_check,
--   drop constraint if exists competitions_anyone_listed,
--   drop constraint if exists competitions_listed_needs_club,
--   drop constraint if exists competitions_max_entrants_check,
--   drop constraint if exists competitions_waitlist_needs_cap,
--   drop constraint if exists competitions_signup_window,
--   drop constraint if exists competitions_venue_check,
--   drop column if exists signup_audience,
--   drop column if exists listed,
--   drop column if exists max_entrants,
--   drop column if exists waitlist_enabled,
--   drop column if exists signup_opens_at,
--   drop column if exists signup_closes_at,
--   drop column if exists venue;
-- alter table public.clubs drop constraint if exists clubs_kind_check;
-- alter table public.clubs drop column if exists kind;
-- drop table if exists public.app_config;
-- commit;
