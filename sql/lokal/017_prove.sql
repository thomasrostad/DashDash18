\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 017_fundament.sql. Rekkefølge i en tom, lokal Postgres:
--   lokal/stub.sql, lokal/stub_storage.sql, 001–016, lokal/017_for.sql,
--   017_fundament.sql (gjerne to ganger), lokal/017_prove.sql.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Folk: Thomas (u1, arrangør i Golfgutu), Anders (u2), Bjørn (u3, markør),
-- Ola (u4, annen klubb), Dag (u5, venter på godkjenning), og to fremmede som
-- registrerer seg etter 017: Frida (u7) og Gunnar (u8).
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

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set u7 '00000000-0000-0000-0000-000000000007'
\set u8 '00000000-0000-0000-0000-000000000008'
\set bane    'cccccccc-0000-0000-0000-000000000001'
\set s2025   '5eeeeeee-0000-0000-0000-000000002025'
\set s2026   '5eeeeeee-0000-0000-0000-000000002026'
\set e3      'eeeeeeee-0000-0000-0000-000000000003'
\set e4      'eeeeeeee-0000-0000-0000-000000000004'
\set r1      'dddddddd-0000-0000-0000-000000000001'
\set r2      'dddddddd-0000-0000-0000-000000000002'
\set r3      'dddddddd-0000-0000-0000-000000000003'
\set r4      'dddddddd-0000-0000-0000-000000000004'
\set r5      'dddddddd-0000-0000-0000-000000000005'

-- === A. Klubbmedlemmene ser og kan det samme som før 017 ====================
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(lokal.bilde(), (select bilde from lokal.for_bilde where uid = :'u1'), 'Thomas (arrangør) ser og kan det samme som før');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(lokal.bilde(), (select bilde from lokal.for_bilde where uid = :'u2'), 'Anders (spiller) ser og kan det samme som før');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(lokal.bilde(), (select bilde from lokal.for_bilde where uid = :'u3'), 'Bjørn (markør) ser og kan det samme som før');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(lokal.bilde(), (select bilde from lokal.for_bilde where uid = :'u4'), 'Ola (annen klubb) ser og kan det samme som før');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik(lokal.bilde(), (select bilde from lokal.for_bilde where uid = :'u5'), 'Dag (venter) ser og kan det samme som før');
reset role;

-- === B. Dagens data i den nye modellen =======================================
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.profiles), 5::bigint, 'én profil per innlogging');
select pg_temp.lik((select display_name || '/' || handicap_index from public.profiles where id = :'u1'), 'Thomas/14.2',
                   'Thomas sin profil er fylt fra klubben');
select pg_temp.lik((select display_name from public.profiles where id = :'u5'), null::text,
                   'Dag venter på godkjenning: profilen har ikke noe navn ennå');
select pg_temp.lik((select count(*) from public.competitions where kind = 'season' and is_main and entry = 'club'), 3::bigint,
                   'én hovedkonkurranse per sesong (tre sesonger)');
select pg_temp.lik((select status || '/' || name from public.competitions where season_id = :'s2026'), 'active/Sesong 2026',
                   'jakkeracet 2026 er aktivt og heter som sesongen');
select pg_temp.lik((select string_agg(right(cr.round_id::text, 1), ',' order by cr.round_id)
                    from public.competition_rounds cr join public.competitions c on c.id = cr.competition_id
                    where c.season_id = :'s2026'), '2,3,4', 'rundene i 2026-kveldene teller i 2026 (også kladden)');
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'r5'), 0::bigint,
                   'runden i en kveld uten sesong teller ikke i noe');
select pg_temp.lik((select count(*) from public.rounds where club_id is null), 0::bigint, 'ingen løse runder ennå');

-- === C. Speilingen: nye runder, kvelder og sesonger ==========================
select pg_temp.som(:'u1'); set role authenticated;
insert into public.rounds (club_id, event_id, course_id, round_no) values (:'klubb', :'e3', :'bane', 3) returning id as r6 \gset
select pg_temp.lik((select source from public.competition_rounds cr join public.competitions c on c.id = cr.competition_id
                    where c.season_id = :'s2026' and cr.round_id = :'r6'), 'season', 'ny runde i en 2026-kveld kobles til jakkeracet');
update public.events set season_id = :'s2026' where id = :'e4';
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'r5'), 1::bigint,
                   'kvelden flyttes inn i 2026: runden følger med');
