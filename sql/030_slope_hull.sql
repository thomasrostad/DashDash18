-- ===========================================================================
-- 030 – HULL FRA SLOPE.NO: PAR, INDEKS OG LENGDE PER TEE – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: forslag 08.10.2026 (fase 20b). Ikke kjørt på test eller prod. Prøvd
-- mot en lokal, midlertidig Postgres (se lokal/030_prove.sql). Krever 029.
--
-- Hvorfor (fase 20b, besluttet av Thomas 08.10.2026): slope.no-eksporten har
-- hull per tee i feltet tees[].holes ([hull, par, indeks, lengde]) for 6162 av
-- 9345 tees (Norge 161 av 161 baner). Fase 20 ble bygget i den tro at hullene
-- manglet, så appen lager i dag en kopi av banen der brukeren skriver inn par
-- og indeks fra scorekortet. Med hullene kan en hentet bane spilles direkte.
-- Par og indeks kan variere mellom tees på samme bane (15 baner har ulik
-- indeks, Valdres GK har par 73, 72 og 66 på tre tees), og lengden varierer
-- alltid. Derfor lagres hullene per tee.
--
-- Hva fila gjør:
--   1. course_tee_holes: hullene per tee (nummer, par, indeks, lengde). Lesing
--      som course_tees (som banen). Bare serveren skriver (service_role,
--      synken); appen har ingen skriverett. Egne tees (uten kilde) har ingen
--      hull her; banens hull i course_holes gjelder for dem som før.
--   2. course_feed_apply (029) tar imot hull, med samme signatur:
--        * tees[].holes: [[hull, par, indeks, lengde], …] erstatter teens hull.
--        * holes på banen: det samme for banens course_holes (synken velger
--          første herre-tee med hull, ellers første tee med hull). Da har en
--          hentet bane hull, regnes som «klar» (CourseReadiness) og virker i
--          all kode som leser course_holes.
--      Mangler nøkkelen holes (synken v1), røres ikke hullene. En tom liste
--      sletter dem (kilden har fjernet hullene). Bare baner og tees med kilde.
--   3. Klubbrunder kan bruke en hentet bane direkte. Fremmednøkkelen
--      rounds_course_fk (course_id, club_id) krevde at banen var klubbens egen.
--      Den byttes med triggeren rounds_guard_course: klubbens egen bane, eller
--      en hentet bane i det felles biblioteket (club_id tom, source satt).
--      rounds_course_id_fk (017) holder fortsatt banen ekte (on delete restrict).
--   4. Hullene fryses på runden når den starter (rounds_holes_snapshot): på en
--      hentet bane kopieres teens hull (eller banens, når teen ikke har egne)
--      til round_holes, rundens overstyring per hull (001), som all kode alt
--      leser (føring, tavla, statistikk, tips, spill). Samme grunn som CR og
--      slope i 029: en ny indeks hos slope.no skal ikke endre poeng i gamle
--      runder. Hull arrangøren har overstyrt selv, står (on conflict do
--      nothing). Klubbenes og brukernes egne baner røres ikke: der gjelder
--      banens hull som før (Golfgutu-pariteten).
--   5. Lagret data_version for slope nullstilles, så neste synk henter hele
--      eksporten (og synken v2 henter uansett én gang når course_tee_holes er
--      tom). Banene, teene og rundene røres ikke av dette.
--
-- Rører ikke course_corrections (019): brukernes og klubbenes rettelser ligger
-- i sin egen tabell og overlever. (Appen leser dem ikke ennå.)
--
-- Hva som skjer med det som finnes:
--   * Hentede baner (1306 på test) får hull ved neste synk, ingen nye rader nå.
--   * Kopiene brukerne har laget (source tom) er egne baner og røres ikke.
--   * Runder: ingen er spilt på hentede baner (0 på test 08.10). Startede
--     runder får ikke round_holes i ettertid; bare runder som starter etter 030.
--
-- Mønsteret fra 025–029: én transaksjon, idempotent (kan kjøres to ganger),
-- set search_path = '', revoke/grant etter hver funksjon.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. COURSE_TEE_HOLES: HULLENE PER TEE
-- ===========================================================================
create table if not exists public.course_tee_holes (
  tee_id        uuid not null references public.course_tees(id) on delete cascade,
  hole_number   smallint not null check (hole_number between 1 and 18),
  par           smallint not null check (par between 3 and 6),
  -- Indeksen på scorekortet (1–18). null = ukjent.
  stroke_index  smallint check (stroke_index between 1 and 18),
  length_m      smallint check (length_m between 50 and 700),
  primary key (tee_id, hole_number),
  constraint course_tee_holes_unique_stroke_index unique (tee_id, stroke_index)
    deferrable initially deferred
);
comment on table public.course_tee_holes is
  'Hullene per tee fra en ekstern kilde (slope.no): par, indeks og lengde. Skrives bare av serveren '
  '(synken). Runder på en hentet bane får hullene frosset i round_holes ved start (rounds_holes_snapshot).';

