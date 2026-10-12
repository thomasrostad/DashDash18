-- 046: varsler (gjennomføringsplanen steg 5). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–045 og 047 (kjøres på test etter dem). Rører ikke 047s tabeller.
--
-- Beslutningen (Thomas 11.10.2026, docs/plan-konkurranser-og-sosialt.md): «fire grupper
-- som kan slås av, demping av én kveld, ett «kvelden er i gang» per kveld, e-post til dem
-- uten push». I tillegg flyttes push per turnering hit fra 034, og det kommer en logg per
-- mottaker.
--
-- Hva fila gjør:
--   1. Fire varselgrupper over dagens kategorier. Nøklene (navn i appen):
--        game      (Spillet):   score, lead, side_prize, round, bet, tips
--        social    (Sosialt):   social, club, thread (og reaksjoner, kommentarer og
--                                @-omtale når de kommer i steg 9)
--        evening   (Kvelden):   signup, reminder, nudge, setup, announcement, og
--                                hendelsen evening_started (kategori round)
--        organizer (Arrangør):  signup_dropped (kategori signup, bare til dem med
--                                rettigheten tournaments), og rapporter senere
--      Gruppen avgjøres av kind først (evening_started, signup_dropped), ellers av
--      kategorien: public.push_group(kategori, kind). Hele tabellen per kind står i
--      public.push_group_map() (appen kan lese den til innstillingene).
--      push_preferences.disabled_groups (tom = alt på) lagres per medlemskap, som
--      disabled_categories. Gruppe av = alle kategoriene i gruppen av. Kategorivalget
--      og trådvalget (thread_mode) virker som før, i tillegg. «Melding til alle»
--      (announcement) kan fortsatt ikke slås av, heller ikke med gruppen Kvelden.
--      RPC push_set_groups(grupper, e-post) skriver valget på alle medlemskapene til
--      innloggingen, så gruppene i praksis er per bruker.
--   2. Demping av én kveld: push_event_mutes (user_id, event_id, created_at), RLS: bare
--      egne rader leses, skriving bare med push_mute_event(kveld, på/av). Dempet gir
--      ingen push for linjer på kvelden (activity.event_id, eller runden sin kveld) og
--      ingen push fra kveldens tråd. Unntak: «Melding til alle». Andre kvelder er som før.
--   3. Ett «kvelden er i gang»: når den første vanlige runden på en kveld går til
--      active, lager en trigger på rounds én linje evening_started (kategori round,
--      gruppe Kvelden) for kvelden. Senere runder samme kveld (ny runde, ny pulje, en
--      runde som startes på nytt) gir ingen ny linje (unik indeks per kveld, og
--      triggeren ser etter en annen runde som alt er startet). Playoff (047) gir ingen.
--      round_started (skrevet av appen per runde) står fortsatt i Hjem og Varsler,
--      fordi den sier hvilken runde og bane, men går ikke lenger som push. Første runde
--      får dermed én push (kvelden er i gang), og runde 2 og 3 ingen.
--      push_job_payload gir collapse = 'event-<kveld>-<gruppe>' for linjer med kveld, så
--      push-send kan sette apns-collapse-id: et nyere varsel i samme gruppe samme kveld
--      erstatter det forrige på låseskjermen. Tråden får ingen collapse (hver melding
--      står).
--   4. Push per turnering (flyttet fra 034): push_queue.competition_id, club_id er
--      valgfri (klubb eller turnering kreves). Hendelser uten klubb (034) går nå i køen.
--      For dem henter push_job_payload mottakerne fra turneringen: aktive deltakere
--      (profil, eller medlem med innlogging), stab, eier, og klubbens aktive medlemmer
--      når entry = 'club'. Medlemmene i svaret har da profil-id som id. For klubbens
--      jobber er svaret som før, med noen nye nøkler (lokal/046_prove.sql X1–X3).
--   5. Logg per mottaker: notifications (user_id, activity_id eller thread_message_id,
--      job_id, channel push/email, status queued/sent/failed/skipped, reason,
--      created_at, sent_at). Skrives bare av push-send (service_role) med
--      push_log_result(jobb, resultater). Brukeren leser egne rader. Én rad per bruker,
--      kanal og linje: en ny runde på samme jobb oppdaterer raden (sent står).
--   6. E-post til dem uten push, grunnmur: push_preferences.email_fallback (på som
--      standard) og push_email_recipients(jobb) (bare service_role): mottakerne av
--      jobben som ikke har noen telefon i push_devices, har e-post på og en e-post i
--      auth.users, med de samme reglene som push (kategori, gruppe, demping, mottakerliste,
--      ikke den som gjorde det), og bare for linjene i push_email_kinds():
--      announcement, nudge, reminder, waitlist_promoted og signup_dropped. Ikke for
--      tråden, store scorer og slikt. Selve sendingen gjør push-send når SMTP er satt
--      opp. SMTP må Thomas sette opp (Supabase → Authentication → SMTP, eller en
--      e-posttjeneste med nøkkel i Edge Function-secrets).
--
-- push_job_payload: nye nøkler
--   på toppen:   group, collapse, event_id (kvelden, også via runden), competition
--                ({id, name} eller null), audience ('club' eller 'competition');
--                club er {id: null, name: turneringens navn, disabled_categories: []}
--                for jobber uten klubb, så dagens push-send ikke krasjer;
--   per medlem:  user_id, disabled_groups, email_fallback, muted, group_off. Er
--                medlemmet dempet eller har slått av gruppen, er devices tom (så dagens
--                push-send ikke sender), og muted/group_off sier hvorfor.
--
-- Mønsteret fra 001–047: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.
--
-- push-send må (ikke i denne fila):
--   * bruke payload.collapse som apns-collapse-id når den finnes (ellers som i dag:
--     lead-<runde>, table-<turnering>);
--   * tekst for evening_started («🏁 Kvelden er i gang: torsdag 8. oktober · Runde 1 –
--     Pebble Beach»), data.event_date, data.round_no, data.course_name;
--   * logge hvert medlem med push_log_result: sent/failed per innlogging etter APNs,
--     skipped med grunn (muted, group_off, category_off, club_off, blocked, actor,
--     not_recipient, too_old) for dem som ellers ville fått den, og ikke logge dem uten
--     innlogging;
--   * jobber uten klubb (audience = 'competition'): id-ene er profil-id-er, så
--     blokkering leses rett fra user_blocks (blocker_id/blocked_id) i stedet for via
--     club_members; threadId competition-<id>;
--   * e-post: når SMTP finnes, kalle push_email_recipients(jobb) for activity-jobber,
--     sende, og logge channel = 'email' med push_log_result.
-- Appen må:
--   * vise de fire gruppene i Deg → Varsler (push_group_map for hva som hører til
--     hvor), lagre med push_set_groups, beholde kategoriene som «Mer» under hver gruppe;
--   * «Demp denne kvelden» på Kveld-skjermen (push_mute_event, lese push_event_mutes);
--   * tekst for evening_started i Hjem og Varsler (ActivityEvent, kategori round);
--   * bryter «E-post når jeg ikke har push» (email_fallback);
--   * gjerne «Varsler sendt» fra notifications senere (valgfritt).