update public.seasons set name = 'Jakkeracet 2026' where id = :'s2026';
select pg_temp.lik((select name from public.competitions where season_id = :'s2026'), 'Jakkeracet 2026', 'nytt sesongnavn speiles');
select pg_temp.feil($$update public.competitions set name = 'Snik' where season_id = '$$ || :'s2026' || $$'$$, '42501');
select pg_temp.feil($$update public.competitions set is_main = false where season_id = '$$ || :'s2026' || $$'$$, '42501');
select pg_temp.feil($$insert into public.competitions (kind, name, club_id, is_main) values ('fun', 'Ny hoved', '$$ || :'klubb' || $$', true)$$, '22023');
delete from public.competition_rounds where round_id = :'r6';
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'r6'), 1::bigint,
                   'sesongens kobling kan ikke slettes av arrangøren (bare triggeren)');
insert into public.seasons (club_id, name) values (:'klubb', 'Sesong 2027') returning id as s2027 \gset
select pg_temp.lik((select status from public.competitions where season_id = :'s2027'), 'planned', 'ny sesong får en planlagt konkurranse');
select pg_temp.lik((public.activate_season(:'s2027')).status, 'active', 'activate_season virker som før');
select pg_temp.lik((select string_agg(c.status, ',' order by c.name) from public.competitions c
                    where c.season_id in (:'s2026', :'s2027')), 'finished,active',
                   'konkurransene følger: 2026 ferdig, 2027 aktiv');
select pg_temp.lik((public.activate_season(:'s2026')).status, 'active', 'tilbake til 2026');
select pg_temp.lik((select count(*) from public.competitions where club_id = :'klubb' and is_main and status = 'active'), 1::bigint,
                   'fortsatt én aktiv hovedkonkurranse i klubben');
reset role;

-- === D. Profiler =============================================================
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.ensure_profile()).display_name, 'Thomas', 'ensure_profile gir Thomas sin profil');
select pg_temp.lik((select count(*) from public.profiles), 4::bigint, 'Thomas ser profilene i klubben (fire med innlogging)');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((public.ensure_profile()).display_name, null::text, 'Dag (venter) får ikke navn fra en klubb han ikke er med i');
update public.profiles set display_name = 'Dag', handicap_index = 30 where id = :'u5';
select pg_temp.lik((select display_name from public.profiles where id = :'u5'), 'Dag', 'Dag setter navnet sitt selv');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
update public.profiles set display_name = 'Hacket' where id = :'u1';
select pg_temp.feil($$insert into public.profiles (id, display_name) values ('$$ || :'u4' || $$', 'Falsk')$$, '42501');
reset role;
select pg_temp.lik((select display_name from public.profiles where id = :'u1'), 'Thomas', 'Anders kan ikke endre Thomas sin profil');
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.profiles), 1::bigint, 'Ola (annen klubb) ser bare sin egen profil');
reset role;

-- === E. To fremmede registrerer seg ==========================================
select pg_temp.som('');
insert into auth.users values (:'u7'), (:'u8');
select pg_temp.lik((select count(*) from public.profiles where id in (:'u7', :'u8')), 2::bigint,
                   'ny innlogging får profil med én gang (trigger på auth.users)');

select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((public.ensure_profile()).id::text, :'u7', 'Frida: ensure_profile uten klubb');
update public.profiles set display_name = 'Frida', handicap_index = 22 where id = :'u7';
select pg_temp.lik((select jsonb_build_object('clubs', jsonb_array_length(b -> 'clubs'), 'rounds', jsonb_array_length(b -> 'rounds'),
                                              'members', jsonb_array_length(b -> 'club_members'), 'courses', jsonb_array_length(b -> 'courses'),
                                              'scores', b -> 'hole_scores', 'les', jsonb_array_length(b -> 'kan_lese'))
                    from lokal.bilde() b),
                   '{"clubs": 0, "rounds": 0, "members": 0, "courses": 0, "scores": 0, "les": 0}'::jsonb,
                   'Frida ser ingenting i noen klubb');
select pg_temp.lik((select count(*) from public.competitions), 0::bigint, 'Frida ser ingen konkurranser');
select pg_temp.lik((select count(*) from public.profiles), 1::bigint, 'Frida ser bare seg selv');
select pg_temp.lik((select count(*) from public.round_roster), 0::bigint, 'Frida ser ingen deltakere');

