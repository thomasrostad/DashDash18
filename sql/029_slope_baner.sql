-- ===========================================================================
-- 029 – BANER FRA SLOPE.NO: TEES, TEE PÅ RUNDEN OG SYNK-STATUS – KJØRT PÅ TEST 08.10.2026
-- ===========================================================================
-- Status: kjørt på test 08.10.2026. Prøvd mot en lokal, midlertidig Postgres (kjørt
-- to ganger på rad etter 001–026, kontrollen nederst gir ok på alle rader).
-- 027 og 028 er reservert for fase 19. 029 rører ingen av tabellene fase 19
-- jobber med (activity, push), og kan kjøres før eller etter dem.
--
-- Hvorfor (fase 20, 08.10.2026): slope.no har et åpent API med 1306 nordiske
-- baner, hver med flere tees (navn, herre/dame, course rating, slope, par).
-- Eieren ber bare om kreditering og lenke. ROADMAP: brukerne legger inn baner
-- i et felles bibliotek, og skjemaet gjøres klart for en ekstern kilde, med
-- ekstern id, kilde og når banen sist ble hentet (017). Lokale rettelser
-- (course_corrections, 019) skal overleve en ny henting.
--
-- Hva fila gjør:
--   1. courses får city, country (ISO-kode, NO/SE/…) og missing_at («borte
--      fra kilden siden»). Hentede baner slettes aldri: forsvinner en bane fra
--      kilden, markeres den. Vakta fra 017 får missing_at i lista over felt
--      bare serveren setter.
--   2. course_tees: flere tees per bane (navn, kjønn, CR, slope, par,
--      rekkefølge). Lesing som course_holes: klubbens baner for medlemmer, det
--      felles biblioteket for alle innloggede. Skriving: tees uten kilde, av den
--      som kan rette banen (arrangøren, eller den som la inn en felles bane).
--      Tees med kilde skriver bare serveren (service_role, synken).
--      save_course_tees(bane, tees) lagrer en banes egne tees i én transaksjon.
--   3. rounds får tee_id, tee_name, course_rating og slope_rating: teen runden
--      spilles fra, og tallene slik de var da runden startet. Triggeren
--      rounds_tee_snapshot henter tallene fra teen (appen kan ikke sende egne),
--      følger teen så lenge runden er kladd, og fryser dem ved start. Uten tee
--      er alt tomt, og banens CR og slope gjelder som før.
--   4. start_loose_round (018) tar valgfritt tee_id i oppsettet. Ellers lik.
--   5. course_feeds: én rad per kilde med data_version, når den sist ble
--      sjekket og synket, antall og siste feil. Bare serveren leser og skriver.
--   6. course_feed_apply(…) og course_feed_note(…): synken (Edge Function
--      slope-sync, service_role) skriver baner og tees i én transaksjon.
--
-- Hvorfor tallene lagres på runden (et bevisst unntak fra «regn ut, ikke
-- lagre»): CR og slope er rådata for runden, ikke noe som regnes ut. En tee kan
-- bli re-ratet, og synken oppdaterer da course_tees. Uten et øyeblikksbilde
-- ville en gammel runde fått nye tall, nytt banehandicap og nye poeng i
-- ettertid. Spillehandicapet fryses alt ved start (round_players.
-- playing_handicap i klubbrunder), men løse runder, statistikken (WHS-
-- differanser) og tavla regner fra CR og slope. Med øyeblikksbildet regner
-- alle med de samme tallene som spillerne så da de startet.
--
-- Rettelser overlever en ny henting: synken skriver bare courses og
-- course_tees for rader med kilde (source = 'slope'). Den rører aldri
-- course_corrections (019), brukernes egne baner (source tom) eller klubbenes
-- baner. Rettelsene ligger i sin egen tabell og legges oppå i appen.
--
-- Mønsteret fra 001–026: én transaksjon, idempotent (kan kjøres to ganger),
-- set search_path = '', revoke/grant etter hver funksjon.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. COURSES: STED OG «BORTE FRA KILDEN»
-- ===========================================================================
alter table public.courses
  add column if not exists city       text check (city is null or char_length(city) <= 80),
  add column if not exists country    text check (country is null or country ~ '^[A-Z]{2}$'),
  add column if not exists missing_at timestamptz;
comment on column public.courses.city is 'Stedet banen ligger (fra kilden), for søk.';
comment on column public.courses.country is 'Landkode (ISO 3166-1 alfa-2, f.eks. NO), for søk og sortering.';
comment on column public.courses.missing_at is
  'Banen er borte fra kilden siden dette tidspunktet. Hentede baner slettes aldri, runder kan peke på dem.';

-- Søk i biblioteket fra kilden (navn, sted og land), bare hentede baner.
create index if not exists courses_source_idx
  on public.courses (source, country) where source is not null;