alter table public.course_tee_holes enable row level security;

drop policy if exists course_tee_holes_select on public.course_tee_holes;
-- Lesing som course_tees (029): klubbens baner for medlemmer, det felles
-- biblioteket for alle innloggede. Ingen policy for skriving: bare service_role.
create policy course_tee_holes_select on public.course_tee_holes
  for select to authenticated
  using (exists (select 1 from public.course_tees t
                   join public.courses c on c.id = t.course_id
                  where t.id = tee_id
                    and (public.is_club_member(c.club_id) or c.club_id is null)));

revoke all on table public.course_tee_holes from public, anon, authenticated;
grant select on table public.course_tee_holes to authenticated;
grant select, insert, update, delete on table public.course_tee_holes to service_role;


-- ===========================================================================
-- 2. SYNKEN: HULL PER TEE OG PÅ BANEN (course_feed_apply fra 029, utvidet)
-- ===========================================================================
-- Samme signatur, rettigheter og oppførsel som i 029. Nytt:
--   p_courses: [{…, holes: [[hull, par, indeks, lengde], …],
--                tees: [{…, holes: [[hull, par, indeks, lengde], …]}]}]
--   * En tee med nøkkelen holes får hullene erstattet (tom liste = ingen hull).
--   * En bane med nøkkelen holes får course_holes erstattet, bare når banen
--     har kilde (source = p_source).
--   * Uten nøkkelen (synken v1) røres ikke hullene.
-- Ugyldige hull (utenfor sjekkene i tabellene) stopper hele delen, så synken
-- vasker dem først (logic.ts: mapHoles).
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
  v_courses     integer := 0;
  v_tees        integer := 0;
  v_gone        integer := 0;
  v_gonetees    integer := 0;
  v_teeholes    integer := 0;
  v_courseholes integer := 0;
  v_total       integer;
  v_now         timestamptz := now();
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

  -- Hull per tee (030): teene som har nøkkelen holes, får hullene erstattet.
  delete from public.course_tee_holes h
   using public.course_tees ct,
         jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
         cross join lateral jsonb_array_elements(coalesce(e -> 'tees', '[]'::jsonb)) x
   where x ? 'holes'
     and ct.source = p_source and ct.external_id = x ->> 'external_id'
     and h.tee_id = ct.id;
  insert into public.course_tee_holes (tee_id, hole_number, par, stroke_index, length_m)
  select ct.id, (hh ->> 0)::smallint, (hh ->> 1)::smallint, (hh ->> 2)::smallint, (hh ->> 3)::smallint
    from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
    cross join lateral jsonb_array_elements(coalesce(e -> 'tees', '[]'::jsonb)) x
    join public.course_tees ct on ct.source = p_source and ct.external_id = x ->> 'external_id'
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x -> 'holes') = 'array'
                                                 then x -> 'holes' else '[]'::jsonb end) hh
   where x ? 'holes';
  get diagnostics v_teeholes = row_count;

  -- Banens hull (030): bare hentede baner, og bare når nøkkelen holes er med.
  delete from public.course_holes h
   using public.courses c,
         jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
   where e ? 'holes'
     and c.source = p_source and c.external_id = e ->> 'external_id'
     and h.course_id = c.id;
  insert into public.course_holes (course_id, hole_number, par, stroke_index, length_m)
  select c.id, (hh ->> 0)::smallint, (hh ->> 1)::smallint, (hh ->> 2)::smallint, (hh ->> 3)::smallint
    from jsonb_array_elements(coalesce(p_courses, '[]'::jsonb)) e
    join public.courses c on c.source = p_source and c.external_id = e ->> 'external_id'
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e -> 'holes') = 'array'
                                                 then e -> 'holes' else '[]'::jsonb end) hh
   where e ? 'holes';
  get diagnostics v_courseholes = row_count;

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
    return jsonb_build_object('courses_written', v_courses, 'tees_written', v_tees, 'tees_missing', v_gonetees,
                              'tee_holes_written', v_teeholes, 'course_holes_written', v_courseholes);
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
                            'tee_holes_written', v_teeholes, 'course_holes_written', v_courseholes,
                            'courses_total', v_total);
