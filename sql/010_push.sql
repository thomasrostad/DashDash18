-- ===========================================================================
-- 010 – PUSH (APNs): ENHETER, KATEGORIER, KØ OG SENDER (FORSLAG)
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5, fase 8). IKKE KJØRT mot
-- Supabase. Kjøres først på TEST etter ja fra brukeren, så kontrollspørringene
-- nederst. Prod først etter ny godkjenning.
--
-- Krever 001 og 008. Uavhengig av 002–007 og 009.
--
-- Innhold:
--   1. push_devices: én rad per telefon (innlogging, token, miljø, bundle,
--      sist sett). Erstatter 008s push_tokens (én rad per medlemskap og enhet),
--      se «Hvorfor ny tabell» under.
--   2. push_preferences: spillerens valg per medlemskap (kategorier av/på og
--      tråden: alle / når jeg nevnes / av).
--   3. clubs.push_disabled_categories: arrangørens «Hva blir push» for hele
--      klubben (PWA: settings.push_av).
--   4. push_queue: køen. En trigger på activity og thread_messages legger inn
--      én jobb per linje/melding. En Database Webhook på køen vekker Edge
--      Function-en push-send, som henter jobbene med service_role.
--   5. RPC-er for appen: register_push_device, unregister_push_device,
--      push_status (arrangøren: hvem har push).
--   6. RPC-er bare for senderen (service_role): claim_push_jobs,
--      push_job_payload, finish_push_job, queue_evening_reminders.
--
-- Hvorfor ny tabell for tokens:
--   * Et APNs-token hører til en telefon og en innlogging, ikke til en klubb.
--     Med én rad per telefon kan tokenet være unikt, og senderen finner
--     medlemskapene selv (club_members.user_id = push_devices.user_id og
--     status = 'active'). Da får en frakoblet innlogging aldri push, og et nytt
--     medlemskap får push uten ny registrering.
--   * Klubbvise valg ligger i push_preferences (per medlemskap), så 008s grunn
--     til én rad per medlemskap («hver klubb sine kategorier senere») faller bort.
--   * Appen har aldri kalt register_push_token, så push_tokens er tom på test.
--     Eventuelle rader flyttes likevel over før tabellen fjernes.
--
-- Hva som går som push (samme regler som PWA-ens _worker.js, pluss valg per
-- spiller). Selve avgjørelsen tas i push-send (logic.ts, med tester):
--   * Linja står alltid i Varsler i appen. Det er bare pushen som stoppes.
--   * Arrangøren slår kategorier av for klubben. «Melding til alle» og purring
--     har ingen klubbryter (arrangøren trykket selv).
--   * Spilleren slår kategorier av for seg selv. «Melding til alle» har ingen
--     spillerbryter.
--   * recipients (008): null = alle, liste = bare dem, tom liste = ingen.
--   * Den som gjorde det, får ikke push om sin egen hendelse.
--   * Tråden: alle / når jeg nevnes (standard) / av. Arrangørens meldinger går
--     også til dem som har «når jeg nevnes» (PWA: mottakereForMelding).
--
-- Lærdom fra PWA-en som er bygd inn:
--   * Tokens og kø leses aldri av appen. Senderen bruker service_role på
--     serveren (Edge Function-secret), aldri i appen.
--   * Hver linje og melding pushes høyst én gang (unik jobb per kilde,
--     done_at, thread_messages.pushed_at).
--   * revoke … from public, anon står ETTER hver create or replace.
--
-- Én transaksjon. Idempotent der det er naturlig.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. KATEGORILISTENE
-- ===========================================================================
-- Samme id-er som activity.category i 008, pluss 'thread' (kveldens tråd).
-- Hjelpefunksjonene brukes i CHECK, så lista står ett sted.

-- Det spilleren kan slå av for seg selv. Ikke 'announcement'. Tråden styres av
-- push_preferences.thread_mode, ikke av denne lista.
create or replace function public.push_player_categories()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['score', 'lead', 'side_prize', 'round', 'setup', 'bet', 'signup',
               'social', 'club', 'tips', 'nudge', 'reminder']::text[];
$$;
revoke all on function public.push_player_categories() from public, anon;
grant execute on function public.push_player_categories() to authenticated;

