-- ===========================================================================
-- 008 – SOSIALT: AKTIVITET, REAKSJONER, TRÅD, TIPPEKUPONG, PUSH-TOKENS, BILDER
-- ===========================================================================
-- Status: UTKAST til godkjenning (ROADMAP B5). IKKE KJØRT noe sted utenom en
-- lokal, midlertidig Postgres (se sql/README.md, «Lokal sjekk»). Kjøres først
-- på TEST etter ja fra brukeren, så kontrollspørringene nederst. Prod først
-- etter ny godkjenning.
--
-- Krever 001 (tabeller og hjelpefunksjonene my_member_id, is_club_member,
-- is_club_organizer og owns_member). Uavhengig av 002–007.
--
-- Innhold (fase 7 og 8):
--   1. events: innsats i POENG og linje for tippekupongen (B10, ingen kroner)
--   2. activity: strukturert hendelseslogg per klubb (type + jsonb), ikke HTML
--   3. activity_reactions: fast emoji-sett per hendelse og medlem
--   4. thread_messages: kveldens tråd per kveld, med @nevnte og valgfritt bilde
--   5. tips: tippekupongen, fem svar per kveld og medlem
--   6. push_tokens: APNs-tokens per medlem og enhet (fase 8)
--   7. Storage: private bøtter avatars og thread
--   8. Realtime for de nye tabellene
--
-- Lærdom fra PWA-en som er bygd inn:
--   * Tider settes av serveren (created_at, updated_at), ikke av klientens
--     klokke. PWA-en sjekket ±1 minutt i policyen; her overskriver en trigger.
--   * pushed_at kan ikke settes av klienten, ellers kunne en melding sperre
--     sin egen push.
--   * activity er append-only, også for arrangøren. Kategoriene for
--     «Melding til alle», purring og påminnelse, og en mottakerliste, er bare
--     for arrangøren (PWA: activity_log_vakt_kategori).
--   * Andres tips leses først når kupongen er låst, i databasen og ikke bare
--     i appen. «Hvem har levert» kommer fra en RPC som aldri gir svarene.
--   * Bildestier peker på eierens mappe og radens egen id, så en rad ikke kan
--     peke på andres bilde. Mappen sjekkes som uuid FØR den slås opp (CASE).
--     Ingen overskriving: nytt bilde får ny sti.
--   * Push-tokens leses bare av eieren. Senderen (Edge Function) bruker
--     service_role på serveren, aldri i appen.
--   * revoke … from public, anon står ETTER hver create or replace.
--
-- Én transaksjon. Idempotent der det er naturlig. Endres en tabell etter
-- første kjøring, skjer det i en ny migrering.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. TIPPEKUPONGEN PÅ KVELDEN: INNSATS (POENG) OG LINJE
-- ===========================================================================
-- null = regelsettets standard (Golfgutu-malen: 50 og +2,5). Tallene står i
-- regelsettet i appen, ikke her. 0 poeng = «for æra». Linja er alltid et
-- halvt slag, så snittet sjelden lander rett på den (som PWA-ens
-- schedule_tips_linje_check).
alter table public.events
  add column if not exists tips_stake_points smallint
    constraint events_tips_stake_points_check check (tips_stake_points between 0 and 1000);
alter table public.events
  add column if not exists tips_line numeric(3,1)
    constraint events_tips_line_check
    check (tips_line between -9.5 and 18.5 and tips_line - floor(tips_line) = 0.5);
comment on column public.events.tips_stake_points is
  'Tippekupongen: innsats per kupong i POENG (B10). null = regelsettets standard. 0 = for æra.';
comment on column public.events.tips_line is
  'Tippekupongen: linja på over/under, netto slag over par per ni hull, snitt for feltet. '
  'Alltid x,5. null = regelsettets standard.';


-- ===========================================================================
-- 2. TABELLER
-- ===========================================================================