-- Felles bibliotek: Frida legger inn Losby.
insert into public.courses (club_id, name, kind) values (null, 'Losby', 'course') returning id as losby \gset
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select :'losby', h, 4, h from generate_series(1, 18) h;
select pg_temp.lik((select created_by_profile::text from public.courses where id = :'losby'), :'u7', 'Frida står som den som la inn banen');
select pg_temp.feil($$insert into public.courses (club_id, name, source, external_id) values (null, 'Hentet', 'golfapi', '123')$$, '42501');
select pg_temp.feil($$update public.courses set club_id = '$$ || :'klubb' || $$' where id = '$$ || :'losby' || $$'$$, '42501');
update public.courses set name = 'Kapret' where id = :'bane';
select pg_temp.feil($$select public.create_loose_round('$$ || :'bane' || $$')$$, '22023');
select pg_temp.feil($$select public.create_loose_round('$$ || :'losby' || $$', 18, 1, 'stableford', 'course',
  '[{"guest_name": "Per", "handicap_index": 12.4}, {"profile_id": "$$ || :'u8' || $$"}]')$$, '42501');
select pg_temp.lik((select count(*) from public.rounds), 0::bigint, 'avvist runde rulles helt tilbake');
select (public.create_loose_round(:'losby', 18, 1, 'stableford', 'course',
        '[{"guest_name": "Per", "handicap_index": 12.4}]')) ->> 'round_id' as frida_runde \gset
select pg_temp.lik((select status || '/' || coalesce(club_id::text, '-') || '/' || owner_id from public.rounds where id = :'frida_runde'),
                   'active/-/' || :'u7', 'løs runde: pågår, uten klubb, Frida eier');
select id as per from public.round_participants where round_id = :'frida_runde' and profile_id is null \gset
select id as frida_deltaker from public.round_participants where round_id = :'frida_runde' and profile_id = :'u7' \gset
select pg_temp.lik((select string_agg(display_name || ':' || is_guest || ':' || coalesce(handicap_index::text, '-'), ','
                                      order by display_name)
                    from public.round_roster r join public.round_players rp on rp.round_id = r.round_id and rp.member_id = r.player_id
                    where r.round_id = :'frida_runde'),
                   'Frida:false:22.0,Per:true:12.4', 'deltakerne: Frida (profil, handicap fra profilen) og Per (gjest)');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'frida_runde', 0,
                   jsonb_build_array(jsonb_build_object('member_id', :'per', 'strokes', 5),
                                     jsonb_build_object('member_id', :'frida_deltaker', 'strokes', 4)))), 2,
                   'Frida fører for seg selv og gjesten');
select pg_temp.feil($$delete from public.round_participants where id = '$$ || :'per' || $$'$$, '55000');
select pg_temp.feil($$insert into public.round_participants (round_id, profile_id, display_name)
  values ('$$ || :'frida_runde' || $$', '$$ || :'u8' || $$', 'Gunnar')$$, '42501');
select pg_temp.feil($$update public.rounds set owner_id = '$$ || :'u8' || $$' where id = '$$ || :'frida_runde' || $$'$$, '42501');
select pg_temp.feil($$update public.rounds set club_id = '$$ || :'klubb' || $$', event_id = '$$ || :'e3' || $$' where id = '$$ || :'frida_runde' || $$'$$, '42501');
select pg_temp.feil($$insert into public.round_participants (round_id, display_name) values ('$$ || :'r3' || $$', 'Snik')$$, '42501');
select pg_temp.feil($$select public.save_hole('$$ || :'r3' || $$', 0, '[{"member_id": "$$ || :'anders' || $$", "strokes": 3}]')$$, 'P0002');
reset role;
select pg_temp.lik((select name from public.courses where id = :'bane'), 'Marco Simone', 'Frida kan ikke endre klubbens bane');

