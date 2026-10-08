\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 029_slope_baner.sql. Rekkefølge i en tom, lokal Postgres:
-- lokal/stub.sql, lokal/stub_storage.sql, 001–026 (009 er tatt med i 011),
-- 029 (gjerne to ganger), så denne fila. Lager sin egen verden.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
-- ===========================================================================

create function pg_temp.feil(p_sql text, p_kode text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FEIL (gikk gjennom): ' || p_sql;
exception when others then
  if sqlstate = p_kode then return 'ok ' || p_kode || ': ' || left(sqlerrm, 70);
  else return 'FEIL ' || sqlstate || ': ' || sqlerrm || ' <- ' || p_sql; end if;
end $$;
create function pg_temp.lik(p_verdi anyelement, p_forventet anyelement, p_hva text) returns text language sql as $$
  select case when p_verdi is not distinct from p_forventet then 'ok ' || p_hva
              else 'FEIL ' || p_hva || ': fikk ' || coalesce(p_verdi::text, 'null') || ', forventet ' || coalesce(p_forventet::text, 'null') end
$$;
create function pg_temp.som(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_uid, false);
$$;
grant execute on all functions in schema pg_temp to public;

-- === Verdenen ================================================================
-- Klubb K med Olga (arrangør) og Petter. Una er ikke i klubben.
\set uO '29000000-0000-0000-0000-00000000000a'
\set uP '29000000-0000-0000-0000-00000000000b'
\set uU '29000000-0000-0000-0000-00000000000c'
\set K  'a2900000-0000-0000-0000-000000000001'

select pg_temp.som('');
insert into auth.users values (:'uO'), (:'uP'), (:'uU');
update public.profiles set display_name = case id when :'uO' then 'Olga' when :'uP' then 'Petter' else 'Una' end
 where id in (:'uO', :'uP', :'uU');
insert into public.clubs (id, name) values (:'K', 'Klubb 029');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status) values
  (:'K', :'uO', 'Olga',   true,  'active'),
  (:'K', :'uP', 'Petter', false, 'active');

-- === A. Synken (service_role) ================================================
set role service_role;
select pg_temp.lik((public.course_feed_apply('slope', '5021', '2026-10-08T17:02:12Z',
  '[{"external_id":"77","name":"A6 Golfklubb","city":"Jönköping","country":"SE","course_rating":73,"slope_rating":132,
     "tees":[{"external_id":"10762","name":"Gul-Blå - Hvit","gender":"men","course_rating":73,"slope_rating":132,"par":72,"sort_order":1},
             {"external_id":"10766","name":"Gul-Blå - Gul","gender":"women","course_rating":77.4,"slope_rating":134,"par":72,"sort_order":5}]},
    {"external_id":"9","name":"Oslo Golfklubb","city":"Oslo","country":"NO","course_rating":72.1,"slope_rating":130,
     "tees":[{"external_id":"901","name":"Gul","gender":"men","course_rating":72.1,"slope_rating":130,"par":72,"sort_order":1}]}]'::jsonb,
  array['77', '9']) ->> 'tees_written')::int, 3, 'Første synk skriver tre tees');
select pg_temp.lik((select count(*)::int from public.courses where source = 'slope' and club_id is null and kind = 'course'), 2,
                   'To hentede baner i det felles biblioteket, ekte baner');
select pg_temp.lik((select data_version from public.course_feeds where source = 'slope'), '5021', 'Versjonen er lagret');
select pg_temp.lik((select country from public.courses where source = 'slope' and external_id = '9'), 'NO', 'Landkoden er lagret');
-- Ny versjon: A6 er re-ratet og har mistet dameteen, Oslo GK er borte fra eksporten.
select pg_temp.lik((public.course_feed_apply('slope', '5022', '2026-10-09T17:00:00Z',
  '[{"external_id":"77","name":"A6 Golfklubb","city":"Jönköping","country":"SE","course_rating":73.4,"slope_rating":133,
     "tees":[{"external_id":"10762","name":"Gul-Blå - Hvit","gender":"men","course_rating":73.4,"slope_rating":133,"par":72,"sort_order":1}]}]'::jsonb,
  array['77']) ->> 'courses_missing')::int, 1, 'Oslo GK markeres borte');
