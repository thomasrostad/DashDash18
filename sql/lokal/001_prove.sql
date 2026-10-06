\set ON_ERROR_STOP on
\pset footer off
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 001_skjema_v1.sql mot en lokal, midlertidig Postgres med
-- sql/lokal/stub.sql. Legger inn falske brukere i auth.users og bytter rolle
-- med `set role`. Hver resultatlinje skal starte med "ok"; ingen "FEIL".
-- Slik kjøres den: se sql/README.md, «Lokal sjekk».
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
grant execute on all functions in schema pg_temp to public;

insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004');

-- === Arrangør Thomas lager klubben ==========================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
select public.create_club('Golfgutu', 'Thomas', 12.4) as klubb \gset
select join_code as kode from public.clubs where id = :'klubb' \gset
insert into public.club_members (club_id, display_name, handicap_index) values
  (:'klubb', 'Anders', 18.4), (:'klubb', 'Bjørn', 9.0), (:'klubb', 'Cato', 30.0);
select id as anders from public.club_members where display_name = 'Anders' \gset
select id as bjorn  from public.club_members where display_name = 'Bjørn'  \gset
select id as thomas from public.club_members where display_name = 'Thomas' \gset
select pg_temp.lik((select count(*) from public.club_members where club_id = :'klubb'), 4::bigint, 'arrangør ser 4 i troppen');
select pg_temp.feil($$update public.club_members set is_organizer = false where display_name = 'Thomas'$$, '42501');
reset role;

-- === Anders tar ledig navn ==================================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
set role authenticated;
select pg_temp.lik((select count(*) from public.club_members), 0::bigint, 'ikke-medlem ser ingen tropp');
select pg_temp.lik(jsonb_array_length(public.club_preview(:'kode') -> 'open_members'), 3, 'preview viser 3 ledige navn');
select pg_temp.lik(public.join_club(:'kode', :'anders') ->> 'status', 'active', 'Anders tar navnet sitt');
select pg_temp.lik(public.join_club(:'kode', :'anders') ->> 'status', 'active', 'join_club er idempotent');
select pg_temp.lik((select count(*) from public.club_members), 4::bigint, 'medlem ser hele troppen');
select pg_temp.feil($$update public.club_members set is_organizer = true where user_id = auth.uid()$$, '42501');
select pg_temp.feil($$update public.club_members set seed_group = 1 where user_id = auth.uid()$$, '42501');
update public.club_members set handicap_index = 17.9 where user_id = auth.uid();
select pg_temp.lik((select handicap_index from public.club_members where user_id = auth.uid()), 17.9, 'eget handicap kan endres');
with u as (update public.club_members set display_name = 'Kapret' where display_name = 'Bjørn' returning 1)
select pg_temp.lik((select count(*) from u), 0::bigint, 'kan ikke endre ledig rad direkte');
select pg_temp.feil($$insert into public.club_members (club_id, display_name) values ('$$ || :'klubb' || $$', 'Snik')$$, '42501');
reset role;

-- === Dag ber om å bli med som ny ===========================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
set role authenticated;
select pg_temp.lik(public.join_club(:'kode', null, 'Dag', 22.1) ->> 'status', 'pending', 'ny spiller venter');
select pg_temp.lik((select count(*) from public.club_members), 1::bigint, 'ventende ser bare seg selv');
select pg_temp.lik((select count(*) from public.clubs), 1::bigint, 'ventende ser klubbnavnet');
select id as dag from public.club_members where user_id = auth.uid() \gset
select pg_temp.feil($$update public.club_members set status = 'active' where user_id = auth.uid()$$, '42501');
reset role;

-- === Utenforstående i en annen klubb =======================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', false);
set role authenticated;
select public.create_club('Andre', 'Ola') as klubb2 \gset
select id as ola from public.club_members where user_id = auth.uid() \gset
select pg_temp.lik((select count(*) from public.club_members where club_id = :'klubb'), 0::bigint, 'annen klubb ser ikke vår tropp');
reset role;