begin;


-- ===========================================================================
-- 1. GRUPPENE
-- ===========================================================================
create or replace function public.push_groups()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['game', 'social', 'evening', 'organizer']::text[];
$$;
revoke all on function public.push_groups() from public, anon;
grant execute on function public.push_groups() to authenticated, service_role;

-- Gruppen for en linje (kategori og kind) eller tråden (kategori 'thread').
-- kind går foran kategorien. Ukjent kategori gir null (push-send hopper over den).
create or replace function public.push_group(p_category text, p_kind text default null)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_kind = 'signup_dropped' then 'organizer'
    when p_kind = 'evening_started' then 'evening'
    when p_category in ('score', 'lead', 'side_prize', 'round', 'bet', 'tips') then 'game'
    when p_category in ('social', 'club', 'thread') then 'social'
    when p_category in ('signup', 'reminder', 'nudge', 'setup', 'announcement') then 'evening'
  end;
$$;
revoke all on function public.push_group(text, text) from public, anon;
grant execute on function public.push_group(text, text) to authenticated, service_role;

-- Hele kartet: hver kjente kind (fra appens ActivityEvent.knownKinds, 045 og 046) med
-- kategori og gruppe, pluss tråden. Kategorier uten egen kind (en ny kind fra en nyere
-- klient) følger kategorien.
create or replace function public.push_group_map()
returns table (group_key text, category text, kind text)
language sql
immutable
set search_path = ''
as $$
  select public.push_group(m.category, m.kind), m.category, m.kind
  from (values
    ('round', 'round_started'), ('round', 'round_locked'), ('round', 'round_deleted'),
    ('round', 'table_changed'), ('round', 'evening_started'),
    ('score', 'big_score'), ('lead', 'lead_changed'), ('side_prize', 'side_prize'),
    ('setup', 'score_corrected'),
    ('signup', 'signup'), ('signup', 'waitlist_promoted'), ('signup', 'signup_dropped'),
    ('nudge', 'nudge'), ('reminder', 'reminder'), ('announcement', 'announcement'),
    ('social', 'committee_drawn'), ('club', 'member_joined'), ('tips', 'tips_king'),
    ('bet', 'bet_created'), ('bet', 'bet_challenge'), ('bet', 'bet_resolved'),
    ('thread', 'thread_message')
  ) as m (category, kind)
  order by 1, 2, 3;
