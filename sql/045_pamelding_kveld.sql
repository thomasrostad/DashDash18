-- 045: påmelding per kveld (gjennomføringsplanen steg 4). Venter på godkjenning.
--
-- Krever 001–044 (044_roller kjøres på test før denne: private.has_club_right).
--
-- Beslutningene (Thomas 11.10.2026, docs/plan-konkurranser-og-sosialt.md):
--   * standardsvar som i dag: ingen rad i signups = «ikke svart»;
--   * ingen frister som standard, arrangøren slår dem på per kveld;
--   * venteliste med automatisk opprykk når det blir ledig plass, med varsel.
--
-- Hva fila gjør:
--   1. events: max_players (null = ingen grense), signup_deadline (ny «kommer» etter
--      fristen avvises), withdraw_deadline (avmelding fra «kommer» etter fristen
--      avvises), allow_guests (av som standard). Alle er tomme/av for kvelder som
--      finnes, så de oppfører seg som i dag. Arrangøren setter dem med vanlig update
--      (events_update, rettigheten tournaments).
--   2. signups: waitlisted_at (står på ventelista når satt; status er fortsatt 'yes',
--      så gamle bygg kan lese raden) og late (meldte av etter avmeldingsfristen; kan
--      bare skje når arrangøren endrer svaret).
--   3. event_guests (gjest på en kveld, lagt inn av et medlem når kvelden tillater
--      det): egen tabell, fordi signups har primærnøkkel (kveld, medlem) og
--      fremmednøkkel til club_members, og gamle bygg dekoder member_id som påkrevd.
--      En rad uten medlem i signups ville stoppe hele lista i dagens app. Gjester
--      teller mot max_players og står i samme venteliste (etter tid).
--   4. event_views («sett» per medlem og kveld): egen tabell, ikke en kolonne i
--      signups. En rad i signups betyr «har svart» for gamle bygg og for purringen;
--      «sett, men ikke svart» må derfor ligge et annet sted.
--   5. signup_log: hver endring av status (også venteliste, opprykk, gjester), hvem som
--      endret og en merknad (organizer, late, promoted, direct, system). Leses av
--      medlemmet selv og av dem med rettigheten tournaments.
--   6. Reglene ligger i triggere på signups (før og etter), så de gjelder uansett vei
--      inn (RPC, gamle bygg, service_role):
--        * kvelden låses med select … for update før noe telles, så to samtidige svar
--          aldri gir flere enn taket;
--        * «kommer» når kvelden er full gir waitlisted_at = clock_timestamp();
--        * en bekreftet «kommer» som går (nei, usikker, sletting, medlemmet slettes)
--          gir opprykk for den første på ventelista i samme transaksjon, med
--          aktivitet waitlist_promoted til den som rykker opp;
--        * fra bekreftet «kommer» til «kommer ikke» (eller sletting) gir aktivitet
--          signup_dropped til dem med rettigheten tournaments;
--        * fristene gjelder for medlemmet selv («Fristen er ute. Kontakt arrangøren.»,
--          SQLSTATE DDB02). Arrangøren (tournaments) og systemet kan alltid endre;
--          avmelding etter fristen merkes late;
--        * waitlisted_at, late og created_at settes alltid av triggeren.
--      Høyere eller fjernet tak på kvelden gir opprykk med en gang (trigger på events).
--      Lavere tak flytter ingen som alt er bekreftet.
--   7. RPC-er (security definer):
--        evening_signup(kveld, status, kommentar, medlem default null) -> jsonb
--        evening_mark_seen(kveld) -> timestamptz
--        evening_guest_add(kveld, navn, invitert_av default null) -> jsonb
--        evening_guest_remove(gjest) -> jsonb
--   8. Skrivepolicyene på signups: signups_insert/_update/_delete fjernes (også
--      arrangørgrenen). For gamle bygg, som skriver svaret med upsert rett i
--      tabellen, står to smale policyer igjen: signups_insert_old_builds og
--      signups_update_old_builds, bare egen rad (owns_member), og bare kolonnene
--      event_id, member_id, club_id, status og comment. De går gjennom de samme
--      triggerne (tak, venteliste, frister, opprykk, logg). Fjernes når
--      app_config.min_ios_build er bygget med evening_signup (linja står nederst).
--   9. queue_evening_reminders teller ikke dem på ventelista som «kommer», men teller
--      bekreftede gjester. Nøkkelen waitlist kommer bare med når noen står der.
--  10. activity_before_insert: aktivitet som serveren lager (dd18.server_activity =
--      on, satt av funksjonene her) kan ha mottakere selv om den som utløste den ikke
--      er arrangør.
--
-- Ingen andre funksjoner leser signups (søkt i hele sql/ og i basen: tavla_data,
-- tv_board_data, my_activity og push-funksjonene gjør det ikke). Appen og web-admin
-- teller selv, se «Appen må» nederst.
--
-- Mønsteret fra 001–044: én transaksjon, idempotent, search_path = '', revoke etter
-- hver create or replace, kontroll og rullebakke nederst.
--
-- Appen må (ikke i denne fila):
--   * svare med evening_signup i stedet for upsert, og vise «På venteliste (nr. N)»
--     og feilen DDB02;
--   * telle «kommer» som status = 'yes' and waitlisted_at is null (Kveld, Hjem-kortet,
--     arrangørsiden, RoundParticipants.initial, web-admin initialParticipants), og
--     legge til bekreftede gjester;
--   * ikke logge «meldte seg på» når svaret havnet på ventelista;
--   * kalle evening_mark_seen når kvelden vises, og vise «ikke sett» i purringen;
--   * push-send: tekst for waitlist_promoted og signup_dropped (i dag «Ny hendelse
--     i klubben»).

begin;