-- Det arrangøren kan slå av for hele klubben. Ikke 'announcement' og 'nudge'
-- (PWA: ALLTID = melding, purring). 'thread' stopper all push fra tråden.
create or replace function public.push_club_categories()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['score', 'lead', 'side_prize', 'round', 'setup', 'bet', 'signup',
               'social', 'club', 'tips', 'reminder', 'thread']::text[];
$$;
revoke all on function public.push_club_categories() from public, anon;
grant execute on function public.push_club_categories() to authenticated;


-- ===========================================================================
-- 2. TABELLER
-- ===========================================================================

-- --- push_devices: én rad per telefon ---------------------------------------
-- device_id er identifierForVendor. Tokenet er unikt: en telefon som bytter
-- innlogging, flytter raden til den nye innloggingen (register_push_device).
create table if not exists public.push_devices (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  device_id     text not null check (char_length(device_id) between 1 and 100),
  -- APNs-token som heks, små bokstaver.
  token         text not null check (token ~ '^[0-9a-f]{64,200}$'),
  -- sandbox = utviklerbygg fra Xcode, production = TestFlight og App Store.
  environment   text not null check (environment in ('sandbox', 'production')),
  -- apns-topic. null = senderens APNS_BUNDLE_ID.
  bundle_id     text check (bundle_id is null or bundle_id ~ '^[A-Za-z0-9.-]{1,155}$'),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- Sist appen registrerte seg (hver oppstart). Vises arrangøren i push_status.
  last_seen_at  timestamptz not null default now(),
  constraint push_devices_token_key unique (token),
  constraint push_devices_device_key unique (device_id)
);
comment on table public.push_devices is
  'APNs-token per telefon. Bare eieren leser. Skrives via register_push_device(). '
  'Senderen (service_role) finner medlemskapene via club_members.user_id.';
create index if not exists push_devices_user_idx on public.push_devices (user_id);

-- --- Flytt eventuelle rader fra 008s push_tokens, og fjern den ---------------
do $$
begin
  if to_regclass('public.push_tokens') is not null then
    insert into public.push_devices (user_id, device_id, token, environment, bundle_id, created_at, last_seen_at)
    select distinct on (pt.device_id)
           pt.user_id, pt.device_id, pt.token, pt.environment, pt.bundle_id, pt.created_at, pt.updated_at
    from public.push_tokens pt
    order by pt.device_id, pt.updated_at desc
    on conflict do nothing;
    drop function if exists public.register_push_token(text, text, text, text);
    drop table public.push_tokens;
  end if;
end $$;