$$;
revoke all on function public.push_group_map() from public, anon;
grant execute on function public.push_group_map() to authenticated, service_role;

-- Linjene som også kan gå som e-post (punkt 6).
create or replace function public.push_email_kinds()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['announcement', 'nudge', 'reminder', 'waitlist_promoted', 'signup_dropped']::text[];
$$;
revoke all on function public.push_email_kinds() from public, anon;
grant execute on function public.push_email_kinds() to authenticated, service_role;

alter table public.push_preferences
  add column if not exists disabled_groups text[] not null default '{}',
  add column if not exists email_fallback boolean not null default true;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.push_preferences'::regclass
                   and conname = 'push_preferences_disabled_groups_check') then
    alter table public.push_preferences add constraint push_preferences_disabled_groups_check
      check (disabled_groups <@ public.push_groups());
  end if;
end $$;

-- Gruppene (og e-post) for alle medlemskapene til innloggingen. null for e-post = uendret.
create or replace function public.push_set_groups(p_disabled_groups text[], p_email_fallback boolean default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_groups text[] := coalesce(p_disabled_groups, '{}');
  v_count  integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if not (v_groups <@ public.push_groups()) then
    raise exception 'Ukjent varselgruppe' using errcode = '22023';
  end if;
  select coalesce(array_agg(distinct g order by g), '{}') into v_groups from unnest(v_groups) g;

  insert into public.push_preferences (member_id, club_id, disabled_groups, email_fallback)
  select m.id, m.club_id, v_groups, coalesce(p_email_fallback, true)
    from public.club_members m
   where m.user_id = auth.uid() and m.status = 'active'
  on conflict (member_id) do update
     set disabled_groups = excluded.disabled_groups,
         email_fallback  = coalesce(p_email_fallback, public.push_preferences.email_fallback);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.push_set_groups(text[], boolean) from public, anon;
grant execute on function public.push_set_groups(text[], boolean) to authenticated;


-- ===========================================================================
-- 2. DEMPING AV ÉN KVELD
-- ===========================================================================
create table if not exists public.push_event_mutes (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  event_id   uuid not null references public.events (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, event_id)
);
create index if not exists push_event_mutes_event_idx on public.push_event_mutes (event_id);
alter table public.push_event_mutes enable row level security;
revoke all on table public.push_event_mutes from public, anon, authenticated;
grant select on table public.push_event_mutes to authenticated;
grant all on table public.push_event_mutes to service_role;
drop policy if exists push_event_mutes_select on public.push_event_mutes;
create policy push_event_mutes_select on public.push_event_mutes
  for select to authenticated using (user_id = (select auth.uid()));

-- Demp (p_on = true) eller slå på igjen. Svarer om kvelden er dempet etterpå.
create or replace function public.push_mute_event(p_event_id uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_on is null then
    raise exception 'Velg på eller av' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.events e
     where e.id = p_event_id
       and (public.is_club_member(e.club_id)
            or (e.competition_id is not null and public.can_read_competition(e.competition_id)))
  ) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if p_on then
    insert into public.push_event_mutes (user_id, event_id)
    values (auth.uid(), p_event_id)
    on conflict do nothing;
  else
    delete from public.push_event_mutes m where m.user_id = auth.uid() and m.event_id = p_event_id;
  end if;
  return p_on;
end;
$$;
revoke all on function public.push_mute_event(uuid, boolean) from public, anon;
grant execute on function public.push_mute_event(uuid, boolean) to authenticated;


-- ===========================================================================
-- 3. «KVELDEN ER I GANG»
-- ===========================================================================
create unique index if not exists activity_evening_started_once
  on public.activity (event_id) where kind = 'evening_started';

create or replace function private.rounds_evening_started()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev   text := current_setting('dd18.server_activity', true);
  v_date   date;
  v_course text;
begin
  if new.status <> 'active' or new.kind <> 'normal' or new.event_id is null or new.club_id is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status = 'active' then
    return null;
  end if;
  -- Kvelden er alt i gang hvis en annen vanlig runde er startet (eller låst).
  if exists (select 1 from public.rounds r
              where r.event_id = new.event_id and r.id <> new.id and r.kind = 'normal'
                and (r.status in ('active', 'locked') or r.started_at is not null)) then
    return null;
  end if;

  select e.event_date into v_date from public.events e where e.id = new.event_id;
  select c.name into v_course from public.courses c where c.id = new.course_id;

  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, event_id, round_id)
  values (new.club_id, 'evening_started', 'round',
          jsonb_strip_nulls(jsonb_build_object(
            'event_date', to_char(v_date, 'YYYY-MM-DD'),
            'round_no', new.round_no,
            'course_name', v_course,
            'hole_count', new.hole_count)),
          case when auth.uid() is null then null else public.my_member_id(new.club_id) end,
          new.event_id, new.id)
  on conflict (event_id) where kind = 'evening_started' do nothing;
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
  return null;