select pg_temp.lik((select count(*)::int from public.courses where source = 'slope'), 2, 'Ingen bane er slettet');
select pg_temp.lik((select missing_at is not null from public.course_tees where external_id = '10766'), true, 'Dameteen er borte, ikke slettet');
select pg_temp.lik((select course_rating from public.course_tees where external_id = '10762'), 73.4::numeric(4,1), 'Re-ratingen er skrevet');
select pg_temp.lik((select missing from public.course_feeds where source = 'slope'), 1, 'Statusen teller én borte');
select pg_temp.feil($$select public.course_feed_apply('slope', '5023', now(), '[]'::jsonb, '{}'::text[])$$, '22023');
select public.course_feed_note('slope', 'meta svarte 503');
select pg_temp.lik((select last_error from public.course_feeds where source = 'slope'), 'meta svarte 503', 'Feilen er notert');
select pg_temp.lik((select data_version from public.course_feeds where source = 'slope'), '5022', 'Notatet rører ikke versjonen');
-- Kommer banen tilbake, er den ikke lenger borte.
select public.course_feed_apply('slope', '5024', now(),
  '[{"external_id":"9","name":"Oslo Golfklubb","city":"Oslo","country":"NO","course_rating":72.1,"slope_rating":130,
     "tees":[{"external_id":"901","name":"Gul","gender":"men","course_rating":72.1,"slope_rating":130,"par":72,"sort_order":1}]}]'::jsonb,
  array['77', '9']) is not null;
select pg_temp.lik((select missing_at from public.courses where external_id = '9'), null::timestamptz, 'Oslo GK er tilbake');
reset role;

select id as slope_course from public.courses where source = 'slope' and external_id = '77' \gset
select id as slope_tee from public.course_tees where external_id = '10762' \gset

-- === B. Appen leser, men skriver ikke kildens rader ==========================
select pg_temp.som(:'uU'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.course_tees where course_id = :'slope_course'), 2, 'Una leser teene til en hentet bane');
select pg_temp.feil(format($$insert into public.course_tees (course_id, name, gender, course_rating, slope_rating)
                              values (%L, 'Egen', 'men', 70, 120)$$, :'slope_course'), '42501');
with u as (update public.course_tees set course_rating = 60 where id = :'slope_tee' returning 1)
select pg_temp.lik(count(*)::int, 0, 'Una kan ikke endre en hentet tee') from u;
with u as (update public.courses set missing_at = now() where id = :'slope_course' returning 1)
select pg_temp.lik(count(*)::int, 0, 'Una kan ikke markere en hentet bane') from u;
select pg_temp.feil($$select public.course_feed_apply('slope', 'x', now(), '[]'::jsonb, array['1'])$$, '42501');
select pg_temp.feil($$select public.course_feed_note('slope')$$, '42501');
select pg_temp.feil($$select count(*) from public.course_feeds$$, '42501');
select pg_temp.feil(format($$select public.save_course_tees(%L, '[]'::jsonb)$$, :'slope_course'), '42501');

-- Una legger inn sin egen bane (kopi fra slope.no) med tees.
select public.save_library_course(null, 'A6 Golfklubb', 'course', 73, 132::smallint,
  (select jsonb_agg(jsonb_build_object('hole_number', n, 'par', 4)) from generate_series(1, 18) n)) as una_course \gset