-- --- activity: hendelsesloggen ----------------------------------------------
-- Én rad per hendelse i klubben («Anders gjorde eagle på hull 5», «runde 2 er
-- låst», «Melding til alle»). Strukturert: kind sier hva, data har detaljene
-- (id-er, hull, tall), og appen lager teksten. Ingen HTML.
-- category er push-kategorien (fase 8, PWA: VARSEL_KATEGORIER), så
-- arrangøren og hver spiller kan slå kategorier av.
-- recipients: null = alle i klubben, en liste = bare dem (purring). Tom liste
-- = ingen, aldri alle. Lista styrer bare push; linja står i varslene for alle.
create table if not exists public.activity (
  id               uuid primary key default gen_random_uuid(),
  club_id          uuid not null references public.clubs(id) on delete cascade,
  kind             text not null check (kind ~ '^[a-z][a-z0-9_]{0,39}$'),
  category         text not null check (category in (
                     'score',         -- store scorer: hole in one, eagle, albatross
                     'lead',          -- ledelsen underveis
                     'side_prize',    -- LD og KP meldt inn
                     'round',         -- ny runde, låst, slettet
                     'setup',         -- båser, matcher, bane, avkorting, rettinger
                     'bet',           -- veddemål (fase 10)
                     'signup',        -- påmeldinger
                     'social',        -- sosialkomiteen
                     'club',          -- spillere, innlogginger, baner, terminliste
                     'tips',          -- tippekupongen (f.eks. tippekongen)
                     'announcement',  -- «Melding til alle» (bare arrangør)
                     'nudge',         -- purring (bare arrangør)
                     'reminder'       -- påminnelse før kvelden (arrangør eller cron)
                   )),
  data             jsonb not null default '{}'::jsonb
                   check (jsonb_typeof(data) = 'object' and pg_column_size(data) <= 8192),
  -- Hvem som gjorde det. Settes av serveren. null = systemet (cron, import).
  actor_member_id  uuid,
  event_id         uuid,
  round_id         uuid,
  recipients       uuid[] check (recipients is null or cardinality(recipients) <= 200),
  created_at       timestamptz not null default now(),
  constraint activity_id_club_key unique (id, club_id),
  constraint activity_actor_fk foreign key (actor_member_id, club_id)
    references public.club_members (id, club_id) on delete set null (actor_member_id),
  constraint activity_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete set null (event_id),
  constraint activity_round_fk foreign key (round_id, club_id)
    references public.rounds (id, club_id) on delete set null (round_id)
);
comment on table public.activity is
  'Hendelsesloggen per klubb: kind + data (jsonb), ikke HTML. Append-only. '
  'category = push-kategori. recipients null = alle, liste = bare dem.';
create index if not exists activity_club_time_idx on public.activity (club_id, created_at desc);
create index if not exists activity_event_idx on public.activity (event_id) where event_id is not null;
create index if not exists activity_round_idx on public.activity (round_id) where round_id is not null;