select pg_temp.som(:'u8'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds), 0::bigint, 'Gunnar ser ikke Fridas runde');
select pg_temp.lik((select count(*) from public.round_participants), 0::bigint, 'Gunnar ser ingen deltakere');
select pg_temp.lik((select count(*) from public.hole_scores), 0::bigint, 'Gunnar ser ingen scorer');
select pg_temp.lik((select count(*) from public.profiles), 1::bigint, 'Gunnar ser bare seg selv (ikke Frida)');
select pg_temp.lik((select count(*) from public.courses), 1::bigint, 'Gunnar ser Losby i det felles biblioteket');
select pg_temp.feil($$select public.save_hole('$$ || :'frida_runde' || $$', 1, '[{"member_id": "$$ || :'per' || $$", "strokes": 3}]')$$, 'P0002');
select pg_temp.feil($$insert into public.round_participants (round_id, display_name) values ('$$ || :'frida_runde' || $$', 'Snik')$$, '42501');
select pg_temp.feil($$insert into public.course_holes (course_id, hole_number, par) values ('$$ || :'losby' || $$', 1, 3)$$, '42501');
update public.course_holes set par = 3 where course_id = :'losby';
update public.courses set name = 'Gunnars' where id = :'losby';
delete from public.rounds where id = :'frida_runde';
reset role;
select pg_temp.lik((select name || '/' || (select sum(par) from public.course_holes where course_id = :'losby') from public.courses where id = :'losby'),
                   'Losby/72', 'Gunnar kan ikke endre Fridas felles bane');
select pg_temp.lik((select count(*) from public.rounds where id = :'frida_runde'), 1::bigint, 'Gunnar kan ikke slette Fridas runde');

-- === F. Thomas: løs runde med Anders og en gjest =============================
select pg_temp.som(:'u1'); set role authenticated;
select (public.create_loose_round(:'losby', 18, 1, 'stableford', 'course',
        jsonb_build_array(jsonb_build_object('profile_id', :'u2'), jsonb_build_object('guest_name', 'Kari')))) ->> 'round_id' as tr \gset
select id as kari from public.round_participants where round_id = :'tr' and display_name = 'Kari' \gset
select id as anders_l from public.round_participants where round_id = :'tr' and profile_id = :'u2' \gset
select pg_temp.lik((select count(*) from public.round_roster where round_id = :'tr'), 3::bigint, 'Thomas, Anders og Kari i runden');
select pg_temp.lik((select handicap_index from public.round_players where round_id = :'tr' and member_id = :'anders_l'), 9.8,
                   'Anders sitt handicap frosset fra profilen ved start');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds where club_id is null), 1::bigint, 'Anders ser den løse runden han er med i');
select pg_temp.lik(jsonb_array_length(public.save_hole(:'tr', 0, jsonb_build_array(jsonb_build_object('member_id', :'anders_l', 'strokes', 4)))), 1,
                   'Anders fører for seg selv i den løse runden');
select pg_temp.feil($$select public.save_hole('$$ || :'tr' || $$', 0, '[{"member_id": "$$ || :'kari' || $$", "strokes": 4}]')$$, '42501');
insert into public.side_claims (round_id, member_id, kind, meters, created_by) values (:'tr', :'anders_l', 'drive', 251, :'thomas');
select pg_temp.lik((select created_by from public.side_claims where round_id = :'tr'), null::uuid,
                   'Anders melder inn egen sidepremie; created_by kan ikke forfalskes');
update public.rounds set status = 'locked' where id = :'tr';
reset role;
select pg_temp.lik((select status from public.rounds where id = :'tr'), 'active', 'Anders kan ikke låse Thomas sin runde');
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds where club_id is null), 0::bigint, 'Bjørn (i klubben, ikke i runden) ser den ikke');
reset role;

-- Kari tar runden med Frida sin konto (invitasjonsflyten kommer i fase 13; her som postgres).
select pg_temp.som('');
update public.round_participants set profile_id = :'u7' where id = :'kari';
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds), 2::bigint, 'Frida ser sin egen og Thomas sin løse runde');
select pg_temp.lik((select string_agg(display_name, ',' order by display_name) from public.profiles), 'Anders,Frida,Thomas',
                   'Frida ser profilene til dem hun har spilt med');
select pg_temp.lik((select count(*) from public.club_members), 0::bigint, 'men ikke troppen i Golfgutu');
reset role;