select pg_temp.lik(public.save_course_tees(:'una_course',
  '[{"name":"Hvit","gender":"men","course_rating":73,"slope_rating":132,"par":72,"sort_order":1},
    {"name":"Gul","gender":"women","course_rating":77.4,"slope_rating":134,"par":72,"sort_order":2}]'::jsonb), 2, 'Una lagrer to tees');
select id as una_tee from public.course_tees where course_id = :'una_course' and name = 'Hvit' \gset
select pg_temp.feil(format($$select public.save_course_tees(%L, '[{"name":"Hvit","gender":"men","course_rating":73,"slope_rating":132},
                                                                {"name":"hvit","gender":"men","course_rating":70,"slope_rating":120}]'::jsonb)$$,
                           :'una_course'), '22023');
select pg_temp.feil(format($$insert into public.course_tees (course_id, source, external_id, name, gender, course_rating, slope_rating)
                              values (%L, 'slope', '1', 'Falsk', 'men', 70, 120)$$, :'una_course'), '42501');

-- === C. Teen på runden =======================================================
-- Løs runde med tee: tallene hentes fra teen.
select (public.start_loose_round(jsonb_build_object('course_id', :'una_course', 'tee_id', :'una_tee', 'format', 'stableford',
        'venue', 'course', 'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', true)) ->> 'round_id') as r1 \gset
select pg_temp.lik((select tee_name || ' ' || course_rating || ' ' || slope_rating from public.rounds where id = :'r1'),
                   'Hvit 73.0 132', 'Runden har teen og tallene');
-- Re-rating etter start: runden beholder tallene.
select public.save_course_tees(:'una_course',
  '[{"name":"Hvit","gender":"men","course_rating":74,"slope_rating":136,"par":72,"sort_order":1},
    {"name":"Gul","gender":"women","course_rating":77.4,"slope_rating":134,"par":72,"sort_order":2}]'::jsonb) = 2;
select pg_temp.lik((select id from public.course_tees where course_id = :'una_course' and name = 'Hvit'), :'una_tee'::uuid,
                   'Samme navn og kjønn beholder id-en');
select pg_temp.lik((select course_rating from public.rounds where id = :'r1'), 73.0::numeric(4,1), 'Startet runde beholder CR etter re-rating');
-- Appen kan ikke skrive egne tall, og teen byttes ikke etter start.
update public.rounds set course_rating = 50, slope_rating = 60 where id = :'r1';
select pg_temp.lik((select slope_rating from public.rounds where id = :'r1'), 132::smallint, 'Egne tall fra appen blir ikke stående');
select pg_temp.feil(format($$update public.rounds set tee_id = null where id = %L$$, :'r1'), '22023');
-- En tee fra en annen bane stoppes.
select pg_temp.feil(format($$select public.start_loose_round(jsonb_build_object('course_id', %L, 'tee_id', %L,
                              'players', '[{"guest_name":"G"}]'::jsonb))$$, :'una_course', :'slope_tee'), '22023');
-- Kladd: tallene følger teen til start.
select (public.start_loose_round(jsonb_build_object('course_id', :'una_course', 'tee_id', :'una_tee',
        'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', false)) ->> 'round_id') as r2 \gset
select public.save_course_tees(:'una_course',
  '[{"name":"Hvit","gender":"men","course_rating":74.5,"slope_rating":137,"par":72,"sort_order":1},
    {"name":"Gul","gender":"women","course_rating":77.4,"slope_rating":134,"par":72,"sort_order":2}]'::jsonb) = 2;
update public.rounds set status = 'active' where id = :'r2';
select pg_temp.lik((select course_rating from public.rounds where id = :'r2'), 74.5::numeric(4,1), 'Kladden fikk tallene teen hadde ved start');
-- Uten tee: alt tomt, banens tall gjelder som før.
select (public.start_loose_round(jsonb_build_object('course_id', :'una_course', 'players', '[{"guest_name":"G"}]'::jsonb))
        ->> 'round_id') as r3 \gset
select pg_temp.lik((select coalesce(tee_name, '') || coalesce(course_rating::text, '') from public.rounds where id = :'r3'), '',
                   'Runde uten tee har ingen tall');
-- Teen slettes: runden beholder navn og tall.
select public.save_course_tees(:'una_course', '[{"name":"Gul","gender":"women","course_rating":77.4,"slope_rating":134}]'::jsonb) = 1;
select pg_temp.lik((select coalesce(tee_id::text, '-') || ' ' || tee_name || ' ' || course_rating from public.rounds where id = :'r1'),
                   '- Hvit 73.0', 'Slettet tee: runden beholder navn og tall');

-- === D. Klubbens bane ========================================================
reset role; select pg_temp.som(:'uO'); set role authenticated;
select public.save_course(:'K', null, 'Bjaavann', null, 70.2, 125::smallint, true, '[]'::jsonb) as club_course \gset
select pg_temp.lik(public.save_course_tees(:'club_course',
  '[{"name":"Gul","gender":"men","course_rating":70.2,"slope_rating":125,"par":72,"sort_order":1}]'::jsonb), 1, 'Arrangøren lagrer klubbens tees');
reset role; select pg_temp.som(:'uP'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.course_tees where course_id = :'club_course'), 1, 'Medlemmet leser klubbens tees');
select pg_temp.feil(format($$select public.save_course_tees(%L, '[]'::jsonb)$$, :'club_course'), '42501');
select pg_temp.feil(format($$select public.save_course_tees(%L, '[]'::jsonb)$$, :'una_course'), '42501');
reset role; select pg_temp.som(:'uU'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.course_tees where course_id = :'club_course'), 0, 'Andre ser ikke klubbens tees');

-- === E. anon ================================================================
reset role; select pg_temp.som(''); set role anon;
select pg_temp.feil($$select count(*) from public.course_tees$$, '42501');
select pg_temp.feil($$select public.save_course_tees(gen_random_uuid(), '[]'::jsonb)$$, '42501');
reset role;