end;
$$;
revoke all on function private.rounds_evening_started() from public, anon, authenticated;

drop trigger if exists rounds_evening_started on public.rounds;
create trigger rounds_evening_started
  after insert or update of status on public.rounds
  for each row
  when (new.status = 'active')
  execute function private.rounds_evening_started();


-- ===========================================================================
-- 4. PUSH PER TURNERING
-- ===========================================================================
alter table public.push_queue
  add column if not exists competition_id uuid references public.competitions (id) on delete cascade;
alter table public.push_queue alter column club_id drop not null;
do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.push_queue'::regclass and conname = 'push_queue_club_or_competition') then
    alter table public.push_queue add constraint push_queue_club_or_competition
      check (club_id is not null or competition_id is not null);
  end if;
end $$;
create index if not exists push_queue_competition_idx on public.push_queue (competition_id)
  where competition_id is not null;

-- Fra 034. Nytt: hendelser uten klubb går i køen med turneringen, og round_started går
-- ikke som push (kveldens push er evening_started).
create or replace function public.push_enqueue_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is null and new.competition_id is null then
    return null;
  end if;
  if new.kind = 'round_started' then
    return null;
  end if;
  if new.round_id is not null
     and exists (select 1 from public.rounds r where r.id = new.round_id and r.status = 'draft') then
    return null;
  end if;
  insert into public.push_queue (club_id, competition_id, activity_id)
  values (new.club_id, new.competition_id, new.id)
  on conflict do nothing;
  return null;
end;
$$;
revoke all on function public.push_enqueue_activity() from public, anon, authenticated;

