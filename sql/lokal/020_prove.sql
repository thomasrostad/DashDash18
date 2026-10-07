\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 020_spill.sql. Rekkefølge i en tom, lokal Postgres:
--   lokal/stub.sql, lokal/stub_storage.sql, 001–017, 020_spill.sql (gjerne to
--   ganger), lokal/020_prove.sql.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Folk: Thomas (u1, arrangør i Golfgutu), Anders (u2), Bjørn (u3, markør i bås
-- 1), Carl (ledig navn uten innlogging, bås 2), Ola (u4, annen klubb) og Frida
-- (u7, fremmed uten klubb).
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
\set ola     '22222222-0000-0000-0000-000000000004'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u7 '00000000-0000-0000-0000-000000000007'
\set bane    'cccccccc-0000-0000-0000-000000000001'
\set felles  'cccccccc-0000-0000-0000-0000000000ff'
\set e1      'eeeeeeee-0000-0000-0000-000000000001'
\set r1      'dddddddd-0000-0000-0000-000000000001'
\set r2      'dddddddd-0000-0000-0000-000000000002'

-- === Verdenen (som postgres) =================================================
select pg_temp.som('');
insert into auth.users values (:'u1'), (:'u2'), (:'u3'), (:'u4'), (:'u7');
update public.profiles set display_name = 'Frida' where id = :'u7';
insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, handicap_index, is_organizer, status) values
  (:'thomas', :'klubb',  :'u1', 'Thomas', 14.2, true,  'active'),
  (:'anders', :'klubb',  :'u2', 'Anders', 9.8,  false, 'active'),
  (:'bjorn',  :'klubb',  :'u3', 'Bjørn',  20.1, false, 'active'),
  (:'carl',   :'klubb',  null,  'Carl',   18.0, false, 'active'),
  (:'ola',    :'klubb2', :'u4', 'Ola',    5.0,  true,  'active');
insert into public.courses (id, club_id, name) values (:'bane', :'klubb', 'Marco Simone'), (:'felles', null, 'Felles bane');
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select c, h, 4, h from (values (:'bane'::uuid), (:'felles'::uuid)) v(c), generate_series(1, 18) h;
insert into public.events (id, club_id, event_date) values (:'e1', :'klubb', '2026-10-08');
-- r1 pågår (9 hull): Thomas uten bås, Anders og Bjørn (markør) i bås 1, Carl i bås 2.
-- r2 er låst.
insert into public.rounds (id, club_id, event_id, course_id, round_no, hole_count) values
  (:'r1', :'klubb', :'e1', :'bane', 1, 9),
  (:'r2', :'klubb', :'e1', :'bane', 2, 18);
insert into public.round_players (round_id, member_id, club_id, bay_no, is_marker) values
  (:'r1', :'thomas', :'klubb', null, false),
  (:'r1', :'anders', :'klubb', 1, false),
  (:'r1', :'bjorn',  :'klubb', 1, true),
  (:'r1', :'carl',   :'klubb', 2, false),
  (:'r2', :'thomas', :'klubb', null, false),
  (:'r2', :'anders', :'klubb', null, false);
update public.rounds set status = 'active' where id = :'r1';
update public.rounds set status = 'locked' where id = :'r2';

-- === A. Rettigheter ==========================================================
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$insert into public.round_games (round_id, kind) values ('$$ || :'r1' || $$', 'skins')$$, '42501');
select pg_temp.feil($$update public.round_games set status = 'settled'$$, '42501');
select pg_temp.feil($$delete from public.round_game_results$$, '42501');
select pg_temp.feil($$select public.round_game_shape_ok('wolf', '{null,null,null}')$$, '42501');
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.feil($$select count(*) from public.round_games$$, '42501');
select pg_temp.feil($$select public.create_round_game(null, 'skins', '{}', '[]')$$, '42501');
reset role;