-- ===========================================================================
-- 1. EVENTS: TAK, FRISTER OG GJESTER
-- ===========================================================================
alter table public.events
  add column if not exists max_players       smallint,
  add column if not exists signup_deadline   timestamptz,
  add column if not exists withdraw_deadline timestamptz,
  add column if not exists allow_guests      boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'events_max_players_check') then
    alter table public.events add constraint events_max_players_check
      check (max_players is null or max_players between 1 and 500);
  end if;
end $$;

comment on column public.events.max_players is
  'Tak for «kommer» (medlemmer og gjester). null = ingen grense. Over taket havner man på ventelista.';
comment on column public.events.signup_deadline is
  'Påmeldingsfrist. Etter den kan bare arrangøren gi «kommer». null = ingen frist.';
comment on column public.events.withdraw_deadline is
  'Avmeldingsfrist. Etter den kan bare arrangøren melde av en som kommer (merkes late). null = ingen frist.';
comment on column public.events.allow_guests is
  'Medlemmer kan melde på gjester (event_guests). Av som standard.';


-- ===========================================================================
-- 2. SIGNUPS: VENTELISTE OG SEN AVMELDING
-- ===========================================================================
alter table public.signups
  add column if not exists waitlisted_at timestamptz,
  add column if not exists late          boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'signups_waitlist_only_yes') then
    alter table public.signups add constraint signups_waitlist_only_yes
      check (waitlisted_at is null or status = 'yes');
  end if;
end $$;

create index if not exists signups_waitlist_idx
  on public.signups (event_id, waitlisted_at) where waitlisted_at is not null;

comment on column public.signups.waitlisted_at is
  'Satt = på ventelista (status er yes). Rekkefølgen er etter tid. Settes av triggeren.';
comment on column public.signups.late is
  'Meldte av etter avmeldingsfristen (arrangøren endret svaret). Settes av triggeren.';


