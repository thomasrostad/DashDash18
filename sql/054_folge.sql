-- 054: følge andre spillere (gjennomføringsplanen steg 13). Godkjent og kjørt på test 12.10.2026.
--
-- Krever 001–052 (kjøres på test etter dem; 052b er infrastruktur og spiller ingen rolle her).
-- Bygger på 017/019 (profiles, can_see_profile, user_blocks, block_user, content_reports),
-- 034 (hendelser uten klubb), 037 (known_profiles), 046 (push_queue, push_job_payload,
-- push_group_map) og 050 (reactions, comments, can_read_target, comment_add, delete_account_data).
-- Rører ikke veddemål (052).
--
-- Beslutningene (Thomas 12.10.2026, docs/folge.md):
--   Følge som Strava (den du følger trenger ikke følge tilbake). Nye følgere må godkjennes
--   som standard, kan slås av. Navnesøk (synlig som standard, kan skjules), QR-kode (å vise
--   koden er godkjenningen), «Følg X» etter en runde. Følging gir profil og runder dere har
--   spilt sammen, den du følger sine ferdige runder i en «Følger»-fane, reaksjoner og
--   kommentarer på dem, og invitasjoner til turneringer og runder.
--
-- Hva fila gjør:
--   1. follows (follower_id, followee_id, status pending|accepted, source search|qr|round|link|
--      suggestion, created_at, accepted_at), nøkkel (follower, followee), ikke deg selv.
--      Lesing: radene der du er en av de to. Skriving bare med RPC-ene.
--      profiles.follow_approval (standard true) og profiles.searchable (standard true), skrevet
--      med vanlig update av egen profil eller follow_settings. Slås godkjenning av, blir
--      ventende forespørsler godtatt (trigger, med varsel follow_accepted).
--      Følgekoden ligger IKKE på profiles (avvik fra skissen): profilraden leses av alle som
--      ser profilen (profiles_select, known_profiles gir p.*), og koden gir følging uten
--      godkjenning. Den ligger derfor i follow_codes (user_id, code, created_at) uten
--      policyer, som calendar_tokens i 051. 8 tegn fra 32 tegn uten I, O, 0 og 1 (40 bit).
--   2. RPC-er (security definer, norske feil, ikke anon):
--        follow_request(profil, kilde default 'search')  pending eller accepted etter
--              mottakerens follow_approval. Må kunne finne personen (searchable, eller
--              can_see_profile). Blokkert (begge veier) = «Fant ikke personen» (P0002).
--              Høyst 50 forespørsler i døgnet (54000). Finnes raden, svares statusen, uten nytt
--              varsel. Ny forespørsel til samme person innen et døgn gir ikke nytt varsel.
--        follow_respond(følger, godta)    godta (accepted + follow_accepted) eller avslå (raden
--              slettes, ingen varsel).
--        follow_remove(profil)            slutt å følge (eller trekk forespørselen).
--        follower_remove(profil)          fjern en følger (eller en forespørsel).
--        follow_code(fornye default false) din kode (lages når den mangler; true gir ny, den
--              gamle dør).
--        follow_by_code(kode, kilde default 'qr')  følger eieren med en gang (accepted, også
--              når eieren krever godkjenning), varsel followed. Svarer {profile_id, display_name,
--              avatar_path, status, already}; ukjent kode (eller blokkert) gir {status: not_found}
--              uten feil, så forsøket blir stående i loggen. Høyst 20 forsøk i timen.
--        follow_settings(godkjenning, søkbar)  null = uendret.
--        search_people(tekst, antall default 20)  minst 3 tegn (høyst 40), ILIKE på navnet,
--              bare søkbare profiler med navn, ikke deg, ingen blokkerte (begge veier). Svarer
--              id, navn, bilde, ÉN klubb (eldste aktive medlemskap; ikke antall, ikke de andre),
--              min følgestatus (none|pending|accepted) og om personen følger meg. Høyst 60 søk
--              i timen (54000), 1–50 treff.
--        my_follows()                    følger (mine, pending og accepted), følgere og
--              forespørsler til meg, med navn og bilde.
--        following_feed_page(før tid, før id, antall default 30)  «Følger»-fanen.
--   3. Synlighet:
--        can_see_profile og known_profiles: godtatt følging i begge retninger (følgeren ser
--        den hen følger, og den som blir fulgt ser følgerne sine; begge kan dermed legge den
--        andre til i runder og turneringer, som med felles klubb). Ventende forespørsler gir
--        ikke profilen; navnet og bildet står i my_follows, og block_user og
--        report_content('profile') godtar den som har sendt deg en forespørsel.
--        Runder: valget er en hendelse per spiller (round_finished) når runden låses, ikke
--        en ny target_kind 'round'. Hendelsen er en «personlig» linje i activity: uten klubb
--        og uten turnering, med activity.actor_profile_id (ny kolonne) = spilleren og
--        recipients null. Den ses av spilleren selv og av dem som følger spilleren (godtatt),
--        når runden er låst og ingen er blokkert. Dermed virker 050 uendret for reaksjoner,
--        kommentarer, «følg tråden», omtaler, varsler, rapport og opprydding: target_kind er
--        'activity', og reaksjonene og kommentarene lagres som profil (uten klubb). Med en ny
--        target_kind måtte reactions, comments, thread_follows, target_info, react,
--        comment_add, social_cleanup og rapportene alle få en tredje gren, og en reaksjon fra
--        en følger utenfor klubben passer ikke i klubbmodellen (member_id i klubben).
--        Kortet regnes ut når det leses (following_feed_page), ikke lagret: data har bare
--        player_id (round_players.member_id). Følgeren får ikke lese runden selv
--        (can_read_round er uendret), bare kortet.
--        En runde som låses opp igjen, forsvinner fra fanen (bare låste runder), og kommer
--        tilbake når den låses (én hendelse per runde og spiller). Slettes runden, slettes
--        hendelsene. Eksisterende låste runder fylles inn nå (følgere ser historikken).
--        Playoff gir ingen. Bare spillere med innlogging (klubbmedlem eller profil i løs runde).
--        Personlige linjer: activity_select, can_read_target og user_can_read_target har en
--        tredje gren (private.personal_activity_visible). activity_club_or_competition tillater
--        nå klubb, turnering ELLER actor_profile_id. activity_fill_competition hopper over
--        personlige linjer. Appen kan ikke sette actor_profile_id (activity_before_insert).
--        Den som eier kortet kan slette kommentarer på det (comment_delete).
--   4. Varsler (personlige linjer med mottakerliste = profil-id-er, kategori social, gruppen
--      Sosialt): follow_requested (til den som blir spurt), follow_accepted (til følgeren),
--      followed (til den som blir fulgt, når godkjenning er av eller via kode). data:
--      actor_name, source. Når følgingen forsvinner (avslag, fjerning, blokkering), slettes
--      varslene mellom de to. push_queue tar personlige jobber (uten klubb og turnering, med
--      hendelse); push_job_payload får audience 'person' (medlemmene er mottakerlisten,
--      profil-id-er, gruppene og kategoriene fra medlemskapene som for turneringer, ingen kveld
--      og ingen collapse) og activity.actor_profile_id når den er satt (ellers som før).
--      round_finished går ikke som push. push_group_map: alle 27 radene fra 050 (med
--      bill_share_*) pluss follow_requested, follow_accepted, followed (Sosialt) og
--      round_finished (Spillet) = 31.
--   5. Opprydding: blokkering (trigger på user_blocks, alle veier inn) sletter følging begge
--      veier, også ventende, og varslene mellom dem. delete_account_data sletter følgingen,
--      koden, søkeloggen, de personlige linjene der kontoen er aktør, tar kontoen ut av
--      mottakerlistene, og setter searchable av.
--   6. Søke- og forespørselsloggen: private.people_rate_log (user_id, kind search|follow|code,
--      target_id, created_at). Rader eldre enn to døgn slettes når samme bruker skriver.
--
-- Mønsteret fra 001–052: én transaksjon, idempotent, search_path = '', revoke etter hver
-- create or replace, kontroll og rullebakke nederst.
--
-- Merk: 050s kontroll 9 krever at en kommentar har klubb eller turnering. Kommentarer på et
-- kort i «Følger» har ingen av delene, så 050 kan ikke kjøres på nytt etter 054 når slike
-- finnes (kontrollen i 054 sjekker dem i stedet).
--
-- Appen må (ikke i denne fila): se docs/folge.md («Appen etter 054»).
-- push-send må: audience 'person' (id-ene er profil-id-er, blokkering fra user_blocks mot
--   activity.actor_profile_id, threadId 'person-<mottaker>' eller 'follow'), tekst for
--   follow_requested, follow_accepted og followed, og comment_added/mentioned uten klubb og
--   turnering («… kommenterte runden din»).

begin;


-- ===========================================================================
-- 1. TABELLER OG KOLONNER
-- ===========================================================================
alter table public.profiles
  add column if not exists follow_approval boolean not null default true,
  add column if not exists searchable boolean not null default true;
comment on column public.profiles.follow_approval is
  '054: nye følgere må godkjennes (standard). Av = åpen profil, følging med en gang.';
comment on column public.profiles.searchable is
  '054: synlig i navnesøket (search_people). Av = finnes bare via felles klubb, runde, QR-kode eller følging.';