-- === B. Lage spill ===========================================================
select pg_temp.som(:'u2'); set role authenticated;
-- Anders lager skins med Thomas, seg selv og Bjørn.
select public.create_round_game(:'r1', 'skins', '{"valuePerSkin": 5}',
  jsonb_build_array(jsonb_build_object('player_id', :'thomas'), jsonb_build_object('player_id', :'anders'),
                    jsonb_build_object('player_id', :'bjorn'))) as g_skins \gset
select pg_temp.lik((select kind || '/' || status || '/' || (settings ->> 'valuePerSkin') from public.round_games where id = :'g_skins'),
                   'skins/open/5', 'Anders lager skins med overstyrt verdi');
select pg_temp.lik((select string_agg(seat || ':' || right(player_id::text, 1), ',' order by seat) from public.round_game_players
                    where game_id = :'g_skins'), '1:1,2:2,3:3', 'deltakerne står i rekkefølge');
select pg_temp.lik((select created_by from public.round_games where id = :'g_skins'), :'u2'::uuid, 'skaperen er Anders sin profil');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '{}', '[{"player_id":"$$ || :'thomas' || $$"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '42501');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'wolf', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'best_ball', '{}', '[{"player_id":"$$ || :'anders' || $$","side":1},{"player_id":"$$ || :'bjorn' || $$","side":1},{"player_id":"$$ || :'thomas' || $$","side":1},{"player_id":"$$ || :'carl' || $$","side":2}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'ola' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'anders' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '[1]', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'kroner', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '{}', '[{"player_id":"ikke-en-id"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'nassau', '{}', '[{"player_id":"$$ || :'anders' || $$","side":1},{"player_id":"$$ || :'bjorn' || $$"}]')$$, '22023');
select pg_temp.feil($$select public.create_round_game('$$ || :'r2' || $$', 'skins', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'thomas' || $$"}]')$$, '55000');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
-- Thomas (arrangør) lager Wolf for de fire (også Carl uten innlogging), uten å
-- måtte være med selv, og 2 mot 2.
select public.create_round_game(:'r1', 'wolf', '{}',
  jsonb_build_array(jsonb_build_object('player_id', :'thomas'), jsonb_build_object('player_id', :'anders'),
                    jsonb_build_object('player_id', :'bjorn'), jsonb_build_object('player_id', :'carl'))) as g_wolf \gset
select public.create_round_game(:'r1', 'best_ball', '{"scoring": "stableford"}',
  jsonb_build_array(jsonb_build_object('player_id', :'thomas', 'side', 1), jsonb_build_object('player_id', :'anders', 'side', 1),
                    jsonb_build_object('player_id', :'bjorn', 'side', 2), jsonb_build_object('player_id', :'carl', 'side', 2))) as g_bb \gset
select pg_temp.lik((select count(*) from public.round_games where round_id = :'r1'), 3::bigint, 'tre spill i runden');
select public.create_round_game(:'r1', 'bbb', '{}',
  jsonb_build_array(jsonb_build_object('player_id', :'anders'), jsonb_build_object('player_id', :'carl'))) as g_bbb \gset
select pg_temp.lik((select string_agg(right(player_id::text, 1), ',' order by seat) from public.round_game_players where game_id = :'g_bbb'),
                   '2,9', 'spillere kan være med i noen spill og ikke andre');
select pg_temp.lik((select string_agg(side::text, ',' order by seat) from public.round_game_players where game_id = :'g_bb'),
                   '1,1,2,2', 'sidene i best ball');
reset role;

-- === C. Lesing ===============================================================
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_games), 4::bigint, 'Bjørn ser alle spillene i runden');
select pg_temp.lik((select count(*) from public.round_game_players), 13::bigint, 'Bjørn ser deltakerne');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_games), 0::bigint, 'Ola (annen klubb) ser ingen spill');
select pg_temp.lik((select count(*) from public.round_game_players), 0::bigint, 'Ola ser ingen deltakere');
select pg_temp.feil($$select public.create_round_game('$$ || :'r1' || $$', 'skins', '{}', '[{"player_id":"$$ || :'anders' || $$"},{"player_id":"$$ || :'bjorn' || $$"}]')$$, 'P0002');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 0, 'wolf', null, 'alone')$$, 'P0002');
select pg_temp.feil($$select public.delete_round_game('$$ || :'g_skins' || $$')$$, 'P0002');
reset role;