-- Vakta fra 017, med missing_at blant feltene bare serveren setter.
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
    if new.source is not null or new.external_id is not null or new.fetched_at is not null
       or new.missing_at is not null then
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
       or new.fetched_at is distinct from old.fetched_at
       or new.missing_at is distinct from old.missing_at then
      raise exception 'Kilden til banen endres bare av serveren' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.courses_guard_library() from public, anon, authenticated;


-- ===========================================================================
-- 2. COURSE_TEES: FLERE TEES PER BANE
-- ===========================================================================
create table if not exists public.course_tees (
  id             uuid primary key default gen_random_uuid(),
  course_id      uuid not null references public.courses(id) on delete cascade,
  -- Kilden (f.eks. slope) og teens id der. Tom = lagt inn av en bruker eller klubb.
  source         text check (source is null or source ~ '^[a-z0-9_-]{1,30}$'),
  external_id    text check (external_id is null or char_length(external_id) <= 100),
  name           text not null check (char_length(btrim(name)) between 1 and 60),
  gender         text not null check (gender in ('men', 'women', 'mixed')),
  course_rating  numeric(4,1) not null check (course_rating between 20 and 90),
  slope_rating   smallint not null check (slope_rating between 55 and 155),
  -- Teens par (18 eller 9 hull). Banens par per hull står fortsatt i course_holes.
  par            smallint check (par between 27 and 80),
  sort_order     smallint not null default 0 check (sort_order between 0 and 999),
  fetched_at     timestamptz,
  missing_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint course_tees_external_whole check (external_id is null or source is not null)
);
comment on table public.course_tees is
  'Tees per bane: navn, kjønn, course rating, slope og par. Med kilde skrives de bare av serveren '
  '(synken); uten kilde av den som kan rette banen. Hentede tees slettes aldri, de markeres med missing_at.';
create unique index if not exists course_tees_external_key
  on public.course_tees (source, external_id) where external_id is not null;
create unique index if not exists course_tees_unique_manual
  on public.course_tees (course_id, lower(btrim(name)), gender) where source is null;
create index if not exists course_tees_course_idx on public.course_tees (course_id, sort_order);

drop trigger if exists course_tees_set_updated_at on public.course_tees;
create trigger course_tees_set_updated_at before update on public.course_tees
  for each row execute function public.set_updated_at();

-- Vakt: kilde, ekstern id og tidspunktene for hentingen settes bare av
-- serveren, og en tee flyttes ikke til en annen bane fra appen.
create or replace function public.course_tees_guard()
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
    if new.source is not null or new.external_id is not null or new.fetched_at is not null
       or new.missing_at is not null then
      raise exception 'Hentede tees legges inn av serveren' using errcode = '42501';
    end if;
  elsif new.course_id is distinct from old.course_id
        or new.source is distinct from old.source
        or new.external_id is distinct from old.external_id
        or new.fetched_at is distinct from old.fetched_at
        or new.missing_at is distinct from old.missing_at then
    raise exception 'Kilden til teen endres bare av serveren' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.course_tees_guard() from public, anon, authenticated;

drop trigger if exists course_tees_guard on public.course_tees;
create trigger course_tees_guard
  before insert or update on public.course_tees
  for each row execute function public.course_tees_guard();

alter table public.course_tees enable row level security;

drop policy if exists course_tees_select on public.course_tees;
drop policy if exists course_tees_insert on public.course_tees;
drop policy if exists course_tees_update on public.course_tees;
drop policy if exists course_tees_delete on public.course_tees;
-- Lesing som course_holes (017): klubbens baner for medlemmer, det felles
-- biblioteket for alle innloggede.
create policy course_tees_select on public.course_tees
  for select to authenticated
  using (exists (select 1 from public.courses c
                 where c.id = course_id
                   and (public.is_club_member(c.club_id) or c.club_id is null)));
-- Skriving: bare tees uten kilde, på en bane du kan rette (arrangøren for
-- klubbens baner, den som la inn en felles bane uten kilde).
create policy course_tees_insert on public.course_tees
  for insert to authenticated
  with check (source is null
              and exists (select 1 from public.courses c
                          where c.id = course_id
                            and (public.is_club_organizer(c.club_id)
                                 or (c.club_id is null and c.source is null
                                     and c.created_by_profile = auth.uid()))));
create policy course_tees_update on public.course_tees
  for update to authenticated
  using (source is null
         and exists (select 1 from public.courses c
                     where c.id = course_id
                       and (public.is_club_organizer(c.club_id)
                            or (c.club_id is null and c.source is null
                                and c.created_by_profile = auth.uid()))))
  with check (source is null
              and exists (select 1 from public.courses c
                          where c.id = course_id
                            and (public.is_club_organizer(c.club_id)
                                 or (c.club_id is null and c.source is null
                                     and c.created_by_profile = auth.uid()))));