-- --- push_preferences: spillerens valg per medlemskap ------------------------
-- Ingen rad = standard: alt på, tråden «når jeg nevnes» (PWA: prat_push
-- 'nevnt'). Lista er det som er AV, så en ny kategori er på til spilleren slår
-- den av (som PWA-ens push_av).
create table if not exists public.push_preferences (
  member_id            uuid primary key,
  club_id              uuid not null,
  disabled_categories  text[] not null default '{}'
                       check (disabled_categories <@ public.push_player_categories()),
  thread_mode          text not null default 'mentions'
                       check (thread_mode in ('all', 'mentions', 'off')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint push_preferences_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.push_preferences is
  'Spillerens push-valg per medlemskap. disabled_categories = det som er AV. '
  'thread_mode: all / mentions / off. Ingen rad = alt på, tråden mentions.';
create index if not exists push_preferences_club_idx on public.push_preferences (club_id);

-- --- clubs.push_disabled_categories: «Hva blir push» for hele klubben -------
-- Arrangøren skriver den med vanlig update (clubs_update i 001 krever
-- arrangør). Alle i klubben kan lese den, så appen kan vise «slått av av
-- arrangøren».
alter table public.clubs
  add column if not exists push_disabled_categories text[] not null default '{}';
alter table public.clubs drop constraint if exists clubs_push_disabled_categories_check;
alter table public.clubs add constraint clubs_push_disabled_categories_check
  check (push_disabled_categories <@ public.push_club_categories());
comment on column public.clubs.push_disabled_categories is
  'Push-kategorier arrangøren har slått AV for hele klubben (PWA: settings.push_av). '
  'Linjene står i Varsler uansett.';

-- --- push_queue: én jobb per linje eller melding ----------------------------
-- Fylles av triggere (under). Leses og skrives bare av senderen
-- (service_role). Ingen policyer: authenticated og anon får ingenting.
create table if not exists public.push_queue (
  id                 bigint generated always as identity primary key,
  club_id            uuid not null references public.clubs(id) on delete cascade,
  activity_id        uuid references public.activity(id) on delete cascade,
  thread_message_id  uuid references public.thread_messages(id) on delete cascade,
  created_at         timestamptz not null default now(),
  -- Antall forsøk. Etter 5 gis jobben opp (done_at settes, last_error står).
  attempts           smallint not null default 0 check (attempts between 0 and 100),
  -- En sender har tatt jobben til dette tidspunktet (dobbel webhook, retry).
  locked_until       timestamptz,
  done_at            timestamptz,
  -- Hva som skjedde: {"sent": 3, "failed": 0, "removed": 1, "skipped": "…"}.
  result             jsonb check (result is null or pg_column_size(result) <= 4096),
  last_error         text check (last_error is null or char_length(last_error) <= 500),
  constraint push_queue_one_source check (num_nonnulls(activity_id, thread_message_id) = 1),
  constraint push_queue_activity_key unique (activity_id),
  constraint push_queue_thread_message_key unique (thread_message_id)
);
comment on table public.push_queue is
  'Push-køen. Én jobb per activity-linje eller trådmelding. Bare service_role. '
  'En Database Webhook på INSERT vekker Edge Function-en push-send.';
create index if not exists push_queue_pending_idx on public.push_queue (id) where done_at is null;


-- ===========================================================================
-- 3. TRIGGERE
-- ===========================================================================

drop trigger if exists push_devices_set_updated_at on public.push_devices;
create trigger push_devices_set_updated_at
  before update on public.push_devices
  for each row execute function public.set_updated_at();

drop trigger if exists push_preferences_set_updated_at on public.push_preferences;
create trigger push_preferences_set_updated_at
  before update on public.push_preferences
  for each row execute function public.set_updated_at();

-- --- Køen fylles fra aktivitetsloggen og tråden -----------------------------
-- Alle linjer går i køen; senderen avgjør (kategori, valg, mottakere) og
-- skriver hvorfor den hoppet over i result. Linjer fra en kladdrunde hoppes
-- over allerede her (de vises bare for arrangøren, can_read_round i 008).
create or replace function public.push_enqueue_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.round_id is not null
     and exists (select 1 from public.rounds r where r.id = new.round_id and r.status = 'draft') then
    return null;
  end if;
  insert into public.push_queue (club_id, activity_id)
  values (new.club_id, new.id)
  on conflict do nothing;
  return null;
end;
$$;
revoke all on function public.push_enqueue_activity() from public, anon, authenticated;

drop trigger if exists push_enqueue_activity on public.activity;
create trigger push_enqueue_activity
  after insert on public.activity
  for each row execute function public.push_enqueue_activity();

create or replace function public.push_enqueue_thread_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.pushed_at is null then
    insert into public.push_queue (club_id, thread_message_id)
    values (new.club_id, new.id)
    on conflict do nothing;
  end if;
  return null;
end;
$$;
revoke all on function public.push_enqueue_thread_message() from public, anon, authenticated;

drop trigger if exists push_enqueue_thread_message on public.thread_messages;
create trigger push_enqueue_thread_message
  after insert on public.thread_messages
  for each row execute function public.push_enqueue_thread_message();


-- ===========================================================================
-- 4. RLS-POLICYER
-- ===========================================================================

alter table public.push_devices      enable row level security;
alter table public.push_preferences  enable row level security;
alter table public.push_queue        enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('push_devices', 'push_preferences', 'push_queue')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- --- push_devices: bare eieren leser; skriving og sletting via RPC ----------
create policy push_devices_select on public.push_devices
  for select to authenticated using (user_id = auth.uid());

-- --- push_preferences: bare egne, og bare aktive medlemskap -----------------
create policy push_preferences_select on public.push_preferences
  for select to authenticated using (public.owns_member(member_id));
create policy push_preferences_insert on public.push_preferences
  for insert to authenticated with check (public.owns_member(member_id));
create policy push_preferences_update on public.push_preferences
  for update to authenticated
  using (public.owns_member(member_id))
  with check (public.owns_member(member_id));
create policy push_preferences_delete on public.push_preferences
  for delete to authenticated using (public.owns_member(member_id));

-- --- push_queue: ingen policyer (bare service_role, som omgår RLS) ----------


-- ===========================================================================
-- 5. TABELLRETTIGHETER
-- ===========================================================================
do $$
declare
  t text;
begin
  foreach t in array array['push_devices', 'push_preferences', 'push_queue'] loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end $$;
grant select                         on table public.push_devices     to authenticated;
grant select, insert, update, delete on table public.push_preferences to authenticated;


-- ===========================================================================
-- 6. RPC-ER FOR APPEN
-- ===========================================================================

-- --- register_push_device: denne telefonen skal få push for meg -------------
-- Kalles ved hver oppstart med tokenet fra APNs. I én transaksjon:
--   1. samme token på en annen enhets-id fjernes (ny installasjon gir ny
--      identifierForVendor, men APNs kan gi samme token);
--   2. raden for enheten opprettes, eller tas over (ny innlogging på samme
--      telefon), og token, miljø, bundle og sist sett oppdateres.
-- Returnerer raden. Krever ikke medlemskap: senderen sjekker aktive
-- medlemskap ved hver sending.
create or replace function public.register_push_device(
  p_device_id    text,
  p_token        text,
  p_environment  text,
  p_bundle_id    text default null
)
returns setof public.push_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_device  text := btrim(p_device_id);
  v_token   text := lower(btrim(p_token));
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if v_device is null or char_length(v_device) not between 1 and 100 then
    raise exception 'Ugyldig enhets-id' using errcode = '22023';
  end if;
  if v_token is null or v_token !~ '^[0-9a-f]{64,200}$' then
    raise exception 'Ugyldig push-token' using errcode = '22023';
  end if;
  if p_environment is null or p_environment not in ('sandbox', 'production') then
    raise exception 'Miljø må være sandbox eller production' using errcode = '22023';
  end if;
  if p_bundle_id is not null and p_bundle_id !~ '^[A-Za-z0-9.-]{1,155}$' then
    raise exception 'Ugyldig bundle-id' using errcode = '22023';
  end if;

  delete from public.push_devices d
   where d.token = v_token and d.device_id <> v_device;

  insert into public.push_devices (user_id, device_id, token, environment, bundle_id, last_seen_at)
  values (v_uid, v_device, v_token, p_environment, p_bundle_id, now())
  on conflict (device_id) do update
    set user_id      = excluded.user_id,
        token        = excluded.token,
        environment  = excluded.environment,
        bundle_id    = excluded.bundle_id,
        last_seen_at = now();

  return query
    select * from public.push_devices d
    where d.device_id = v_device and d.user_id = v_uid;
end;
$$;
revoke all on function public.register_push_device(text, text, text, text) from public, anon;
grant execute on function public.register_push_device(text, text, text, text) to authenticated;

-- --- unregister_push_device: logg ut eller push slått av --------------------
-- Sletter min rad for enheten. Returnerer antall slettede (0 = fantes ikke).
create or replace function public.unregister_push_device(p_device_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_count  integer;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  delete from public.push_devices d
   where d.user_id = v_uid and d.device_id = btrim(p_device_id);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.unregister_push_device(text) from public, anon;
grant execute on function public.unregister_push_device(text) to authenticated;

-- --- push_status: hvem i klubben har push (bare arrangøren) ------------------
-- Spiller-id, antall telefoner og når en av dem sist meldte seg. Aldri
-- tokenene (PWA: push_status, push-status-test.js). Ledige navn (uten
-- innlogging) kommer med, med 0 telefoner.
create or replace function public.push_status(p_club_id uuid)
returns table (member_id uuid, has_login boolean, devices integer, last_seen_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_club_organizer(p_club_id) then
    raise exception 'Bare arrangøren ser hvem som har push' using errcode = '42501';
  end if;
  return query
    select m.id,
           m.user_id is not null,
           count(d.id)::integer,
           max(d.last_seen_at)
    from public.club_members m
    left join public.push_devices d on d.user_id = m.user_id
    where m.club_id = p_club_id and m.status = 'active'
    group by m.id, m.user_id
    order by m.id;
end;
$$;
revoke all on function public.push_status(uuid) from public, anon;
grant execute on function public.push_status(uuid) to authenticated;


-- ===========================================================================
-- 7. RPC-ER BARE FOR SENDEREN (service_role)
-- ===========================================================================
-- Ingen av disse kan kalles av appen (revoke fra authenticated).

-- --- claim_push_jobs: ta de neste jobbene ------------------------------------
-- Ikke ferdige, ikke låst av en annen sender, under 5 forsøk og yngre enn en
-- time (eldre push er ikke verdt en lyd i lomma). skip locked gjør at to
-- samtidige webhooker ikke tar samme jobb.
create or replace function public.claim_push_jobs(p_limit integer default 20)
returns setof public.push_queue
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
    update public.push_queue q
       set attempts = q.attempts + 1,
           locked_until = now() + interval '2 minutes'
     where q.id in (
       select j.id from public.push_queue j
       where j.done_at is null
         and j.attempts < 5
         and j.created_at > now() - interval '1 hour'
         and (j.locked_until is null or j.locked_until < now())
       order by j.id
       limit greatest(1, least(coalesce(p_limit, 20), 100))
       for update skip locked
     )
    returning q.*;
end;
$$;
revoke all on function public.claim_push_jobs(integer) from public, anon, authenticated;
grant execute on function public.claim_push_jobs(integer) to service_role;

-- --- push_job_payload: alt senderen trenger for én jobb, i ett kall ---------
-- Linja eller meldingen, klubbens valg og alle medlemmene med navn, valg og
-- telefoner. Telefoner tas bare med for aktive medlemmer der innloggingen
-- fortsatt er koblet (club_members.user_id = push_devices.user_id).
-- Logikken (hvem får hva, og teksten) ligger i push-send/logic.ts.
create or replace function public.push_job_payload(p_job_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'job_id', q.id,
    'kind', case when q.activity_id is not null then 'activity' else 'thread' end,
    'club', jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'disabled_categories', to_jsonb(c.push_disabled_categories)
    ),
    'activity', (
      select jsonb_build_object(
        'id', a.id, 'kind', a.kind, 'category', a.category, 'data', a.data,
        'actor_member_id', a.actor_member_id, 'event_id', a.event_id,
        'round_id', a.round_id, 'recipients', to_jsonb(a.recipients),
        'created_at', a.created_at,
        'round_status', (select r.status from public.rounds r where r.id = a.round_id))
      from public.activity a where a.id = q.activity_id
    ),
    'message', (
      select jsonb_build_object(
        'id', t.id, 'event_id', t.event_id, 'member_id', t.member_id,
        'body', t.body, 'mentions', to_jsonb(t.mentions),
        'has_image', t.image_path is not null, 'created_at', t.created_at,
        'pushed_at', t.pushed_at,
        'event_date', (select e.event_date from public.events e where e.id = t.event_id))
      from public.thread_messages t where t.id = q.thread_message_id
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'display_name', m.display_name,
        'is_organizer', m.is_organizer,
        'active', m.status = 'active' and m.user_id is not null,
        'disabled_categories', to_jsonb(coalesce(p.disabled_categories, '{}'::text[])),
        'thread_mode', coalesce(p.thread_mode, 'mentions'),
        'devices', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'token', d.token, 'environment', d.environment, 'bundle_id', d.bundle_id)
                 order by d.device_id)
          from public.push_devices d
          where m.status = 'active' and d.user_id = m.user_id
        ), '[]'::jsonb)
      ) order by m.id)
      from public.club_members m
      left join public.push_preferences p on p.member_id = m.id
      where m.club_id = q.club_id
    ), '[]'::jsonb)
  )
  from public.push_queue q
  join public.clubs c on c.id = q.club_id
  where q.id = p_job_id;