-- Mottakerne i en turnering uten klubb: innloggingene (profil-id).
create or replace function private.push_competition_audience(p_competition_id uuid)
returns table (user_id uuid, is_organizer boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with c as (select * from public.competitions where id = p_competition_id),
  u as (
    select p.profile_id as uid from public.competition_participants p, c
     where p.competition_id = c.id and p.status = 'active' and p.profile_id is not null
    union
    select m.user_id from public.competition_participants p
      join public.club_members m on m.id = p.member_id, c
     where p.competition_id = c.id and p.status = 'active' and m.status = 'active' and m.user_id is not null
    union
    select s.profile_id from public.competition_staff s, c where s.competition_id = c.id
    union
    select c.owner_id from c where c.owner_id is not null
    union
    select m.user_id from public.club_members m, c
     where c.entry = 'club' and m.club_id = c.club_id and m.status = 'active' and m.user_id is not null
  )
  select u.uid,
         exists (select 1 from c where c.owner_id = u.uid)
         or exists (select 1 from public.competition_staff s
                     where s.competition_id = p_competition_id and s.profile_id = u.uid and s.role = 'organizer')
    from u
   where u.uid is not null;
$$;
revoke all on function private.push_competition_audience(uuid) from public, anon, authenticated;

-- Fra 010. For klubbens jobber er de gamle nøklene uendret (lokal/046_prove.sql X1–X3).
create or replace function public.push_job_payload(p_job_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select * from public.push_queue where id = p_job_id
  ),
  a as (
    select a.* from public.activity a join q on a.id = q.activity_id
  ),
  t as (
    select t.* from public.thread_messages t join q on t.id = q.thread_message_id
  ),
  ctx as (
    select q.id as job_id,
           q.club_id,
           coalesce(q.competition_id, (select a.competition_id from a)) as competition_id,
           coalesce((select a.event_id from a),
                    (select r.event_id from a join public.rounds r on r.id = a.round_id),
                    (select t.event_id from t)) as event_id,
           case when q.activity_id is not null then (select a.category from a) else 'thread' end as category,
           case when q.activity_id is not null
                then public.push_group((select a.category from a), (select a.kind from a))
                else 'social' end as grp
      from q
  ),
  -- Klubbens jobber: alle i klubben, som før.
  club_aud as (
    select m.id, m.user_id, m.display_name, m.is_organizer,
           (m.status = 'active' and m.user_id is not null) as active,
           (m.status = 'active') as may_have_devices,
           coalesce(p.disabled_categories, '{}'::text[]) as disabled_categories,
           coalesce(p.thread_mode, 'mentions') as thread_mode,
           coalesce(p.disabled_groups, '{}'::text[]) as disabled_groups,
           coalesce(p.email_fallback, true) as email_fallback
      from ctx
      join public.club_members m on m.club_id = ctx.club_id
      left join public.push_preferences p on p.member_id = m.id
  ),
  -- Turnering uten klubb: innloggingene, med valgene fra medlemskapene (det strengeste).
  comp_aud as (
    select ca.user_id as id, ca.user_id,
           coalesce(pr.display_name, 'Noen') as display_name,
           ca.is_organizer,
           true as active,
           true as may_have_devices,
           coalesce((select array_agg(distinct c order by c)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_categories) c
                      where m.user_id = ca.user_id and m.status = 'active'), '{}'::text[]) as disabled_categories,
           'mentions'::text as thread_mode,
           coalesce((select array_agg(distinct g order by g)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_groups) g
                      where m.user_id = ca.user_id and m.status = 'active'), '{}'::text[]) as disabled_groups,
           coalesce((select bool_and(p.email_fallback)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id
                      where m.user_id = ca.user_id and m.status = 'active'), true) as email_fallback
      from ctx
      cross join lateral private.push_competition_audience(ctx.competition_id) ca
      left join public.profiles pr on pr.id = ca.user_id
     where ctx.club_id is null
  ),
  aud as (
    select x.*,
           (ctx.category <> 'announcement' and ctx.event_id is not null and x.user_id is not null
            and exists (select 1 from public.push_event_mutes mu
                         where mu.user_id = x.user_id and mu.event_id = ctx.event_id)) as muted,
           (ctx.category <> 'announcement' and ctx.grp = any (x.disabled_groups)) as group_off
      from (select * from club_aud union all select * from comp_aud) x, ctx
  )
  select jsonb_build_object(
    'job_id', q.id,
    'kind', case when q.activity_id is not null then 'activity' else 'thread' end,
    'club', case
      when c.id is not null then jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'disabled_categories', to_jsonb(c.push_disabled_categories))
      else jsonb_build_object('id', null, 'name', co.name, 'disabled_categories', '[]'::jsonb)
    end,
    'activity', (
      select jsonb_build_object(
        'id', a.id, 'kind', a.kind, 'category', a.category, 'data', a.data,
        'actor_member_id', a.actor_member_id, 'event_id', a.event_id,
        'round_id', a.round_id, 'recipients', to_jsonb(a.recipients),
        'created_at', a.created_at,
        'round_status', (select r.status from public.rounds r where r.id = a.round_id))
      from a
    ),
    'message', (
      select jsonb_build_object(
        'id', t.id, 'event_id', t.event_id, 'member_id', t.member_id,
        'body', t.body, 'mentions', to_jsonb(t.mentions),
        'has_image', t.image_path is not null, 'created_at', t.created_at,
        'pushed_at', t.pushed_at,
        'event_date', (select e.event_date from public.events e where e.id = t.event_id))
      from t
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id,
        'display_name', m.display_name,
        'is_organizer', m.is_organizer,
        'active', m.active,
        'disabled_categories', to_jsonb(m.disabled_categories),
        'thread_mode', m.thread_mode,
        'devices', case when m.muted or m.group_off then '[]'::jsonb else coalesce((
          select jsonb_agg(jsonb_build_object(
                   'token', d.token, 'environment', d.environment, 'bundle_id', d.bundle_id)
                 order by d.device_id)
          from public.push_devices d
          where m.may_have_devices and d.user_id = m.user_id
        ), '[]'::jsonb) end,
        'user_id', m.user_id,
        'disabled_groups', to_jsonb(m.disabled_groups),
        'email_fallback', m.email_fallback,
        'muted', m.muted,
        'group_off', m.group_off
      ) order by m.id)
      from aud m
    ), '[]'::jsonb),
    'group', ctx.grp,
    'event_id', ctx.event_id,
    'collapse', case when q.activity_id is not null and ctx.event_id is not null and ctx.grp is not null
                     then 'event-' || ctx.event_id || '-' || ctx.grp end,
    'competition', case when co.id is not null then jsonb_build_object('id', co.id, 'name', co.name) end,
    'audience', case when q.club_id is not null then 'club' else 'competition' end
  )
  from q
  cross join ctx
  left join public.clubs c on c.id = q.club_id
  left join public.competitions co on co.id = ctx.competition_id;