create policy course_tees_delete on public.course_tees
  for delete to authenticated
  using (source is null
         and exists (select 1 from public.courses c
                     where c.id = course_id
                       and (public.is_club_organizer(c.club_id)
                            or (c.club_id is null and c.source is null
                                and c.created_by_profile = auth.uid()))));

revoke all on table public.course_tees from public, anon, authenticated;
grant select, insert, update, delete on table public.course_tees to authenticated;
grant select, insert, update, delete on table public.course_tees to service_role;


-- --- save_course_tees: en banes egne tees i én transaksjon ------------------
-- SECURITY INVOKER: RLS avgjør. Først en tom oppdatering av banen, så vet vi
-- at du kan rette den (arrangøren, eller den som la inn en felles bane uten
-- kilde). p_tees: [{name, gender, course_rating, slope_rating, par, sort_order}].
-- Tees med samme navn og kjønn beholder id-en (runder peker på den). Tees uten
-- kilde som ikke står i lista, slettes; runder som brukte dem, beholder navnet
-- og tallene (rounds_tee_snapshot). Returnerer antall tees banen har etterpå.
create or replace function public.save_course_tees(p_course_id uuid, p_tees jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_n  integer;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_tees, '[]'::jsonb)) <> 'array' then
    raise exception 'Teene må være en liste' using errcode = '22023';
  end if;
  if jsonb_array_length(coalesce(p_tees, '[]'::jsonb)) > 120 then
    raise exception 'For mange tees på én bane' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(coalesce(p_tees, '[]'::jsonb)) e)
     <> (select count(distinct (lower(btrim(e ->> 'name')), e ->> 'gender'))
           from jsonb_array_elements(coalesce(p_tees, '[]'::jsonb)) e) then
    raise exception 'To tees har samme navn og kjønn' using errcode = '22023';
  end if;

  update public.courses c set updated_at = now()
   where c.id = p_course_id
  returning c.id into v_id;
  if v_id is null then
    raise exception 'Bare den som kan rette banen, kan endre teene' using errcode = '42501';
  end if;

  delete from public.course_tees t
   where t.course_id = v_id
     and t.source is null
     and not exists (select 1 from jsonb_array_elements(coalesce(p_tees, '[]'::jsonb)) e
                      where lower(btrim(e ->> 'name')) = lower(btrim(t.name))
                        and e ->> 'gender' = t.gender);

  insert into public.course_tees (course_id, name, gender, course_rating, slope_rating, par, sort_order)
  select v_id,
         btrim(e ->> 'name'),
         e ->> 'gender',
         (e ->> 'course_rating')::numeric,
         (e ->> 'slope_rating')::smallint,
         (e ->> 'par')::smallint,
         coalesce((e ->> 'sort_order')::smallint, 0)
    from jsonb_array_elements(coalesce(p_tees, '[]'::jsonb)) e
  on conflict (course_id, (lower(btrim(name))), gender) where source is null do update
     set name = excluded.name,
         course_rating = excluded.course_rating,
         slope_rating = excluded.slope_rating,
         par = excluded.par,
         sort_order = excluded.sort_order;

  select count(*) into v_n from public.course_tees t where t.course_id = v_id;
  return v_n;
end;
$$;
revoke all on function public.save_course_tees(uuid, jsonb) from public, anon;
grant execute on function public.save_course_tees(uuid, jsonb) to authenticated;


-- ===========================================================================
-- 3. ROUNDS: TEEN RUNDEN SPILLES FRA, MED TALLENE SLIK DE VAR VED START
-- ===========================================================================
alter table public.rounds
  add column if not exists tee_id        uuid references public.course_tees(id) on delete set null,
  add column if not exists tee_name      text check (tee_name is null or char_length(tee_name) <= 60),
  add column if not exists course_rating numeric(4,1) check (course_rating between 20 and 90),
  add column if not exists slope_rating  smallint check (slope_rating between 55 and 155);
comment on column public.rounds.tee_id is
  'Teen runden spilles fra (ekte bane). Tom = banens CR og slope gjelder, som før.';
comment on column public.rounds.course_rating is
  'Teens course rating da runden startet (settes av rounds_tee_snapshot, ikke av appen).';
comment on column public.rounds.slope_rating is
  'Teens slope da runden startet (settes av rounds_tee_snapshot, ikke av appen).';
create index if not exists rounds_tee_idx on public.rounds (tee_id) where tee_id is not null;