create table if not exists public.follows (
  follower_id  uuid not null references public.profiles (id) on delete cascade,
  followee_id  uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  source       text not null default 'search'
               check (source in ('search', 'qr', 'round', 'link', 'suggestion')),
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  primary key (follower_id, followee_id),
  constraint follows_not_self check (follower_id <> followee_id),
  constraint follows_accepted_at check ((status = 'accepted') = (accepted_at is not null))
);
comment on table public.follows is
  '054: følging (som Strava). Lesing: de to. Skriving: follow_request, follow_respond, follow_remove, '
  'follower_remove, follow_by_code. Blokkering og sletting av konto fjerner radene.';
create index if not exists follows_followee_idx on public.follows (followee_id, status);

alter table public.follows enable row level security;
revoke all on table public.follows from public, anon, authenticated;
grant select on table public.follows to authenticated;
grant all on table public.follows to service_role;
drop policy if exists follows_select on public.follows;
create policy follows_select on public.follows
  for select to authenticated
  using (follower_id = (select auth.uid()) or followee_id = (select auth.uid()));

create table if not exists public.follow_codes (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  code        text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_at  timestamptz not null default now()
);
comment on table public.follow_codes is
  '054: QR-koden for følging (vises av eieren, gir følging med en gang). Ingen policyer: bare '
  'follow_code og follow_by_code.';
alter table public.follow_codes enable row level security;
revoke all on table public.follow_codes from public, anon, authenticated;
grant all on table public.follow_codes to service_role;

create table if not exists private.people_rate_log (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  kind        text not null check (kind in ('search', 'follow', 'code')),
  target_id   uuid,
  created_at  timestamptz not null default now()
);
create index if not exists people_rate_log_user_idx on private.people_rate_log (user_id, kind, created_at);
revoke all on table private.people_rate_log from public, anon, authenticated;

-- Personlige linjer i activity: uten klubb og turnering, med aktøren som profil.
alter table public.activity
  add column if not exists actor_profile_id uuid references public.profiles (id) on delete cascade;
comment on column public.activity.actor_profile_id is
  '054: aktøren som profil i personlige linjer (uten klubb og turnering): round_finished, '
  'follow_requested, follow_accepted, followed, og kommentarvarsler på «Følger»-kort.';
alter table public.activity drop constraint if exists activity_club_or_competition;
alter table public.activity add constraint activity_club_or_competition
  check (club_id is not null or competition_id is not null or actor_profile_id is not null);
create index if not exists activity_actor_profile_idx
  on public.activity (actor_profile_id, created_at desc, id desc) where actor_profile_id is not null;
create unique index if not exists activity_round_finished_once
  on public.activity (round_id, actor_profile_id) where kind = 'round_finished';

-- Personlige jobber i push-køen (uten klubb og turnering, men med hendelse).
alter table public.push_queue drop constraint if exists push_queue_club_or_competition;
alter table public.push_queue add constraint push_queue_club_or_competition
  check (club_id is not null or competition_id is not null or activity_id is not null);


-- ===========================================================================
-- 2. HJELPERE
-- ===========================================================================
-- Ser p_uid en personlig linje? Aktøren selv, en mottaker, eller (uten mottakerliste) en som
-- følger aktøren (godtatt). Ikke blokkert mot aktøren. Gjelder linjen en runde, må den være låst.
create or replace function private.personal_activity_visible(p_uid uuid, p_actor uuid,
                                                             p_recipients uuid[], p_round_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_uid is not null and p_actor is not null
     and (   p_uid = p_actor
          or (p_recipients is not null and p_uid = any (p_recipients))
          or (p_recipients is null and exists (
                select 1 from public.follows f
                 where f.follower_id = p_uid and f.followee_id = p_actor and f.status = 'accepted')))
     and not private.users_blocked(p_uid, p_actor)
     and (p_round_id is null
          or exists (select 1 from public.rounds r where r.id = p_round_id and r.status = 'locked'));
$$;
revoke all on function private.personal_activity_visible(uuid, uuid, uuid[], uuid) from public, anon, authenticated;
grant execute on function private.personal_activity_visible(uuid, uuid, uuid[], uuid) to authenticated;

-- Godtatt følging mellom to (begge veier).
create or replace function private.follow_accepted_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not null and p_b is not null and exists (
    select 1 from public.follows f
     where f.status = 'accepted'
       and ((f.follower_id = p_a and f.followee_id = p_b) or (f.follower_id = p_b and f.followee_id = p_a)));
$$;
revoke all on function private.follow_accepted_between(uuid, uuid) from public, anon, authenticated;

-- En følgerad (hvilken som helst status) mellom to, begge veier.
create or replace function private.follow_any_between(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_a is not null and p_b is not null and exists (
    select 1 from public.follows f
     where (f.follower_id = p_a and f.followee_id = p_b) or (f.follower_id = p_b and f.followee_id = p_a));
$$;
revoke all on function private.follow_any_between(uuid, uuid) from public, anon, authenticated;

-- Grense per bruker: teller og logger. Rydder egne rader eldre enn to døgn.
create or replace function private.people_rate_hit(p_kind text, p_target uuid, p_limit integer,
                                                   p_window interval, p_what text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  delete from private.people_rate_log l
   where l.user_id = auth.uid() and l.created_at < now() - interval '2 days';
  select count(*) into v_n from private.people_rate_log l
   where l.user_id = auth.uid() and l.kind = p_kind and l.created_at > now() - p_window;
  if v_n >= p_limit then
    raise exception 'Grensen er nådd: høyst % %. Prøv igjen senere.', p_limit, p_what using errcode = '54000';
  end if;
  insert into private.people_rate_log (user_id, kind, target_id) values (auth.uid(), p_kind, p_target);
end;
$$;
revoke all on function private.people_rate_hit(text, uuid, integer, interval, text) from public, anon, authenticated;

-- Et personlig varsel fra p_actor til p_to (follow_requested, follow_accepted, followed).
create or replace function private.follow_notify(p_kind text, p_actor uuid, p_to uuid, p_source text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := current_setting('dd18.server_activity', true);
begin
  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, competition_id, kind, category, data, actor_profile_id, recipients)
  select null, null, p_kind, 'social',
         jsonb_strip_nulls(jsonb_build_object('actor_name', p.display_name, 'source', p_source)),
         p_actor, array[p_to]
    from public.profiles p where p.id = p_actor;
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.follow_notify(text, uuid, uuid, text) from public, anon, authenticated;

-- Følgekoden: 8 tegn fra 32 (uten I, O, 0, 1), fra de tilfeldige bytene i gen_random_uuid.
create or replace function private.new_follow_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_abc   constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := uuid_send(gen_random_uuid());
  v_pos   int[] := array[0, 1, 2, 3, 4, 5, 10, 11];
  v_out   text := '';
  i       int;
begin
  foreach i in array v_pos loop
    v_out := v_out || substr(v_abc, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_out;
end;
$$;
revoke all on function private.new_follow_code() from public, anon, authenticated;


-- ===========================================================================
-- 3. SYNLIGHET: PROFILER
-- ===========================================================================
-- Fra 019. Nytt: godtatt følging i begge retninger.
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
                         or (c.owner_id = p_profile_id and b.profile_id = auth.uid())))
       -- 054: godtatt følging, begge veier.
       or exists (select 1 from public.follows f
                  where f.status = 'accepted'
                    and (   (f.follower_id = auth.uid() and f.followee_id = p_profile_id)
                         or (f.followee_id = auth.uid() and f.follower_id = p_profile_id)))))
  );
$$;
revoke all on function public.can_see_profile(uuid) from public, anon;
grant execute on function public.can_see_profile(uuid) to authenticated;

-- Fra 037. Nytt: godtatt følging, begge veier (folkevelgerne i «Ny runde» og turneringer).
create or replace function public.known_profiles()
returns setof public.profiles
language sql
stable
security definer
set search_path = ''
as $$
  with me as (select auth.uid() as id),
  candidates as (
    -- Felles klubb (du aktiv, den andre med hvilken som helst status).
    select b.user_id as id
      from public.club_members a join public.club_members b on b.club_id = a.club_id, me
     where a.user_id = me.id and a.status = 'active' and b.user_id is not null
    union
    -- Felles runde.
    select b.profile_id
      from public.round_participants a join public.round_participants b on b.round_id = a.round_id, me
     where a.profile_id = me.id and b.profile_id is not null
    union
    -- Løs runde du eier, eller som eieren har deg med i.
    select b.profile_id
      from public.rounds r join public.round_participants b on b.round_id = r.id, me
     where r.club_id is null and r.owner_id = me.id and b.profile_id is not null
    union
    select r.owner_id
      from public.rounds r join public.round_participants b on b.round_id = r.id, me
     where r.club_id is null and b.profile_id = me.id and r.owner_id is not null
    union
    -- Felles turnering (begge aktive).
    select b.profile_id
      from public.competition_participants a
      join public.competition_participants b on b.competition_id = a.competition_id, me
     where a.profile_id = me.id and b.profile_id is not null and a.status = 'active' and b.status = 'active'
    union
    -- Turnering uten klubb du eier, eller som eieren har deg med i.
    select b.profile_id
      from public.competitions c join public.competition_participants b on b.competition_id = c.id, me
     where c.club_id is null and b.status = 'active' and c.owner_id = me.id and b.profile_id is not null
    union
    select c.owner_id
      from public.competitions c join public.competition_participants b on b.competition_id = c.id, me
     where c.club_id is null and b.status = 'active' and b.profile_id = me.id and c.owner_id is not null
    union
    -- 054: godtatt følging, begge veier.
    select f.followee_id from public.follows f, me where f.follower_id = me.id and f.status = 'accepted'
    union
    select f.follower_id from public.follows f, me where f.followee_id = me.id and f.status = 'accepted'
  )
  select p.*
    from public.profiles p, me
   where me.id is not null
     and p.id in (select id from candidates)
     and p.id <> me.id
     and not public.blocked_between(p.id);