end;
$$;
revoke all on function public.course_feed_apply(text, text, timestamptz, jsonb, text[]) from public, anon, authenticated;
grant execute on function public.course_feed_apply(text, text, timestamptz, jsonb, text[]) to service_role;


-- ===========================================================================
-- 3. KLUBBRUNDER PÅ EN HENTET BANE
-- ===========================================================================
-- Erstatter fremmednøkkelen rounds_course_fk (001), som bare tillot klubbens
-- egne baner. En klubbrunde kan nå også bruke en hentet bane i det felles
-- biblioteket (ikke andre brukeres egne baner). Løse runder sjekkes som før av
-- rounds_guard_home (017). Brudd gir 23503 som fremmednøkkelen.
create or replace function public.rounds_guard_course()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.club_id is not null and new.course_id is not null
     and (tg_op = 'INSERT' or new.course_id is distinct from old.course_id
          or new.club_id is distinct from old.club_id)
     and not exists (select 1 from public.courses c
                      where c.id = new.course_id
                        and (c.club_id = new.club_id
                             or (c.club_id is null and c.source is not null))) then
    raise exception 'Runden må bruke en av klubbens baner eller en bane fra slope.no'
      using errcode = '23503';
  end if;
  return new;
end;
$$;
revoke all on function public.rounds_guard_course() from public, anon, authenticated;

drop trigger if exists rounds_guard_course on public.rounds;
create trigger rounds_guard_course
  before insert or update on public.rounds
  for each row execute function public.rounds_guard_course();

alter table public.rounds drop constraint if exists rounds_course_fk;


-- ===========================================================================
-- 4. HULLENE FRYSES PÅ RUNDEN VED START (bare hentede baner)
-- ===========================================================================
-- Når en runde går fra kladd til i gang (eller settes inn som i gang) på en
-- bane med kilde, kopieres hullene til round_holes:
--   * teens hull når runden har en tee med hull i course_tee_holes,
--   * ellers banens hull (course_holes, som synken skriver).
-- Rundens hull i (0-basert) er banens hull nummer i + 1, eller i + 10 for
-- «siste ni» (first_hole = 10) når kilden har 18 hull, som regelmotoren
-- (Round.courseHoles). Rader arrangøren har lagt inn selv, står.
create or replace function public.rounds_holes_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source  text;
  v_teehole boolean;
  v_count   integer;
  v_offset  integer;