-- Henter navn, CR og slope fra teen. Appen sender bare tee_id.
--   * Kladd: tallene følger teen (en re-rating før start tas med).
--   * Startet eller låst: tallene står. Teen kan ikke byttes.
--   * Teen slettes (on delete set null): navn og tall blir stående.
--   * Teen må høre til rundens bane.
create or replace function public.rounds_tee_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tee public.course_tees;
begin
  if tg_op = 'UPDATE' and new.tee_id is null and old.tee_id is not null
     and not exists (select 1 from public.course_tees t where t.id = old.tee_id) then
    -- Teen er slettet: runden beholder det den ble spilt med.
    new.tee_name := old.tee_name;
    new.course_rating := old.course_rating;
    new.slope_rating := old.slope_rating;
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status <> 'draft' then
    if new.tee_id is distinct from old.tee_id then
      raise exception 'Teen kan bare velges før runden starter' using errcode = '22023';
    end if;
    new.tee_name := old.tee_name;
    new.course_rating := old.course_rating;
    new.slope_rating := old.slope_rating;
  elsif new.tee_id is null then
    new.tee_name := null;
    new.course_rating := null;
    new.slope_rating := null;
  else
    select t.* into v_tee from public.course_tees t where t.id = new.tee_id;
    if not found then
      raise exception 'Fant ikke teen' using errcode = '22023';
    end if;
    new.tee_name := v_tee.name;
    new.course_rating := v_tee.course_rating;
    new.slope_rating := v_tee.slope_rating;
  end if;

  if new.tee_id is not null
     and (tg_op = 'INSERT' or new.tee_id is distinct from old.tee_id or new.course_id is distinct from old.course_id)
     and not exists (select 1 from public.course_tees t
                     where t.id = new.tee_id and t.course_id is not distinct from new.course_id) then
    raise exception 'Teen hører til en annen bane' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.rounds_tee_snapshot() from public, anon, authenticated;

drop trigger if exists rounds_tee_snapshot on public.rounds;
create trigger rounds_tee_snapshot
  before insert or update on public.rounds
  for each row execute function public.rounds_tee_snapshot();