-- === G. Konkurranse med runder fra to steder ================================
select pg_temp.som(:'u1'); set role authenticated;
select public.create_competition('fun', 'Høstcup') as cup \gset
select pg_temp.lik((select owner_id::text || '/' || entry from public.competitions where id = :'cup'), :'u1' || '/listed', 'Høstcup: Thomas eier, påmeldte');
insert into public.competition_participants (competition_id, profile_id) values (:'cup', :'u7'), (:'cup', :'u2');
select pg_temp.feil($$insert into public.competition_participants (competition_id, profile_id) values ('$$ || :'cup' || $$', '$$ || :'u8' || $$')$$, '42501');
select pg_temp.feil($$insert into public.competition_participants (competition_id, member_id) values ('$$ || :'cup' || $$', '$$ || :'anders' || $$')$$, '22023');
insert into public.competition_rounds (competition_id, round_id) values (:'cup', :'r2'), (:'cup', :'tr');
select pg_temp.feil($$insert into public.competition_rounds (competition_id, round_id) values ('$$ || :'cup' || $$', '$$ || :'frida_runde' || $$')$$, '42501');
select pg_temp.feil($$insert into public.competition_rounds (competition_id, round_id, source) values ('$$ || :'cup' || $$', '$$ || :'r1' || $$', 'season')$$, '42501');
select pg_temp.feil($$update public.competitions set requires_purchase = true where id = '$$ || :'cup' || $$'$$, '42501');
select pg_temp.feil($$insert into public.entitlements (product_id) values ('no.dashdash.turnering')$$, '42501');
select pg_temp.lik((select count(*) from public.competition_rounds where competition_id = :'cup'), 2::bigint,
                   'Høstcup teller en klubbrunde (r2) og en løs runde');
reset role;

select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((select string_agg(name, ',') from public.competitions), 'Høstcup', 'Frida ser Høstcup og ingen klubbkonkurranser');
select pg_temp.lik((select count(*) from public.rounds), 3::bigint, 'Frida ser r2 via Høstcup, pluss de to løse');
select pg_temp.lik((select count(*) from public.hole_scores where round_id = :'r2'), 54::bigint, 'Frida ser scorene i r2 (til tabellen)');
select pg_temp.lik((select string_agg(display_name, ',' order by display_name) from public.round_roster where round_id = :'r2'),
                   'Anders,Bjørn,Thomas', 'og navnene i r2, via round_roster');
select pg_temp.lik((select count(*) from public.rounds where id in (:'r1', :'r3', :'r4')), 0::bigint, 'men ingen andre Golfgutu-runder');
select pg_temp.lik((select count(*) from public.seasons) + (select count(*) from public.events) + (select count(*) from public.club_members), 0::bigint,
                   'og ingen sesonger, kvelder eller tropp');
select pg_temp.feil($$select public.save_hole('$$ || :'r2' || $$', 0, '[{"member_id": "$$ || :'anders' || $$", "strokes": 3}]')$$, '42501');
select pg_temp.feil($$insert into public.competition_rounds (competition_id, round_id) values ('$$ || :'cup' || $$', '$$ || :'frida_runde' || $$')$$, '42501');
reset role;

select pg_temp.som(:'u8'); set role authenticated;
select pg_temp.lik((select count(*) from public.competitions) + (select count(*) from public.competition_rounds)
                   + (select count(*) from public.competition_participants), 0::bigint, 'Gunnar ser ingen konkurranser, koblinger eller påmeldte');
select public.create_competition('league', 'Gunnars liga') as liga \gset
select pg_temp.feil($$insert into public.competition_rounds (competition_id, round_id) values ('$$ || :'liga' || $$', '$$ || :'r2' || $$')$$, '42501');
select pg_temp.feil($$insert into public.competition_participants (competition_id, profile_id) values ('$$ || :'liga' || $$', '$$ || :'u1' || $$')$$, '42501');
select pg_temp.feil($$select public.create_competition('fun', 'Inntrenger', '$$ || :'klubb' || $$')$$, '42501');
select pg_temp.feil($$select public.create_competition('season', 'Falsk sesong')$$, '22023');
reset role;

select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.competitions where club_id is null), 0::bigint, 'Bjørn er ikke påmeldt Høstcup og ser den ikke');
select pg_temp.lik((select count(*) from public.competitions where club_id = :'klubb'), 3::bigint, 'men ser klubbens tre sesongkonkurranser');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.competitions where id = :'cup'), 1::bigint, 'Anders er påmeldt og ser Høstcup');
reset role;

select pg_temp.som(:'u7'); set role authenticated;
delete from public.competition_participants where competition_id = :'cup' and profile_id = :'u7';
select pg_temp.lik((select count(*) from public.rounds where id = :'r2'), 0::bigint, 'Frida melder seg av: r2 forsvinner for henne');
reset role;