$$;
revoke all on function public.known_profiles() from public, anon;
grant execute on function public.known_profiles() to authenticated;


-- ===========================================================================
-- 4. FØLGE: RPC-ER
-- ===========================================================================
create or replace function public.follow_request(p_profile_id uuid, p_source text default 'search')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_target  public.profiles;
  v_status  text;
  v_source  text := coalesce(p_source, 'search');
  v_recent  boolean;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if v_source not in ('search', 'round', 'link', 'suggestion') then
    raise exception 'Ukjent kilde (QR-koden går via follow_by_code)' using errcode = '22023';
  end if;
  if p_profile_id is null or p_profile_id = v_uid then
    raise exception 'Du kan ikke følge deg selv' using errcode = '22023';
  end if;
  select * into v_target from public.profiles p where p.id = p_profile_id;
  if not found or v_target.display_name is null
     or private.users_blocked(v_uid, p_profile_id)
     or not (v_target.searchable or public.can_see_profile(p_profile_id)
             or exists (select 1 from public.follows f
                         where f.follower_id = p_profile_id and f.followee_id = v_uid)) then
    raise exception 'Fant ikke personen' using errcode = 'P0002';
  end if;

  select f.status into v_status from public.follows f
   where f.follower_id = v_uid and f.followee_id = p_profile_id;
  if found then
    return v_status;
  end if;

  select exists (select 1 from private.people_rate_log l
                  where l.user_id = v_uid and l.kind = 'follow' and l.target_id = p_profile_id
                    and l.created_at > now() - interval '1 day') into v_recent;
  perform private.people_rate_hit('follow', p_profile_id, 50, interval '1 day', 'forespørsler om å følge i døgnet');

  v_status := case when v_target.follow_approval then 'pending' else 'accepted' end;
  insert into public.follows (follower_id, followee_id, status, source, accepted_at)
  values (v_uid, p_profile_id, v_status, v_source, case when v_status = 'accepted' then now() end);

  if not v_recent then
    perform private.follow_notify(case when v_status = 'pending' then 'follow_requested' else 'followed' end,
                                  v_uid, p_profile_id, v_source);
  end if;
  return v_status;
end;
$$;
revoke all on function public.follow_request(uuid, text) from public, anon;
grant execute on function public.follow_request(uuid, text) to authenticated;