begin
  if new.status = 'draft' or new.course_id is null then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status <> 'draft' then
    return null;
  end if;
  select c.source into v_source from public.courses c where c.id = new.course_id;
  if v_source is null then
    -- Klubbens og brukernes egne baner: banens hull gjelder som før.
    return null;
  end if;

  v_teehole := new.tee_id is not null
               and exists (select 1 from public.course_tee_holes h where h.tee_id = new.tee_id);
  if v_teehole then
    select count(*) into v_count from public.course_tee_holes h where h.tee_id = new.tee_id;
  else
    select count(*) into v_count from public.course_holes h where h.course_id = new.course_id;
  end if;
  v_offset := case when new.first_hole = 10 and v_count = 18 then 9 else 0 end;

  insert into public.round_holes (round_id, hole_index, par, stroke_index, length_m)
  select new.id, s.hole_number - 1 - v_offset, s.par, s.stroke_index, s.length_m
    from (select h.hole_number, h.par, h.stroke_index, h.length_m
            from public.course_tee_holes h
           where v_teehole and h.tee_id = new.tee_id
          union all
          select h.hole_number, h.par, h.stroke_index, h.length_m
            from public.course_holes h
           where not v_teehole and h.course_id = new.course_id) s
   where s.hole_number - 1 - v_offset between 0 and new.hole_count - 1
  on conflict (round_id, hole_index) do nothing;
  return null;
end;
$$;
revoke all on function public.rounds_holes_snapshot() from public, anon, authenticated;

drop trigger if exists rounds_holes_snapshot on public.rounds;
create trigger rounds_holes_snapshot
  after insert or update of status on public.rounds
  for each row execute function public.rounds_holes_snapshot();


-- ===========================================================================
-- 5. NESTE SYNK HENTER ALT PÅ NYTT
-- ===========================================================================
-- Versjonen glemmes, så synken henter eksporten neste natt (eller ved en
-- kjøring for hånd) og skriver hullene. Banene og teene røres ikke her.
update public.course_feeds set data_version = null where source = 'slope';

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Alle rader skal ha ok = true.
-- ===========================================================================
-- with f as (
--   select p.proname, p.prosrc, p.proconfig,
--          has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--          has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
--          has_function_privilege('service_role', p.oid, 'execute') as server_kan
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public'
--     and p.proname in ('course_feed_apply', 'rounds_guard_course', 'rounds_holes_snapshot')
-- )
-- select 1 as nr, 'course_tee_holes finnes med RLS på og én policy (lesing)' as sjekk,
--        (select relrowsecurity from pg_class where oid = 'public.course_tee_holes'::regclass)
--        and (select count(*) = 1 from pg_policies where schemaname = 'public' and tablename = 'course_tee_holes'
--               and cmd = 'SELECT') as ok
-- union all
-- select 2, 'course_tee_holes: anon ingenting, authenticated bare select, service_role skriver',
--        not exists (select 1 from information_schema.role_table_grants
--                     where table_schema = 'public' and table_name = 'course_tee_holes' and grantee in ('anon', 'PUBLIC'))
--        and (select array_agg(privilege_type::text order by privilege_type) = array['SELECT']
--               from information_schema.role_table_grants
--              where table_schema = 'public' and table_name = 'course_tee_holes' and grantee = 'authenticated')
--        and has_table_privilege('service_role', 'public.course_tee_holes', 'insert')
-- union all
-- select 3, 'Unik indeks per tee (utsatt) og primærnøkkel (tee, hull)',
--        exists (select 1 from pg_constraint where conname = 'course_tee_holes_unique_stroke_index' and condeferrable)
--        and exists (select 1 from pg_constraint where conrelid = 'public.course_tee_holes'::regclass and contype = 'p')
-- union all
-- select 4, 'course_feed_apply skriver hull, bare service_role',
--        (select prosrc like '%course_tee_holes%' and prosrc like '%course_holes%'
--                and server_kan and not auth_kan and not anon_kan from f where proname = 'course_feed_apply')
-- union all
-- select 5, 'rounds_course_fk er borte, rounds_course_id_fk står, vakta rounds_guard_course finnes',
--        not exists (select 1 from pg_constraint where conrelid = 'public.rounds'::regclass and conname = 'rounds_course_fk')
--        and exists (select 1 from pg_constraint where conrelid = 'public.rounds'::regclass and conname = 'rounds_course_id_fk')
--        and exists (select 1 from pg_trigger where tgrelid = 'public.rounds'::regclass and tgname = 'rounds_guard_course')
-- union all
-- select 6, 'Triggeren rounds_holes_snapshot finnes (etter insert eller statusendring)',
--        exists (select 1 from pg_trigger where tgrelid = 'public.rounds'::regclass and tgname = 'rounds_holes_snapshot')
-- union all
-- select 7, 'Triggerfunksjonene kan ikke kalles av appen',
--        (select bool_and(not auth_kan and not anon_kan) from f where proname in ('rounds_guard_course', 'rounds_holes_snapshot'))
-- union all
-- select 8, 'Alle tre funksjonene har tom search_path',
--        (select count(*) = 3 and bool_and('search_path=""' = any(proconfig)) from f)
-- union all
-- select 9, 'Neste synk henter hullene: versjonen er glemt, eller hullene er alt skrevet',
--        coalesce((select data_version is null from public.course_feeds where source = 'slope'), true)
--        or exists (select 1 from public.course_tee_holes)
-- union all
-- select 10, 'Ingen hull på brukernes eller klubbenes egne tees (bare kildens)',
--        not exists (select 1 from public.course_tee_holes h join public.course_tees t on t.id = h.tee_id
--                     where t.source is null)
-- order by nr;