-- === anon får ingenting ====================================================
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select pg_temp.feil($$select * from public.clubs$$, '42501');
select pg_temp.feil($$select * from public.hole_scores$$, '42501');
select pg_temp.feil($$select public.is_club_member('$$ || :'klubb' || $$')$$, '42501');
select pg_temp.feil($$select public.delete_round(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.club_preview('X')$$, '42501');
reset role;

-- === Arrangøren godkjenner Dag og setter opp sesong, kveld, bane, runde ====
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
update public.club_members set status = 'active' where id = :'dag';
insert into public.seasons (club_id, name, status, rules) values (:'klubb', '2026', 'active', '{"version":1,"preset":"golfgutu"}') returning id as sesong \gset
select pg_temp.feil($$insert into public.seasons (club_id, name, rules) values ('$$ || :'klubb' || $$', 'X', '{"preset":"x"}')$$, '23514');
select pg_temp.feil($$insert into public.seasons (club_id, name, rules) values ('$$ || :'klubb' || $$', 'X', '{"version":"1"}')$$, '23514');
insert into public.events (club_id, season_id, event_date, start_time) values (:'klubb', :'sesong', '2026-10-08', '17:00') returning id as kveld \gset
insert into public.courses (club_id, name, course_rating, slope_rating) values (:'klubb', 'Elisefarm', 72.1, 130) returning id as bane \gset
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select :'bane', h, 4, h from generate_series(1, 18) h;
-- bytte indeks på to hull i én setning (utsatt unik-sjekk)
update public.course_holes set stroke_index = case hole_number when 1 then 2 when 2 then 1 end
 where course_id = :'bane' and hole_number in (1, 2);
select pg_temp.lik((select stroke_index from public.course_holes where course_id = :'bane' and hole_number = 1), 2::smallint, 'indeksbytte i én setning');
begin;
set constraints all immediate;
select pg_temp.feil($$update public.course_holes set stroke_index = 5 where course_id = '$$ || :'bane' || $$' and hole_number = 1$$, '23505');
commit;
insert into public.rounds (club_id, event_id, course_id) values (:'klubb', :'kveld', :'bane') returning id as runde \gset
select pg_temp.lik(public.set_round_setup(:'runde',
  jsonb_build_array(
    jsonb_build_object('member_id', :'anders', 'bay_no', 1, 'is_marker', true),
    jsonb_build_object('member_id', :'dag',    'bay_no', 1),
    jsonb_build_object('member_id', :'thomas', 'bay_no', 2),
    jsonb_build_object('member_id', :'bjorn',  'bay_no', 2)),
  jsonb_build_array(jsonb_build_object('match_no', 1, 'player_a', :'anders', 'player_b', :'dag'))
) ->> 'players', '4', 'oppsett med 4 spillere');
select pg_temp.lik((select handicap_index from public.round_players where round_id = :'runde' and member_id = :'anders'), 17.9, 'handicap kopiert fra troppen');
-- Ola fra annen klubb kan ikke legges inn (sammensatt FK)
select pg_temp.feil($$select public.set_round_setup('$$ || :'runde' || $$', '[{"member_id":"$$ || :'ola' || $$"}]')$$, '23503');
reset role;

-- === Kladden er usynlig for spillere ======================================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
set role authenticated;
select pg_temp.lik((select count(*) from public.rounds), 0::bigint, 'spiller ser ikke kladd');
select pg_temp.lik((select count(*) from public.round_players), 0::bigint, 'spiller ser ikke kladdens deltakere');
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 0, '[{"member_id":"$$ || :'anders' || $$","strokes":4}]')$$, 'P0002');
reset role;

-- === Start: handicap fryses på nytt ========================================
update public.club_members set handicap_index = 16.0 where id = :'anders';  -- som postgres
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
update public.rounds set status = 'active' where id = :'runde';
select pg_temp.lik((select handicap_index from public.round_players where round_id = :'runde' and member_id = :'anders'), 16.0, 'handicap fryses ved start');
select pg_temp.lik((select started_at is not null from public.rounds where id = :'runde'), true, 'started_at satt');
select pg_temp.feil($$insert into public.rounds (club_id, event_id, round_no, status) values ('$$ || :'klubb' || $$', '$$ || :'kveld' || $$', 2, 'active')$$, '23505');
reset role;

-- === Føring =================================================================
-- Anders er markør i bås 1 (Anders, Dag)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
set role authenticated;
select pg_temp.lik(jsonb_array_length(public.save_hole(:'runde', 0,
  jsonb_build_array(jsonb_build_object('member_id', :'anders', 'strokes', 4),
                    jsonb_build_object('member_id', :'dag', 'strokes', 5)))), 2, 'markør lagrer hull for båsen');
select pg_temp.lik((select updated_by::text from public.hole_scores where round_id = :'runde' and member_id = :'dag' and hole_index = 0), :'anders', 'updated_by = markøren');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'runde', 0,
  jsonb_build_array(jsonb_build_object('member_id', :'anders', 'strokes', 4),
                    jsonb_build_object('member_id', :'dag', 'strokes', 5)))), 2, 'samme hull på nytt (idempotent)');
-- eldre innsending fra utboksen overskriver ikke
select pg_temp.lik((public.save_hole(:'runde', 0,
  jsonb_build_array(jsonb_build_object('member_id', :'anders', 'strokes', 9)), now() - interval '1 hour') -> 0 ->> 'strokes'), '4', 'gammel innsending hoppes over');
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 0, '[{"member_id":"$$ || :'thomas' || $$","strokes":4}]')$$, '42501');
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 0, '[{"member_id":"$$ || :'anders' || $$","strokes":4},{"member_id":"$$ || :'thomas' || $$","strokes":4}]')$$, '42501');
select pg_temp.lik((select strokes from public.hole_scores where round_id = :'runde' and member_id = :'anders' and hole_index = 0), 4::smallint, 'alt-eller-ingenting');
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 18, '[{"member_id":"$$ || :'anders' || $$","strokes":4}]')$$, '22023');
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 1, '[{"member_id":"$$ || :'anders' || $$","strokes":0}]')$$, '23514');
-- sidepremie
insert into public.side_claims (round_id, member_id, kind, meters) values (:'runde', :'anders', 'drive', 251.5);
select pg_temp.feil($$insert into public.side_claims (round_id, member_id, kind, meters) values ('$$ || :'runde' || $$', '$$ || :'dag' || $$', 'drive', 300)$$, '42501');
select pg_temp.feil($$insert into public.side_claims (round_id, member_id, kind, meters) values ('$$ || :'runde' || $$', '$$ || :'anders' || $$', 'kp', 600)$$, '23514');
-- påmelding
insert into public.signups (event_id, member_id, club_id, status, comment) values (:'kveld', :'anders', :'klubb', 'yes', 'kommer 17:30')
  on conflict (event_id, member_id) do update set status = excluded.status, comment = excluded.comment;
