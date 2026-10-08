\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 030_slope_hull.sql. Rekkefølge i en tom, lokal Postgres:
-- lokal/stub.sql, lokal/stub_storage.sql, 001–027 (009 er tatt med i 011),
-- 029, 030 (gjerne to ganger), så denne fila. Lager sin egen verden.
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
-- 18 hull som jsonb: par fra en liste, indeks 1..18 forskjøvet med p_shift, lengde 100 + 10·hull.
create function pg_temp.hull(p_pars int[], p_shift int default 0) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_array(n, p_pars[n], ((n - 1 + p_shift) % 18) + 1, 100 + 10 * n) order by n)
    from generate_series(1, cardinality(p_pars)) n
$$;
-- Utsatte unike nøkler (indeksen) sjekkes ved commit; her med en gang, så feil() ser bruddet.
create function pg_temp.straks(p_sql text) returns void language plpgsql as $$
begin
  set constraints all immediate;
  execute p_sql;
end $$;
grant execute on all functions in schema pg_temp to public;

-- === Verdenen ================================================================
-- Klubb K med Olga (arrangør) og Petter. Klubb L (en annen). Una er ikke i klubben.
\set uO '30000000-0000-0000-0000-00000000000a'
\set uP '30000000-0000-0000-0000-00000000000b'
\set uU '30000000-0000-0000-0000-00000000000c'
\set K  'a3000000-0000-0000-0000-000000000001'
\set L  'a3000000-0000-0000-0000-000000000002'
\set svart '{5,4,3,4,5,4,3,4,4,5,4,3,4,5,4,3,4,5}'
\set gronn '{4,3,3,4,4,4,3,4,4,4,3,3,4,4,4,3,4,4}'

select pg_temp.som('');
insert into auth.users values (:'uO'), (:'uP'), (:'uU');
update public.profiles set display_name = case id when :'uO' then 'Olga' when :'uP' then 'Petter' else 'Una' end
 where id in (:'uO', :'uP', :'uU');
insert into public.clubs (id, name) values (:'K', 'Klubb 030'), (:'L', 'Klubb L');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status) values
  (:'K', :'uO', 'Olga',   true,  'active'),
  (:'K', :'uP', 'Petter', false, 'active');
insert into public.seasons (club_id, name, status, rules) values (:'K', '2026', 'active', '{"version":1,"preset":"golfgutu"}')
  returning id as sesong \gset
insert into public.events (club_id, season_id, event_date, start_time) values (:'K', :'sesong', '2026-10-08', '17:00')
  returning id as kveld \gset
insert into public.courses (club_id, name) values (:'L', 'Klubb Ls bane') returning id as l_course \gset

-- === A. Synken (service_role) skriver hull per tee og på banen ===============
select pg_temp.som(''); set role service_role;
-- Valdres (forenklet): Svart (par 73) og Grønn (par 66) med hver sine hull, og en
-- dametee uten hull. Banens hull kommer fra Svart (første herre-tee med hull).
select pg_temp.lik((public.course_feed_apply('slope', '5021', now(),
  jsonb_build_array(
    jsonb_build_object('external_id', '154', 'name', 'Valdres Golfklubb', 'city', 'Aurdal', 'country', 'NO',
      'course_rating', 72.4, 'slope_rating', 130, 'holes', pg_temp.hull(:'svart'::int[]),
      'tees', jsonb_build_array(
        jsonb_build_object('external_id', '1541', 'name', 'Svart 73', 'gender', 'men', 'course_rating', 72.4,
                           'slope_rating', 130, 'par', 73, 'sort_order', 1, 'holes', pg_temp.hull(:'svart'::int[])),
        jsonb_build_object('external_id', '1543', 'name', 'Grønn 66', 'gender', 'men', 'course_rating', 63.1,
                           'slope_rating', 110, 'par', 66, 'sort_order', 3, 'holes', pg_temp.hull(:'gronn'::int[], 4)),
        jsonb_build_object('external_id', '1544', 'name', 'Rød', 'gender', 'women', 'course_rating', 70,
                           'slope_rating', 125, 'sort_order', 4, 'holes', '[]'::jsonb))),
    jsonb_build_object('external_id', '700', 'name', 'Uten hull GK', 'country', 'DK', 'course_rating', 60,
      'slope_rating', 100, 'tees', jsonb_build_array(
        jsonb_build_object('external_id', '7001', 'name', 'Gul', 'gender', 'men', 'course_rating', 60, 'slope_rating', 100)))),
  array['154', '700']) ->> 'tee_holes_written')::int, 36, 'Synken skriver 18 hull på hver av to tees');