-- ===========================================================================
-- ETTER MIGRERINGEN (ikke en del av fila)
-- ===========================================================================
-- A. Deploy slope-sync v2 (supabase/functions/slope-sync/, med --no-verify-jwt
--    som før). Rekkefølgen 030 og deploy spiller ingen rolle: v2 før 030 feiler
--    på course_tee_holes og noterer feilen uten å skrive; v1 etter 030 skriver
--    uten hull, og v2 henter alt på nytt når course_tee_holes er tom.
-- B. Kjør synken for hånd (samme select som i 029, «Etter migreringen» C, uten
--    cron.schedule), eller vent til natten (03:17 UTC). Forventet svar: rundt
--    1300 baner endret, skipped_holes 14 (Bollnäs, Gjøvik og Toten,
--    Strängnäs Beijerslingan og Tönnersjö Äventyrsbanan: par per hull stemmer
--    ikke med teens par, så de teene står uten hull).
-- C. Sjekk: select count(distinct h.course_id) from public.course_holes h
--      join public.courses c on c.id = h.course_id where c.source = 'slope';  -- rundt 937
--    select count(distinct tee_id) from public.course_tee_holes;              -- rundt 6146
-- D. Slå på SlopeNoFeature.usesHoles i appen.


-- ===========================================================================
-- RULLEBAKKE (bare test)
-- ===========================================================================
-- 1. Slå av SlopeNoFeature.usesHoles i appen, og deploy slope-sync v1 igjen
--    (v1 sender ingen hull, men fungerer også mot 030).
-- 2. Kjør avsnitt 6 («course_feed_apply») fra 029_slope_baner.sql på nytt.
-- 3. Klubbrunder på hentede baner må slettes eller flyttes til en egen bane
--    før fremmednøkkelen kan legges tilbake (ellers feiler steg 4):
--      select r.id from public.rounds r join public.courses c on c.id = r.course_id
--       where r.club_id is not null and c.club_id is null;
-- 4. Kjør blokken under. Frosne round_holes blir stående (de er rundens hull).
--    Banens hull på hentede baner slettes; runder som er spilt på dem, har
--    hullene sine i round_holes.
--
-- begin;
-- drop trigger if exists rounds_holes_snapshot on public.rounds;
-- drop function if exists public.rounds_holes_snapshot();
-- drop trigger if exists rounds_guard_course on public.rounds;
-- drop function if exists public.rounds_guard_course();
-- alter table public.rounds add constraint rounds_course_fk
--   foreign key (course_id, club_id) references public.courses (id, club_id) on delete restrict;
-- delete from public.course_holes h using public.courses c
--  where c.id = h.course_id and c.source is not null;
-- drop table if exists public.course_tee_holes;
-- commit;