insert into public.signups (event_id, member_id, club_id, status) values (:'kveld', :'anders', :'klubb', 'maybe')
  on conflict (event_id, member_id) do update set status = excluded.status;
select pg_temp.lik((select status from public.signups where member_id = :'anders'), 'maybe', 'påmelding upsert');
select pg_temp.feil($$insert into public.signups (event_id, member_id, club_id, status) values ('$$ || :'kveld' || $$', '$$ || :'dag' || $$', '$$ || :'klubb' || $$', 'yes')$$, '42501');
-- skrive oppsett / slette runde som spiller
select pg_temp.feil($$select public.delete_round('$$ || :'runde' || $$')$$, '42501');
select pg_temp.feil($$select public.set_round_setup('$$ || :'runde' || $$', '[]')$$, '42501');
with d as (delete from public.rounds where id = :'runde' returning 1) select pg_temp.lik((select count(*) from d), 0::bigint, 'spiller kan ikke slette runde direkte');
reset role;

-- Dag (i bås med markør) kan ikke føre seg selv
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false);
set role authenticated;
select pg_temp.feil($$select public.save_hole('$$ || :'runde' || $$', 1, '[{"member_id":"$$ || :'dag' || $$","strokes":4}]')$$, '42501');
select pg_temp.feil($$insert into public.hole_scores (round_id, member_id, hole_index, strokes) values ('$$ || :'runde' || $$', '$$ || :'dag' || $$', 1, 4)$$, '42501');
reset role;

-- === Arrangøren: markørbytte, fjerning, lås, sletting ======================
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
select pg_temp.lik(public.set_round_setup(:'runde',
  jsonb_build_array(
    jsonb_build_object('member_id', :'anders', 'bay_no', 1),
    jsonb_build_object('member_id', :'dag',    'bay_no', 1, 'is_marker', true),
    jsonb_build_object('member_id', :'thomas', 'bay_no', 2),
    jsonb_build_object('member_id', :'bjorn',  'bay_no', 2))) ->> 'players', '4', 'markørbytte i samme bås');
select pg_temp.feil($$select public.set_round_setup('$$ || :'runde' || $$', '[{"member_id":"$$ || :'thomas' || $$"}]')$$, '55000');
select pg_temp.feil($$select public.set_round_setup('$$ || :'runde' || $$', '[{"member_id":"$$ || :'thomas' || $$","bay_no":1,"is_marker":true},{"member_id":"$$ || :'dag' || $$","bay_no":1,"is_marker":true},{"member_id":"$$ || :'anders' || $$"}]')$$, '23505');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'runde', 1,
  jsonb_build_array(jsonb_build_object('member_id', :'bjorn', 'strokes', 6)))), 1, 'arrangør fører for alle');
update public.rounds set status = 'locked' where id = :'runde';
select pg_temp.feil($$select public.delete_round('$$ || :'runde' || $$')$$, '55000');
with d as (delete from public.rounds where id = :'runde' returning 1) select pg_temp.lik((select count(*) from d), 0::bigint, 'låst runde slettes ikke direkte');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'runde', 2,
  jsonb_build_array(jsonb_build_object('member_id', :'bjorn', 'strokes', 5)))), 1, 'arrangør retter i låst runde');
update public.rounds set status = 'active' where id = :'runde';
select pg_temp.lik(public.delete_round(:'runde') ->> 'hole_scores', '4', 'delete_round teller scorer');
select pg_temp.lik((select count(*) from public.round_players where round_id = :'runde'), 0::bigint, 'barna er borte');
reset role;

-- Låst runde: markøren kan ikke føre
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false);
set role authenticated;
insert into public.rounds (club_id, event_id, round_no, status) values (:'klubb', :'kveld', 3, 'draft') returning id as runde2 \gset
select public.set_round_setup(:'runde2', jsonb_build_array(jsonb_build_object('member_id', :'anders', 'bay_no', 1, 'is_marker', true))) is not null as satt;
update public.rounds set status = 'locked' where id = :'runde2';
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false);
set role authenticated;
select pg_temp.feil($$select public.save_hole('$$ || :'runde2' || $$', 0, '[{"member_id":"$$ || :'anders' || $$","strokes":4}]')$$, '42501');
reset role;
