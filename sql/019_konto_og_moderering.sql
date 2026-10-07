-- ===========================================================================
-- 019 – KONTO OG MODERERING (FASE 17) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt mot Supabase, verken
-- test eller prod. Prøvd lokalt (lokal/019_prove.sql). Krever 001–018.
-- Uavhengig av 020 og 021 (kan kjøres før eller etter dem).
--
-- Hvorfor (docs/visjon-apen-app.md fase 17, docs/datamodell-v2.md «Apples krav»
-- og «Felles banebibliotek»): når alle kan registrere seg, krever App Store
--   * 5.1.1(v): sletting av konto i appen,
--   * 1.2 (brukerinnhold): rapportere innhold, blokkere brukere, vilkår med
--     «ingen toleranse», og at noen følger opp rapportene (innen 24 timer).
-- I tillegg kommer banerettelser som overlever en ny henting av banen.
--
-- Hva fila gjør:
--   1. course_corrections: din eller klubbens rettelse av en bane i det
--      felles biblioteket (par, indeks og lengde per hull, CR og slope for
--      banen). Hentingen rører aldri tabellen, så rettelsene står. Appen
--      legger rettelsen oppå grunnlaget: din, så klubbens, så kilden.
--   2. user_blocks: blokkering mellom profiler. Den som blokkerer, ser ikke
--      lenger trådmeldinger og reaksjoner fra den blokkerte, og ingen av dem
--      kan legge den andre til i runder eller konkurranser (can_see_profile får
--      et «ikke blokkert»-ledd). Den blokkerte får ikke vite det.
--   3. content_reports: rapporter om en melding, et bilde, en profil eller et
--      navn i troppen. Skrives bare via report_content(). Den som rapporterer,
--      leser sine egne. Arrangøren leser klubbens og avgjør dem med
--      resolve_report() (fjern innholdet eller avvis). Vi (service_role) ser
--      alle i Supabase.
--   4. profiles.terms_accepted_at/terms_version: vilkårene er godtatt
--      (accept_terms()).
--   5. Sletting av konto (kalles bare av Edge Function delete-account med
--      service_role, aldri fra appen):
--        account_storage_objects(bruker)  filene som skal slettes (portretter
--                                         og trådbilder), FØR anonymiseringen
--        delete_account_data(bruker)      anonymiserer: navnet blir «Slettet
--                                         spiller» i troppen og i løse runder,
--                                         scorene står, trådmeldinger,
--                                         reaksjoner, push og blokkeringer
--                                         slettes. Klubbens siste arrangør
--                                         erstattes av det eldste aktive
--                                         medlemmet med innlogging.
--      Etterpå sletter funksjonen auth-brukeren (auth.admin.deleteUser), og
--      profilen følger med (on delete cascade fra 017).
--
-- Ingen endring i hole_scores, rounds, save_hole eller føringen. Policyene på
-- thread_messages og activity_reactions byttes ut med de samme uttrykkene som
-- i 008, pluss «ikke blokkert». can_see_profile byttes ut med samme kropp som i
-- 017, pluss «ikke blokkert».
--
-- Mønsteret fra 001–018 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, og
-- triggerfunksjoner tas fra authenticated også. Funksjonene bare serveren
-- skal bruke, tas også fra authenticated og gis til service_role.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. BANERETTELSER SOM OVERLEVER EN NY HENTING
-- ===========================================================================
create table if not exists public.course_corrections (
  id              uuid primary key default gen_random_uuid(),
  course_id       uuid not null references public.courses(id) on delete cascade,
  -- Hvem rettelsen gjelder for: en klubb (arrangøren retter) eller en profil.
  club_id         uuid references public.clubs(id) on delete cascade,
  profile_id      uuid references public.profiles(id) on delete cascade,
  -- Tom = banen (CR og slope). 1–18 = ett hull (par, indeks, lengde).
  hole_number     smallint check (hole_number between 1 and 18),
  par             smallint check (par between 3 and 6),
  stroke_index    smallint check (stroke_index between 1 and 18),
  length_m        smallint check (length_m between 50 and 700),
  course_rating   numeric(4,1) check (course_rating between 20 and 90),
  slope_rating    smallint check (slope_rating between 55 and 155),
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint course_corrections_one_owner check (num_nonnulls(club_id, profile_id) = 1),
  constraint course_corrections_shape check (
    case when hole_number is null
         then par is null and stroke_index is null and length_m is null
              and (course_rating is not null or slope_rating is not null)
         else course_rating is null and slope_rating is null
              and (par is not null or stroke_index is not null or length_m is not null)
    end)
);
comment on table public.course_corrections is
  'Rettelser av en bane i det felles biblioteket, per klubb eller profil. En ny henting av banen '
  'rører aldri denne tabellen. Appen legger rettelsen oppå: din, så klubbens, så kilden.';