-- Svar på en forespørsel. true = godta, false = avslå (raden slettes). Svarer 'accepted'/'denied'.
create or replace function public.follow_respond(p_follower_id uuid, p_accept boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_row  public.follows;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_accept is null then
    raise exception 'Velg godta eller avslå' using errcode = '22023';
  end if;
  select * into v_row from public.follows f
   where f.follower_id = p_follower_id and f.followee_id = v_uid and f.status = 'pending'
   for update;
  if not found then
    raise exception 'Fant ingen forespørsel' using errcode = 'P0002';
  end if;
  if not p_accept then
    delete from public.follows f where f.follower_id = p_follower_id and f.followee_id = v_uid;
    return 'denied';
  end if;
  update public.follows f set status = 'accepted', accepted_at = now()
   where f.follower_id = p_follower_id and f.followee_id = v_uid;
  perform private.follow_notify('follow_accepted', v_uid, p_follower_id, v_row.source);
  return 'accepted';
end;
$$;
revoke all on function public.follow_respond(uuid, boolean) from public, anon;
grant execute on function public.follow_respond(uuid, boolean) to authenticated;

-- Slutt å følge (eller trekk forespørselen). Svarer om noe ble fjernet.
create or replace function public.follow_remove(p_profile_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  delete from public.follows f where f.follower_id = auth.uid() and f.followee_id = p_profile_id;
  return found;
end;
$$;
revoke all on function public.follow_remove(uuid) from public, anon;
grant execute on function public.follow_remove(uuid) to authenticated;

-- Fjern en følger (eller avslå en forespørsel uten å si hvorfor). Svarer om noe ble fjernet.
create or replace function public.follower_remove(p_profile_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  delete from public.follows f where f.follower_id = p_profile_id and f.followee_id = auth.uid();
  return found;
end;
$$;
revoke all on function public.follower_remove(uuid) from public, anon;
grant execute on function public.follower_remove(uuid) to authenticated;

-- Min kode (lages når den mangler). p_renew = true gir ny kode, og den gamle virker ikke lenger.
create or replace function public.follow_code(p_renew boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_code text;
  v_try  int := 0;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;
  if not coalesce(p_renew, false) then
    select c.code into v_code from public.follow_codes c where c.user_id = v_uid;
    if found then
      return v_code;
    end if;
  end if;
  loop
    v_try := v_try + 1;
    v_code := private.new_follow_code();
    begin
      insert into public.follow_codes (user_id, code) values (v_uid, v_code)
      on conflict (user_id) do update set code = excluded.code, created_at = now();
      return v_code;
    exception when unique_violation then
      if v_try >= 10 then
        raise;
      end if;
    end;
  end loop;
end;
$$;
revoke all on function public.follow_code(boolean) from public, anon;
grant execute on function public.follow_code(boolean) to authenticated;

-- Følg eieren av koden med en gang (å vise koden er godkjenningen).
create or replace function public.follow_by_code(p_code text, p_source text default 'qr')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_code   text := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  v_source text := coalesce(p_source, 'qr');
  v_owner  uuid;
  v_old    text;
  v_p      public.profiles;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if v_source not in ('qr', 'link') then
    raise exception 'Ukjent kilde' using errcode = '22023';
  end if;
  perform private.people_rate_hit('code', null, 20, interval '1 hour', 'forsøk med kode i timen');
  -- Ukjent kode gir svar (ikke feil), så forsøket står i loggen (en feil ruller den tilbake).
  select c.user_id into v_owner from public.follow_codes c where c.code = v_code;
  if v_owner is null or private.users_blocked(v_uid, v_owner) then
    return jsonb_build_object('status', 'not_found');
  end if;
  if v_owner = v_uid then
    raise exception 'Det er din egen kode' using errcode = '22023';
  end if;
  insert into public.profiles (id) values (v_uid) on conflict (id) do nothing;

  select f.status into v_old from public.follows f where f.follower_id = v_uid and f.followee_id = v_owner for update;
  if v_old is null then
    insert into public.follows (follower_id, followee_id, status, source, accepted_at)
    values (v_uid, v_owner, 'accepted', v_source, now());
  elsif v_old = 'pending' then
    update public.follows f set status = 'accepted', accepted_at = now(), source = v_source
     where f.follower_id = v_uid and f.followee_id = v_owner;
  end if;
  if v_old is distinct from 'accepted' then
    perform private.follow_notify('followed', v_uid, v_owner, v_source);
  end if;

  select * into v_p from public.profiles p where p.id = v_owner;
  return jsonb_build_object('profile_id', v_owner, 'display_name', v_p.display_name,
                            'avatar_path', v_p.avatar_path, 'status', 'accepted',
                            'already', coalesce(v_old = 'accepted', false));
end;
$$;
revoke all on function public.follow_by_code(text, text) from public, anon;
grant execute on function public.follow_by_code(text, text) to authenticated;

-- Innstillingene. null = uendret. Svarer begge.
create or replace function public.follow_settings(p_approval boolean default null, p_searchable boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;
  update public.profiles p
     set follow_approval = coalesce(p_approval, p.follow_approval),
         searchable = coalesce(p_searchable, p.searchable)
   where p.id = auth.uid()
  returning * into v_p;
  return jsonb_build_object('follow_approval', v_p.follow_approval, 'searchable', v_p.searchable);
end;
$$;
revoke all on function public.follow_settings(boolean, boolean) from public, anon;
grant execute on function public.follow_settings(boolean, boolean) to authenticated;

-- Godkjenning slått av: ventende forespørsler godtas (med varsel).
create or replace function private.profiles_follow_approval_off()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
begin
  for v_row in
    update public.follows f set status = 'accepted', accepted_at = now()
     where f.followee_id = new.id and f.status = 'pending'
    returning f.follower_id, f.source
  loop
    perform private.follow_notify('follow_accepted', new.id, v_row.follower_id, v_row.source);
  end loop;
  return null;
end;
$$;
revoke all on function private.profiles_follow_approval_off() from public, anon, authenticated;

drop trigger if exists profiles_follow_approval_off on public.profiles;
create trigger profiles_follow_approval_off
  after update of follow_approval on public.profiles
  for each row
  when (old.follow_approval and not new.follow_approval)
  execute function private.profiles_follow_approval_off();

-- Når følgingen forsvinner (avslag, fjerning, blokkering, sletting), forsvinner varslene mellom de to.
create or replace function private.follows_after_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.activity a
   where a.club_id is null and a.competition_id is null
     and a.kind in ('follow_requested', 'follow_accepted', 'followed')
     and (   (a.actor_profile_id = old.follower_id and old.followee_id = any (a.recipients))
          or (a.actor_profile_id = old.followee_id and old.follower_id = any (a.recipients)));
  return null;
end;
$$;
revoke all on function private.follows_after_delete() from public, anon, authenticated;

drop trigger if exists follows_after_delete on public.follows;
create trigger follows_after_delete
  after delete on public.follows
  for each row execute function private.follows_after_delete();

-- Følger, følgere og forespørsler, med navn.
--   direction 'following': jeg følger (status pending = jeg venter på svar)
--   direction 'follower':  følger meg (status pending = forespørsel til meg)
create or replace function public.my_follows()
returns table (profile_id uuid, display_name text, avatar_path text, direction text,
               status text, source text, created_at timestamptz, accepted_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select x.pid, coalesce(p.display_name, 'Ukjent'), p.avatar_path, x.direction, x.status, x.source,
         x.created_at, x.accepted_at
    from (
      select f.followee_id as pid, 'following'::text as direction, f.status, f.source, f.created_at, f.accepted_at
        from public.follows f where f.follower_id = auth.uid()
      union all
      select f.follower_id, 'follower', f.status, f.source, f.created_at, f.accepted_at
        from public.follows f where f.followee_id = auth.uid()
    ) x
    left join public.profiles p on p.id = x.pid
   where auth.uid() is not null
     and not private.users_blocked(auth.uid(), x.pid)
   order by x.direction, (x.status = 'pending') desc, coalesce(x.accepted_at, x.created_at) desc, x.pid;
$$;
revoke all on function public.my_follows() from public, anon;
grant execute on function public.my_follows() to authenticated;

-- Navnesøk. Minst 3 tegn. Én klubb per person (eldste aktive medlemskap), ikke flere.
create or replace function public.search_people(p_query text, p_limit integer default 20)
returns table (id uuid, display_name text, avatar_path text, club_name text,
               my_status text, follows_me boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_q   text := btrim(coalesce(p_query, ''));
  v_pat text;
  v_n   integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if char_length(v_q) < 3 then
    raise exception 'Skriv minst tre tegn' using errcode = '22023';
  end if;
  if char_length(v_q) > 40 then
    raise exception 'Høyst 40 tegn' using errcode = '22023';
  end if;
  perform private.people_rate_hit('search', null, 60, interval '1 hour', 'søk i timen');
  v_pat := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return query
  select p.id, p.display_name, p.avatar_path,
         (select c.name from public.club_members m join public.clubs c on c.id = m.club_id
           where m.user_id = p.id and m.status = 'active'
           order by m.created_at, m.id limit 1),
         coalesce((select f.status from public.follows f where f.follower_id = v_uid and f.followee_id = p.id), 'none'),
         exists (select 1 from public.follows f
                  where f.follower_id = p.id and f.followee_id = v_uid and f.status = 'accepted')
    from public.profiles p
   where p.searchable
     and p.display_name is not null
     and p.id <> v_uid
     and p.display_name ilike v_pat
     and not private.users_blocked(v_uid, p.id)
   order by (p.display_name ilike replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%') desc,
            lower(p.display_name), p.id
   limit v_n;
end;
$$;
revoke all on function public.search_people(text, integer) from public, anon;
grant execute on function public.search_people(text, integer) to authenticated;


-- ===========================================================================
-- 5. BLOKKERING OG RAPPORT
-- ===========================================================================
-- Blokkering fjerner følging begge veier (også ventende). Trigger, så alle veier inn er med.
create or replace function private.user_blocks_drop_follows()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows f
   where (f.follower_id = new.blocker_id and f.followee_id = new.blocked_id)
      or (f.follower_id = new.blocked_id and f.followee_id = new.blocker_id);
  return null;
end;
$$;
revoke all on function private.user_blocks_drop_follows() from public, anon, authenticated;

drop trigger if exists user_blocks_drop_follows on public.user_blocks;
create trigger user_blocks_drop_follows
  after insert on public.user_blocks
  for each row execute function private.user_blocks_drop_follows();

-- Fra 019. Nytt: du kan også blokkere den som har en følgerad med deg (også en forespørsel),
-- og en søkbar profil (du har sett den i søket).
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
     and not public.can_see_profile(v_target)
     and not private.follow_any_between(v_uid, v_target)
     and not exists (select 1 from public.profiles p
                      where p.id = v_target and p.searchable and p.display_name is not null) then
    raise exception 'Fant ikke personen' using errcode = 'P0002';
  end if;
  insert into public.user_blocks (blocker_id, blocked_id) values (v_uid, v_target)
  on conflict do nothing;
  return v_target;
end;
$$;
revoke all on function public.block_user(uuid, uuid) from public, anon;
grant execute on function public.block_user(uuid, uuid) to authenticated;

-- Fra 050. Nytt: en profil kan rapporteres av den som har en følgerad med den (også en
-- forespørsel) eller ser den i søket.
create or replace function public.report_content(p_kind text, p_target_id uuid, p_reason text, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_club      uuid;
  v_comp      uuid;
  v_author    uuid;
  v_snapshot  text;
  v_id        uuid;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('message', 'image', 'member', 'profile', 'comment') then
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
  elsif p_kind = 'comment' then
    select c.club_id, case when c.club_id is null then c.competition_id end,
           private.person_user(c.member_id, c.profile_id), left(c.body, 600)
      into v_club, v_comp, v_author, v_snapshot
    from public.comments c
    where c.id = p_target_id and private.can_read_target('comment', c.id);
  else
    select null, p.id, left(p.display_name, 600) into v_club, v_author, v_snapshot
    from public.profiles p
    where p.id = p_target_id and p.id <> v_uid
      and (public.can_see_profile(p.id)
           or private.follow_any_between(v_uid, p.id)
           or (p.searchable and p.display_name is not null and not private.users_blocked(v_uid, p.id)));
  end if;
  if not found then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;

  insert into public.content_reports (reporter_id, kind, target_id, club_id, competition_id,
                                      target_profile_id, reason, note, snapshot)
  values (v_uid, p_kind, p_target_id, v_club, v_comp, v_author, p_reason, nullif(btrim(p_note), ''), v_snapshot)
  on conflict (reporter_id, kind, target_id) where status = 'open'
  do update set reason = excluded.reason, note = excluded.note
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.report_content(text, uuid, text, text) from public, anon;
grant execute on function public.report_content(text, uuid, text, text) to authenticated;


-- ===========================================================================
-- 6. PERSONLIGE LINJER I ACTIVITY
-- ===========================================================================
-- Fra 031. Nytt: personlige linjer får ingen turnering (runden kan høre til en kveld i en turnering).
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
  if new.club_id is null and new.actor_profile_id is not null then
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

-- Fra 050. Nytt: appen kan ikke sette actor_profile_id (bare serveren).
create or replace function public.activity_before_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is not null then
    new.recipients := public.clean_member_list(new.recipients, new.club_id);
  elsif new.recipients is not null then
    select coalesce(array_agg(distinct u), '{}') into new.recipients
      from unnest(new.recipients) u where u is not null;
    if exists (select 1 from unnest(new.recipients) u
                where not exists (select 1 from public.profiles p where p.id = u)) then
      raise exception 'Lista har noen som ikke finnes' using errcode = '23503';
    end if;
  end if;

  if auth.uid() is null then
    return new;
  end if;
  -- 045: laget av serveren (opprykk, avmelding): aktøren og mottakerne er satt av funksjonen.
  if coalesce(current_setting('dd18.server_activity', true), '') = 'on' then
    return new;
  end if;

  new.actor_member_id := public.my_member_id(new.club_id);
  new.actor_profile_id := null;
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

-- Fra 050. Nytt: personlige linjer (tredje gren).
drop policy if exists activity_select on public.activity;
create policy activity_select on public.activity
  for select to authenticated
  using (
    (club_id is not null and public.is_club_member(club_id)
     and (recipients is null or public.my_member_id(club_id) = any (recipients)
          or actor_member_id = public.my_member_id(club_id) or public.is_club_organizer(club_id))
     and (round_id is null or public.can_read_round(round_id)))
    or (club_id is null and competition_id is not null
        and (recipients is null or (select auth.uid()) = any (recipients))
        and public.can_read_competition(competition_id)
        and (round_id is null or public.can_read_round(round_id)))
    or (club_id is null and competition_id is null
        and private.personal_activity_visible((select auth.uid()), actor_profile_id, recipients, round_id)));

-- Fra 050. Nytt: forfatteren av en personlig linje er profilen.
create or replace function private.target_info(p_kind text, p_id uuid)
returns table (club_id uuid, competition_id uuid, event_id uuid, round_id uuid,
               author_member_id uuid, author_profile_id uuid, recipients uuid[])
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_kind = 'activity' then
    return query
    select a.club_id, a.competition_id, a.event_id, a.round_id, a.actor_member_id, a.actor_profile_id, a.recipients
      from public.activity a where a.id = p_id;
  elsif p_kind = 'message' then
    return query
    select t.club_id, e.competition_id, t.event_id, null::uuid, t.member_id, null::uuid, null::uuid[]
      from public.thread_messages t left join public.events e on e.id = t.event_id
     where t.id = p_id;
  elsif p_kind = 'comment' then
    return query
    select c.club_id, c.competition_id, null::uuid, null::uuid, c.member_id, c.profile_id, null::uuid[]
      from public.comments c where c.id = p_id and c.deleted_at is null;
  end if;
end;
$$;
revoke all on function private.target_info(text, uuid) from public, anon, authenticated;

-- Fra 050. Nytt: personlige linjer.
create or replace function private.can_read_target(p_kind text, p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_id   uuid;
begin
  if auth.uid() is null or p_id is null then
    return false;
  end if;
  if p_kind = 'activity' then
    return exists (
      select 1 from public.activity a
       where a.id = p_id
         and (   (a.club_id is not null and public.is_club_member(a.club_id)
                  and (a.recipients is null or public.my_member_id(a.club_id) = any (a.recipients)
                       or a.actor_member_id = public.my_member_id(a.club_id)
                       or public.is_club_organizer(a.club_id))
                  and (a.round_id is null or public.can_read_round(a.round_id)))
              or (a.club_id is null and a.competition_id is not null
                  and (a.recipients is null or auth.uid() = any (a.recipients))
                  and public.can_read_competition(a.competition_id)
                  and (a.round_id is null or public.can_read_round(a.round_id)))
              or (a.club_id is null and a.competition_id is null
                  and private.personal_activity_visible(auth.uid(), a.actor_profile_id, a.recipients, a.round_id)))
         and not private.person_blocked(a.actor_member_id, null));
  elsif p_kind = 'message' then
    return exists (
      select 1 from public.thread_messages t
       where t.id = p_id and public.is_club_member(t.club_id)
         and not private.person_blocked(t.member_id, null));
  elsif p_kind = 'comment' then
    select c.target_kind, c.target_id into v_kind, v_id
      from public.comments c
     where c.id = p_id and c.deleted_at is null and not private.person_blocked(c.member_id, c.profile_id);
    if not found then
      return false;
    end if;
    return private.can_read_target(v_kind, v_id);
  end if;
  return false;
end;
$$;
revoke all on function private.can_read_target(text, uuid) from public, anon, authenticated;
grant execute on function private.can_read_target(text, uuid) to authenticated;

-- Fra 050. Nytt: personlige linjer.
create or replace function private.user_can_read_target(p_uid uuid, p_kind text, p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_id   uuid;
begin
  if p_uid is null or p_id is null then
    return false;
  end if;
  if p_kind = 'activity' then
    return exists (
      select 1 from public.activity a
       where a.id = p_id
         and (   (a.club_id is not null and exists (
                    select 1 from public.club_members m
                     where m.club_id = a.club_id and m.user_id = p_uid and m.status = 'active'
                       and (a.recipients is null or m.id = any (a.recipients) or m.id = a.actor_member_id
                            or private.member_has_any_right(m.id))
                       and (a.round_id is null or private.member_has_any_right(m.id)
                            or exists (select 1 from public.rounds r where r.id = a.round_id and r.status <> 'draft'))))
              or (a.club_id is null and a.competition_id is not null
                  and (a.recipients is null or p_uid = any (a.recipients))
                  and exists (select 1 from private.push_competition_audience(a.competition_id) au where au.user_id = p_uid)
                  and (a.round_id is null
                       or exists (select 1 from public.rounds r where r.id = a.round_id and r.status <> 'draft')))
              or (a.club_id is null and a.competition_id is null
                  and private.personal_activity_visible(p_uid, a.actor_profile_id, a.recipients, a.round_id)))
         and not private.users_blocked(p_uid, private.person_user(a.actor_member_id, null)));
  elsif p_kind = 'message' then
    return exists (
      select 1 from public.thread_messages t
        join public.club_members m on m.club_id = t.club_id and m.user_id = p_uid and m.status = 'active'
       where t.id = p_id
         and not private.users_blocked(p_uid, private.person_user(t.member_id, null)));
  elsif p_kind = 'comment' then
    select c.target_kind, c.target_id into v_kind, v_id
      from public.comments c
     where c.id = p_id and c.deleted_at is null
       and not private.users_blocked(p_uid, private.person_user(c.member_id, c.profile_id));
    if not found then
      return false;
    end if;
    return private.user_can_read_target(p_uid, v_kind, v_id);
  end if;
  return false;
end;
$$;
revoke all on function private.user_can_read_target(uuid, text, uuid) from public, anon, authenticated;

-- Fra 050. Nytt: varsler om kommentarer på et personlig kort er også personlige
-- (actor_profile_id = den som skrev).
create or replace function private.comment_notify(p_comment public.comments, p_mentions uuid[], p_new_comment boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev    text := current_setting('dd18.server_activity', true);
  v_t       record;
  v_author  uuid := private.person_user(p_comment.member_id, p_comment.profile_id);
  v_name    text;
  v_mention_users uuid[];
  v_users   uuid[];
  v_recips  uuid[];
  v_data    jsonb;
  v_actor_p uuid;
begin
  select * into v_t from private.target_info(p_comment.target_kind, p_comment.target_id) limit 1;
  if not found then
    return;
  end if;
  if p_comment.member_id is not null then
    select m.display_name into v_name from public.club_members m where m.id = p_comment.member_id;
  else
    select p.display_name into v_name from public.profiles p where p.id = p_comment.profile_id;
  end if;
  v_data := jsonb_strip_nulls(jsonb_build_object(
    'target_kind', p_comment.target_kind, 'target_id', p_comment.target_id,
    'comment_id', p_comment.id, 'preview', left(p_comment.body, 140), 'author_name', v_name,
    'author_profile', p_comment.profile_id));
  v_actor_p := case when p_comment.club_id is null and v_t.competition_id is null then p_comment.profile_id end;

  select coalesce(array_agg(private.person_user(case when p_comment.club_id is not null then x end,
                                                 case when p_comment.club_id is null then x end)), '{}')
    into v_mention_users from unnest(coalesce(p_mentions, '{}')) x;

  perform set_config('dd18.server_activity', 'on', true);

  if p_new_comment then
    -- Forfatteren av målet (uten å følge, men ikke om hen har slått tråden av) og de som følger.
    select coalesce(array_agg(distinct u), '{}') into v_users
      from (
        select private.person_user(v_t.author_member_id, v_t.author_profile_id) as u
         where not exists (select 1 from public.thread_follows f
                            where f.target_kind = p_comment.target_kind and f.target_id = p_comment.target_id
                              and f.user_id = private.person_user(v_t.author_member_id, v_t.author_profile_id)
                              and not f.following)
        union
        select f.user_id from public.thread_follows f
         where f.target_kind = p_comment.target_kind and f.target_id = p_comment.target_id and f.following
      ) x
     where u is not null and u <> v_author and not (u = any (v_mention_users))
       and not private.users_blocked(u, v_author)
       and private.user_can_read_target(u, p_comment.target_kind, p_comment.target_id);

    if p_comment.club_id is not null then
      select coalesce(array_agg(m.id order by m.id), '{}') into v_recips
        from public.club_members m
       where m.club_id = p_comment.club_id and m.status = 'active' and m.user_id = any (v_users);
    else
      select coalesce(array_agg(u order by u), '{}') into v_recips from unnest(v_users) u;
    end if;

    if cardinality(v_recips) > 0 then
      insert into public.activity (club_id, competition_id, kind, category, data, actor_member_id,
                                   actor_profile_id, event_id, round_id, recipients)
      values (p_comment.club_id, v_t.competition_id, 'comment_added', 'social', v_data,
              p_comment.member_id, v_actor_p, v_t.event_id, v_t.round_id, v_recips[1:200]);
    end if;
  end if;

  if cardinality(coalesce(p_mentions, '{}')) > 0 then
    insert into public.activity (club_id, competition_id, kind, category, data, actor_member_id,
                                 actor_profile_id, event_id, round_id, recipients)
    values (p_comment.club_id, v_t.competition_id, 'mentioned', 'social', v_data,
            p_comment.member_id, v_actor_p, v_t.event_id, v_t.round_id, p_mentions);
  end if;

  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
end;
$$;
revoke all on function private.comment_notify(public.comments, uuid[], boolean) from public, anon, authenticated;

-- Fra 050. Nytt: personlige kort (uten klubb og turnering) kan kommenteres.
create or replace function public.comment_add(p_kind text, p_id uuid, p_body text,
                                              p_mentions uuid[] default '{}', p_follow boolean default true)
returns public.comments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_body     text := btrim(p_body);
  v_t        record;
  v_member   uuid;
  v_mentions uuid[];
  v_n        integer;
  v_row      public.comments;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('activity', 'message') then
    raise exception 'Bare hendelser og meldinger kan kommenteres' using errcode = '22023';
  end if;
  if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 1000 then
    raise exception 'Kommentaren må ha 1–1000 tegn' using errcode = '22023';
  end if;
  select * into v_t from private.target_info(p_kind, p_id) limit 1;
  if not found or not private.can_read_target(p_kind, p_id) then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;
  if v_t.club_id is not null then
    v_member := public.my_member_id(v_t.club_id);
    if v_member is null then
      raise exception 'Du er ikke med i klubben' using errcode = '42501';
    end if;
  elsif v_t.competition_id is null and v_t.author_profile_id is null then
    raise exception 'Fant ikke innholdet' using errcode = 'P0002';
  end if;

  select count(*) into v_n from public.comments c
   where (c.member_id = v_member or c.profile_id = v_uid) and c.created_at > now() - interval '10 minutes';
  if v_n >= 60 then
    raise exception 'Grensen er nådd: høyst 60 kommentarer på ti minutter. Prøv igjen senere.'
      using errcode = '54000';
  end if;

  v_mentions := private.valid_mentions(p_kind, p_id, v_t.club_id, p_mentions, v_uid);

  insert into public.comments (club_id, competition_id, target_kind, target_id, member_id, profile_id,
                               body, mentions)
  values (v_t.club_id, v_t.competition_id, p_kind, p_id, v_member,
          case when v_member is null then v_uid end, v_body, v_mentions)
  returning * into v_row;

  if coalesce(p_follow, true) then
    insert into public.thread_follows (user_id, target_kind, target_id, following)
    values (v_uid, p_kind, p_id, true)
    on conflict do nothing;
  end if;

  perform private.comment_notify(v_row, v_mentions, true);
  return v_row;
end;
$$;
revoke all on function public.comment_add(text, uuid, text, uuid[], boolean) from public, anon;
grant execute on function public.comment_add(text, uuid, text, uuid[], boolean) to authenticated;

-- Fra 050. Nytt: den som eier et personlig kort, kan slette kommentarer på det.
create or replace function public.comment_delete(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.comments;
begin
  if v_uid is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  select * into v_row from public.comments c where c.id = p_id for update;
  if not found then
    raise exception 'Fant ikke kommentaren' using errcode = 'P0002';
  end if;
  if not (   (private.person_user(v_row.member_id, v_row.profile_id) = v_uid
              and (v_row.member_id is null or public.owns_member(v_row.member_id)))
          or private.can_moderate(v_row.club_id, v_row.competition_id)
          or (v_row.club_id is null and v_row.competition_id is null and v_row.target_kind = 'activity'
              and exists (select 1 from public.activity a
                           where a.id = v_row.target_id and a.club_id is null and a.competition_id is null
                             and a.actor_profile_id = v_uid))) then
    if private.can_read_target(v_row.target_kind, v_row.target_id) then
      raise exception 'Bare den som skrev, eller en moderator, kan slette kommentaren' using errcode = '42501';
    end if;
    raise exception 'Fant ikke kommentaren' using errcode = 'P0002';
  end if;
  return private.comment_soft_delete(p_id, v_uid);
end;
$$;
revoke all on function public.comment_delete(uuid) from public, anon;
grant execute on function public.comment_delete(uuid) to authenticated;


-- ===========================================================================
-- 7. RUNDER: round_finished NÅR RUNDEN LÅSES
-- ===========================================================================
-- Én linje per spiller med innlogging (klubbmedlem eller profil i løs runde). Ikke playoff.
create or replace function private.round_finished_insert(p_round_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prev text := current_setting('dd18.server_activity', true);
  v_n    integer;
begin
  perform set_config('dd18.server_activity', 'on', true);
  insert into public.activity (club_id, competition_id, kind, category, data, actor_profile_id, round_id, created_at)
  select null, null, 'round_finished', 'round', jsonb_build_object('player_id', x.player_id),
         x.uid, r.id, coalesce(r.locked_at, now())
    from public.rounds r
    cross join lateral (
      select distinct on (coalesce(cm.user_id, pt.profile_id))
             coalesce(cm.user_id, pt.profile_id) as uid, rp.member_id as player_id
        from public.round_players rp
        left join public.club_members cm on cm.id = rp.member_id and rp.club_id is not null and cm.status = 'active'
        left join public.round_participants pt on pt.id = rp.member_id and rp.club_id is null
       where rp.round_id = r.id and coalesce(cm.user_id, pt.profile_id) is not null
       order by coalesce(cm.user_id, pt.profile_id), rp.member_id) x
   where r.id = p_round_id and r.status = 'locked' and r.kind = 'normal'
     and exists (select 1 from public.profiles p where p.id = x.uid)
  on conflict (round_id, actor_profile_id) where kind = 'round_finished' do nothing;
  get diagnostics v_n = row_count;
  perform set_config('dd18.server_activity', coalesce(v_prev, ''), true);
  return v_n;
end;
$$;
revoke all on function private.round_finished_insert(uuid) from public, anon, authenticated;

create or replace function private.rounds_round_finished()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'locked' and old.status is distinct from 'locked' and new.kind = 'normal' then
    perform private.round_finished_insert(new.id);
  end if;
  return null;
end;
$$;
revoke all on function private.rounds_round_finished() from public, anon, authenticated;

drop trigger if exists rounds_round_finished on public.rounds;
create trigger rounds_round_finished
  after update of status on public.rounds
  for each row
  when (new.status = 'locked')
  execute function private.rounds_round_finished();

-- Runden slettes: de personlige linjene om den også (activity_round_fk sjekkes ikke uten klubb).
create or replace function private.rounds_delete_personal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.activity a
   where a.round_id = old.id and a.club_id is null and a.competition_id is null;
  return null;
end;
$$;
revoke all on function private.rounds_delete_personal() from public, anon, authenticated;

drop trigger if exists rounds_delete_personal on public.rounds;
create trigger rounds_delete_personal
  after delete on public.rounds
  for each row execute function private.rounds_delete_personal();

-- Det som alt er låst.
do $$
begin
  perform private.round_finished_insert(r.id) from public.rounds r where r.status = 'locked' and r.kind = 'normal';
end $$;


-- ===========================================================================
-- 8. «FØLGER»-FANEN
-- ===========================================================================
-- Ferdige (låste) runder fra dem du følger (godtatt) og dine egne, nyeste først, nøkkel
-- (created_at, id) som feed_page. Uten blokkerte. Kortet regnes ut nå: spillerens slag,
-- hull spilt, par for de spilte hullene, og hullene ({hole, par, strokeIndex, strokes}) fra
-- øyeblikksbildet (048). Ingen andre spillere, ingen klubb. id er hendelsen (react/comment_add
-- med 'activity').
create or replace function public.following_feed_page(p_before_ts timestamptz default null,
                                                      p_before_id uuid default null,
                                                      p_limit integer default 30)
returns table (id uuid, round_id uuid, created_at timestamptz, profile_id uuid, display_name text,
               avatar_path text, is_mine boolean, played_on date, course_name text, hole_count integer,
               format text, playing_handicap integer, strokes integer, holes_played integer,
               par_played integer, to_par integer, holes jsonb,
               reactions jsonb, my_reactions text[], comment_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  with lim as (
    select least(greatest(coalesce(p_limit, 30), 1), 100) as n,
           coalesce(p_before_id, '00000000-0000-0000-0000-000000000000'::uuid) as before_id
  ),
  blocked as (
    select b.blocked_id as uid from public.user_blocks b where b.blocker_id = auth.uid()
    union
    select b.blocker_id from public.user_blocks b where b.blocked_id = auth.uid()
  ),
  people as (
    select f.followee_id as pid from public.follows f
     where f.follower_id = auth.uid() and f.status = 'accepted'
       and not exists (select 1 from blocked where blocked.uid = f.followee_id)
    union
    select auth.uid() where auth.uid() is not null
  ),
  cand as (
    select a.* from people cross join lateral (
      select a.* from public.activity a, lim
       where a.actor_profile_id = people.pid and a.kind = 'round_finished'
         and a.club_id is null and a.competition_id is null
         and (p_before_ts is null or (a.created_at, a.id) < (p_before_ts, lim.before_id))
         and exists (select 1 from public.rounds r where r.id = a.round_id and r.status = 'locked')
       order by a.created_at desc, a.id desc
       limit (select n from lim)) a
  ),
  page as (
    select * from cand order by created_at desc, id desc limit (select n from lim)
  ),
  card as (
    select p.*, r.hole_count as r_holes, r.format as r_format, r.holes_snapshot,
           coalesce(e.event_date, (r.locked_at at time zone 'Europe/Oslo')::date) as r_date,
           co.name as r_course,
           (select rp.playing_handicap from public.round_players rp
             where rp.round_id = r.id and rp.member_id = (p.data ->> 'player_id')::uuid) as r_ph,
           (select coalesce(jsonb_agg(jsonb_build_object(
                     'hole', coalesce((h.x ->> 'hole')::int, r.first_hole + i.i),
                     'par', (h.x ->> 'par')::int,
                     'strokeIndex', (h.x ->> 'strokeIndex')::int,
                     'strokes', s.strokes) order by i.i), '[]'::jsonb)
              from generate_series(0, r.hole_count - 1) as i (i)
              left join lateral (select r.holes_snapshot -> 'holes' -> i.i as x) h on true
              left join public.hole_scores s
                on s.round_id = r.id and s.member_id = (p.data ->> 'player_id')::uuid and s.hole_index = i.i) as r_holes_json
      from page p
      join public.rounds r on r.id = p.round_id
      left join public.events e on e.id = r.event_id
      left join public.courses co on co.id = r.course_id
  )
  select c.id, c.round_id, c.created_at, c.actor_profile_id, pr.display_name, pr.avatar_path,
         c.actor_profile_id = auth.uid(), c.r_date, c.r_course, c.r_holes::integer, c.r_format,
         c.r_ph::integer,
         (select sum((h ->> 'strokes')::int)::integer from jsonb_array_elements(c.r_holes_json) h),
         (select count(*)::integer from jsonb_array_elements(c.r_holes_json) h where h ->> 'strokes' is not null),
         (select sum((h ->> 'par')::int)::integer from jsonb_array_elements(c.r_holes_json) h
           where h ->> 'strokes' is not null),
         (select (sum((h ->> 'strokes')::int) - sum((h ->> 'par')::int))::integer
            from jsonb_array_elements(c.r_holes_json) h
           where h ->> 'strokes' is not null and h ->> 'par' is not null),
         c.r_holes_json,
         coalesce((
           select jsonb_agg(jsonb_build_object('emoji', x.emoji, 'count', x.n) order by x.n desc, x.first, x.emoji)
             from (select r.emoji, count(*) as n, min(r.created_at) as first
                     from public.reactions r
                     left join public.club_members rm on rm.id = r.member_id
                    where r.target_kind = 'activity' and r.target_id = c.id
                      and not exists (select 1 from blocked where blocked.uid = coalesce(r.profile_id, rm.user_id))
                    group by r.emoji) x), '[]'::jsonb),
         coalesce((
           select array_agg(r.emoji order by r.created_at, r.emoji)
             from public.reactions r
            where r.target_kind = 'activity' and r.target_id = c.id and r.person_id = auth.uid()), '{}'::text[]),
         (select count(*)::integer
            from public.comments cm
            left join public.club_members m on m.id = cm.member_id
           where cm.target_kind = 'activity' and cm.target_id = c.id and cm.deleted_at is null
             and not exists (select 1 from blocked where blocked.uid = coalesce(cm.profile_id, m.user_id)))
    from card c
    left join public.profiles pr on pr.id = c.actor_profile_id
   order by c.created_at desc, c.id desc;
$$;
revoke all on function public.following_feed_page(timestamptz, uuid, integer) from public, anon;
grant execute on function public.following_feed_page(timestamptz, uuid, integer) to authenticated;


-- ===========================================================================
-- 9. PUSH
-- ===========================================================================
-- Fra 046. Nytt: personlige linjer med mottakerliste går i køen (uten klubb og turnering);
-- round_finished går ikke som push.
create or replace function public.push_enqueue_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is null and new.competition_id is null
     and (new.actor_profile_id is null or new.recipients is null) then
    return null;
  end if;
  if new.kind in ('round_started', 'round_finished') then
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

-- Fra 050, med de fire nye kindene.
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
    ('thread', 'thread_message'),
    ('social', 'comment_added'), ('social', 'mentioned'), ('social', 'photo_prompt'),
    ('social', 'bill_share_sent'), ('social', 'bill_share_disputed'),
    ('social', 'follow_requested'), ('social', 'follow_accepted'), ('social', 'followed'),
    ('round', 'round_finished')
  ) as m (category, kind)
  order by 1, 2, 3;
$$;
revoke all on function public.push_group_map() from public, anon;
grant execute on function public.push_group_map() to authenticated, service_role;

-- Fra 050. Nytt: audience 'person' for personlige jobber (mottakerlisten, profil-id-er; ingen
-- kveld, ingen collapse), og activity.actor_profile_id når den er satt. Klubb- og
-- turneringsjobber gir samme svar som før.
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
  ctx0 as (
    select q.id as job_id,
           q.club_id,
           coalesce(q.competition_id, (select a.competition_id from a)) as competition_id
      from q
  ),
  ctx as (
    select ctx0.job_id, ctx0.club_id, ctx0.competition_id,
           (ctx0.club_id is null and ctx0.competition_id is null) as personal,
           case when ctx0.club_id is null and ctx0.competition_id is null then null
                else coalesce((select a.event_id from a),
                              (select r.event_id from a join public.rounds r on r.id = a.round_id),
                              (select t.event_id from t)) end as event_id,
           case when q.activity_id is not null then (select a.category from a) else 'thread' end as category,
           case when q.activity_id is not null
                then public.push_group((select a.category from a), (select a.kind from a))
                else 'social' end as grp
      from ctx0 join q on q.id = ctx0.job_id
  ),
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
  prof_aud as (
    select x.uid, x.is_organizer
      from ctx cross join lateral private.push_competition_audience(ctx.competition_id) x (uid, is_organizer)
     where ctx.club_id is null and not ctx.personal
    union all
    select u, false
      from ctx, a cross join lateral unnest(coalesce(a.recipients, '{}'::uuid[])) u
     where ctx.personal
  ),
  comp_aud as (
    select ca.uid as id, ca.uid as user_id,
           coalesce(pr.display_name, 'Noen') as display_name,
           ca.is_organizer,
           true as active,
           true as may_have_devices,
           coalesce((select array_agg(distinct c order by c)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_categories) c
                      where m.user_id = ca.uid and m.status = 'active'), '{}'::text[]) as disabled_categories,
           'mentions'::text as thread_mode,
           coalesce((select array_agg(distinct g order by g)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id,
                            unnest(p.disabled_groups) g
                      where m.user_id = ca.uid and m.status = 'active'), '{}'::text[]) as disabled_groups,
           coalesce((select bool_and(p.email_fallback)
                       from public.club_members m
                       join public.push_preferences p on p.member_id = m.id
                      where m.user_id = ca.uid and m.status = 'active'), true) as email_fallback
      from prof_aud ca
      left join public.profiles pr on pr.id = ca.uid
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
      else jsonb_build_object('id', null, 'name', case when ctx.personal then 'Atten' else co.name end,
                              'disabled_categories', '[]'::jsonb)
    end,
    'activity', (
      select jsonb_build_object(
        'id', a.id, 'kind', a.kind, 'category', a.category, 'data', a.data,
        'actor_member_id', a.actor_member_id, 'event_id', a.event_id,
        'round_id', a.round_id, 'recipients', to_jsonb(a.recipients),
        'created_at', a.created_at,
        'round_status', (select r.status from public.rounds r where r.id = a.round_id))
        || case when a.actor_profile_id is not null
                then jsonb_build_object('actor_profile_id', a.actor_profile_id) else '{}'::jsonb end
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
                      and coalesce((select a.kind from a), '') not in ('comment_added', 'mentioned')
                     then 'event-' || ctx.event_id || '-' || ctx.grp end,
    'competition', case when co.id is not null then jsonb_build_object('id', co.id, 'name', co.name) end,
    'audience', case when q.club_id is not null then 'club'
                     when ctx.personal then 'person'
                     else 'competition' end
  )
  from q
  cross join ctx
  left join public.clubs c on c.id = q.club_id
  left join public.competitions co on co.id = ctx.competition_id;
$$;
revoke all on function public.push_job_payload(bigint) from public, anon, authenticated;
grant execute on function public.push_job_payload(bigint) to service_role;


-- ===========================================================================
-- 10. SLETTING AV KONTO
-- ===========================================================================
-- Fra 050. Nytt: følging, koden, søkeloggen og de personlige linjene.
create or replace function public.delete_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_members   uuid[];
  v_messages  integer := 0;
  v_comments  integer := 0;
  v_promoted  integer := 0;
  v_owners    integer := 0;
  v_rounds    integer := 0;
  v_follows   integer := 0;
  v_row       record;
  v_heir      uuid;
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

  -- 044: og ikke uten eier. Den eldste gjenværende arrangøren overtar, ellers det
  -- eldste aktive medlemmet med innlogging.
  for v_row in
    select m.id, m.club_id from public.club_members m
    where m.user_id = p_user_id and private.member_is_last_owner(m.id)
  loop
    select n.id into v_heir from public.club_members n
     where n.club_id = v_row.club_id and n.status = 'active'
       and n.user_id is not null and n.user_id <> p_user_id
     order by n.is_organizer desc, n.created_at, n.id limit 1;
    if v_heir is not null then
      insert into public.club_member_roles (club_id, member_id, role_id)
      select v_row.club_id, v_heir, r.id from public.club_roles r
       where r.club_id = v_row.club_id and r.is_owner
      on conflict do nothing;
      v_owners := v_owners + 1;
    end if;
  end loop;
  delete from public.club_member_roles mr where mr.member_id = any (v_members);

  -- Innholdet personen har skrevet.
  delete from public.thread_messages t where t.member_id = any (v_members);
  get diagnostics v_messages = row_count;
  delete from public.activity_reactions r where r.member_id = any (v_members);
  -- 050: kommentarer, reaksjoner og følging av tråder.
  delete from public.comments c where c.member_id = any (v_members) or c.profile_id = p_user_id;
  get diagnostics v_comments = row_count;
  delete from public.reactions r where r.member_id = any (v_members) or r.profile_id = p_user_id;
  delete from public.thread_follows f where f.user_id = p_user_id;
  delete from public.push_preferences p where p.member_id = any (v_members);
  delete from public.push_devices d where d.user_id = p_user_id;
  delete from public.user_blocks b where b.blocker_id = p_user_id or b.blocked_id = p_user_id;
  -- 054: følging, koden, søkeloggen og de personlige linjene.
  delete from public.follows f where f.follower_id = p_user_id or f.followee_id = p_user_id;
  get diagnostics v_follows = row_count;
  delete from public.follow_codes c where c.user_id = p_user_id;
  delete from private.people_rate_log l where l.user_id = p_user_id;
  delete from public.activity a
   where a.club_id is null and a.competition_id is null and a.actor_profile_id = p_user_id;
  update public.activity a set recipients = array_remove(a.recipients, p_user_id)
   where a.club_id is null and a.competition_id is null and p_user_id = any (a.recipients);

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
     set display_name = null, avatar_path = null, handicap_index = null, searchable = false
   where p.id = p_user_id;

  return jsonb_build_object('memberships', cardinality(v_members), 'messages', v_messages,
                            'comments', v_comments,
                            'loose_rounds', v_rounds, 'organizers_promoted', v_promoted,
                            'owners_promoted', v_owners, 'follows', v_follows);
end;
$$;
revoke all on function public.delete_account_data(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_data(uuid) to service_role;


-- ===========================================================================
-- 11. REALTIME
-- ===========================================================================
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'Publikasjonen supabase_realtime finnes ikke – hopper over realtime';
    return;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'follows') then
    alter publication supabase_realtime add table public.follows;
  end if;
end $$;


-- ===========================================================================
-- KONTROLL (kjøres i samme transaksjon; feiler ved avvik)
-- ===========================================================================
do $$
declare
  v_fail text := '';
  v_fn   text;
begin
  -- 1. Tabellene har RLS, appen kan bare lese follows, ikke koder eller loggen.
  if exists (select 1 from pg_class
              where oid in ('public.follows'::regclass, 'public.follow_codes'::regclass) and not relrowsecurity)
     or has_table_privilege('authenticated', 'public.follows', 'insert')
     or has_table_privilege('authenticated', 'public.follows', 'update')
     or has_table_privilege('authenticated', 'public.follows', 'delete')
     or has_table_privilege('authenticated', 'public.follow_codes', 'select')
     or has_table_privilege('anon', 'public.follows', 'select')
     or has_table_privilege('authenticated', 'private.people_rate_log', 'select') then
    v_fail := v_fail || ' 1';
  end if;
  -- 2. Kolonnene på profiles og activity, med standardverdiene.
  if (select count(*) from information_schema.columns
       where table_schema = 'public'
         and ((table_name = 'profiles' and column_name in ('follow_approval', 'searchable') and column_default = 'true')
           or (table_name = 'activity' and column_name = 'actor_profile_id'))) <> 3
     or exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'profiles' and column_name = 'follow_code') then
    v_fail := v_fail || ' 2';
  end if;
  -- 3. RPC-ene: innlogget ja, anon nei.
  foreach v_fn in array array['public.follow_request(uuid, text)', 'public.follow_respond(uuid, boolean)',
                              'public.follow_remove(uuid)', 'public.follower_remove(uuid)',
                              'public.follow_code(boolean)', 'public.follow_by_code(text, text)',
                              'public.follow_settings(boolean, boolean)', 'public.my_follows()',
                              'public.search_people(text, integer)',
                              'public.following_feed_page(timestamptz, uuid, integer)',
                              'public.can_see_profile(uuid)', 'public.known_profiles()',
                              'public.block_user(uuid, uuid)', 'public.report_content(text, uuid, text, text)',
                              'public.comment_add(text, uuid, text, uuid[], boolean)',
                              'public.comment_delete(uuid)'] loop
    if not has_function_privilege('authenticated', v_fn, 'execute')
       or has_function_privilege('anon', v_fn, 'execute') then
      v_fail := v_fail || ' 3(' || v_fn || ')';
    end if;
  end loop;
  -- 4. Kartet: 27 fra 050 + 4, de nye i riktig gruppe, alle kinds i activity har en gruppe.
  if (select count(*) from public.push_group_map()) <> 31
     or (select count(*) from public.push_group_map()
          where (kind in ('follow_requested', 'follow_accepted', 'followed', 'bill_share_sent',
                          'bill_share_disputed', 'comment_added', 'mentioned', 'photo_prompt') and group_key = 'social')
             or (kind = 'round_finished' and group_key = 'game')) <> 9
     or exists (select 1 from public.activity a where public.push_group(a.category, a.kind) is null) then
    v_fail := v_fail || ' 4';
  end if;
  -- 5. Triggerne.
  if (select count(*) from pg_trigger where not tgisinternal
        and ((tgname = 'rounds_round_finished' and tgrelid = 'public.rounds'::regclass)
          or (tgname = 'rounds_delete_personal' and tgrelid = 'public.rounds'::regclass)
          or (tgname = 'follows_after_delete' and tgrelid = 'public.follows'::regclass)
          or (tgname = 'user_blocks_drop_follows' and tgrelid = 'public.user_blocks'::regclass)
          or (tgname = 'profiles_follow_approval_off' and tgrelid = 'public.profiles'::regclass))) <> 5 then
    v_fail := v_fail || ' 5';
  end if;
  -- 6. Hver låste vanlige runde har en round_finished per spiller med innlogging, og ingen dobbel.
  if exists (select 1 from public.rounds r
               join public.round_players rp on rp.round_id = r.id
               left join public.club_members cm on cm.id = rp.member_id and rp.club_id is not null and cm.status = 'active'
               left join public.round_participants pt on pt.id = rp.member_id and rp.club_id is null
              where r.status = 'locked' and r.kind = 'normal' and coalesce(cm.user_id, pt.profile_id) is not null
                and not exists (select 1 from public.activity a
                                 where a.kind = 'round_finished' and a.round_id = r.id
                                   and a.actor_profile_id = coalesce(cm.user_id, pt.profile_id)))
     or exists (select 1 from public.activity where kind = 'round_finished'
                 group by round_id, actor_profile_id having count(*) > 1)
     or exists (select 1 from public.activity
                 where kind = 'round_finished' and (club_id is not null or competition_id is not null
                                                     or recipients is not null)) then
    v_fail := v_fail || ' 6';
  end if;
  -- 7. Ingen følging mellom blokkerte, ingen følging av seg selv.
  if exists (select 1 from public.follows f join public.user_blocks b
               on (b.blocker_id = f.follower_id and b.blocked_id = f.followee_id)
               or (b.blocker_id = f.followee_id and b.blocked_id = f.follower_id)) then
    v_fail := v_fail || ' 7';
  end if;
  -- 8. Koden er ikke på profilen, og koder har riktig form.
  if exists (select 1 from public.follow_codes where code !~ '^[A-HJ-NP-Z2-9]{8}$') then
    v_fail := v_fail || ' 8';
  end if;
  -- 9. Kommentarer uten klubb og turnering står bare på personlige linjer.
  if exists (select 1 from public.comments c
              where c.club_id is null and c.competition_id is null and c.deleted_at is null
                and not exists (select 1 from public.activity a
                                 where c.target_kind = 'activity' and a.id = c.target_id
                                   and a.club_id is null and a.competition_id is null)) then
    v_fail := v_fail || ' 9';
  end if;
  -- 10. Senderens funksjon er fortsatt bare for service_role, og alle jobber gir svar.
  if has_function_privilege('authenticated', 'public.push_job_payload(bigint)', 'execute')
     or exists (select 1 from public.push_queue q where public.push_job_payload(q.id) is null) then
    v_fail := v_fail || ' 10';
  end if;

  if v_fail <> '' then
    raise exception '054 kontroll feilet:%', v_fail;
  end if;
  raise notice '054 kontroll: 10 av 10 (følging: %, koder: %, ferdige runder: %, låste runder: %)',
    (select count(*) from public.follows),
    (select count(*) from public.follow_codes),
    (select count(*) from public.activity where kind = 'round_finished'),
    (select count(*) from public.rounds where status = 'locked' and kind = 'normal');
end $$;

commit;

-- ===========================================================================
-- RULLEBAKKE (før appen bruker følging)
-- ===========================================================================
-- Følging, koder, «Følger»-kortene og kommentarene og reaksjonene på dem går tapt.
-- begin;
-- (gjenopprett fra 050_sosialt.sql: delete_account_data, push_job_payload, push_group_map,
--  comment_delete, comment_add, comment_notify, user_can_read_target, can_read_target,
--  target_info, policyen activity_select, activity_before_insert og report_content;
--  push_enqueue_activity fra 046_varsler.sql; activity_fill_competition fra
--  031_turnering_kjerne_trinn1.sql; block_user og can_see_profile fra 019_konto_og_moderering.sql;
--  known_profiles fra 037_mengde_rpc.sql)
-- delete from public.comments c using public.activity a
--  where c.target_kind = 'activity' and c.target_id = a.id and a.club_id is null and a.competition_id is null;
-- delete from public.push_queue q where q.club_id is null and q.competition_id is null;
-- alter table public.push_queue drop constraint if exists push_queue_club_or_competition;
-- alter table public.push_queue add constraint push_queue_club_or_competition
--   check (club_id is not null or competition_id is not null);
-- delete from public.activity where club_id is null and competition_id is null;
-- drop trigger if exists rounds_delete_personal on public.rounds;
-- drop function if exists private.rounds_delete_personal();
-- drop trigger if exists rounds_round_finished on public.rounds;
-- drop function if exists private.rounds_round_finished();
-- drop function if exists private.round_finished_insert(uuid);
-- drop function if exists public.following_feed_page(timestamptz, uuid, integer);
-- drop trigger if exists user_blocks_drop_follows on public.user_blocks;
-- drop function if exists private.user_blocks_drop_follows();
-- drop function if exists public.search_people(text, integer);
-- drop function if exists public.my_follows();
-- drop trigger if exists follows_after_delete on public.follows;
-- drop function if exists private.follows_after_delete();
-- drop trigger if exists profiles_follow_approval_off on public.profiles;
-- drop function if exists private.profiles_follow_approval_off();
-- drop function if exists public.follow_settings(boolean, boolean);
-- drop function if exists public.follow_by_code(text, text);
-- drop function if exists public.follow_code(boolean);
-- drop function if exists public.follower_remove(uuid);
-- drop function if exists public.follow_remove(uuid);
-- drop function if exists public.follow_respond(uuid, boolean);
-- drop function if exists public.follow_request(uuid, text);
-- drop function if exists private.new_follow_code();
-- drop function if exists private.follow_notify(text, uuid, uuid, text);
-- drop function if exists private.people_rate_hit(text, uuid, integer, interval, text);
-- drop function if exists private.follow_any_between(uuid, uuid);
-- drop function if exists private.follow_accepted_between(uuid, uuid);
-- (etter at activity_select og can_read_target er satt tilbake:)
-- drop function if exists private.personal_activity_visible(uuid, uuid, uuid[], uuid);
-- drop index if exists public.activity_round_finished_once;
-- drop index if exists public.activity_actor_profile_idx;
-- alter table public.activity drop constraint if exists activity_club_or_competition;
-- alter table public.activity add constraint activity_club_or_competition
--   check (club_id is not null or competition_id is not null);
-- alter table public.activity drop column if exists actor_profile_id;
-- drop table if exists private.people_rate_log;
-- drop table if exists public.follow_codes;
-- drop table if exists public.follows;   -- også ut av supabase_realtime
-- alter table public.profiles drop column if exists searchable, drop column if exists follow_approval;
-- commit;