-- --- activity_reactions: reaksjoner på en hendelse --------------------------
-- Én rad per hendelse, medlem og emoji. Flere ulike emojier er lov, samme
-- bare én gang. Trykk igjen = slett raden. Ingen push.
-- Settet er fast og må stå likt i appen (PWA: REAKSJONER og reaksjoner.sql).
create table if not exists public.activity_reactions (
  activity_id  uuid not null,
  member_id    uuid not null,
  club_id      uuid not null,
  emoji        text not null check (emoji in ('👍', '😂', '⛳', '🔥', '❤️')),
  created_at   timestamptz not null default now(),
  primary key (activity_id, member_id, emoji),
  constraint activity_reactions_activity_fk foreign key (activity_id, club_id)
    references public.activity (id, club_id) on delete cascade,
  constraint activity_reactions_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
create index if not exists activity_reactions_member_idx on public.activity_reactions (member_id);


-- --- thread_messages: kveldens tråd -----------------------------------------
-- Én rad per melding, knyttet til kvelden. Slettes kvelden, går tråden med.
-- Klienten lager id-en før opplasting, fordi bildestien er
-- <member_id>/<id>.jpg i bøtta thread. Med bilde kan teksten være tom.
-- mentions er de som er nevnt med @navn (appen regner dem ut); de styrer
-- hvem som får push når de har valgt «når jeg nevnes» (fase 8).
-- Ingen redigering. Sletting: egen, eller arrangøren alle.
create table if not exists public.thread_messages (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null,
  event_id    uuid not null,
  member_id   uuid not null,
  body        text not null default '',
  mentions    uuid[] not null default '{}' check (cardinality(mentions) <= 50),
  image_path  text,
  created_at  timestamptz not null default now(),
  -- Settes av push-senderen (service_role), så hver melding pushes én gang.
  pushed_at   timestamptz,
  constraint thread_messages_body_check check (
    char_length(body) <= 500
    and (char_length(btrim(body)) >= 1 or image_path is not null)
  ),
  constraint thread_messages_image_path_check check (
    image_path is null
    or lower(image_path) = member_id::text || '/' || id::text || '.jpg'
  ),
  constraint thread_messages_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint thread_messages_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.thread_messages is
  'Kveldens tråd. 0–500 tegn (minst 1 uten bilde), @nevnte, valgfritt bilde '
  '<member_id>/<id>.jpg i bøtta thread. created_at og pushed_at settes av serveren.';
create index if not exists thread_messages_event_time_idx
  on public.thread_messages (event_id, created_at);
create index if not exists thread_messages_member_idx on public.thread_messages (member_id);


-- --- tips: tippekupongen ------------------------------------------------------
-- Én rad per kveld og medlem, fem svar (som PWA-ens tips). null = ikke svart
-- på det spørsmålet. Fasit, poeng og resultat lagres IKKE; de regnes fra
-- hullscorene i regelmotoren (tipsFasit/tipsResultat i db-nytt.js).
-- Ingen betalingstabell: innsatsen er poeng (B10). Poengbanken kommer i fase 10.
create table if not exists public.tips (
  event_id    uuid not null,
  member_id   uuid not null,
  club_id     uuid not null,
  winner      uuid,      -- flest stablefordpoeng over hele kvelden
  front_nine  uuid,      -- lavest netto på banens hull 1–9
  most_pars   uuid,      -- flest hull på netto par eller bedre
  birdie      boolean,   -- minst én netto birdie eller bedre i løpet av kvelden
  over_line   boolean,   -- true = feltets snitt over linja, false = under
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (event_id, member_id),
  constraint tips_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint tips_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade,
  constraint tips_winner_fk foreign key (winner, club_id)
    references public.club_members (id, club_id) on delete set null (winner),
  constraint tips_front_nine_fk foreign key (front_nine, club_id)
    references public.club_members (id, club_id) on delete set null (front_nine),
  constraint tips_most_pars_fk foreign key (most_pars, club_id)
    references public.club_members (id, club_id) on delete set null (most_pars)
);
comment on table public.tips is
  'Tippekupongen: ett tips per medlem og kveld. Andres tips leses først når '
  'kupongen er låst (tips_open). Fasit og poeng regnes i appen.';
create index if not exists tips_member_idx on public.tips (member_id);


-- --- push_tokens: APNs per medlem og enhet (fase 8) -------------------------
-- Én rad per medlemskap og enhet. En innlogging i to klubber på samme
-- telefon gir to rader (hver klubb sine kategorier senere). Skrives bare via
-- register_push_token(), som også tar over en enhet som har byttet eier.
-- Leses og slettes bare av eieren. Senderen må i tillegg sjekke at
-- club_members.user_id = push_tokens.user_id og status = 'active', så en
-- frakoblet innlogging ikke får push.
create table if not exists public.push_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  member_id    uuid not null,
  club_id      uuid not null,
  -- identifierForVendor (fast per app-leverandør og enhet).
  device_id    text not null check (char_length(device_id) between 1 and 100),
  -- APNs-token som heks, små bokstaver.
  token        text not null check (token ~ '^[0-9a-f]{64,200}$'),
  -- sandbox = utviklerbygg, production = TestFlight og App Store.
  environment  text not null check (environment in ('sandbox', 'production')),
  bundle_id    text check (bundle_id is null or char_length(bundle_id) <= 200),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint push_tokens_member_device_key unique (member_id, device_id),
  constraint push_tokens_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.push_tokens is
  'APNs-tokens per medlem og enhet. Bare eieren leser og sletter. Skrives via '
  'register_push_token(). Senderen bruker service_role på serveren.';
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
create index if not exists push_tokens_token_idx on public.push_tokens (token);


-- --- club_members.avatar_path: formatet låses nå som bøtta finnes ----------
-- <member_id>/<uuid>.jpg i bøtta avatars. Ny fil = ny uuid (ingen
-- hurtigbuffer viser det gamle). Raden kan ikke peke på andres bilde.
alter table public.club_members drop constraint if exists club_members_avatar_path_shape;
alter table public.club_members add constraint club_members_avatar_path_shape check (
  avatar_path is null
  or lower(avatar_path) ~ ('^' || id::text
       || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
);


-- ===========================================================================
-- 3. HJELPEFUNKSJONER
-- ===========================================================================

-- --- tips_deadline: når kvelden starter, i Oslo-tid -------------------------
-- Kveldens dato + start_time som Europe/Oslo, ellers 17:00 (Golfgutu-
-- standarden, som PWA-ens TIPS_START_STANDARD). Postgres regner om til UTC
-- og tar sommertid riktig. events.start_time er en ekte time-kolonne, så
-- PWA-ens tolkning av fritekst («17:00–20:00») trengs ikke.
-- null hvis kvelden ikke finnes eller du ikke er medlem.
create or replace function public.tips_deadline(p_event_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select (e.event_date + coalesce(e.start_time, time '17:00')) at time zone 'Europe/Oslo'
  from public.events e
  where e.id = p_event_id
    and public.is_club_member(e.club_id);
$$;
revoke all on function public.tips_deadline(uuid) from public, anon;
grant execute on function public.tips_deadline(uuid) to authenticated;

-- --- tips_open: kan det tippes ennå? ---------------------------------------
-- Før fristen OG før første score på en runde den kvelden, det som kommer
-- først (PWA: tips_aapen). Kladder teller med: har arrangøren ført i en
-- kladd, er kvelden i gang.
create or replace function public.tips_open(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(now() < public.tips_deadline(p_event_id), false)
     and not exists (
       select 1
       from public.hole_scores hs
       join public.rounds r on r.id = hs.round_id
       where r.event_id = p_event_id
     );
$$;
revoke all on function public.tips_open(uuid) from public, anon;
grant execute on function public.tips_open(uuid) to authenticated;

-- --- Storage: mappen i stien er et medlem ----------------------------------
-- Stien er <member_id>/<uuid>.jpg. Formatet sjekkes FØR mappen gjøres om til
-- uuid (CASE), ellers kunne en ugyldig sti gitt en castfeil i stedet for nei.
create or replace function public.storage_path_member(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$'
      then split_part(p_name, '/', 1)::uuid
  end;
$$;
revoke all on function public.storage_path_member(text) from public, anon;
grant execute on function public.storage_path_member(text) to authenticated;

-- Kan jeg se fila? Mappen tilhører et medlem i en klubb der jeg er aktiv.
create or replace function public.storage_can_read(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.id = public.storage_path_member(p_name)
      and public.is_club_member(m.club_id)
  );
$$;
revoke all on function public.storage_can_read(text) from public, anon;
grant execute on function public.storage_can_read(text) to authenticated;

-- Kan jeg skrive eller slette fila? Egen mappe, eller (når p_organizer_ok)
-- arrangør i medlemmets klubb.
create or replace function public.storage_can_write(p_name text, p_organizer_ok boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    where m.id = public.storage_path_member(p_name)
      and (public.owns_member(m.id)
           or (p_organizer_ok and public.is_club_organizer(m.club_id)))
  );
$$;
revoke all on function public.storage_can_write(text, boolean) from public, anon;
grant execute on function public.storage_can_write(text, boolean) to authenticated;


-- ===========================================================================
-- 4. TRIGGERE
-- ===========================================================================
-- auth.uid() is null slipper gjennom, som i 001: SQL Editor, cron og
-- service_role (import, push-senderen). anon har ingen tabellrettigheter.

-- --- felles: rydd en liste med medlems-id-er og sjekk at de er i klubben ----
create or replace function public.clean_member_list(p_ids uuid[], p_club_id uuid)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if p_ids is null then
    return null;
  end if;
  select coalesce(array_agg(distinct u), '{}') into v_ids
  from unnest(p_ids) u where u is not null;
  if exists (select 1 from unnest(v_ids) u
             where not exists (select 1 from public.club_members m
                               where m.id = u and m.club_id = p_club_id)) then
    raise exception 'Lista har noen som ikke er med i klubben' using errcode = '23503';
  end if;
  return v_ids;
end;
$$;
revoke all on function public.clean_member_list(uuid[], uuid) from public, anon, authenticated;

-- --- activity: hvem og når settes av serveren, og arrangørens kategorier ----
create or replace function public.activity_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.recipients := public.clean_member_list(new.recipients, new.club_id);

  if auth.uid() is null then
    return new;
  end if;

  new.actor_member_id := public.my_member_id(new.club_id);
  new.created_at := now();

  if (new.category in ('announcement', 'nudge', 'reminder') or new.recipients is not null)
     and not public.is_club_organizer(new.club_id) then
    raise exception 'Bare arrangøren kan sende til alle, purre eller velge mottakere'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.activity_before_insert() from public, anon, authenticated;

drop trigger if exists activity_before_insert on public.activity;
create trigger activity_before_insert
  before insert on public.activity
  for each row execute function public.activity_before_insert();

-- --- thread_messages: tid, push-merke og nevnte ----------------------------
create or replace function public.thread_messages_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.mentions := public.clean_member_list(new.mentions, new.club_id);
  if new.image_path is not null then
    new.image_path := lower(new.image_path);
  end if;
  if auth.uid() is not null then
    new.created_at := now();
    new.pushed_at := null;
  end if;
  return new;
end;
$$;
revoke all on function public.thread_messages_before_insert() from public, anon, authenticated;

drop trigger if exists thread_messages_before_insert on public.thread_messages;
create trigger thread_messages_before_insert
  before insert on public.thread_messages
  for each row execute function public.thread_messages_before_insert();

-- --- tips: tidene settes av serveren, nøklene står fast --------------------
create or replace function public.tips_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    if new.event_id is distinct from old.event_id
       or new.member_id is distinct from old.member_id
       or new.club_id is distinct from old.club_id then
      raise exception 'Et tips kan ikke flyttes til en annen kveld eller spiller'
        using errcode = '22023';
    end if;
    new.created_at := old.created_at;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function public.tips_before_write() from public, anon, authenticated;

drop trigger if exists tips_before_write on public.tips;
create trigger tips_before_write
  before insert or update on public.tips
  for each row execute function public.tips_before_write();

-- --- events: innsats og linje står fast når første kupong er levert --------
-- Da har noen tippet på det som sto (PWA-README, «Tippekupongen»).
create or replace function public.events_guard_tips()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null
     and (new.tips_stake_points is distinct from old.tips_stake_points
          or new.tips_line is distinct from old.tips_line)
     and exists (select 1 from public.tips t where t.event_id = old.id) then
    raise exception 'Innsats og linje kan ikke endres etter at noen har levert kupongen'
      using errcode = '55000';
  end if;
  return new;
end;
$$;
revoke all on function public.events_guard_tips() from public, anon, authenticated;

drop trigger if exists events_guard_tips on public.events;
create trigger events_guard_tips
  before update of tips_stake_points, tips_line on public.events
  for each row execute function public.events_guard_tips();

-- --- push_tokens: updated_at ------------------------------------------------
drop trigger if exists push_tokens_set_updated_at on public.push_tokens;
create trigger push_tokens_set_updated_at
  before update on public.push_tokens
  for each row execute function public.set_updated_at();


-- ===========================================================================
-- 5. RLS-POLICYER
-- ===========================================================================
-- Bare rollen authenticated. Én policy per kommando. Aktivt medlemskap
-- (is_club_member / owns_member) kreves overalt; en som venter på
-- godkjenning ser ingenting av dette.

alter table public.activity            enable row level security;
alter table public.activity_reactions  enable row level security;
alter table public.thread_messages     enable row level security;
alter table public.tips                enable row level security;
alter table public.push_tokens         enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('activity', 'activity_reactions', 'thread_messages', 'tips', 'push_tokens')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- --- activity: les medlem, skriv medlem (vakten tar resten), aldri endre ----
create policy activity_select on public.activity
  for select to authenticated using (public.is_club_member(club_id));
create policy activity_insert on public.activity
  for insert to authenticated with check (public.is_club_member(club_id));

-- --- activity_reactions: les medlem, sett og fjern egne --------------------
create policy activity_reactions_select on public.activity_reactions
  for select to authenticated using (public.is_club_member(club_id));
create policy activity_reactions_insert on public.activity_reactions
  for insert to authenticated with check (public.owns_member(member_id));
create policy activity_reactions_delete on public.activity_reactions
  for delete to authenticated using (public.owns_member(member_id));

-- --- thread_messages: les medlem, skriv egne, slett egne (arrangør alle) ---
create policy thread_messages_select on public.thread_messages
  for select to authenticated using (public.is_club_member(club_id));
create policy thread_messages_insert on public.thread_messages
  for insert to authenticated with check (public.owns_member(member_id));
create policy thread_messages_delete on public.thread_messages
  for delete to authenticated
  using (public.owns_member(member_id) or public.is_club_organizer(club_id));

-- --- tips: eget alltid; andres først når kupongen er låst -----------------
-- Skrive og trekke eget bare mens den er åpen. Arrangøren kan fjerne et tips
-- når som helst (utveien om noen leverte ved en feil).
create policy tips_select on public.tips
  for select to authenticated
  using (public.owns_member(member_id)
         or (public.is_club_member(club_id) and not public.tips_open(event_id)));
create policy tips_insert on public.tips
  for insert to authenticated
  with check (public.owns_member(member_id) and public.tips_open(event_id));
create policy tips_update on public.tips
  for update to authenticated
  using (public.owns_member(member_id) and public.tips_open(event_id))
  with check (public.owns_member(member_id) and public.tips_open(event_id));
create policy tips_delete on public.tips
  for delete to authenticated
  using ((public.owns_member(member_id) and public.tips_open(event_id))
         or public.is_club_organizer(club_id));

-- --- push_tokens: bare eieren leser og sletter; skriving via RPC -----------
create policy push_tokens_select on public.push_tokens
  for select to authenticated using (user_id = auth.uid());
create policy push_tokens_delete on public.push_tokens
  for delete to authenticated using (user_id = auth.uid());


-- ===========================================================================
-- 6. TABELLRETTIGHETER
-- ===========================================================================
-- Alt tas fra public, anon og authenticated, så får authenticated bare det
-- som trengs. Ingen update på activity (append-only), activity_reactions og
-- thread_messages (ingen redigering) eller push_tokens (via RPC).
do $$
declare
  t text;
begin
  foreach t in array array['activity', 'activity_reactions', 'thread_messages', 'tips', 'push_tokens'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;
grant select, insert                 on table public.activity           to authenticated;
grant select, insert, delete         on table public.activity_reactions to authenticated;
grant select, insert, delete         on table public.thread_messages    to authenticated;
grant select, insert, update, delete on table public.tips               to authenticated;
grant select, delete                 on table public.push_tokens        to authenticated;


-- ===========================================================================
-- 7. RPC-ER
-- ===========================================================================

-- --- tips_submitted: hvem har levert, uten svarene -------------------------
-- Det kupongkortet viser før låsing («6 har levert»). Bare for medlemmer.
create or replace function public.tips_submitted(p_event_id uuid)
returns table (member_id uuid, submitted_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select e.club_id into v_club from public.events e where e.id = p_event_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  return query
    select t.member_id, t.updated_at
    from public.tips t
    where t.event_id = p_event_id
    order by t.updated_at;
end;
$$;
revoke all on function public.tips_submitted(uuid) from public, anon;
grant execute on function public.tips_submitted(uuid) to authenticated;

-- --- register_push_token: denne enheten skal få push for meg --------------
-- Registrerer enheten for alle mine aktive medlemskap, i én transaksjon:
--   1. har enheten eller tokenet tilhørt en annen innlogging, slettes de
--      radene (telefonen har byttet eier, eller noen logget inn på en annen
--      konto);
--   2. mine gamle rader med samme token, men annen enhets-id, slettes
--      (identifierForVendor kan endre seg ved ny installasjon);
--   3. mine rader for denne enheten i klubber der jeg ikke lenger er aktiv,
--      slettes;
--   4. upsert per aktivt medlemskap.
-- Returnerer radene for denne enheten. Tom liste = ingen aktive medlemskap.
-- Avregistrering (logg ut): vanlig delete where device_id = …, RLS sjekker eier.
create or replace function public.register_push_token(
  p_device_id    text,
  p_token        text,
  p_environment  text,
  p_bundle_id    text default null
)
returns setof public.push_tokens
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_token  text := lower(btrim(p_token));
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_device_id is null or char_length(btrim(p_device_id)) not between 1 and 100 then
    raise exception 'Ugyldig enhets-id' using errcode = '22023';
  end if;
  if v_token is null or v_token !~ '^[0-9a-f]{64,200}$' then
    raise exception 'Ugyldig push-token' using errcode = '22023';
  end if;
  if p_environment is null or p_environment not in ('sandbox', 'production') then
    raise exception 'Miljø må være sandbox eller production' using errcode = '22023';
  end if;

  delete from public.push_tokens pt
   where pt.user_id <> v_uid
     and (pt.token = v_token or pt.device_id = btrim(p_device_id));

  delete from public.push_tokens pt
   where pt.user_id = v_uid
     and pt.token = v_token
     and pt.device_id <> btrim(p_device_id);

  delete from public.push_tokens pt
   where pt.user_id = v_uid
     and pt.device_id = btrim(p_device_id)
     and not exists (select 1 from public.club_members m
                     where m.id = pt.member_id and m.user_id = v_uid and m.status = 'active');

  insert into public.push_tokens (user_id, member_id, club_id, device_id, token, environment, bundle_id)
  select v_uid, m.id, m.club_id, btrim(p_device_id), v_token, p_environment, p_bundle_id
  from public.club_members m
  where m.user_id = v_uid and m.status = 'active'
  on conflict (member_id, device_id) do update
    set token       = excluded.token,
        environment = excluded.environment,
        bundle_id   = excluded.bundle_id,
        user_id     = excluded.user_id;

  return query
    select * from public.push_tokens pt
    where pt.user_id = v_uid and pt.device_id = btrim(p_device_id)
    order by pt.club_id;
end;
$$;
revoke all on function public.register_push_token(text, text, text, text) from public, anon;
grant execute on function public.register_push_token(text, text, text, text) to authenticated;


-- ===========================================================================
-- 8. STORAGE: PRIVATE BØTTER FOR PORTRETTER OG TRÅDBILDER
-- ===========================================================================
-- Begge er private, bare JPEG, maks 3 MB. Bildene vises med signerte lenker
-- (PWA: én time). Ingen update-policy: ingen kan overskrive, så appen laster
-- opp med upsert = false og ny sti for nytt bilde. Stien må ha små bokstaver
-- (Swift: uuidString.lowercased()).
--   avatars/<member_id>/<uuid>.jpg   portrett. Medlemmet selv eller arrangøren
--                                    i klubben laster opp og sletter.
--   thread/<member_id>/<melding>.jpg trådbilde. Bare avsenderen laster opp;
--                                    avsenderen eller arrangøren sletter.
-- Lesing: aktive medlemmer i klubben til medlemmet i mappen. Andre klubber
-- og anon ser ingenting.
-- Rekkefølge i appen (som PWA-en): fil først, så raden, så slett den gamle.
-- Feiler raden, fjernes den nye fila igjen. Supabase sperrer sletting av
-- filer rett i SQL (protect_objects_delete); de slettes via Storage-API-et.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 3145728, array['image/jpeg']),
       ('thread',  'thread',  false, 3145728, array['image/jpeg'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists dd18_avatars_select on storage.objects;
drop policy if exists dd18_avatars_insert on storage.objects;
drop policy if exists dd18_avatars_delete on storage.objects;
drop policy if exists dd18_thread_select  on storage.objects;
drop policy if exists dd18_thread_insert  on storage.objects;
drop policy if exists dd18_thread_delete  on storage.objects;

create policy dd18_avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and public.storage_can_read(name));
create policy dd18_avatars_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and public.storage_can_write(name, true));
create policy dd18_avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and public.storage_can_write(name, true));

create policy dd18_thread_select on storage.objects
  for select to authenticated
  using (bucket_id = 'thread' and public.storage_can_read(name));
create policy dd18_thread_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'thread' and public.storage_can_write(name, false));
create policy dd18_thread_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'thread' and public.storage_can_write(name, true));


-- ===========================================================================
-- 9. REALTIME
-- ===========================================================================
-- Realtime følger SELECT-policyene: før låsing får du bare hendelser for ditt
-- eget tips. push_tokens er ikke med (ingen skjerm lytter, og den er privat).
-- NB (PWA, 01.10.2026): realtime kobler til igjen uten å sende det som kom i
-- mellomtiden. Appen må hente tråden og varslene på nytt når den kommer
-- fram fra bakgrunnen.
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  foreach t in array array['activity', 'activity_reactions', 'thread_messages', 'tips'] loop
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
-- 1. De fem tabellene finnes og har RLS på. Forventet: 5 rader, rls = true.
--
-- select c.relname as tabell, c.relrowsecurity as rls
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
--   and c.relname in ('activity','activity_reactions','thread_messages','tips','push_tokens')
-- order by 1;
--
-- 2. anon har INGEN tabellrettigheter. Forventet: 0 rader.
--
-- select table_name, privilege_type from information_schema.role_table_grants
-- where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
--   and table_name in ('activity','activity_reactions','thread_messages','tips','push_tokens');
--
-- 3. authenticated har bare det som trengs. Forventet:
--    activity: INSERT, SELECT · activity_reactions: DELETE, INSERT, SELECT ·
--    push_tokens: DELETE, SELECT · thread_messages: DELETE, INSERT, SELECT ·
--    tips: DELETE, INSERT, SELECT, UPDATE.
--
-- select table_name, string_agg(privilege_type, ', ' order by privilege_type)
-- from information_schema.role_table_grants
-- where table_schema = 'public' and grantee = 'authenticated'
--   and table_name in ('activity','activity_reactions','thread_messages','tips','push_tokens')
-- group by 1 order by 1;
--
-- 4. Funksjonsrettigheter. Forventet: anon_kan = false på ALLE. auth_kan =
--    true på tips_deadline, tips_open, storage_*, tips_submitted og
--    register_push_token; false på clean_member_list og triggerfunksjonene.
--
-- select p.proname as funksjon, p.prosecdef as definer,
--        has_function_privilege('anon',          p.oid, 'execute') as anon_kan,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--        p.proconfig as innstillinger
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('tips_deadline','tips_open','storage_path_member','storage_can_read',
--                     'storage_can_write','clean_member_list','activity_before_insert',
--                     'thread_messages_before_insert','tips_before_write','events_guard_tips',
--                     'tips_submitted','register_push_token')
-- order by anon_kan desc, p.proname;
--
-- 5. Bøttene. Forventet: 2 rader, public = false, 3145728, {image/jpeg}.
--
-- select id, public, file_size_limit, allowed_mime_types from storage.buckets
-- where id in ('avatars', 'thread');
--
-- 6. Storage-policyene. Forventet: 6 rader, alle {authenticated}.
--
-- select policyname, cmd, roles from pg_policies
-- where schemaname = 'storage' and tablename = 'objects' and policyname like 'dd18_%'
-- order by 1;
--
-- 7. Realtime. Forventet: activity, activity_reactions, thread_messages, tips.
--
-- select tablename from pg_publication_tables
-- where pubname = 'supabase_realtime' and schemaname = 'public'
--   and tablename in ('activity','activity_reactions','thread_messages','tips','push_tokens')
-- order by 1;
--
-- 8. Fristen i Oslo-tid regnet om til UTC. Forventet: 15:00, 16:00, 16:00,
--    15:00 (samme tall som tippekupong-test.js). tips_deadline() gir null i
--    SQL Editor (ingen innlogging), så uttrykket står her direkte.
--
-- set time zone 'UTC';
-- select (date '2026-10-08' + time '17:00') at time zone 'Europe/Oslo',
--        (date '2026-11-05' + time '17:00') at time zone 'Europe/Oslo',
--        (date '2026-10-25' + time '17:00') at time zone 'Europe/Oslo',
--        (date '2026-03-29' + time '17:00') at time zone 'Europe/Oslo';
--
-- 9. Ingen eksisterende portrett-sti bryter det nye formatet. Kjør gjerne
--    FØR migreringen også (ellers feiler den på club_members_avatar_path_shape).
--    Forventet: 0.
--
-- select count(*) from public.club_members
-- where avatar_path is not null and not (lower(avatar_path) ~ ('^' || id::text || '/'));
--
-- Rolleprøven sql/lokal/008_prove.sql er KUN for lokal Postgres.


-- ===========================================================================
-- RULLEBAKKE (fjerner ALT fra denne migreringen, inkludert data)
-- ===========================================================================
-- Bare på test. Tøm bøttene avatars og thread i Storage-panelet først
-- (filer kan ikke slettes i SQL), og slett så bøttene der.
--
-- begin;
-- do $$
-- declare t text;
-- begin
--   if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
--     foreach t in array array['activity','activity_reactions','thread_messages','tips'] loop
--       if exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
--                  and schemaname = 'public' and tablename = t) then
--         execute format('alter publication supabase_realtime drop table public.%I', t);
--       end if;
--     end loop;
--   end if;
-- end $$;
-- drop policy if exists dd18_avatars_select on storage.objects;
-- drop policy if exists dd18_avatars_insert on storage.objects;
-- drop policy if exists dd18_avatars_delete on storage.objects;
-- drop policy if exists dd18_thread_select  on storage.objects;
-- drop policy if exists dd18_thread_insert  on storage.objects;
-- drop policy if exists dd18_thread_delete  on storage.objects;
-- drop function if exists public.register_push_token(text, text, text, text);
-- drop function if exists public.tips_submitted(uuid);
-- drop trigger if exists events_guard_tips on public.events;
-- drop table if exists public.push_tokens, public.tips, public.thread_messages,
--   public.activity_reactions, public.activity cascade;
-- drop function if exists public.events_guard_tips();
-- drop function if exists public.tips_before_write();
-- drop function if exists public.thread_messages_before_insert();
-- drop function if exists public.activity_before_insert();
-- drop function if exists public.clean_member_list(uuid[], uuid);
-- drop function if exists public.storage_can_write(text, boolean);
-- drop function if exists public.storage_can_read(text);
-- drop function if exists public.storage_path_member(text);
-- drop function if exists public.tips_open(uuid);
-- drop function if exists public.tips_deadline(uuid);
-- alter table public.club_members drop constraint if exists club_members_avatar_path_shape;
-- alter table public.events drop column if exists tips_line;
-- alter table public.events drop column if exists tips_stake_points;
-- commit;