-- ===========================================================================
-- 4. START_LOOSE_ROUND (fra 018): valgfritt tee_id i oppsettet
-- ===========================================================================
-- Samme kropp, signatur og rettigheter som i 018. Eneste endring: tee_id fra
-- oppsettet går inn i rundens rad (tom = ingen tee). rounds_tee_snapshot
-- henter tallene og sjekker at teen hører til banen.
create or replace function public.start_loose_round(p_setup jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me       public.profiles;
  v_round    uuid;
  v_players  jsonb;
  v_entry    jsonb;
  v_seats    jsonb := '[]'::jsonb;
  v_ids      uuid[] := '{}';
  v_prof     uuid;
  v_name     text;
  v_id       uuid;
  v_i        integer;
  v_m        jsonb;
  v_no       integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;
  if jsonb_typeof(p_setup) is distinct from 'object' then
    raise exception 'Oppsettet mangler' using errcode = '22023';
  end if;
  v_players := coalesce(p_setup -> 'players', '[]'::jsonb);
  if jsonb_typeof(v_players) <> 'array' or jsonb_typeof(coalesce(p_setup -> 'matches', '[]'::jsonb)) <> 'array' then
    raise exception 'Spillerlista og matchlista må være lister' using errcode = '22023';
  end if;
  if jsonb_array_length(v_players) > 47 then
    raise exception 'For mange spillere i én runde' using errcode = '22023';
  end if;

  v_me := public.ensure_profile();

  insert into public.rounds (club_id, event_id, course_id, tee_id, hole_count, first_hole, format, venue,
                             handicap_allowance, external_handicap, ld_enabled, ld_hole_index,
                             kp_enabled, kp_hole_index, status)
  values (null, null, (p_setup ->> 'course_id')::uuid,
          nullif(p_setup ->> 'tee_id', '')::uuid,
          coalesce((p_setup ->> 'hole_count')::smallint, 18),
          coalesce((p_setup ->> 'first_hole')::smallint, 1),
          coalesce(p_setup ->> 'format', 'stableford'),
          coalesce(p_setup ->> 'venue', 'simulator'),
          coalesce((p_setup ->> 'handicap_allowance')::numeric, 1),
          coalesce((p_setup ->> 'external_handicap')::boolean, false),
          coalesce((p_setup ->> 'ld_enabled')::boolean, true),
          (p_setup ->> 'ld_hole_index')::smallint,
          coalesce((p_setup ->> 'kp_enabled')::boolean, true),
          (p_setup ->> 'kp_hole_index')::smallint,
          'draft')
  returning id into v_round;

  -- Deg først, så lista i rekkefølge. Indeksene i matchene peker hit.
  insert into public.round_participants (round_id, profile_id, display_name)
  values (v_round, v_me.id, coalesce(v_me.display_name, 'Meg'))
  returning id into v_id;
  v_ids := v_ids || v_id;
  v_seats := v_seats || jsonb_build_array(coalesce(p_setup -> 'me', '{}'::jsonb));

  for v_entry in select value from jsonb_array_elements(v_players) loop
    v_prof := nullif(v_entry ->> 'profile_id', '')::uuid;
    if v_prof is not null then
      if v_prof = v_me.id then
        raise exception 'Du står allerede først på lista' using errcode = '22023';
      end if;
      if not public.can_see_profile(v_prof) then
        raise exception 'Du kan bare legge til folk du kjenner fra en klubb, runde eller konkurranse'
          using errcode = '42501';
      end if;
      select p.display_name into v_name from public.profiles p where p.id = v_prof;
      insert into public.round_participants (round_id, profile_id, display_name)
      values (v_round, v_prof, coalesce(v_name, 'Spiller'))
      returning id into v_id;
    else
      v_name := btrim(coalesce(v_entry ->> 'guest_name', ''));
      if v_name = '' then
        raise exception 'En gjest må ha et navn' using errcode = '22023';
      end if;
      insert into public.round_participants (round_id, display_name, handicap_index)
      values (v_round, v_name, (v_entry ->> 'handicap_index')::numeric)
      returning id into v_id;
    end if;
    v_ids := v_ids || v_id;
    v_seats := v_seats || jsonb_build_array(v_entry);
  end loop;

  -- Flight og markør per deltaker (én markør per flight, sjekket av indeksen fra 001).
  for v_i in 1 .. cardinality(v_ids) loop
    update public.round_players rp
       set bay_no = (v_seats -> (v_i - 1) ->> 'bay_no')::smallint,
           is_marker = coalesce((v_seats -> (v_i - 1) ->> 'is_marker')::boolean, false)
     where rp.round_id = v_round and rp.member_id = v_ids[v_i];
  end loop;

  -- Matcher med indekser i deltakerlista. En indeks utenfor lista gir null, og
  -- da stopper sjekken på round_matches (minst to spillere).
  for v_m in select value from jsonb_array_elements(coalesce(p_setup -> 'matches', '[]'::jsonb)) loop
    v_no := v_no + 1;
    insert into public.round_matches (round_id, match_no, player_a, player_b, player_c)
    values (v_round, v_no,
            v_ids[(v_m ->> 'a')::integer + 1],
            v_ids[(v_m ->> 'b')::integer + 1],
            v_ids[(v_m ->> 'c')::integer + 1]);
  end loop;

  if coalesce((p_setup ->> 'start')::boolean, true) then
    -- rounds_freeze_participants (017) fryser handicapet.
    update public.rounds set status = 'active', par_confirmed_at = now() where id = v_round;
  end if;

  return jsonb_build_object(
    'round_id', v_round,
    'status', (select r.status from public.rounds r where r.id = v_round),
    'participants', (select jsonb_agg(jsonb_build_object('id', p.id, 'profile_id', p.profile_id,
                                                         'display_name', p.display_name)
                                      order by array_position(v_ids, p.id))
                     from public.round_participants p where p.round_id = v_round)
  );
end;
$$;
revoke all on function public.start_loose_round(jsonb) from public, anon;
grant execute on function public.start_loose_round(jsonb) to authenticated;


-- ===========================================================================
-- 5. COURSE_FEEDS: SYNK-STATUS PER KILDE
-- ===========================================================================
create table if not exists public.course_feeds (
  source        text primary key check (source ~ '^[a-z0-9_-]{1,30}$'),
  -- Kildens versjon av dataene (slope.no: meta.data_version). Ny versjon = hent alt.
  data_version  text check (data_version is null or char_length(data_version) <= 100),
  generated_at  timestamptz,
  -- Sist meta ble sjekket, og sist en ny versjon ble skrevet.
  checked_at    timestamptz,
  synced_at     timestamptz,
  courses       integer,
  tees          integer,
  missing       integer,
  last_error    text check (last_error is null or char_length(last_error) <= 500),
  updated_at    timestamptz not null default now()
);
comment on table public.course_feeds is
  'Synk-status per ekstern banekilde (slope.no). Bare serveren (service_role) leser og skriver.';

drop trigger if exists course_feeds_set_updated_at on public.course_feeds;
create trigger course_feeds_set_updated_at before update on public.course_feeds
  for each row execute function public.set_updated_at();

alter table public.course_feeds enable row level security;
-- Ingen policy: appen ser ikke tabellen. service_role går forbi RLS.
revoke all on table public.course_feeds from public, anon, authenticated;
grant select, insert, update on table public.course_feeds to service_role;


-- ===========================================================================
-- 6. SYNKEN: SKRIV BANER OG TEES FRA EN KILDE I ÉN TRANSAKSJON
-- ===========================================================================
-- course_feed_apply: bare service_role (Edge Function slope-sync).
--   p_courses: banene som er nye eller endret, ferdig vasket i synken:
--     [{external_id, name, city, country, course_rating, slope_rating,
--       tees: [{external_id, name, gender, course_rating, slope_rating, par, sort_order}]}]
--   p_present: id-ene til ALLE banene i kildens eksport.
--   p_data_version: kildens versjon. Store synker sendes i deler: alle delene
--     unntatt den siste har tom versjon og bare skriver banene sine. Den siste
--     (med versjon) markerer hva som er borte og skriver statusen. Feiler en
--     del, er versjonen ikke lagret, og neste kjøring prøver alt på nytt.
-- Hva den gjør:
--   * upsert av banene på (source, external_id): felles bibliotek (club_id
--     tom), ekte bane, i bruk. Navn, sted, land og banens CR/slope (fra
--     standard-teen) oppdateres. Banen er ikke lenger «borte».
--   * upsert av teene på (source, external_id). Tees på en endret bane som
--     ikke lenger står i kilden, markeres borte (slettes ikke).
--   * fetched_at = nå for alle banene i eksporten. Baner fra kilden som ikke
--     står i eksporten, markeres borte (missing_at), slettes aldri.
--   * course_feeds får versjonen og antallene.
-- Den rører aldri course_holes, course_corrections, baner uten kilde eller
-- klubbenes baner.
create or replace function public.course_feed_apply(
  p_source        text,
  p_data_version  text,
  p_generated_at  timestamptz,
  p_courses       jsonb,
  p_present       text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_courses  integer := 0;
  v_tees     integer := 0;
  v_gone     integer := 0;
  v_gonetees integer := 0;
  v_total    integer;
  v_now      timestamptz := now();
begin
  if p_source is null or p_source !~ '^[a-z0-9_-]{1,30}$' then
    raise exception 'Ugyldig kilde' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_courses, '[]'::jsonb)) <> 'array' then
    raise exception 'Banene må være en liste' using errcode = '22023';
  end if;
  if p_data_version is not null and coalesce(cardinality(p_present), 0) = 0 then
    -- En tom eksport ville markert alle banene som borte. Da er noe galt hos kilden.
    raise exception 'Eksporten er tom' using errcode = '22023';
  end if;

  insert into public.courses (club_id, name, kind, source, external_id, city, country,
                              course_rating, slope_rating, in_use, fetched_at, missing_at)
  select null, btrim(x.name), 'course', p_source, x.external_id,
         nullif(btrim(x.city), ''), x.country, x.course_rating, x.slope_rating, true, v_now, null
    from jsonb_to_recordset(coalesce(p_courses, '[]'::jsonb))
         as x(external_id text, name text, city text, country text, course_rating numeric, slope_rating smallint)
  on conflict (source, external_id) where external_id is not null do update
     set name = excluded.name,
         kind = 'course',
         city = excluded.city,
         country = excluded.country,
         course_rating = excluded.course_rating,
         slope_rating = excluded.slope_rating,
         fetched_at = excluded.fetched_at,
         missing_at = null;
  get diagnostics v_courses = row_count;

  insert into public.course_tees (course_id, source, external_id, name, gender, course_rating,
                                  slope_rating, par, sort_order, fetched_at, missing_at)
  select c.id, p_source, t.external_id, btrim(t.name), t.gender, t.course_rating,
         t.slope_rating, t.par, coalesce(t.sort_order, 0), v_now, null
    from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
    join public.courses c on c.source = p_source and c.external_id = e ->> 'external_id'
    cross join lateral jsonb_to_recordset(coalesce(e -> 'tees', '[]'::jsonb))
         as t(external_id text, name text, gender text, course_rating numeric, slope_rating smallint,
              par smallint, sort_order smallint)
  on conflict (source, external_id) where external_id is not null do update
     set course_id = excluded.course_id,
         name = excluded.name,
         gender = excluded.gender,
         course_rating = excluded.course_rating,
         slope_rating = excluded.slope_rating,
         par = excluded.par,
         sort_order = excluded.sort_order,
         fetched_at = excluded.fetched_at,
         missing_at = null;
  get diagnostics v_tees = row_count;

  -- Tees på en endret bane som ikke lenger står i kilden: borte, ikke slettet.
  update public.course_tees t
     set missing_at = v_now
    from public.courses c
   where c.id = t.course_id
     and t.source = p_source
     and t.missing_at is null
     and c.source = p_source
     and c.external_id in (select e ->> 'external_id' from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e)
     and not exists (select 1
                       from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
                       cross join lateral jsonb_array_elements(coalesce(e -> 'tees', '[]'::jsonb)) x
                      where x ->> 'external_id' = t.external_id);
  get diagnostics v_gonetees = row_count;

  if p_data_version is null then
    -- En del av en større synk: resten gjør siste del.
    return jsonb_build_object('courses_written', v_courses, 'tees_written', v_tees, 'tees_missing', v_gonetees);
  end if;

  -- Alle banene i eksporten er hentet nå. De andre fra kilden er borte.
  update public.courses c
     set fetched_at = v_now, missing_at = null
   where c.source = p_source and c.external_id = any(p_present)
     and (c.fetched_at is distinct from v_now or c.missing_at is not null);
  update public.courses c
     set missing_at = v_now
   where c.source = p_source and c.missing_at is null
     and not (c.external_id = any(p_present));
  get diagnostics v_gone = row_count;

  select count(*) into v_total from public.courses c where c.source = p_source and c.missing_at is null;

  insert into public.course_feeds (source, data_version, generated_at, checked_at, synced_at,
                                   courses, tees, missing, last_error)
  values (p_source, p_data_version, p_generated_at, v_now, v_now, v_total,
          (select count(*) from public.course_tees t where t.source = p_source and t.missing_at is null),
          (select count(*) from public.courses c where c.source = p_source and c.missing_at is not null),
          null)
  on conflict (source) do update
     set data_version = excluded.data_version,
         generated_at = excluded.generated_at,
         checked_at = excluded.checked_at,
         synced_at = excluded.synced_at,
         courses = excluded.courses,
         tees = excluded.tees,
         missing = excluded.missing,
         last_error = null;

  return jsonb_build_object('courses_written', v_courses, 'tees_written', v_tees,
                            'courses_missing', v_gone, 'tees_missing', v_gonetees,
                            'courses_total', v_total);