select pg_temp.lik((select count(*)::int from public.course_holes h join public.courses c on c.id = h.course_id
                     where c.external_id = '154'), 18, 'Banen får 18 hull');
select pg_temp.lik((select sum(h.par)::int from public.course_holes h join public.courses c on c.id = h.course_id
                     where c.external_id = '154'), 73, 'Banens hull er Svart (par 73)');
select pg_temp.lik((select sum(h.par)::int from public.course_tee_holes h join public.course_tees t on t.id = h.tee_id
                     where t.external_id = '1543'), 66, 'Grønn har sine egne hull (par 66)');
select pg_temp.lik((select count(*)::int from public.course_tee_holes h join public.course_tees t on t.id = h.tee_id
                     where t.external_id = '1544'), 0, 'Dameteen uten hull får ingen');
select pg_temp.lik((select count(*)::int from public.course_holes h join public.courses c on c.id = h.course_id
                     where c.external_id = '700'), 0, 'Banen uten hull får ingen (nøkkelen mangler)');

-- Synken v1 (uten nøkkelen holes) rører ikke hullene.
select pg_temp.lik((public.course_feed_apply('slope', null, null,
  jsonb_build_array(jsonb_build_object('external_id', '154', 'name', 'Valdres Golfklubb', 'country', 'NO',
    'course_rating', 72.4, 'slope_rating', 130, 'tees', jsonb_build_array(
      jsonb_build_object('external_id', '1541', 'name', 'Svart 73', 'gender', 'men', 'course_rating', 72.4, 'slope_rating', 130, 'par', 73, 'sort_order', 1),
      jsonb_build_object('external_id', '1543', 'name', 'Grønn 66', 'gender', 'men', 'course_rating', 63.1, 'slope_rating', 110, 'par', 66, 'sort_order', 3),
      jsonb_build_object('external_id', '1544', 'name', 'Rød', 'gender', 'women', 'course_rating', 70, 'slope_rating', 125, 'sort_order', 4)))),
  null) ->> 'tee_holes_written')::int, 0, 'Uten nøkkelen holes skrives ingen hull');
select pg_temp.lik((select count(*)::int from public.course_tee_holes), 36, 'Uten nøkkelen holes står hullene');
select pg_temp.lik((select count(*)::int from public.course_holes h join public.courses c on c.id = h.course_id
                     where c.external_id = '154'), 18, 'Uten nøkkelen holes står banens hull');

-- Ugyldige hull stopper hele delen (synken vasker dem først).
select pg_temp.feil($$select public.course_feed_apply('slope', null, null,
  '[{"external_id":"700","name":"Uten hull GK","country":"DK","course_rating":60,"slope_rating":100,
     "tees":[{"external_id":"7001","name":"Gul","gender":"men","course_rating":60,"slope_rating":100,
              "holes":[[1,7,1,300]]}]}]'::jsonb, null)$$, '23514');