$$;
revoke all on function public.push_job_payload(bigint) from public, anon, authenticated;
grant execute on function public.push_job_payload(bigint) to service_role;


-- ===========================================================================
-- 5. LOGG PER MOTTAKER
-- ===========================================================================
create table if not exists public.notifications (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users (id) on delete cascade,
  activity_id       uuid references public.activity (id) on delete cascade,
  thread_message_id uuid references public.thread_messages (id) on delete cascade,
  job_id            bigint references public.push_queue (id) on delete set null,
  channel           text not null check (channel in ('push', 'email')),
  status            text not null check (status in ('queued', 'sent', 'failed', 'skipped')),
  reason            text check (reason is null or char_length(reason) <= 200),
  created_at        timestamptz not null default now(),
  sent_at           timestamptz,
  source_id         uuid generated always as (coalesce(activity_id, thread_message_id)) stored,
  constraint notifications_one_source check (num_nonnulls(activity_id, thread_message_id) = 1),
  constraint notifications_once unique (user_id, channel, source_id)
);
create index if not exists notifications_user_time_idx on public.notifications (user_id, created_at desc);
create index if not exists notifications_activity_idx on public.notifications (activity_id) where activity_id is not null;
create index if not exists notifications_thread_idx on public.notifications (thread_message_id) where thread_message_id is not null;
create index if not exists notifications_job_idx on public.notifications (job_id) where job_id is not null;
alter table public.notifications enable row level security;
revoke all on table public.notifications from public, anon, authenticated;
grant select on table public.notifications to authenticated;
grant all on table public.notifications to service_role;
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));