-- === H. Dagens RPC-er virker som før =========================================
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(jsonb_array_length(public.save_hole(:'r3', 4, jsonb_build_array(jsonb_build_object('member_id', :'anders', 'strokes', 6)))), 1,
                   'save_hole: markøren Bjørn fører for Anders');
select pg_temp.lik(public.confirm_round_par(:'r3') is not null, true, 'confirm_round_par: markøren bekrefter');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.save_hole('$$ || :'r3' || $$', 5, '[{"member_id": "$$ || :'anders' || $$", "strokes": 4}]')$$, '42501');
select pg_temp.lik((public.create_bet(:'klubb', :'r3', null, 'Bjørn slår Anders i kveld', null, null, 'yes', 50)) ->> 'bet_id' is not null, true,
                   'create_bet virker i en klubbrunde');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.set_round_setup(:'r4', jsonb_build_array(jsonb_build_object('member_id', :'anders'),
                                                                    jsonb_build_object('member_id', :'bjorn')))) ->> 'players', '2',
                   'set_round_setup virker');
select pg_temp.feil($$select public.start_round('$$ || :'r4' || $$', '[{"member_id": "$$ || :'anders' || $$"}]')$$, '23505');
select pg_temp.lik((public.delete_round(:'r4')) ->> 'players', '2', 'delete_round virker');
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'r4'), 0::bigint, 'og koblingen til jakkeracet går med');
select pg_temp.lik((public.create_club('Ny klubb', 'Thomas')) is not null, true, 'create_club virker');
reset role;

-- === I. Sletting av runde og konto ============================================
select pg_temp.som(:'u1'); set role authenticated;
delete from public.rounds where id = :'tr';
select pg_temp.lik((select count(*) from public.rounds where id = :'tr'), 0::bigint, 'Thomas sletter sin løse runde (med scorer)');
reset role;
select pg_temp.lik((select count(*) from public.round_participants where round_id = :'tr')
                   + (select count(*) from public.competition_rounds where round_id = :'tr'), 0::bigint,
                   'deltakerne og konkurransekoblingen går med');
-- Frida slettes av serveren (uten auth.uid()), Gunnar «selv» (som en RPC ville gjort det).
select pg_temp.som('');
delete from auth.users where id = :'u7';
select pg_temp.lik((select owner_id from public.rounds where id = :'frida_runde'), null::uuid, 'Frida sletter kontoen: runden hennes står uten eier');
select pg_temp.lik((select count(*) from public.profiles where id = :'u7'), 0::bigint, 'og profilen er borte');
select pg_temp.lik((select string_agg(display_name || ':' || (profile_id is null), ',' order by display_name)
                    from public.round_participants where round_id = :'frida_runde'), 'Frida:true,Per:true',
                   'deltakerne står igjen som gjester med navn');
select pg_temp.lik((select count(*) from public.courses where id = :'losby' and created_by_profile is null), 1::bigint,
                   'banen hun la inn, står i biblioteket');
select pg_temp.som(:'u8');
delete from auth.users where id = :'u8';
select pg_temp.som('');
select pg_temp.lik((select owner_id from public.competitions where id = :'liga'), null::uuid, 'Gunnar sletter kontoen: ligaen står uten eier');

-- === J. Uinnlogget (anon) ====================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.profiles$$, '42501');
select pg_temp.feil($$select * from public.round_participants$$, '42501');
select pg_temp.feil($$select * from public.competitions$$, '42501');
select pg_temp.feil($$select * from public.competition_participants$$, '42501');
select pg_temp.feil($$select * from public.competition_rounds$$, '42501');
select pg_temp.feil($$select * from public.entitlements$$, '42501');
select pg_temp.feil($$select * from public.round_roster$$, '42501');
select pg_temp.feil($$select public.ensure_profile()$$, '42501');
select pg_temp.feil($$select public.create_loose_round(null)$$, '42501');
select pg_temp.feil($$select public.create_competition('fun', 'x')$$, '42501');
select pg_temp.feil($$select public.can_see_profile(gen_random_uuid())$$, '42501');
reset role;

-- Innlogget, men uten auth.uid() (bakvei): RPC-ene nekter.
select pg_temp.som('');
set role authenticated;
select pg_temp.feil($$select public.ensure_profile()$$, '42501');
select pg_temp.feil($$select public.create_loose_round(null)$$, '42501');
reset role;