select pg_temp.feil($$select pg_temp.straks($q$select public.course_feed_apply('slope', null, null,
  '[{"external_id":"700","name":"Uten hull GK","country":"DK","course_rating":60,"slope_rating":100,
     "tees":[{"external_id":"7001","name":"Gul","gender":"men","course_rating":60,"slope_rating":100,
              "holes":[[1,4,1,300],[2,4,1,300]]}]}]'::jsonb, null)$q$)$$, '23505');
reset role;

select c.id as valdres from public.courses c where c.source = 'slope' and c.external_id = '154' \gset
select c.id as utenhull from public.courses c where c.source = 'slope' and c.external_id = '700' \gset
select t.id as svart_tee from public.course_tees t where t.external_id = '1541' \gset
select t.id as gronn_tee from public.course_tees t where t.external_id = '1543' \gset
select t.id as rod_tee from public.course_tees t where t.external_id = '1544' \gset
-- En lokal rettelse (019) på den hentede banen, som ikke skal røres.
insert into public.course_corrections (course_id, profile_id, hole_number, par)
values (:'valdres', :'uU', 1, 4);

-- === B. Appen leser hullene, men skriver dem ikke ============================
select pg_temp.som(:'uU'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.course_tee_holes where tee_id = :'gronn_tee'), 18, 'Una leser hullene til en hentet tee');
select pg_temp.lik((select count(*)::int from public.course_holes where course_id = :'valdres'), 18, 'Una leser banens hull');
select pg_temp.feil(format($$insert into public.course_tee_holes (tee_id, hole_number, par) values (%L, 1, 4)$$, :'rod_tee'), '42501');
select pg_temp.feil(format($$update public.course_tee_holes set par = 3 where tee_id = %L$$, :'gronn_tee'), '42501');
select pg_temp.feil(format($$delete from public.course_tee_holes where tee_id = %L$$, :'gronn_tee'), '42501');
select pg_temp.feil(format($$insert into public.course_holes (course_id, hole_number, par) values (%L, 1, 4)$$, :'utenhull'), '42501');
with u as (update public.course_holes set par = 3 where course_id = :'valdres' returning 1)
select pg_temp.lik(count(*)::int, 0, 'Una kan ikke endre hullene på en hentet bane') from u;
with d as (delete from public.course_holes where course_id = :'valdres' returning 1)
select pg_temp.lik(count(*)::int, 0, 'Una kan ikke slette hullene på en hentet bane') from d;
select pg_temp.feil($$select public.course_feed_apply('slope', null, null, '[]'::jsonb, null)$$, '42501');
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.feil($$select count(*) from public.course_tee_holes$$, '42501');
reset role;

-- === C. Klubbrunde på en hentet bane =========================================
select pg_temp.som(:'uO'); set role authenticated;
insert into public.rounds (club_id, event_id, round_no, course_id, tee_id, venue)
values (:'K', :'kveld', 1, :'valdres', :'gronn_tee', 'course') returning id as kr1 \gset
select pg_temp.lik((select tee_name || ' ' || slope_rating from public.rounds where id = :'kr1'), 'Grønn 66 110',
                   'Klubbrunde på hentet bane med tee (CR og slope fra teen)');
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'kr1'), 0, 'Kladden har ingen frosne hull');
reset role;
select pg_temp.som(:'uU'); set role authenticated;
select public.save_library_course(null, 'Unas bane', 'course', 70, 120::smallint,
  (select jsonb_agg(jsonb_build_object('hole_number', n, 'par', 4)) from generate_series(1, 18) n)) as una_course \gset
reset role;
select pg_temp.som(:'uO'); set role authenticated;
select pg_temp.feil(format($$insert into public.rounds (club_id, event_id, round_no, course_id) values (%L, %L, 2, %L)$$,
                           :'K', :'kveld', :'una_course'), '23503');
select pg_temp.feil(format($$insert into public.rounds (club_id, event_id, round_no, course_id) values (%L, %L, 2, %L)$$,
                           :'K', :'kveld', :'l_course'), '23503');