end;
$$;
revoke all on function public.course_feed_apply(text, text, timestamptz, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.course_feed_apply(text, text, timestamptz, jsonb, text[]) to service_role;

-- course_feed_note: synken sjekket meta. Uten ny versjon (eller ved feil)
-- skrives bare når og eventuelt hva som gikk galt. Versjonen røres ikke:
-- den endres bare av course_feed_apply, så en feilet henting prøves igjen.
create or replace function public.course_feed_note(p_source text, p_error text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_source is null or p_source !~ '^[a-z0-9_-]{1,30}$' then
    raise exception 'Ugyldig kilde' using errcode = '22023';
  end if;
  insert into public.course_feeds (source, checked_at, last_error)
  values (p_source, now(), left(p_error, 500))
  on conflict (source) do update
     set checked_at = excluded.checked_at,
         last_error = excluded.last_error;
end;
$$;
revoke all on function public.course_feed_note(text, text) from public, anon, authenticated;
grant execute on function public.course_feed_note(text, text) to service_role;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Alle rader skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname, p.prosrc, p.prosecdef, p.proconfig,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          has_function_privilege('service_role', p.oid, 'execute') as server_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('courses_guard_library', 'course_tees_guard', 'save_course_tees', 'rounds_tee_snapshot',
--                       'start_loose_round', 'course_feed_apply', 'course_feed_note')
-- )
-- select 1 as nr, 'courses har city, country og missing_at' as sjekk,
--        (select count(*) = 3 from information_schema.columns
--          where table_schema = 'public' and table_name = 'courses'
--            and column_name in ('city', 'country', 'missing_at')) as ok
-- union all
-- select 2, 'course_tees finnes med RLS på og fire policyer',
--        (select relrowsecurity from pg_class where oid = 'public.course_tees'::regclass)
--        and (select count(*) = 4 from pg_policies where schemaname = 'public' and tablename = 'course_tees')
-- union all
-- select 3, 'course_tees: anon har ingenting, authenticated har select/insert/update/delete',
--        not exists (select 1 from information_schema.role_table_grants
--                     where table_schema = 'public' and table_name = 'course_tees' and grantee in ('anon', 'PUBLIC'))
--        and (select count(*) = 4 from information_schema.role_table_grants
--              where table_schema = 'public' and table_name = 'course_tees' and grantee = 'authenticated'
--                and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE'))
-- union all
-- select 4, 'Unike nøkler: kildens id og navn+kjønn for egne tees',
--        (select count(*) = 2 from pg_indexes where schemaname = 'public'
--          and indexname in ('course_tees_external_key', 'course_tees_unique_manual'))
-- union all
-- select 5, 'rounds har tee_id, tee_name, course_rating og slope_rating',
--        (select count(*) = 4 from information_schema.columns
--          where table_schema = 'public' and table_name = 'rounds'
--            and column_name in ('tee_id', 'tee_name', 'course_rating', 'slope_rating'))
-- union all
-- select 6, 'Triggerne finnes: rounds_tee_snapshot, course_tees_guard, courses_guard_library',
--        exists (select 1 from pg_trigger where tgrelid = 'public.rounds'::regclass and tgname = 'rounds_tee_snapshot')
--        and exists (select 1 from pg_trigger where tgrelid = 'public.course_tees'::regclass and tgname = 'course_tees_guard')
--        and exists (select 1 from pg_trigger where tgrelid = 'public.courses'::regclass and tgname = 'courses_guard_library')
-- union all
-- select 7, 'Vakta på courses kjenner missing_at',
--        (select prosrc like '%missing_at%' from f where proname = 'courses_guard_library')
-- union all
-- select 8, 'start_loose_round tar tee_id',
--        (select prosrc like '%tee_id%' from f where proname = 'start_loose_round')
-- union all
-- select 9, 'course_feeds: RLS på, ingen policy, appen har ingen rettigheter',
--        (select relrowsecurity from pg_class where oid = 'public.course_feeds'::regclass)
--        and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'course_feeds')
--        and not exists (select 1 from information_schema.role_table_grants
--                         where table_schema = 'public' and table_name = 'course_feeds'
--                           and grantee in ('anon', 'authenticated', 'PUBLIC'))
-- union all
-- select 10, 'Synk-funksjonene: bare service_role',
--        (select bool_and(server_kan and not auth_kan and not anon_kan) from f
--          where proname in ('course_feed_apply', 'course_feed_note'))
-- union all
-- select 11, 'save_course_tees og start_loose_round: authenticated, ikke anon',
--        (select bool_and(auth_kan and not anon_kan) from f where proname in ('save_course_tees', 'start_loose_round'))
-- union all
-- select 12, 'Alle funksjonene har tom search_path',
--        (select count(*) = 7 and bool_and('search_path=""' = any(proconfig)) from f)
-- order by nr;


-- ===========================================================================
-- ETTER MIGRERINGEN (ikke en del av fila, gjøres i Supabase-panelet)
-- ===========================================================================
-- A. Edge Function slope-sync (supabase/functions/slope-sync/), deployet med
--    --no-verify-jwt (cron sender ingen innlogging; hemmeligheten under er
--    nøkkelen). Secrets: SLOPE_SYNC_SECRET (lang, tilfeldig). SUPABASE_URL og
--    SUPABASE_SERVICE_ROLE_KEY setter Supabase selv.
-- B. Hemmeligheten i Vault, så cron kan sende den (aldri i git):
--      select vault.create_secret('<samme verdi som SLOPE_SYNC_SECRET>', 'slope_sync_secret');
-- C. Én gang i døgnet med pg_cron og pg_net (begge er på i test):
--      select cron.schedule('dd18-slope-sync', '17 3 * * *', $cron$
--        select net.http_post(
--          url := 'https://<prosjekt-id>.supabase.co/functions/v1/slope-sync',
--          headers := jsonb_build_object(
--            'content-type', 'application/json',
--            'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets
--                              where name = 'slope_sync_secret')),
--          body := '{}'::jsonb,
--          timeout_milliseconds := 120000)
--      $cron$);
--    03:17 UTC = 05:17/04:17 i Oslo, utenom kveldene. Funksjonen sjekker bare
--    meta (liten), og henter eksporten (~4 MB) bare når data_version er ny.
--    Første kjøring kan gjøres for hånd med samme select (uten cron.schedule).
-- D. Status: select * from public.course_feeds;  (bare i SQL Editor)