-- === D. Markeringer ==========================================================
-- Wolf-rekkefølgen er Thomas, Anders, Bjørn, Carl: Thomas er wolf på hull 1 (0).
select pg_temp.som(:'u2'); set role authenticated;
-- Anders står i bås 1 med markør, og Thomas fører selv: Anders kan ikke føre for noen.
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 0, 'wolf', '$$ || :'anders' || $$', 'partner')$$, '42501');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((public.set_round_game_mark(:'g_wolf', 0, 'wolf', :'anders', 'partner')) ->> 'wolf_mode', 'partner',
                   'Bjørn (markør) fører Wolf-valget: Thomas tar Anders');
select pg_temp.lik((public.set_round_game_mark(:'g_wolf', 0, 'wolf', null, 'alone')) ->> 'wolf_mode', 'alone',
                   'valget kan endres (alene)');
select pg_temp.lik((select count(*) from public.round_game_marks where game_id = :'g_wolf'), 1::bigint, 'én rad per hull og markering');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 0, 'wolf', '$$ || :'thomas' || $$', 'partner')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 1, 'wolf', null, 'partner')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 1, 'wolf', '$$ || :'carl' || $$', 'alone')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 9, 'wolf', null, 'blind')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 1, 'bingo', '$$ || :'anders' || $$')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_bbb' || $$', 1, 'bingo', '$$ || :'thomas' || $$')$$, '22023');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_skins' || $$', 1, 'bingo', '$$ || :'thomas' || $$')$$, '22023');
select pg_temp.lik((public.set_round_game_mark(:'g_wolf', 5, 'wolf', :'thomas', 'partner')) ->> 'hole_index', '5',
                   'hull 6: Anders er wolf og tar Thomas');
select pg_temp.lik((public.set_round_game_mark(:'g_bbb', 2, 'bango', :'carl')) ->> 'award', 'bango', 'Bjørn fører bango for Carl i bbb');
select pg_temp.lik(public.set_round_game_mark(:'g_wolf', 5, 'wolf'), null::jsonb, 'markeringen fjernes med tomme verdier');
select pg_temp.lik((select count(*) from public.round_game_marks where game_id = :'g_wolf'), 1::bigint, 'hull 6 er borte igjen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.set_round_game_mark(:'g_bbb', 3, 'bongo', :'anders')) ->> 'award', 'bongo', 'arrangøren fører alltid');
reset role;

-- === E. Fjerne et spill ======================================================
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$select public.delete_round_game('$$ || :'g_bbb' || $$')$$, '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.delete_round_game(:'g_bbb');
select pg_temp.lik((select count(*) from public.round_games where id = :'g_bbb'), 0::bigint, 'arrangøren fjerner bbb-spillet');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.round_game_marks where game_id = :'g_bbb'), 0::bigint, 'markeringene forsvant med spillet');