-- p_results: [{user_id | member_id, channel ('push' standard), status, reason}, …].
-- Flere rader for samme innlogging og kanal (flere telefoner) slås sammen: sent > failed
-- > skipped > queued. En rad som er sent, blir stående som sent.
create or replace function public.push_log_result(p_job_id bigint, p_results jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job   public.push_queue;
  v_count integer;
begin
  select * into v_job from public.push_queue where id = p_job_id;
  if not found then
    raise exception 'Fant ikke jobben' using errcode = 'P0002';
  end if;
  if p_results is null or jsonb_typeof(p_results) <> 'array' or jsonb_array_length(p_results) > 5000 then
    raise exception 'Resultatene må være en liste (høyst 5000)' using errcode = '22023';
  end if;

  insert into public.notifications (user_id, activity_id, thread_message_id, job_id, channel, status, reason, sent_at)
  select distinct on (x.uid, x.channel)
         x.uid, v_job.activity_id, v_job.thread_message_id, p_job_id, x.channel, x.status, x.reason,
         case when x.status = 'sent' then now() end
    from (
      select coalesce(r.user_id, m.user_id) as uid,
             coalesce(r.channel, 'push') as channel,
             r.status,
             left(r.reason, 200) as reason
        from jsonb_to_recordset(p_results) as r (user_id uuid, member_id uuid, channel text, status text, reason text)
        left join public.club_members m on m.id = r.member_id and r.user_id is null
    ) x
   where x.uid is not null
     and exists (select 1 from auth.users u where u.id = x.uid)
   order by x.uid, x.channel,
            array_position(array['sent', 'failed', 'skipped', 'queued'], x.status) nulls last
  on conflict (user_id, channel, source_id) do update
     set status  = case when public.notifications.status = 'sent' then 'sent' else excluded.status end,
         reason  = case when public.notifications.status = 'sent' then public.notifications.reason else excluded.reason end,
         job_id  = excluded.job_id,
         sent_at = coalesce(public.notifications.sent_at, excluded.sent_at);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.push_log_result(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.push_log_result(bigint, jsonb) to service_role;


-- ===========================================================================
-- 6. E-POST TIL DEM UTEN PUSH (grunnmur)
-- ===========================================================================
-- Mottakerne av en activity-jobb som ikke har noen telefon, har e-post på og en e-post.
-- Samme regler som push-send for push: klubbens og egne kategorier, gruppen, demping,
-- mottakerlista, ikke den som gjorde det. Blokkering (user_blocks) sjekkes også her.
-- E-posten leses med to_jsonb, så funksjonen også kan lages der auth.users er en stubb.
create or replace function public.push_email_recipients(p_job_id bigint)
returns table (user_id uuid, member_id uuid, display_name text, email text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p    jsonb := public.push_job_payload(p_job_id);
  v_a    jsonb := v_p -> 'activity';
  v_cat  text  := v_a ->> 'category';
  v_kind text  := v_a ->> 'kind';
  v_actor_user uuid;
begin
  if v_p is null or v_a is null or jsonb_typeof(v_a) <> 'object' then
    return;
  end if;
  if not (v_kind = any (public.push_email_kinds())) then
    return;
  end if;
  if v_cat not in ('announcement', 'nudge')
     and v_cat = any (array(select jsonb_array_elements_text(v_p -> 'club' -> 'disabled_categories'))) then
    return;
  end if;
  select m.user_id into v_actor_user from public.club_members m
   where m.id = (v_a ->> 'actor_member_id')::uuid;

  return query
  select (m ->> 'user_id')::uuid,
         case when v_p ->> 'audience' = 'club' then (m ->> 'id')::uuid end,
         m ->> 'display_name',
         to_jsonb(u) ->> 'email'
    from jsonb_array_elements(v_p -> 'members') m
    join auth.users u on u.id = (m ->> 'user_id')::uuid
   where (m ->> 'active')::boolean
     and not (m ->> 'muted')::boolean
     and not (m ->> 'group_off')::boolean
     and (m ->> 'email_fallback')::boolean
     and coalesce(to_jsonb(u) ->> 'email', '') like '%@%'
     and not exists (select 1 from public.push_devices d where d.user_id = (m ->> 'user_id')::uuid)
     and (v_cat = 'announcement'
          or not (v_cat = any (array(select jsonb_array_elements_text(m -> 'disabled_categories')))))
     and (jsonb_typeof(v_a -> 'recipients') <> 'array'
          or (v_a -> 'recipients') ? (m ->> 'id'))
     and (m ->> 'id') is distinct from (v_a ->> 'actor_member_id')
     and (v_actor_user is null
          or not exists (select 1 from public.user_blocks b
                          where b.blocker_id = (m ->> 'user_id')::uuid and b.blocked_id = v_actor_user))
     and not exists (select 1 from public.notifications n
                      where n.user_id = (m ->> 'user_id')::uuid and n.channel = 'email'
                        and n.activity_id = (v_a ->> 'id')::uuid and n.status = 'sent');
end;
$$;
revoke all on function public.push_email_recipients(bigint) from public, anon, authenticated;
grant execute on function public.push_email_recipients(bigint) to service_role;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
  v_cat  text;
  v_n    integer;
begin
  -- 1. Hver kategori (activity, push og tråden) har en gruppe.
  foreach v_cat in array (public.push_player_categories() || public.push_club_categories()
                          || array['announcement', 'thread']) loop
    if public.push_group(v_cat) is null then
      v_fail := v_fail || ' 1(' || v_cat || ')';
    end if;
  end loop;
  -- 2. Hver kind i activity og i kartet har en gruppe, og kartet har bare kjente grupper.
  if exists (select 1 from public.activity a where public.push_group(a.category, a.kind) is null)
     or exists (select 1 from public.push_group_map() m
                where m.group_key is null or not (m.group_key = any (public.push_groups()))) then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. De nye kolonnene og kravet på køen.
  if (select count(*) from information_schema.columns
       where table_schema = 'public'
         and ((table_name = 'push_preferences' and column_name in ('disabled_groups', 'email_fallback'))
           or (table_name = 'push_queue' and column_name = 'competition_id'))) <> 3
     or (select is_nullable from information_schema.columns
          where table_schema = 'public' and table_name = 'push_queue' and column_name = 'club_id') <> 'YES'
     or exists (select 1 from public.push_queue where club_id is null and competition_id is null) then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. RLS på de nye tabellene, og ingen skriving for appen.
  if not (select relrowsecurity from pg_class where oid = 'public.push_event_mutes'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.notifications'::regclass)
     or has_table_privilege('authenticated', 'public.notifications', 'insert')
     or has_table_privilege('authenticated', 'public.push_event_mutes', 'insert')
     or has_table_privilege('anon', 'public.notifications', 'select') then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Bare service_role kaller senderens funksjoner.
  if has_function_privilege('authenticated', 'public.push_log_result(bigint, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.push_log_result(bigint, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.push_email_recipients(bigint)', 'execute')
     or has_function_privilege('anon', 'public.push_email_recipients(bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.push_job_payload(bigint)', 'execute')
     or not has_function_privilege('service_role', 'public.push_log_result(bigint, jsonb)', 'execute')
     or not has_function_privilege('service_role', 'public.push_email_recipients(bigint)', 'execute') then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Appens RPC-er: innlogget ja, anon nei.
  if not has_function_privilege('authenticated', 'public.push_mute_event(uuid, boolean)', 'execute')
     or has_function_privilege('anon', 'public.push_mute_event(uuid, boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.push_set_groups(text[], boolean)', 'execute')
     or has_function_privilege('anon', 'public.push_set_groups(text[], boolean)', 'execute') then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Triggeren og den unike indeksen for «kvelden er i gang».
  if not exists (select 1 from pg_trigger where tgrelid = 'public.rounds'::regclass
                  and tgname = 'rounds_evening_started' and not tgisinternal)
     or not exists (select 1 from pg_indexes where schemaname = 'public'
                     and indexname = 'activity_evening_started_once') then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Alle jobbene i køen gir et svar fra push_job_payload.
  select count(*) into v_n from public.push_queue q where public.push_job_payload(q.id) is null;
  if v_n > 0 then
    v_fail := v_fail || ' 8';
  end if;
  if v_fail <> '' then
    raise exception '046 kontroll feilet:%', v_fail;
  end if;
  raise notice '046 kontroll: 8 av 8';
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (før appen og push-send bruker gruppene, dempingen eller loggen)
-- ===========================================================================
-- begin;
-- drop function if exists public.push_email_recipients(bigint);
-- drop function if exists public.push_log_result(bigint, jsonb);
-- drop table if exists public.notifications;
-- (gjenopprett push_job_payload fra 010_push.sql)
-- drop function if exists private.push_competition_audience(uuid);
-- (gjenopprett push_enqueue_activity fra 034_turnering_kjerne_trinn4.sql)
-- delete from public.push_queue where club_id is null;
-- drop index if exists public.push_queue_competition_idx;
-- alter table public.push_queue drop constraint if exists push_queue_club_or_competition;
-- alter table public.push_queue alter column club_id set not null;
-- alter table public.push_queue drop column if exists competition_id;
-- drop trigger if exists rounds_evening_started on public.rounds;
-- drop function if exists private.rounds_evening_started();
-- delete from public.activity where kind = 'evening_started';
-- drop index if exists public.activity_evening_started_once;
-- drop function if exists public.push_mute_event(uuid, boolean);
-- drop table if exists public.push_event_mutes;
-- drop function if exists public.push_set_groups(text[], boolean);
-- alter table public.push_preferences drop constraint if exists push_preferences_disabled_groups_check;
-- alter table public.push_preferences drop column if exists disabled_groups;
-- alter table public.push_preferences drop column if exists email_fallback;
-- drop function if exists public.push_email_kinds();
-- drop function if exists public.push_group_map();
-- drop function if exists public.push_group(text, text);
-- drop function if exists public.push_groups();
-- commit;