create unique index if not exists course_corrections_one_per_owner
  on public.course_corrections (course_id, coalesce(club_id, profile_id), coalesce(hole_number, 0));
create index if not exists course_corrections_profile_idx
  on public.course_corrections (profile_id) where profile_id is not null;
create index if not exists course_corrections_club_idx
  on public.course_corrections (club_id) where club_id is not null;

drop trigger if exists course_corrections_set_updated_at on public.course_corrections;
create trigger course_corrections_set_updated_at before update on public.course_corrections
  for each row execute function public.set_updated_at();

-- Vakt: bare baner i det felles biblioteket rettes slik (klubbens egne baner
-- endres direkte av arrangøren). Hvem som skrev, settes av serveren, og en
-- rettelse flyttes ikke til en annen bane, klubb eller profil.
create or replace function public.course_corrections_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and (new.course_id is distinct from old.course_id or new.club_id is distinct from old.club_id
          or new.profile_id is distinct from old.profile_id or new.hole_number is distinct from old.hole_number) then
    raise exception 'En rettelse kan ikke flyttes' using errcode = '42501';
  end if;
  if not exists (select 1 from public.courses c where c.id = new.course_id and c.club_id is null) then
    raise exception 'Bare baner i det felles biblioteket rettes slik' using errcode = '22023';
  end if;
  new.created_by := auth.uid();
  return new;
end;
$$;
revoke all on function public.course_corrections_before_write() from public, anon, authenticated;

drop trigger if exists course_corrections_before_write on public.course_corrections;
create trigger course_corrections_before_write
  before insert or update on public.course_corrections
  for each row execute function public.course_corrections_before_write();


-- ===========================================================================
-- 2. BLOKKERING
-- ===========================================================================
create table if not exists public.user_blocks (
  blocker_id  uuid not null references public.profiles(id) on delete cascade,
  blocked_id  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_not_self check (blocker_id <> blocked_id)
);
comment on table public.user_blocks is
  'Blokkering (App Store 1.2). Den som blokkerer, ser ikke trådmeldinger og reaksjoner fra den '
  'blokkerte, og ingen av dem kan legge den andre til i runder eller konkurranser.';
create index if not exists user_blocks_blocked_idx on public.user_blocks (blocked_id);

-- Har jeg blokkert innloggingen? (For å skjule innhold fra den.)
create or replace function public.i_blocked(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_user_id is not null and exists (
    select 1 from public.user_blocks b where b.blocker_id = auth.uid() and b.blocked_id = p_user_id);
$$;
revoke all on function public.i_blocked(uuid) from public, anon;
grant execute on function public.i_blocked(uuid) to authenticated;

-- Har jeg blokkert den som eier klubbmedlemskapet?
create or replace function public.i_blocked_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.club_members m
    join public.user_blocks b on b.blocked_id = m.user_id and b.blocker_id = auth.uid()
    where m.id = p_member_id);
$$;
revoke all on function public.i_blocked_member(uuid) from public, anon;
grant execute on function public.i_blocked_member(uuid) to authenticated;

-- Er det en blokkering mellom meg og profilen, i en av retningene?
create or replace function public.blocked_between(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_id = auth.uid() and b.blocked_id = p_profile_id)
       or (b.blocker_id = p_profile_id and b.blocked_id = auth.uid()));
$$;
revoke all on function public.blocked_between(uuid) from public, anon;
grant execute on function public.blocked_between(uuid) to authenticated;