-- === F. Oppgjøret ============================================================
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":5,"$$ || :'anders' || $$":-5,"$$ || :'bjorn' || $$":0}')$$, '55000');
reset role;
select pg_temp.som(''); update public.rounds set status = 'locked' where id = :'r1';
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":5,"$$ || :'anders' || $$":-4,"$$ || :'bjorn' || $$":0}')$$, '22023');
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":5,"$$ || :'anders' || $$":-5}')$$, '22023');
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":5,"$$ || :'anders' || $$":-5,"$$ || :'carl' || $$":0}')$$, '22023');
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":2.5,"$$ || :'anders' || $$":-2.5,"$$ || :'bjorn' || $$":0}')$$, '22023');
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":5,"$$ || :'anders' || $$":-5,"$$ || :'bjorn' || $$":0,"x":0}')$$, '22023');
select public.settle_round_game(:'g_skins', jsonb_build_object(:'thomas', 10, :'anders', -15, :'bjorn', 5));
select pg_temp.lik((select status from public.round_games where id = :'g_skins'), 'settled', 'Anders (skaperen) gjør opp skins');
select pg_temp.lik((select sum(points) from public.round_game_results where game_id = :'g_skins'), 0::bigint, 'oppgjøret går i null');
select pg_temp.lik((select points from public.round_game_results where game_id = :'g_skins' and player_id = :'anders'), -15,
                   'Anders sine poeng står i banken for runden');
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_skins' || $$', '{"$$ || :'thomas' || $$":0,"$$ || :'anders' || $$":0,"$$ || :'bjorn' || $$":0}')$$, '55000');
select pg_temp.feil($$select public.delete_round_game('$$ || :'g_skins' || $$')$$, '55000');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$select public.settle_round_game('$$ || :'g_wolf' || $$', '{}')$$, '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.settle_round_game(:'g_skins', jsonb_build_object(:'thomas', 5, :'anders', -10, :'bjorn', 5));
select pg_temp.lik((select points from public.round_game_results where game_id = :'g_skins' and player_id = :'anders'), -10,
                   'arrangøren gjør opp på nytt (rettet score)');
select pg_temp.lik((select count(*) from public.round_game_results where game_id = :'g_skins'), 3::bigint, 'fortsatt én rad per spiller');
select pg_temp.lik(public.set_round_game_mark(:'g_wolf', 1, 'wolf', null, 'blind') ->> 'wolf_mode', 'blind',
                   'arrangøren kan rette Wolf-valg etter at runden er låst');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_wolf' || $$', 2, 'wolf', null, 'alone')$$, '42501');
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_skins' || $$', 2, 'wolf', null, 'alone')$$, '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$select public.set_round_game_mark('$$ || :'g_skins' || $$', 2, 'bingo', '$$ || :'thomas' || $$')$$, '55000');
reset role;

-- === G. Løs runde: bare deltakerne ser spillene ==============================
select pg_temp.som(:'u7'); set role authenticated;
select (public.create_loose_round(:'felles', 9, 1, 'stableford', null, '[{"guest_name": "Per"}]', true)) ->> 'round_id' as rl \gset
select id as frida from public.round_participants where round_id = :'rl' and profile_id = :'u7' \gset
select id as per from public.round_participants where round_id = :'rl' and profile_id is null \gset
select public.create_round_game(:'rl', 'bbb', '{"bango": 2}',
  jsonb_build_array(jsonb_build_object('player_id', :'frida'), jsonb_build_object('player_id', :'per'))) as g_los \gset
select pg_temp.lik((select count(*) from public.round_games where round_id = :'rl'), 1::bigint, 'Frida lager et spill i sin løse runde');
select pg_temp.lik((public.set_round_game_mark(:'g_los', 0, 'bingo', :'per')) ->> 'award', 'bingo', 'eieren fører for gjesten');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_games where round_id = :'rl'), 0::bigint, 'Thomas ser ikke spill i Fridas løse runde');
select pg_temp.feil($$select public.create_round_game('$$ || :'rl' || $$', 'skins', '{}', '[{"player_id":"$$ || :'frida' || $$"},{"player_id":"$$ || :'per' || $$"}]')$$, 'P0002');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_game_marks), 0::bigint, 'Ola ser ingen markeringer');
reset role;

-- === H. Sletting følger runden ===============================================
select pg_temp.som('');
delete from public.rounds where id = :'rl';
select pg_temp.lik((select count(*) from public.round_games where id = :'g_los'), 0::bigint, 'spillet forsvinner med runden');
select pg_temp.lik((select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
                    and tablename in ('round_games', 'round_game_players', 'round_game_marks', 'round_game_results')),
                   4::bigint, 'realtime for de fire tabellene');