$$;
revoke all on function public.push_job_payload(bigint) from public, anon, authenticated;
grant execute on function public.push_job_payload(bigint) to service_role;

-- --- finish_push_job: ferdig, eller prøv igjen -------------------------------
-- I én transaksjon: fjern tokens APNs sa var døde (410 eller BadDeviceToken),
-- merk jobben, og merk trådmeldingen som pushet. p_ok = false slipper låsen,
-- så neste webhook prøver igjen; etter 5 forsøk gis jobben opp.
create or replace function public.finish_push_job(
  p_job_id       bigint,
  p_ok           boolean,
  p_result       jsonb default null,
  p_error        text default null,
  p_dead_tokens  text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.push_queue;
begin
  select * into v_job from public.push_queue where id = p_job_id for update;
  if not found then
    raise exception 'Fant ikke jobben' using errcode = 'P0002';
  end if;

  if coalesce(cardinality(p_dead_tokens), 0) > 0 then
    delete from public.push_devices d where d.token = any (p_dead_tokens);
  end if;

  if p_ok then
    update public.push_queue
       set done_at = now(), locked_until = null, result = p_result, last_error = null
     where id = p_job_id;
    if v_job.thread_message_id is not null then
      update public.thread_messages
         set pushed_at = now()
       where id = v_job.thread_message_id and pushed_at is null;
    end if;
  else
    update public.push_queue
       set locked_until = null,
           result = p_result,
           last_error = left(coalesce(p_error, 'ukjent feil'), 500),
           done_at = case when v_job.attempts >= 5 then now() end
     where id = p_job_id;
  end if;
end;
$$;
revoke all on function public.finish_push_job(bigint, boolean, jsonb, text, text[]) from public, anon, authenticated;
grant execute on function public.finish_push_job(bigint, boolean, jsonb, text, text[]) to service_role;

-- --- queue_evening_reminders: «påminnelse før kvelden» (cron) ---------------
-- Skriver en reminder-linje i aktivitetsloggen for hver kveld som er
-- p_days_before dager fram (Oslo-dato), med antall som kommer og er usikre.
-- Linja går i køen som alle andre (kategori reminder). Høyst én fra systemet
-- per kveld (unik indeks under). Kjøres av pg_cron (se nederst), aldri appen.
-- 7 dager er PWA-ens «En uke før hver kveld». Returnerer antall nye linjer.
create unique index if not exists activity_reminder_once_per_event
  on public.activity (event_id)
  where kind = 'reminder' and actor_member_id is null and event_id is not null;

create or replace function public.queue_evening_reminders(p_days_before integer default 7)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_days_before is null or p_days_before not between 0 and 60 then
    raise exception 'Antall dager må være 0–60' using errcode = '22023';
  end if;
  insert into public.activity (club_id, kind, category, data, event_id)
  select e.club_id, 'reminder', 'reminder',
         jsonb_build_object(
           'event_date', to_char(e.event_date, 'YYYY-MM-DD'),
           'coming', (select count(*) from public.signups s where s.event_id = e.id and s.status = 'yes'),
           'unsure', (select count(*) from public.signups s where s.event_id = e.id and s.status = 'maybe')),
         e.id
  from public.events e
  where e.event_date = (now() at time zone 'Europe/Oslo')::date + p_days_before
  on conflict (event_id) where kind = 'reminder' and actor_member_id is null and event_id is not null
  do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.queue_evening_reminders(integer) from public, anon, authenticated;
grant execute on function public.queue_evening_reminders(integer) to service_role;

commit;


-- ===========================================================================
-- ETTER MIGRERINGEN (ikke en del av fila, gjøres i Supabase-panelet)
-- ===========================================================================
-- A. Database Webhook (Database → Webhooks → Create):
--      navn  dd18_push_queue · tabell public.push_queue · hendelse INSERT
--      type  Supabase Edge Functions · funksjon push-send · metode POST
--      header  x-push-secret: <samme verdi som secret PUSH_HOOK_SECRET>
--    Hemmeligheten står bare i webhooken og i Edge Function-secrets, aldri i git.
--
-- B. Påminnelse før kvelden (valgfritt, krever pg_cron i Integrations):
--      select cron.schedule('dd18-paaminnelse', '0 8 * * *',
--                           $$select public.queue_evening_reminders(7)$$);
--    08:00 UTC = 09:00/10:00 i Oslo.
--
-- C. Feilet sending prøves igjen ved neste webhook (senderen tar alle
--    ventende jobber). Vil du ha et sikkerhetsnett uten ny trafikk, kan
--    pg_cron + pg_net kalle push-send hvert minutt. Ikke foreslått nå.


-- ===========================================================================
-- KONTROLL (kjør etterpå, én blokk om gangen, i SQL Editor)
-- ===========================================================================
-- 1. Tabellene finnes og har RLS på, push_tokens er borte.
--    Forventet: push_devices, push_preferences, push_queue med rls = true,
--    og ingen push_tokens.
--
-- select c.relname as tabell, c.relrowsecurity as rls
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
--   and c.relname in ('push_devices', 'push_preferences', 'push_queue', 'push_tokens')
-- order by 1;
--
-- 2. anon har INGEN tabellrettigheter. Forventet: 0 rader.
--
-- select table_name, privilege_type from information_schema.role_table_grants
-- where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
--   and table_name in ('push_devices', 'push_preferences', 'push_queue');
--
-- 3. authenticated har bare det som trengs. Forventet:
--    push_devices: SELECT · push_preferences: DELETE, INSERT, SELECT, UPDATE ·
--    push_queue: ingen rad.
--
-- select table_name, string_agg(privilege_type, ', ' order by privilege_type)
-- from information_schema.role_table_grants
-- where table_schema = 'public' and grantee = 'authenticated'
--   and table_name in ('push_devices', 'push_preferences', 'push_queue')
-- group by 1 order by 1;
--
-- 4. Funksjonsrettigheter. Forventet: anon_kan = false på ALLE.
--    auth_kan = true på push_player_categories, push_club_categories,
--    register_push_device, unregister_push_device og push_status; false på
--    resten. service_kan = true på claim_push_jobs, push_job_payload,
--    finish_push_job og queue_evening_reminders (Supabase gir service_role
--    alt som standard, så den er true på de andre også). register_push_token
--    skal ikke finnes lenger.
--
-- select p.proname as funksjon, p.prosecdef as definer,
--        has_function_privilege('anon',          p.oid, 'execute') as anon_kan,
--        has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--        has_function_privilege('service_role',  p.oid, 'execute') as service_kan
-- from pg_proc p join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('push_player_categories', 'push_club_categories',
--                     'register_push_device', 'unregister_push_device', 'push_status',
--                     'claim_push_jobs', 'push_job_payload', 'finish_push_job',
--                     'queue_evening_reminders', 'push_enqueue_activity',
--                     'push_enqueue_thread_message', 'register_push_token')
-- order by anon_kan desc, p.proname;
--
-- 5. Triggerne som fyller køen. Forventet: 2 rader.
--
-- select tgname, tgrelid::regclass from pg_trigger
-- where tgname in ('push_enqueue_activity', 'push_enqueue_thread_message');
--
-- 6. Klubbkolonnen. Forventet: 1 rad, default '{}'.
--
-- select column_name, column_default from information_schema.columns
-- where table_schema = 'public' and table_name = 'clubs'
--   and column_name = 'push_disabled_categories';
--
-- 7. Køen etter en prøvelinje (bare test). Skriv en linje i appen, så:
--    Forventet: én ny jobb med activity_id, done_at fylt etter at
--    push-send har kjørt, og result med sent/skipped.
--
-- select id, activity_id, thread_message_id, attempts, done_at, result, last_error
-- from public.push_queue order by id desc limit 5;
--
-- Rolleprøven sql/lokal/010_prove.sql er KUN for lokal Postgres.


-- ===========================================================================
-- RULLEBAKKE (fjerner ALT fra denne migreringen, inkludert data)
-- ===========================================================================
-- Bare på test. Slett webhooken dd18_push_queue og eventuell cron-jobb først.
-- push_tokens og register_push_token kommer IKKE tilbake av seg selv; kjør
-- avsnittene for dem fra 008 på nytt om de trengs.
--
-- begin;
-- drop function if exists public.queue_evening_reminders(integer);
-- drop index if exists public.activity_reminder_once_per_event;
-- drop function if exists public.finish_push_job(bigint, boolean, jsonb, text, text[]);
-- drop function if exists public.push_job_payload(bigint);
-- drop function if exists public.claim_push_jobs(integer);
-- drop function if exists public.push_status(uuid);
-- drop function if exists public.unregister_push_device(text);
-- drop function if exists public.register_push_device(text, text, text, text);
-- drop trigger if exists push_enqueue_thread_message on public.thread_messages;
-- drop trigger if exists push_enqueue_activity on public.activity;
-- drop function if exists public.push_enqueue_thread_message();
-- drop function if exists public.push_enqueue_activity();
-- drop table if exists public.push_queue, public.push_preferences, public.push_devices;
-- alter table public.clubs drop constraint if exists clubs_push_disabled_categories_check;
-- alter table public.clubs drop column if exists push_disabled_categories;
-- drop function if exists public.push_club_categories();
-- drop function if exists public.push_player_categories();
-- commit;