select pg_temp.feil(format($$update public.rounds set course_id = %L, tee_id = null where id = %L$$, :'una_course', :'kr1'), '23503');
select public.save_course(:'K', null, 'Bjaavann', null, 70.2, 125::smallint, true,
  (select jsonb_agg(jsonb_build_object('hole_number', n, 'par', 3)) from generate_series(1, 18) n)) as club_course \gset
insert into public.rounds (club_id, event_id, round_no, course_id, venue) values (:'K', :'kveld', 2, :'club_course', 'simulator')
  returning id as kr2 \gset
select pg_temp.lik((select count(*)::int from public.rounds where id = :'kr2'), 1, 'Klubbrunde på klubbens egen bane som før');

-- === D. Hullene fryses ved start =============================================
-- Arrangøren har overstyrt hull 1 selv: det står.
insert into public.round_holes (round_id, hole_index, par) values (:'kr1', 0, 5);
update public.rounds set status = 'active' where id = :'kr1';
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'kr1'), 18, 'Start fryser 18 hull på runden');
select pg_temp.lik((select sum(par)::int from public.round_holes where round_id = :'kr1' and hole_index > 0),
                   (select sum(par)::int - 4 from public.course_tee_holes where tee_id = :'gronn_tee'),
                   'Hull 2–18 er Grønn-teens par, ikke banens');
select pg_temp.lik((select par from public.round_holes where round_id = :'kr1' and hole_index = 0), 5::smallint,
                   'Arrangørens overstyring av hull 1 står');
select pg_temp.lik((select stroke_index from public.round_holes where round_id = :'kr1' and hole_index = 1), 6::smallint,
                   'Indeksen er teens (hull 2, forskjøvet 4)');
select pg_temp.lik((select length_m from public.round_holes where round_id = :'kr1' and hole_index = 17), 280::smallint,
                   'Lengden er teens');
update public.rounds set status = 'locked' where id = :'kr2';
reset role;
-- Klubbens egen bane: banens hull gjelder som før, ingenting frosset.
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'kr2'), 0,
                   'Klubbens egen bane: ingen frosne hull (Golfgutu-pariteten)');

-- Ny indeks hos kilden etter start: runden beholder sine.
select pg_temp.som(''); set role service_role;
select public.course_feed_apply('slope', '5022', now(),
  jsonb_build_array(jsonb_build_object('external_id', '154', 'name', 'Valdres Golfklubb', 'country', 'NO',
    'course_rating', 72.4, 'slope_rating', 130, 'holes', pg_temp.hull(:'svart'::int[], 9),
    'tees', jsonb_build_array(
      jsonb_build_object('external_id', '1541', 'name', 'Svart 73', 'gender', 'men', 'course_rating', 72.4, 'slope_rating', 130, 'par', 73, 'sort_order', 1,
                         'holes', pg_temp.hull(:'svart'::int[], 9)),
      jsonb_build_object('external_id', '1543', 'name', 'Grønn 66', 'gender', 'men', 'course_rating', 63.1, 'slope_rating', 110, 'par', 66, 'sort_order', 3,
                         'holes', pg_temp.hull(:'gronn'::int[], 9)),
      jsonb_build_object('external_id', '1544', 'name', 'Rød', 'gender', 'women', 'course_rating', 70, 'slope_rating', 125, 'sort_order', 4)))),
  array['154', '700']) is not null;
reset role;
select pg_temp.lik((select stroke_index from public.course_tee_holes where tee_id = :'gronn_tee' and hole_number = 2), 11::smallint,
                   'Kilden har ny indeks på Grønn');
select pg_temp.lik((select stroke_index from public.round_holes where round_id = :'kr1' and hole_index = 1), 6::smallint,
                   'Startet runde beholder indeksen den startet med');
select pg_temp.lik((select count(*)::int from public.course_holes where course_id = :'valdres' and stroke_index = ((1 + 9) % 18) + 1
                     and hole_number = 2), 1, 'Banens hull har fått ny indeks');