-- Samme kropp som i 017, pluss: ingen blokkering mellom oss. Deg selv ser du
-- alltid. Guardene i 017 (deltakere og påmeldte) kaller denne, så en blokkert
-- kan ikke legge deg til i en runde eller konkurranse, og omvendt.
create or replace function public.can_see_profile(p_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
       p_profile_id = auth.uid()
    or (not public.blocked_between(p_profile_id) and (
          exists (select 1 from public.club_members a
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
                         or (c.owner_id = p_profile_id and b.profile_id = auth.uid())))))
  );
$$;
revoke all on function public.can_see_profile(uuid) from public, anon;
grant execute on function public.can_see_profile(uuid) to authenticated;

-- Blokker: bare folk du allerede ser (en felles klubb, runde eller
-- konkurranse), så tabellen ikke kan brukes til å lete etter profil-id-er.
-- Idempotent. Kan også kalles med et klubbmedlem (tråden kjenner medlemmet).
create or replace function public.block_user(p_profile_id uuid default null, p_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_target  uuid := p_profile_id;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if num_nonnulls(p_profile_id, p_member_id) <> 1 then
    raise exception 'Oppgi enten profil eller medlem' using errcode = '22023';
  end if;
  if p_member_id is not null then
    select m.user_id into v_target from public.club_members m
     where m.id = p_member_id and public.is_club_member(m.club_id);
    if v_target is null then
      raise exception 'Fant ingen innlogging bak navnet' using errcode = 'P0002';
    end if;
  end if;
  if v_target = v_uid then
    raise exception 'Du kan ikke blokkere deg selv' using errcode = '22023';
  end if;
  if not exists (select 1 from public.user_blocks b where b.blocker_id = v_uid and b.blocked_id = v_target)
     and not public.can_see_profile(v_target) then
    raise exception 'Fant ikke personen' using errcode = 'P0002';
  end if;
  insert into public.user_blocks (blocker_id, blocked_id) values (v_uid, v_target)
  on conflict do nothing;
  return v_target;
end;
$$;
revoke all on function public.block_user(uuid, uuid) from public, anon;
grant execute on function public.block_user(uuid, uuid) to authenticated;

-- Mine blokkeringer med navn (profilen kan være skjult for meg nå, fordi
-- blokkeringen stopper can_see_profile).
create or replace function public.my_blocks()
returns table (blocked_id uuid, display_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select b.blocked_id,
         coalesce(p.display_name,
                  (select m.display_name from public.club_members m
                    where m.user_id = b.blocked_id order by m.created_at limit 1),
                  'Ukjent'),
         b.created_at
  from public.user_blocks b
  left join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;
revoke all on function public.my_blocks() from public, anon;
grant execute on function public.my_blocks() to authenticated;


-- ===========================================================================
-- 3. RAPPORTER
-- ===========================================================================
create table if not exists public.content_reports (
  id                 uuid primary key default gen_random_uuid(),
  reporter_id        uuid references public.profiles(id) on delete set null,
  -- message = tekst i kveldens tråd, image = bildet i en trådmelding,
  -- member = navn/portrett i troppen, profile = en profil (løse runder).
  kind               text not null check (kind in ('message', 'image', 'member', 'profile')),
  target_id          uuid not null,
  -- Settes av serveren: klubben (arrangøren modererer) og hvem innholdet er fra.
  club_id            uuid references public.clubs(id) on delete cascade,
  target_profile_id  uuid references public.profiles(id) on delete set null,
  reason             text not null check (reason in ('offensive', 'harassment', 'spam', 'inappropriate_image',
                                                      'impersonation', 'other')),
  note               text check (note is null or char_length(note) <= 500),
  -- Kopi av innholdet da det ble rapportert (teksten eller bildestien), så
  -- rapporten kan vurderes selv om meldingen er slettet.
  snapshot           text check (snapshot is null or char_length(snapshot) <= 600),
  status             text not null default 'open' check (status in ('open', 'removed', 'dismissed')),
  handled_by         uuid references public.profiles(id) on delete set null,
  handled_at         timestamptz,
  created_at         timestamptz not null default now()
);
comment on table public.content_reports is
  'Rapportert innhold (App Store 1.2). Skrives via report_content(). Den som rapporterer, leser sine; '
  'arrangøren leser og avgjør klubbens (resolve_report). Alle følges opp innen 24 timer.';
create unique index if not exists content_reports_one_open
  on public.content_reports (reporter_id, kind, target_id) where status = 'open';
create index if not exists content_reports_club_idx on public.content_reports (club_id, status);

-- Rapporter innhold. Du må kunne se det du rapporterer. Rapporterer du det
-- samme på nytt mens den forrige er åpen, oppdateres grunnen. Returnerer id.
create or replace function public.report_content(
  p_kind       text,
  p_target_id  uuid,
  p_reason     text,
  p_note       text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_club      uuid;
  v_author    uuid;
  v_snapshot  text;
  v_id        uuid;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('message', 'image', 'member', 'profile') then
    raise exception 'Ukjent type innhold' using errcode = '22023';
  end if;
  if p_reason is null or p_reason not in ('offensive', 'harassment', 'spam', 'inappropriate_image',
                                          'impersonation', 'other') then
    raise exception 'Ukjent grunn' using errcode = '22023';
  end if;
  if p_note is not null and char_length(p_note) > 500 then
    raise exception 'Kommentaren kan være høyst 500 tegn' using errcode = '22023';
  end if;

  if p_kind in ('message', 'image') then
    select t.club_id, m.user_id,
           case when p_kind = 'image' then t.image_path else left(t.body, 600) end
      into v_club, v_author, v_snapshot
    from public.thread_messages t
    join public.club_members m on m.id = t.member_id
    where t.id = p_target_id and public.is_club_member(t.club_id)
      and (p_kind = 'message' or t.image_path is not null);
  elsif p_kind = 'member' then
    select m.club_id, m.user_id, left(m.display_name, 600) into v_club, v_author, v_snapshot
    from public.club_members m
    where m.id = p_target_id and public.is_club_member(m.club_id);
  else
    select null, p.id, left(p.display_name, 600) into v_club, v_author, v_snapshot
    from public.profiles p
    where p.id = p_target_id and p.id <> v_uid and public.can_see_profile(p.id);
  end if;
  if not found then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;

  insert into public.content_reports (reporter_id, kind, target_id, club_id, target_profile_id,
                                      reason, note, snapshot)
  values (v_uid, p_kind, p_target_id, v_club, v_author, p_reason, nullif(btrim(p_note), ''), v_snapshot)
  on conflict (reporter_id, kind, target_id) where status = 'open'
  do update set reason = excluded.reason, note = excluded.note
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;

-- Arrangøren avgjør en rapport i klubben: 'remove' fjerner innholdet (en
-- trådmelding slettes; bildet må appen fjerne fra Storage, stien kommer
-- tilbake), 'dismiss' avviser. Et navn eller en profil fjernes ikke her:
-- arrangøren gir nytt navn eller arkiverer i troppen. Returnerer
-- {status, image_path}.
create or replace function public.resolve_report(p_report_id uuid, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_report  public.content_reports;
  v_image   text;
  v_status  text;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('remove', 'dismiss') then
    raise exception 'Handlingen må være remove eller dismiss' using errcode = '22023';
  end if;
  select * into v_report from public.content_reports r where r.id = p_report_id for update;
  if not found or v_report.club_id is null or not public.is_club_organizer(v_report.club_id) then
    raise exception 'Bare arrangøren i klubben kan avgjøre rapporten' using errcode = '42501';
  end if;
  if v_report.status <> 'open' then
    raise exception 'Rapporten er allerede avgjort' using errcode = '55000';
  end if;

  v_status := case p_action when 'remove' then 'removed' else 'dismissed' end;
  if p_action = 'remove' and v_report.kind in ('message', 'image') then
    delete from public.thread_messages t
     where t.id = v_report.target_id and t.club_id = v_report.club_id
    returning t.image_path into v_image;
  end if;

  -- Alle åpne rapporter om det samme innholdet avgjøres samtidig.
  update public.content_reports r
     set status = v_status, handled_by = v_uid, handled_at = now()
   where r.status = 'open' and r.target_id = v_report.target_id and r.club_id = v_report.club_id
     and (r.kind = v_report.kind or (r.kind in ('message', 'image') and v_report.kind in ('message', 'image')));

  return jsonb_build_object('status', v_status, 'image_path', v_image);
end;
$$;
revoke all on function public.resolve_report(uuid, text) from public, anon;
grant execute on function public.resolve_report(uuid, text) to authenticated;


-- ===========================================================================
-- 4. VILKÅR GODTATT
-- ===========================================================================
alter table public.profiles
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version text
    check (terms_version is null or terms_version ~ '^[0-9A-Za-z._-]{1,20}$');
comment on column public.profiles.terms_accepted_at is
  'Når vilkårene (docs/vilkar.md, «ingen toleranse for støtende innhold») ble godtatt. Settes av accept_terms().';

create or replace function public.accept_terms(p_version text)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_version is null or p_version !~ '^[0-9A-Za-z._-]{1,20}$' then
    raise exception 'Ugyldig versjon' using errcode = '22023';
  end if;
  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;
  update public.profiles set terms_accepted_at = now(), terms_version = p_version
   where id = auth.uid()
  returning terms_accepted_at into v_at;
  return v_at;
end;
$$;
revoke all on function public.accept_terms(text) from public, anon;
grant execute on function public.accept_terms(text) to authenticated;


-- ===========================================================================
-- 5. SLETTING AV KONTO (bare service_role, via Edge Function delete-account)
-- ===========================================================================
-- Filene som skal bort: portretter (avatars/<medlem>/… og avatars/<profil>/…)
-- og trådbilder (thread/<medlem>/…). Kalles FØR delete_account_data, fordi
-- medlemskapene kobles fra innloggingen der. Bare lesing.
create or replace function public.account_storage_objects(p_user_id uuid)
returns table (bucket_id text, name text)
language sql
stable
security definer
set search_path = ''
as $$
  with folders as (
    select m.id::text as folder from public.club_members m where m.user_id = p_user_id
    union
    select p_user_id::text
  )
  select o.bucket_id, o.name
  from storage.objects o
  where o.bucket_id in ('avatars', 'thread')
    and split_part(o.name, '/', 1) in (select folder from folders)
  order by o.bucket_id, o.name;
$$;
revoke all on function public.account_storage_objects(uuid) from public, anon, authenticated;
grant execute on function public.account_storage_objects(uuid) to service_role;

-- Anonymiserer kontoen i én transaksjon. Scorer, runder, matcher,
-- sidepremier, tips og veddemål står (andres tabeller endres ikke), men
-- navnet blir «Slettet spiller». Idempotent. Returnerer hva som ble gjort.
create or replace function public.delete_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_members   uuid[];
  v_messages  integer := 0;
  v_promoted  integer := 0;
  v_rounds    integer := 0;
  v_row       record;
begin
  if p_user_id is null then
    raise exception 'Mangler bruker' using errcode = '22023';
  end if;

  select coalesce(array_agg(m.id), '{}') into v_members
  from public.club_members m where m.user_id = p_user_id;

  -- Klubben skal ikke stå uten arrangør: er dette den siste, overtar det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.club_id from public.club_members m
    where m.user_id = p_user_id and m.is_organizer and m.status = 'active'
      and not exists (select 1 from public.club_members o
                      where o.club_id = m.club_id and o.id <> m.id and o.is_organizer
                        and o.status = 'active' and o.user_id is not null)
  loop
    update public.club_members o set is_organizer = true
     where o.id = (select n.id from public.club_members n
                   where n.club_id = v_row.club_id and n.status = 'active'
                     and n.user_id is not null and n.user_id <> p_user_id
                   order by n.created_at, n.id limit 1);
    if found then v_promoted := v_promoted + 1; end if;
  end loop;

  -- Innholdet personen har skrevet.
  delete from public.thread_messages t where t.member_id = any (v_members);
  get diagnostics v_messages = row_count;
  delete from public.activity_reactions r where r.member_id = any (v_members);
  delete from public.push_preferences p where p.member_id = any (v_members);
  delete from public.push_devices d where d.user_id = p_user_id;
  delete from public.user_blocks b where b.blocker_id = p_user_id or b.blocked_id = p_user_id;

  -- Troppen: navnet står som «Slettet spiller», arkivert (kan ikke tas av en
  -- annen innlogging), uten roller, portrett eller innlogging.
  update public.club_members m
     set display_name = 'Slettet spiller', avatar_path = null, is_organizer = false,
         is_treasurer = false, status = 'archived', user_id = null
   where m.id = any (v_members);

  -- Løse runder: deltakeren blir en gjest med navnet «Slettet spiller».
  update public.round_participants rp set display_name = 'Slettet spiller'
   where rp.profile_id = p_user_id;
  get diagnostics v_rounds = row_count;

  update public.profiles p
     set display_name = null, avatar_path = null, handicap_index = null
   where p.id = p_user_id;

  return jsonb_build_object('memberships', cardinality(v_members), 'messages', v_messages,
                            'loose_rounds', v_rounds, 'organizers_promoted', v_promoted);
end;
$$;
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;


-- ===========================================================================
-- 6. POLICYER: TRÅDEN SKJULER BLOKKERTE
-- ===========================================================================
-- Samme uttrykk som i 008, pluss «ikke blokkert av meg». Realtime følger
-- SELECT-policyene, så nye meldinger fra den blokkerte kommer heller ikke.
drop policy if exists thread_messages_select on public.thread_messages;
create policy thread_messages_select on public.thread_messages
  for select to authenticated
  using (public.is_club_member(club_id) and not public.i_blocked_member(member_id));

drop policy if exists activity_reactions_select on public.activity_reactions;
create policy activity_reactions_select on public.activity_reactions
  for select to authenticated
  using (public.is_club_member(club_id) and not public.i_blocked_member(member_id));


-- ===========================================================================
-- 7. RLS PÅ DE NYE TABELLENE
-- ===========================================================================
alter table public.course_corrections enable row level security;
alter table public.user_blocks        enable row level security;
alter table public.content_reports    enable row level security;

do $$
declare
  p record;
begin
  for p in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename in ('course_corrections', 'user_blocks', 'content_reports')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- course_corrections: dine egne, og klubbens for medlemmer. Skrive: dine
-- egne, eller klubbens som arrangør.
create policy course_corrections_select on public.course_corrections
  for select to authenticated
  using (profile_id = auth.uid() or (club_id is not null and public.is_club_member(club_id)));
create policy course_corrections_insert on public.course_corrections
  for insert to authenticated
  with check (profile_id = auth.uid() or (club_id is not null and public.is_club_organizer(club_id)));
create policy course_corrections_update on public.course_corrections
  for update to authenticated
  using (profile_id = auth.uid() or (club_id is not null and public.is_club_organizer(club_id)))
  with check (profile_id = auth.uid() or (club_id is not null and public.is_club_organizer(club_id)));
create policy course_corrections_delete on public.course_corrections
  for delete to authenticated
  using (profile_id = auth.uid() or (club_id is not null and public.is_club_organizer(club_id)));

-- user_blocks: bare dine egne. Ny blokkering via block_user(); oppheve er
-- vanlig delete.
create policy user_blocks_select on public.user_blocks
  for select to authenticated using (blocker_id = auth.uid());
create policy user_blocks_delete on public.user_blocks
  for delete to authenticated using (blocker_id = auth.uid());

-- content_reports: dine egne, og klubbens som arrangør. Skriving via RPC.
create policy content_reports_select on public.content_reports
  for select to authenticated
  using (reporter_id = auth.uid() or (club_id is not null and public.is_club_organizer(club_id)));


-- ===========================================================================
-- 8. RETTIGHETER
-- ===========================================================================
revoke all on table public.course_corrections from public, anon, authenticated;
revoke all on table public.user_blocks        from public, anon, authenticated;
revoke all on table public.content_reports    from public, anon, authenticated;
grant select, insert, update, delete on table public.course_corrections to authenticated;
grant select, delete                 on table public.user_blocks        to authenticated;
grant select                         on table public.content_reports    to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (select p.proname,
--                   has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--                   has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--                   has_function_privilege('service_role', p.oid, 'execute') as server_kan
--            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--            where n.nspname = 'public'
--              and p.proname in ('course_corrections_before_write', 'i_blocked', 'i_blocked_member',
--                                'blocked_between', 'can_see_profile', 'block_user', 'my_blocks',
--                                'report_content', 'resolve_report', 'accept_terms',
--                                'account_storage_objects', 'delete_account_data'))
-- select 1 as nr, 'tre nye tabeller med RLS' as sjekk,
--        (select count(*) = 3 from pg_class c
--          where c.oid in ('public.course_corrections'::regclass, 'public.user_blocks'::regclass,
--                          'public.content_reports'::regclass) and c.relrowsecurity) as ok
-- union all
-- select 2, 'policyer: 4 + 2 + 1',
--        (select count(*) from pg_policies where schemaname = 'public' and tablename = 'course_corrections') = 4
--        and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'user_blocks') = 2
--        and (select count(*) from pg_policies where schemaname = 'public' and tablename = 'content_reports') = 1
-- union all
-- select 3, 'anon har ingen rettigheter på de nye tabellene',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public'
--                      and table_name in ('course_corrections', 'user_blocks', 'content_reports')
--                      and grantee in ('anon', 'PUBLIC'))
-- union all
-- select 4, 'appen kan ikke skrive rapporter eller blokkeringer direkte',
--        not has_table_privilege('authenticated', 'public.content_reports', 'insert')
--        and not has_table_privilege('authenticated', 'public.content_reports', 'update')
--        and not has_table_privilege('authenticated', 'public.user_blocks', 'insert')
-- union all
-- select 5, 'anon kan ikke kjøre noen av de nye funksjonene', not exists (select 1 from f where anon_kan)
-- union all
-- select 6, 'kontoslettingen er bare for serveren',
--        (select bool_and(not auth_kan and server_kan) and count(*) = 2 from f
--          where proname in ('account_storage_objects', 'delete_account_data'))
-- union all
-- select 7, 'triggerfunksjonen kan ikke kalles av appen',
--        (select not auth_kan from f where proname = 'course_corrections_before_write')
-- union all
-- select 8, 'tråden har fortsatt tre policyer, med blokkering i lesingen',
--        (select count(*) = 3 from pg_policies where schemaname = 'public' and tablename = 'thread_messages')
--        and (select qual like '%i_blocked_member%' from pg_policies
--              where schemaname = 'public' and tablename = 'thread_messages' and policyname = 'thread_messages_select')
-- union all
-- select 9, 'profiles har vilkårskolonnene',
--        (select count(*) = 2 from information_schema.columns
--          where table_schema = 'public' and table_name = 'profiles'
--            and column_name in ('terms_accepted_at', 'terms_version'))
-- union all
-- select 10, 'ingen åpne rapporter eldre enn 24 timer (Apple)',
--        not exists (select 1 from public.content_reports
--                    where status = 'open' and created_at < now() - interval '24 hours')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner rettelser, blokkeringer og rapporter.
-- Slå av ModerationFeature og AccountDeletionFeature i appen først (de er av
-- fra start). can_see_profile og trådpolicyene settes tilbake til 017/008.
-- ===========================================================================
-- begin;
-- drop policy if exists thread_messages_select on public.thread_messages;
-- create policy thread_messages_select on public.thread_messages
--   for select to authenticated using (public.is_club_member(club_id));
-- drop policy if exists activity_reactions_select on public.activity_reactions;
-- create policy activity_reactions_select on public.activity_reactions
--   for select to authenticated using (public.is_club_member(club_id));
-- -- can_see_profile: kjør blokken «create or replace function public.can_see_profile» fra 017 på nytt.
-- drop function if exists public.delete_account_data(uuid);
-- drop function if exists public.account_storage_objects(uuid);
-- drop function if exists public.accept_terms(text);
-- alter table public.profiles drop column if exists terms_accepted_at, drop column if exists terms_version;
-- drop function if exists public.resolve_report(uuid, text);
-- drop function if exists public.report_content(text, uuid, text, text);
-- drop table if exists public.content_reports;
-- drop function if exists public.my_blocks();
-- drop function if exists public.block_user(uuid, uuid);
-- drop table if exists public.user_blocks;   -- etter at can_see_profile er satt tilbake
-- drop function if exists public.blocked_between(uuid);
-- drop function if exists public.i_blocked_member(uuid);
-- drop function if exists public.i_blocked(uuid);
-- drop table if exists public.course_corrections;
-- drop function if exists public.course_corrections_before_write();
-- commit;