-- ===========================================================================
-- RULLEBAKKE (bare test, sletter alle hentede tees og synk-status)
-- ===========================================================================
-- 1. Slett cron-jobben: select cron.unschedule('dd18-slope-sync');
-- 2. Kjør avsnittene «courses_guard_library» fra 017_fundament.sql og
--    «start_loose_round» fra 018_lose_runder.sql på nytt (create or replace),
--    så ingen funksjon peker på kolonnene som fjernes.
-- 3. Kjør blokken under. Hentede baner (source = 'slope') blir liggende i
--    courses. Vil du fjerne dem, må runder som peker på dem slettes først
--    (on delete restrict).
--
-- begin;
-- drop function if exists public.course_feed_note(text, text);
-- drop function if exists public.course_feed_apply(text, text, timestamptz, jsonb, text[]);
-- drop table if exists public.course_feeds;
-- drop trigger if exists rounds_tee_snapshot on public.rounds;
-- drop function if exists public.rounds_tee_snapshot();
-- drop index if exists public.rounds_tee_idx;
-- alter table public.rounds drop column if exists slope_rating, drop column if exists course_rating,
--   drop column if exists tee_name, drop column if exists tee_id;
-- drop function if exists public.save_course_tees(uuid, jsonb);
-- drop table if exists public.course_tees;
-- drop function if exists public.course_tees_guard();
-- drop index if exists public.courses_source_idx;
-- alter table public.courses drop column if exists missing_at, drop column if exists country,
--   drop column if exists city;
-- commit;