select pg_temp.lik((select count(*)::int from public.course_corrections where course_id = :'valdres'), 1,
                   'Rettelsen på banen (019) står etter synken');

-- Løs runde på hentet bane med en tee uten egne hull: banens hull fryses.
select pg_temp.som(:'uU'); set role authenticated;
select (public.start_loose_round(jsonb_build_object('course_id', :'valdres', 'tee_id', :'rod_tee', 'venue', 'course',
        'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', true)) ->> 'round_id') as lr1 \gset
select pg_temp.lik((select sum(par)::int from public.round_holes where round_id = :'lr1'), 73,
                   'Løs runde, tee uten hull: banens hull (Svart, par 73) fryses');
-- Løs runde på hentet bane, siste ni med Grønn-teen.
select (public.start_loose_round(jsonb_build_object('course_id', :'valdres', 'tee_id', :'gronn_tee', 'venue', 'course',
        'hole_count', 9, 'first_hole', 10, 'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', true)) ->> 'round_id') as lr2 \gset
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'lr2'), 9, 'Siste ni: ni hull');
select pg_temp.lik((select string_agg(par::text, '' order by hole_index) from public.round_holes where round_id = :'lr2'),
                   '433444344', 'Siste ni: hull 10–18 fra Grønn som rundens hull 0–8');
-- Kladd: ingen hull før start.
select (public.start_loose_round(jsonb_build_object('course_id', :'valdres', 'tee_id', :'gronn_tee',
        'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', false)) ->> 'round_id') as lr3 \gset
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'lr3'), 0, 'Løs kladd: ingen frosne hull');
update public.rounds set status = 'active' where id = :'lr3';
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'lr3'), 18, 'Løs kladd som startes: 18 frosne hull');
-- Egen bane i biblioteket: som før.
select (public.start_loose_round(jsonb_build_object('course_id', :'una_course',
        'players', '[{"guest_name":"Gjest"}]'::jsonb, 'start', true)) ->> 'round_id') as lr4 \gset
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'lr4'), 0,
                   'Egen bane i biblioteket: ingen frosne hull');
-- Appen kan ikke kalle triggerfunksjonene.
select pg_temp.feil($$select public.rounds_holes_snapshot()$$, '42501');
reset role;

-- === E. Kilden fjerner hullene ===============================================
select pg_temp.som(''); set role service_role;
select pg_temp.lik((public.course_feed_apply('slope', null, null,
  jsonb_build_array(jsonb_build_object('external_id', '154', 'name', 'Valdres Golfklubb', 'country', 'NO',
    'course_rating', 72.4, 'slope_rating', 130, 'holes', '[]'::jsonb,
    'tees', jsonb_build_array(
      jsonb_build_object('external_id', '1541', 'name', 'Svart 73', 'gender', 'men', 'course_rating', 72.4, 'slope_rating', 130, 'par', 73, 'sort_order', 1, 'holes', '[]'::jsonb),
      jsonb_build_object('external_id', '1543', 'name', 'Grønn 66', 'gender', 'men', 'course_rating', 63.1, 'slope_rating', 110, 'par', 66, 'sort_order', 3, 'holes', '[]'::jsonb),
      jsonb_build_object('external_id', '1544', 'name', 'Rød', 'gender', 'women', 'course_rating', 70, 'slope_rating', 125, 'sort_order', 4)))),
  null) ->> 'course_holes_written')::int, 0, 'Tom liste skriver ingen hull');
reset role;
select pg_temp.lik((select count(*)::int from public.course_tee_holes), 0, 'Tom liste sletter teenes hull');
select pg_temp.lik((select count(*)::int from public.course_holes where course_id = :'valdres'), 0, 'Tom liste sletter banens hull');
select pg_temp.lik((select count(*)::int from public.round_holes where round_id = :'kr1'), 18, 'Rundene har hullene sine');
select pg_temp.lik((select count(*)::int from public.course_holes where course_id = :'una_course'), 18, 'Unas egen bane er urørt');