-- ===========================================================================
-- 3. NYE TABELLER: GJESTER, «SETT» OG LOGG
-- ===========================================================================
create table if not exists public.event_guests (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null,
  club_id        uuid not null,
  name           text not null check (char_length(btrim(name)) between 1 and 60),
  invited_by     uuid not null,
  waitlisted_at  timestamptz,
  created_by     uuid,
  created_at     timestamptz not null default now(),
  constraint event_guests_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint event_guests_inviter_fk foreign key (invited_by, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.event_guests is
  'Gjest på en kveld (kommer), lagt inn av et medlem når events.allow_guests. Teller mot max_players. '
  'Skrives bare av evening_guest_add/evening_guest_remove.';
create unique index if not exists event_guests_name_once
  on public.event_guests (event_id, lower(btrim(name)));
create index if not exists event_guests_inviter_idx on public.event_guests (invited_by);
create index if not exists event_guests_waitlist_idx
  on public.event_guests (event_id, waitlisted_at) where waitlisted_at is not null;

create table if not exists public.event_views (
  event_id   uuid not null,
  member_id  uuid not null,
  club_id    uuid not null,
  seen_at    timestamptz not null default now(),
  primary key (event_id, member_id),
  constraint event_views_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint event_views_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.event_views is
  'Første gang medlemmet så kvelden («sett»). Ingen rad og ingen svar = «ikke sett». Skrives av evening_mark_seen.';
create index if not exists event_views_member_idx on public.event_views (member_id);

create table if not exists public.signup_log (
  id          bigint generated always as identity primary key,
  event_id    uuid not null,
  club_id     uuid not null,
  member_id   uuid,
  guest_id    uuid,
  guest_name  text,
  old_status  text not null check (old_status in ('none', 'yes', 'waitlist', 'maybe', 'no')),
  new_status  text not null check (new_status in ('none', 'yes', 'waitlist', 'maybe', 'no')),
  changed_by  uuid,
  changed_at  timestamptz not null default now(),
  note        text check (note is null or note in ('organizer', 'late', 'promoted', 'direct', 'system')),
  constraint signup_log_event_fk foreign key (event_id, club_id)
    references public.events (id, club_id) on delete cascade,
  constraint signup_log_member_fk foreign key (member_id, club_id)
    references public.club_members (id, club_id) on delete cascade
);
comment on table public.signup_log is
  'Logg over svar per kveld. member_id = medlemmet, eller den som inviterte gjesten (guest_id/guest_name). '
  'status: none = ingen rad, waitlist = yes på ventelista. changed_by = innloggingen, null = systemet. '
  'note: organizer (arrangøren endret), late (avmeldt etter fristen), promoted (opprykk), '
  'direct (gammelt bygg skrev rett i tabellen), system.';
create index if not exists signup_log_event_idx on public.signup_log (event_id, changed_at);
create index if not exists signup_log_member_idx on public.signup_log (member_id) where member_id is not null;

alter table public.event_guests enable row level security;
alter table public.event_views  enable row level security;
alter table public.signup_log   enable row level security;

revoke all on table public.event_guests from public, anon, authenticated;
revoke all on table public.event_views  from public, anon, authenticated;
revoke all on table public.signup_log   from public, anon, authenticated;
grant select on table public.event_guests to authenticated;
grant select on table public.event_views  to authenticated;
grant select on table public.signup_log   to authenticated;
grant all on table public.event_guests to service_role;
grant all on table public.event_views  to service_role;
grant all on table public.signup_log   to service_role;

drop policy if exists event_guests_select on public.event_guests;
create policy event_guests_select on public.event_guests
  for select to authenticated using (public.is_club_member(club_id));

drop policy if exists event_views_select on public.event_views;
create policy event_views_select on public.event_views
  for select to authenticated
  using (public.owns_member(member_id) or private.has_club_right(club_id, 'tournaments'));

drop policy if exists signup_log_select on public.signup_log;
create policy signup_log_select on public.signup_log
  for select to authenticated
  using (public.owns_member(member_id) or private.has_club_right(club_id, 'tournaments'));

-- Sanntid for gjestene, som signups (gamle bygg følger ikke tabellen).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'event_guests') then
    alter publication supabase_realtime add table public.event_guests;
  end if;
end $$;


-- ===========================================================================
-- 4. HJELPERE (private, bare for funksjonene her)
-- ===========================================================================
create or replace function private.signup_syncing()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(current_setting('dd18.signup_sync', true), '') = 'on';
$$;
revoke all on function private.signup_syncing() from public, anon, authenticated;

-- none | yes | waitlist | maybe | no
create or replace function private.signup_state(p_status text, p_waitlisted_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_status is null then 'none'
              when p_status = 'yes' and p_waitlisted_at is not null then 'waitlist'
              else p_status end;
$$;
revoke all on function private.signup_state(text, timestamptz) from public, anon, authenticated;

-- Bekreftede plasser: medlemmer med yes uten venteliste, og gjester uten venteliste.
create or replace function private.evening_confirmed(p_event_id uuid, p_except_member uuid default null)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select ((select count(*) from public.signups s
            where s.event_id = p_event_id and s.status = 'yes' and s.waitlisted_at is null
              and s.member_id is distinct from p_except_member)
        + (select count(*) from public.event_guests g
            where g.event_id = p_event_id and g.waitlisted_at is null))::integer;
$$;
revoke all on function private.evening_confirmed(uuid, uuid) from public, anon, authenticated;

-- Ventelista i rekkefølge (medlemmer og gjester sammen).
create or replace function private.evening_waitlist(p_event_id uuid)
returns table (kind text, id uuid, member_id uuid, guest_name text, waitlisted_at timestamptz, place integer)
language sql
stable
security definer
set search_path = ''
as $$
  select w.kind, w.id, w.member_id, w.guest_name, w.waitlisted_at,
         (row_number() over (order by w.waitlisted_at, w.id))::integer
    from (select 'member'::text as kind, s.member_id as id, s.member_id, null::text as guest_name, s.waitlisted_at
            from public.signups s
           where s.event_id = p_event_id and s.status = 'yes' and s.waitlisted_at is not null
          union all
          select 'guest', g.id, g.invited_by, g.name, g.waitlisted_at
            from public.event_guests g
           where g.event_id = p_event_id and g.waitlisted_at is not null) w
   order by w.waitlisted_at, w.id;
$$;
revoke all on function private.evening_waitlist(uuid) from public, anon, authenticated;

-- Aktive medlemmer med en rettighet (eller eier) i klubben.
create or replace function private.club_members_with_right(p_club_id uuid, p_right text)
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct m.id), '{}')
    from public.club_members m
    join public.club_member_roles mr on mr.member_id = m.id
    join public.club_roles r on r.id = mr.role_id
   where m.club_id = p_club_id and m.status = 'active'
     and (r.is_owner or p_right = any (r.rights));
$$;
revoke all on function private.club_members_with_right(uuid, text) from public, anon, authenticated;

-- Aktivitet som serveren lager (kategori signup). Den som utløste den er aktør
-- (null for systemet). Mottakerlista kan settes uten at aktøren er arrangør.
create or replace function private.evening_activity(p_club_id uuid, p_event_id uuid, p_kind text,
                                                    p_data jsonb, p_recipients uuid[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := current_setting('dd18.server_activity', true);
begin
  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, kind, category, data, actor_member_id, event_id, recipients)
  values (p_club_id, p_kind, 'signup', p_data,
          case when auth.uid() is null then null else public.my_member_id(p_club_id) end,
          p_event_id, p_recipients[1:200]);
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.evening_activity(uuid, uuid, text, jsonb, uuid[]) from public, anon, authenticated;

-- Rykker opp fra ventelista så lenge det er plass. Kalles med kvelden låst (låser
-- den selv også). Gir antall som rykket opp.
create or replace function private.evening_fill(p_event_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e     public.events;
  v_free  integer;
  v_n     integer := 0;
  v_prev  text;
  r       record;
begin
  select * into v_e from public.events where id = p_event_id for update;
  if v_e.id is null then
    return 0;
  end if;
  v_free := case when v_e.max_players is null then 100000
                 else v_e.max_players - private.evening_confirmed(v_e.id) end;
  if v_free <= 0 then
    return 0;
  end if;

  v_prev := current_setting('dd18.signup_sync', true);
  perform set_config('dd18.signup_sync', 'on', true);
  for r in select * from private.evening_waitlist(v_e.id) w order by w.place limit v_free loop
    if r.kind = 'member' then
      update public.signups set waitlisted_at = null
       where event_id = v_e.id and member_id = r.member_id;
      insert into public.signup_log (event_id, club_id, member_id, old_status, new_status, changed_by, note)
      values (v_e.id, v_e.club_id, r.member_id, 'waitlist', 'yes', auth.uid(), 'promoted');
      perform private.evening_activity(v_e.club_id, v_e.id, 'waitlist_promoted',
        jsonb_build_object('member', r.member_id, 'event_date', to_char(v_e.event_date, 'YYYY-MM-DD')),
        array[r.member_id]);
    else
      update public.event_guests set waitlisted_at = null where id = r.id;
      insert into public.signup_log (event_id, club_id, member_id, guest_id, guest_name, old_status, new_status,
                                     changed_by, note)
      values (v_e.id, v_e.club_id, r.member_id, r.id, r.guest_name, 'waitlist', 'yes', auth.uid(), 'promoted');
      perform private.evening_activity(v_e.club_id, v_e.id, 'waitlist_promoted',
        jsonb_build_object('member', r.member_id, 'guest_name', r.guest_name,
                           'event_date', to_char(v_e.event_date, 'YYYY-MM-DD')),
        array[r.member_id]);
    end if;
    v_n := v_n + 1;
  end loop;
  perform set_config('dd18.signup_sync', coalesce(v_prev, ''), true);
  return v_n;
end;
$$;
revoke all on function private.evening_fill(uuid) from public, anon, authenticated;

-- Svaret RPC-ene gir tilbake.
create or replace function private.evening_signup_state(p_event_id uuid, p_member_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'event_id', e.id,
           'member_id', p_member_id,
           'status', s.status,
           'waitlisted', s.waitlisted_at is not null,
           'place', (select w.place from private.evening_waitlist(e.id) w
                      where w.kind = 'member' and w.member_id = p_member_id),
           'late', coalesce(s.late, false),
           'comment', s.comment,
           'confirmed', private.evening_confirmed(e.id),
           'waitlist', (select count(*)::integer from private.evening_waitlist(e.id)),
           'max_players', e.max_players,
           'signup_deadline', e.signup_deadline,
           'withdraw_deadline', e.withdraw_deadline)
    from public.events e
    left join public.signups s on s.event_id = e.id and s.member_id = p_member_id
   where e.id = p_event_id;
$$;
revoke all on function private.evening_signup_state(uuid, uuid) from public, anon, authenticated;


-- ===========================================================================
-- 5. REGLENE: TRIGGERE PÅ SIGNUPS, EVENTS OG EVENT_GUESTS
-- ===========================================================================
-- Før: lås kvelden, frister, tak og venteliste. Gjelder alle veier inn.
create or replace function private.signups_rules_before()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e       public.events;
  v_uid     uuid := auth.uid();
  v_event   uuid;
  v_bypass  boolean;
  v_old     text;
begin
  if private.signup_syncing() then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if tg_op = 'UPDATE' and (new.event_id <> old.event_id or new.member_id <> old.member_id
                           or new.club_id <> old.club_id) then
    raise exception 'Et svar kan ikke flyttes til en annen kveld eller person' using errcode = '22023';
  end if;

  v_event := case when tg_op = 'DELETE' then old.event_id else new.event_id end;
  select * into v_e from public.events where id = v_event for update;
  if v_e.id is null then
    -- Kvelden slettes (cascade), eller fremmednøkkelen avviser raden.
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  v_bypass := v_uid is null or private.has_club_right(v_e.club_id, 'tournaments');

  if tg_op = 'INSERT' then
    -- Upsert på en rad som finnes: BEFORE UPDATE tar seg av den.
    if exists (select 1 from public.signups s where s.event_id = new.event_id and s.member_id = new.member_id) then
      return new;
    end if;
    v_old := 'none';
    new.created_at := now();
  else
    v_old := private.signup_state(old.status, old.waitlisted_at);
  end if;

  if tg_op = 'DELETE' then
    if v_old = 'yes' and not v_bypass
       and v_e.withdraw_deadline is not null and now() > v_e.withdraw_deadline then
      raise exception 'Fristen er ute. Kontakt arrangøren.' using errcode = 'DDB02';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  end if;

  if new.status = 'yes' then
    if v_old in ('yes', 'waitlist') then
      new.waitlisted_at := old.waitlisted_at;
      new.late := old.late;
    else
      if not v_bypass and v_e.signup_deadline is not null and now() > v_e.signup_deadline then
        raise exception 'Fristen er ute. Kontakt arrangøren.' using errcode = 'DDB02';
      end if;
      new.late := false;
      new.waitlisted_at := case
        when v_e.max_players is not null
             and private.evening_confirmed(v_e.id, new.member_id) >= v_e.max_players then clock_timestamp()
        end;
    end if;
  else
    new.waitlisted_at := null;
    if v_old = 'yes' then
      if v_e.withdraw_deadline is not null and now() > v_e.withdraw_deadline then
        if not v_bypass then
          raise exception 'Fristen er ute. Kontakt arrangøren.' using errcode = 'DDB02';
        end if;
        new.late := true;
      else
        new.late := false;
      end if;
    elsif tg_op = 'UPDATE' then
      new.late := old.late;
    else
      new.late := false;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.signups_rules_before() from public, anon, authenticated;

-- Etter: logg, varsel til arrangøren og opprykk.
create or replace function private.signups_rules_after()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_e       public.events;
  v_uid     uuid := auth.uid();
  v_member  uuid := case when tg_op = 'DELETE' then old.member_id else new.member_id end;
  v_old     text;
  v_new     text;
  v_late    boolean;
  v_alive   boolean;
  v_note    text;
begin
  if private.signup_syncing() then
    return null;
  end if;
  select * into v_e from public.events
   where id = case when tg_op = 'DELETE' then old.event_id else new.event_id end;
  if v_e.id is null then
    return null;
  end if;

  v_old := case when tg_op = 'INSERT' then 'none' else private.signup_state(old.status, old.waitlisted_at) end;
  v_new := case when tg_op = 'DELETE' then 'none' else private.signup_state(new.status, new.waitlisted_at) end;
  if v_old = v_new then
    return null;
  end if;

  v_alive := exists (select 1 from public.club_members m where m.id = v_member);
  v_late := v_old = 'yes' and v_new not in ('yes', 'waitlist')
            and v_e.withdraw_deadline is not null and now() > v_e.withdraw_deadline;
  v_note := case
    when v_late then 'late'
    when v_uid is null then 'system'
    when not public.owns_member(v_member) then 'organizer'
    when coalesce(current_setting('dd18.signup_rpc', true), '') <> 'on' then 'direct'
  end;
  insert into public.signup_log (event_id, club_id, member_id, old_status, new_status, changed_by, note)
  values (v_e.id, v_e.club_id, case when v_alive then v_member end, v_old, v_new, v_uid, v_note);

  if v_old = 'yes' and v_new in ('no', 'none') and v_alive then
    perform private.evening_activity(v_e.club_id, v_e.id, 'signup_dropped',
      jsonb_build_object('member', v_member, 'event_date', to_char(v_e.event_date, 'YYYY-MM-DD'),
                         'late', v_late),
      private.club_members_with_right(v_e.club_id, 'tournaments'));
  end if;
  if v_old = 'yes' and v_new <> 'yes' then
    perform private.evening_fill(v_e.id);
  end if;
  return null;
end;
$$;
revoke all on function private.signups_rules_after() from public, anon, authenticated;

drop trigger if exists signups_rules_before on public.signups;
create trigger signups_rules_before
  before insert or update or delete on public.signups
  for each row execute function private.signups_rules_before();

drop trigger if exists signups_rules_after on public.signups;
create trigger signups_rules_after
  after insert or update or delete on public.signups
  for each row execute function private.signups_rules_after();

-- Høyere eller fjernet tak: opprykk med en gang.
create or replace function private.events_capacity_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.evening_fill(new.id);
  return null;
end;
$$;
revoke all on function private.events_capacity_changed() from public, anon, authenticated;

drop trigger if exists events_capacity_changed on public.events;
create trigger events_capacity_changed
  after update of max_players on public.events
  for each row when (new.max_players is distinct from old.max_players)
  execute function private.events_capacity_changed();

-- En bekreftet gjest som forsvinner (RPC, kvelden eller medlemmet slettes): opprykk.
create or replace function private.event_guests_removed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.waitlisted_at is null and not private.signup_syncing() then
    perform private.evening_fill(old.event_id);
  end if;
  return null;
end;
$$;
revoke all on function private.event_guests_removed() from public, anon, authenticated;

drop trigger if exists event_guests_removed on public.event_guests;
create trigger event_guests_removed
  after delete on public.event_guests
  for each row execute function private.event_guests_removed();


-- ===========================================================================
-- 6. ACTIVITY: SERVERENS MOTTAKERLISTER (fra 008, én ny linje)
-- ===========================================================================
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
  -- 045: laget av serveren (opprykk, avmelding): aktøren og mottakerne er satt av funksjonen.
  if coalesce(current_setting('dd18.server_activity', true), '') = 'on' then
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


-- ===========================================================================
-- 7. RPC-ER
-- ===========================================================================
-- Svar på en kveld. p_status: yes | maybe | no, eller null = fjern svaret («ikke
-- svart»). p_comment: null = behold kommentaren, '' = tøm den. p_member_id: null =
-- deg selv; et annet medlem krever rettigheten tournaments (som også går forbi
-- fristene og logges). Svarer med raden etterpå: status, waitlisted, place, late,
-- confirmed, waitlist, max_players og fristene.
create or replace function public.evening_signup(p_event_id uuid, p_status text, p_comment text default null,
                                                 p_member_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_e        public.events;
  v_member   uuid;
  v_comment  text := nullif(btrim(p_comment), '');
  v_prev     text;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_e from public.events where id = p_event_id for update;
  if v_e.id is null or not public.is_club_member(v_e.club_id) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if p_status is not null and p_status not in ('yes', 'maybe', 'no') then
    raise exception 'Ugyldig svar: %', p_status using errcode = '22023';
  end if;
  if char_length(v_comment) > 80 then
    raise exception 'Kommentaren kan være høyst 80 tegn' using errcode = '22023';
  end if;

  if p_member_id is null then
    v_member := public.my_member_id(v_e.club_id);
  else
    if not exists (select 1 from public.club_members m where m.id = p_member_id and m.club_id = v_e.club_id) then
      raise exception 'Fant ikke medlemmet' using errcode = 'P0002';
    end if;
    if not public.owns_member(p_member_id) and not private.has_club_right(v_e.club_id, 'tournaments') then
      raise exception 'Bare arrangøren kan endre svaret til andre' using errcode = '42501';
    end if;
    v_member := p_member_id;
  end if;
  if v_member is null then
    raise exception 'Du er ikke aktiv i klubben' using errcode = '42501';
  end if;

  v_prev := current_setting('dd18.signup_rpc', true);
  perform set_config('dd18.signup_rpc', 'on', true);
  if p_status is null then
    delete from public.signups where event_id = v_e.id and member_id = v_member;
  else
    insert into public.signups as s (event_id, member_id, club_id, status, comment)
    values (v_e.id, v_member, v_e.club_id, p_status, v_comment)
    on conflict (event_id, member_id) do update
      set status = excluded.status,
          comment = case when p_comment is null then s.comment else excluded.comment end;
  end if;
  perform set_config('dd18.signup_rpc', coalesce(v_prev, ''), true);

  if public.owns_member(v_member) then
    insert into public.event_views (event_id, member_id, club_id)
    values (v_e.id, v_member, v_e.club_id)
    on conflict do nothing;
  end if;
  return private.evening_signup_state(v_e.id, v_member);
end;
$$;
revoke all on function public.evening_signup(uuid, text, text, uuid) from public, anon;
grant execute on function public.evening_signup(uuid, text, text, uuid) to authenticated;

-- «Sett»: første gang medlemmet så kvelden. Gir tidspunktet.
create or replace function public.evening_mark_seen(p_event_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club    uuid;
  v_member  uuid;
  v_seen    timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select e.club_id into v_club from public.events e where e.id = p_event_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  v_member := public.my_member_id(v_club);
  insert into public.event_views (event_id, member_id, club_id)
  values (p_event_id, v_member, v_club)
  on conflict do nothing;
  select v.seen_at into v_seen from public.event_views v
   where v.event_id = p_event_id and v.member_id = v_member;
  return v_seen;
end;
$$;
revoke all on function public.evening_mark_seen(uuid) from public, anon;
grant execute on function public.evening_mark_seen(uuid) to authenticated;

-- Gjest på kvelden (events.allow_guests). p_invited_by: null = deg selv; et annet
-- medlem krever tournaments. Høyst 3 gjester per medlem og kveld (arrangøren: 50 per
-- kveld). Påmeldingsfristen gjelder (ikke for arrangøren). Full kveld: ventelista.
create or replace function public.evening_guest_add(p_event_id uuid, p_name text, p_invited_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_e        public.events;
  v_org      boolean;
  v_inviter  uuid;
  v_name     text := btrim(coalesce(p_name, ''));
  v_wait     timestamptz;
  v_id       uuid;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_e from public.events where id = p_event_id for update;
  if v_e.id is null or not public.is_club_member(v_e.club_id) then
    raise exception 'Fant ikke kvelden' using errcode = 'P0002';
  end if;
  if not v_e.allow_guests then
    raise exception 'Gjester er ikke slått på for denne kvelden' using errcode = '55000';
  end if;
  v_org := private.has_club_right(v_e.club_id, 'tournaments');
  if p_invited_by is null then
    v_inviter := public.my_member_id(v_e.club_id);
  else
    if not exists (select 1 from public.club_members m where m.id = p_invited_by and m.club_id = v_e.club_id) then
      raise exception 'Fant ikke medlemmet' using errcode = 'P0002';
    end if;
    if not public.owns_member(p_invited_by) and not v_org then
      raise exception 'Bare arrangøren kan melde på gjester for andre' using errcode = '42501';
    end if;
    v_inviter := p_invited_by;
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Navnet på gjesten må være 1–60 tegn' using errcode = '22023';
  end if;
  if not v_org and v_e.signup_deadline is not null and now() > v_e.signup_deadline then
    raise exception 'Fristen er ute. Kontakt arrangøren.' using errcode = 'DDB02';
  end if;
  if not v_org and (select count(*) from public.event_guests g
                     where g.event_id = v_e.id and g.invited_by = v_inviter) >= 3 then
    raise exception 'Grensen er nådd: høyst 3 gjester per medlem' using errcode = '54000';
  end if;
  if (select count(*) from public.event_guests g where g.event_id = v_e.id) >= 50 then
    raise exception 'Grensen er nådd: høyst 50 gjester per kveld' using errcode = '54000';
  end if;
  if exists (select 1 from public.event_guests g where g.event_id = v_e.id and lower(btrim(g.name)) = lower(v_name)) then
    raise exception 'En gjest med det navnet er alt påmeldt' using errcode = '23505';
  end if;

  if v_e.max_players is not null and private.evening_confirmed(v_e.id) >= v_e.max_players then
    v_wait := clock_timestamp();
  end if;
  insert into public.event_guests (event_id, club_id, name, invited_by, waitlisted_at, created_by)
  values (v_e.id, v_e.club_id, v_name, v_inviter, v_wait, v_uid)
  returning id into v_id;
  insert into public.signup_log (event_id, club_id, member_id, guest_id, guest_name, old_status, new_status,
                                 changed_by, note)
  values (v_e.id, v_e.club_id, v_inviter, v_id, v_name, 'none',
          case when v_wait is null then 'yes' else 'waitlist' end, v_uid,
          case when not public.owns_member(v_inviter) then 'organizer' end);

  return jsonb_build_object(
    'guest_id', v_id, 'event_id', v_e.id, 'name', v_name, 'invited_by', v_inviter,
    'waitlisted', v_wait is not null,
    'place', (select w.place from private.evening_waitlist(v_e.id) w where w.kind = 'guest' and w.id = v_id),
    'confirmed', private.evening_confirmed(v_e.id),
    'max_players', v_e.max_players);
end;
$$;
revoke all on function public.evening_guest_add(uuid, text, uuid) from public, anon;
grant execute on function public.evening_guest_add(uuid, text, uuid) to authenticated;

-- Fjern en gjest: den som inviterte, eller arrangøren. Avmeldingsfristen gjelder for
-- en bekreftet gjest (ikke for arrangøren, som da merkes late i loggen). Plassen går
-- til den første på ventelista (trigger).
create or replace function public.evening_guest_remove(p_guest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_g     public.event_guests;
  v_e     public.events;
  v_org   boolean;
  v_late  boolean := false;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_g from public.event_guests where id = p_guest_id;
  if v_g.id is not null then
    select * into v_e from public.events where id = v_g.event_id for update;
    select * into v_g from public.event_guests where id = p_guest_id;
  end if;
  if v_g.id is null or not public.is_club_member(v_g.club_id) then
    raise exception 'Fant ikke gjesten' using errcode = 'P0002';
  end if;
  v_org := private.has_club_right(v_g.club_id, 'tournaments');
  if not public.owns_member(v_g.invited_by) and not v_org then
    raise exception 'Bare den som meldte på gjesten, eller arrangøren, kan fjerne den' using errcode = '42501';
  end if;
  if v_g.waitlisted_at is null and v_e.withdraw_deadline is not null and now() > v_e.withdraw_deadline then
    if not v_org then
      raise exception 'Fristen er ute. Kontakt arrangøren.' using errcode = 'DDB02';
    end if;
    v_late := true;
  end if;

  insert into public.signup_log (event_id, club_id, member_id, guest_id, guest_name, old_status, new_status,
                                 changed_by, note)
  values (v_g.event_id, v_g.club_id, v_g.invited_by, v_g.id, v_g.name,
          case when v_g.waitlisted_at is null then 'yes' else 'waitlist' end, 'none', v_uid,
          case when v_late then 'late' when not public.owns_member(v_g.invited_by) then 'organizer' end);
  delete from public.event_guests where id = v_g.id;

  return jsonb_build_object(
    'guest_id', v_g.id, 'event_id', v_g.event_id, 'removed', true, 'late', v_late,
    'confirmed', private.evening_confirmed(v_g.event_id),
    'waitlist', (select count(*)::integer from private.evening_waitlist(v_g.event_id)),
    'max_players', v_e.max_players);
end;
$$;
revoke all on function public.evening_guest_remove(uuid) from public, anon;
grant execute on function public.evening_guest_remove(uuid) to authenticated;


-- ===========================================================================
-- 8. SKRIVEPOLICYENE PÅ SIGNUPS
-- ===========================================================================
-- Alt nytt skriver med evening_signup. Gamle bygg skriver svaret sitt med upsert
-- (KveldModel.write: insert … on conflict (event_id, member_id) do update, med
-- event_id, member_id, club_id, status og comment). Den veien står, smalt: bare egen
-- rad, bare de fem kolonnene, og triggerne over gir samme regler som RPC-en.
-- Arrangørens direkte skriving for andre og all sletting er borte.
drop policy if exists signups_insert on public.signups;
drop policy if exists signups_update on public.signups;
drop policy if exists signups_delete on public.signups;

drop policy if exists signups_insert_old_builds on public.signups;
create policy signups_insert_old_builds on public.signups
  for insert to authenticated
  with check (public.owns_member(member_id));
drop policy if exists signups_update_old_builds on public.signups;
create policy signups_update_old_builds on public.signups
  for update to authenticated
  using (public.owns_member(member_id))
  with check (public.owns_member(member_id));

revoke insert, update, delete on table public.signups from authenticated;
grant insert (event_id, member_id, club_id, status, comment) on table public.signups to authenticated;
grant update (event_id, member_id, club_id, status, comment) on table public.signups to authenticated;


-- ===========================================================================
-- 9. PÅMINNELSEN: VENTELISTA KOMMER IKKE (fra 010)
-- ===========================================================================
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
         jsonb_strip_nulls(jsonb_build_object(
           'event_date', to_char(e.event_date, 'YYYY-MM-DD'),
           'coming', (select count(*) from public.signups s
                       where s.event_id = e.id and s.status = 'yes' and s.waitlisted_at is null)
                     + (select count(*) from public.event_guests g
                         where g.event_id = e.id and g.waitlisted_at is null),
           'unsure', (select count(*) from public.signups s where s.event_id = e.id and s.status = 'maybe'),
           'waitlist', nullif((select count(*) from public.signups s
                                where s.event_id = e.id and s.status = 'yes' and s.waitlisted_at is not null)
                              + (select count(*) from public.event_guests g
                                  where g.event_id = e.id and g.waitlisted_at is not null), 0))),
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


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail  text := '';
  v_n     integer;
begin
  -- 1. events har de fire kolonnene, tomme/av for alle kvelder som finnes fra før.
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'events'
        and column_name in ('max_players', 'signup_deadline', 'withdraw_deadline', 'allow_guests')) <> 4
     or not exists (select 1 from pg_constraint where conname = 'events_max_players_check') then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. signups har waitlisted_at og late, og ingen står på venteliste uten yes.
  if (select count(*) from information_schema.columns
      where table_schema = 'public' and table_name = 'signups'
        and column_name in ('waitlisted_at', 'late')) <> 2
     or not exists (select 1 from pg_constraint where conname = 'signups_waitlist_only_yes') then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. De nye tabellene har RLS, bare lesepolicyer, og anon får ingenting.
  if exists (select 1 from pg_class where oid in ('public.event_guests'::regclass, 'public.event_views'::regclass,
                                                   'public.signup_log'::regclass) and not relrowsecurity)
     or exists (select 1 from pg_policies where schemaname = 'public'
                and tablename in ('event_guests', 'event_views', 'signup_log') and cmd <> 'SELECT')
     or has_table_privilege('anon', 'public.event_guests', 'select')
     or has_table_privilege('anon', 'public.signup_log', 'select')
     or has_table_privilege('authenticated', 'public.event_guests', 'insert')
     or has_table_privilege('authenticated', 'public.signup_log', 'insert')
     or has_table_privilege('authenticated', 'public.event_views', 'insert') then
    v_fail := v_fail || ' 3';
  end if;
  -- 4. signups: ingen sletting, ingen arrangørgren, og triggerkolonnene kan ikke skrives.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'signups'
             and (cmd = 'DELETE' or policyname in ('signups_insert', 'signups_update', 'signups_delete')
                  or coalesce(qual, '') || coalesce(with_check, '') like '%has_club_right%'))
     or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'signups'
         and policyname in ('signups_insert_old_builds', 'signups_update_old_builds')) <> 2
     or has_table_privilege('authenticated', 'public.signups', 'delete')
     or has_column_privilege('authenticated', 'public.signups', 'waitlisted_at', 'update')
     or has_column_privilege('authenticated', 'public.signups', 'late', 'insert')
     or not has_column_privilege('authenticated', 'public.signups', 'status', 'update') then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Triggerne.
  if (select count(*) from pg_trigger where not tgisinternal and tgname in
        ('signups_rules_before', 'signups_rules_after', 'events_capacity_changed', 'event_guests_removed')) <> 4 then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. RPC-ene: authenticated kan, anon kan ikke. Hjelperne kan ingen av dem kalle.
  if has_function_privilege('anon', 'public.evening_signup(uuid, text, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.evening_mark_seen(uuid)', 'execute')
     or has_function_privilege('anon', 'public.evening_guest_add(uuid, text, uuid)', 'execute')
     or has_function_privilege('anon', 'public.evening_guest_remove(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.evening_signup(uuid, text, text, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.evening_mark_seen(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.evening_guest_add(uuid, text, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.evening_guest_remove(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.evening_fill(uuid)', 'execute')
     or has_function_privilege('authenticated', 'private.evening_activity(uuid, uuid, text, jsonb, uuid[])', 'execute') then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Alle nye funksjoner er security definer med tom search_path (unntatt de rene hjelperne).
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where (n.nspname, p.proname) in (('public', 'evening_signup'), ('public', 'evening_mark_seen'),
                                               ('public', 'evening_guest_add'), ('public', 'evening_guest_remove'),
                                               ('private', 'evening_fill'), ('private', 'evening_confirmed'),
                                               ('private', 'evening_activity'), ('private', 'signups_rules_before'),
                                               ('private', 'signups_rules_after'))
               and (not p.prosecdef or not ('search_path=""' = any (p.proconfig)))) then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Dataene er som før: ingen på venteliste, ingen sen, ingen tak, frist eller gjester.
  if exists (select 1 from public.signups where waitlisted_at is not null or late)
     or exists (select 1 from public.events where max_players is not null or signup_deadline is not null
                or withdraw_deadline is not null or allow_guests)
     or exists (select 1 from public.event_guests) then
    -- Bare ved første kjøring. Kjøres fila igjen etter at arrangører har tatt det i
    -- bruk, er dette ikke en feil: invarianten i 9 sjekkes uansett.
    if not exists (select 1 from public.signup_log) then
      v_fail := v_fail || ' 8';
    end if;
  end if;
  -- 9. Invarianten: ingen venter mens det er ledig plass, og taket er ikke passert av nye.
  if exists (select 1 from public.events e
             where exists (select 1 from private.evening_waitlist(e.id))
               and (e.max_players is null or private.evening_confirmed(e.id) < e.max_players)) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Påminnelsen og aktivitetsvakten er byttet.
  if (select prosrc from pg_proc where oid = 'public.queue_evening_reminders(integer)'::regprocedure)
       not like '%waitlisted_at is null%'
     or (select prosrc from pg_proc where oid = 'public.activity_before_insert()'::regprocedure)
       not like '%dd18.server_activity%' then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '045 kontroll feilet:%', v_fail;
  end if;
  select count(*) into v_n from public.signups;
  raise notice '045 kontroll: 10 av 10 (svar: %, kvelder med tak: %)',
    v_n, (select count(*) from public.events where max_players is not null);
end $$;

commit;

-- ===========================================================================
-- NÅR GAMLE BYGG ER BORTE (min_ios_build er bygget med evening_signup)
-- ===========================================================================
-- drop policy if exists signups_insert_old_builds on public.signups;
-- drop policy if exists signups_update_old_builds on public.signups;
-- revoke insert, update on table public.signups from authenticated;

-- ===========================================================================
-- RULLEBAKKE (før appen bruker tak, gjester eller frister)
-- ===========================================================================
-- begin;
-- drop function if exists public.evening_signup(uuid, text, text, uuid);
-- drop function if exists public.evening_mark_seen(uuid);
-- drop function if exists public.evening_guest_add(uuid, text, uuid);
-- drop function if exists public.evening_guest_remove(uuid);
-- drop trigger if exists signups_rules_before on public.signups;
-- drop trigger if exists signups_rules_after on public.signups;
-- drop trigger if exists events_capacity_changed on public.events;
-- drop trigger if exists event_guests_removed on public.event_guests;
-- drop function if exists private.signups_rules_before();
-- drop function if exists private.signups_rules_after();
-- drop function if exists private.events_capacity_changed();
-- drop function if exists private.event_guests_removed();
-- drop function if exists private.evening_signup_state(uuid, uuid);
-- drop function if exists private.evening_fill(uuid);
-- drop function if exists private.evening_activity(uuid, uuid, text, jsonb, uuid[]);
-- drop function if exists private.club_members_with_right(uuid, text);
-- drop function if exists private.evening_waitlist(uuid);
-- drop function if exists private.evening_confirmed(uuid, uuid);
-- drop function if exists private.signup_state(text, timestamptz);
-- drop function if exists private.signup_syncing();
-- -- Skrivepolicyene som i 044:
-- drop policy if exists signups_insert_old_builds on public.signups;
-- drop policy if exists signups_update_old_builds on public.signups;
-- grant insert, update, delete on table public.signups to authenticated;
-- create policy signups_insert on public.signups for insert to authenticated
--   with check ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));
-- create policy signups_update on public.signups for update to authenticated
--   using ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')))
--   with check ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));
-- create policy signups_delete on public.signups for delete to authenticated
--   using ((public.owns_member(member_id) OR private.has_club_right(club_id, 'tournaments')));
-- -- Påminnelsen som i 010 (045-utgaven leser event_guests). activity_before_insert kan stå
-- -- (den nye linja gjør ingenting uten funksjonene over), eller kjøres fra 008.
-- create or replace function public.queue_evening_reminders(p_days_before integer default 7)
-- returns integer language plpgsql security definer set search_path = '' as $$
-- declare v_count integer;
-- begin
--   if p_days_before is null or p_days_before not between 0 and 60 then
--     raise exception 'Antall dager må være 0–60' using errcode = '22023';
--   end if;
--   insert into public.activity (club_id, kind, category, data, event_id)
--   select e.club_id, 'reminder', 'reminder',
--          jsonb_build_object('event_date', to_char(e.event_date, 'YYYY-MM-DD'),
--            'coming', (select count(*) from public.signups s where s.event_id = e.id and s.status = 'yes'),
--            'unsure', (select count(*) from public.signups s where s.event_id = e.id and s.status = 'maybe')),
--          e.id
--   from public.events e
--   where e.event_date = (now() at time zone 'Europe/Oslo')::date + p_days_before
--   on conflict (event_id) where kind = 'reminder' and actor_member_id is null and event_id is not null
--   do nothing;
--   get diagnostics v_count = row_count;
--   return v_count;
-- end;
-- $$;
-- revoke all on function public.queue_evening_reminders(integer) from public, anon, authenticated;
-- grant execute on function public.queue_evening_reminders(integer) to service_role;
-- drop table if exists public.signup_log;
-- drop table if exists public.event_views;
-- drop table if exists public.event_guests;
-- alter table public.signups drop constraint if exists signups_waitlist_only_yes;
-- drop index if exists public.signups_waitlist_idx;
-- alter table public.signups drop column if exists waitlisted_at, drop column if exists late;
-- alter table public.events drop constraint if exists events_max_players_check;
-- alter table public.events drop column if exists max_players, drop column if exists signup_deadline,
--   drop column if exists withdraw_deadline, drop column if exists allow_guests;
-- commit;
