\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 022_konkurranser.sql. Rekkefølge i en tom, lokal Postgres:
--   lokal/stub.sql, lokal/stub_storage.sql, 001–016, lokal/017_for.sql,
--   017_fundament.sql, lokal/017_prove.sql, 018, 020, 021 (019 og 023 kan være med),
--   022_konkurranser.sql (gjerne to ganger), lokal/022_prove.sql.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Bygger på verdenen fra 017_for/017_prove: Thomas (u1, arrangør i Golfgutu),
-- Anders (u2), Bjørn (u3), Carl (ledig navn uten innlogging), Ola (u4, annen
-- klubb), Dag (u5, venter på godkjenning). r3 pågår i Golfgutu (Anders, Bjørn,
-- Carl, Thomas) og teller i jakkeracet. Losby er en felles bane. Hanne (u9)
-- registrerer seg her og kjenner ingen.
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
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set ola     '22222222-0000-0000-0000-000000000004'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set u9 '00000000-0000-0000-0000-000000000009'
\set r2      'dddddddd-0000-0000-0000-000000000002'
\set r3      'dddddddd-0000-0000-0000-000000000003'

select pg_temp.som('');
insert into auth.users values (:'u9');
select id as losby from public.courses where name = 'Losby' \gset
select id as jakke from public.competitions where season_id = '5eeeeeee-0000-0000-0000-000000002026' \gset

-- === A. Ny konkurranse med påmeldte (create_competition_with_entrants) =========
select pg_temp.som(:'u1'); set role authenticated;
select public.create_competition_with_entrants('league', 'Torsdagsligaen', :'klubb', 'listed', null, '2026-09-01', '2026-12-01',
                                               true, array[:'anders']::uuid[]) as liga \gset
select pg_temp.lik((select signup_open::text || '/' || entry || '/' || status from public.competitions where id = :'liga'),
                   'true/listed/active', 'liga i klubben: åpen påmelding, påmeldte, aktiv');
select pg_temp.lik((select count(*) from public.competition_participants where competition_id = :'liga'), 1::bigint,
                   'Anders er påmeldt ligaen');
select public.create_competition_with_entrants('cup', 'Klubbcupen', :'klubb', 'listed', '{"version": 2, "competition": {"cup": {"tie": "countback"}}}',
                                               null, null, false,
                                               array[:'thomas', :'anders', :'bjorn', :'carl']::uuid[]) as cup \gset
select pg_temp.lik((select count(*) from public.competition_participants where competition_id = :'cup'), 4::bigint,
                   'cupen har fire påmeldte, også Carl uten innlogging');
select pg_temp.lik((select rules -> 'competition' -> 'cup' ->> 'tie' from public.competitions where id = :'cup'), 'countback',
                   'regelsettet lagres som det kom');
select pg_temp.feil($$select public.create_competition_with_entrants('season', 'Falsk', '$$ || :'klubb' || $$')$$, '22023');
select pg_temp.feil($$select public.create_competition_with_entrants('game', 'Skins', '$$ || :'klubb' || $$')$$, '22023');
select pg_temp.feil($$select public.create_competition_with_entrants('cup', 'Åpen cup', '$$ || :'klubb' || $$', 'open')$$, '22023');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Tropp', '$$ || :'klubb' || $$', 'club', null, null, null, true)$$, '22023');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Fremmed', '$$ || :'klubb' || $$', 'listed', null, null, null, false, array['$$ || :'ola' || $$']::uuid[])$$, '22023');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Feil periode', '$$ || :'klubb' || $$', 'listed', null, '2026-10-02', '2026-10-01')$$, '23514');
select pg_temp.lik((select count(*) from public.competitions where name in ('Falsk', 'Skins', 'Åpen cup', 'Tropp', 'Fremmed', 'Feil periode')),
                   0::bigint, 'ingenting lagret når et kall feiler (én transaksjon)');
reset role;

select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Kupp', '$$ || :'klubb' || $$')$$, '42501');
select public.create_competition_with_entrants('fun', 'Anders sin morro', null, 'listed', null, '2026-10-01', '2026-10-31',
                                               false, '{}', array[:'u1']::uuid[]) as morro \gset
select pg_temp.lik((select string_agg(profile_id::text, ',' order by profile_id) from public.competition_participants
                    where competition_id = :'morro'), :'u1' || ',' || :'u2', 'privat morro: Anders (eier) og Thomas');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Medlemmer', null, 'listed', null, null, null, false, array['$$ || :'bjorn' || $$']::uuid[])$$, '22023');
reset role;

select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'Hannes', null, 'listed', null, null, null, false, '{}', array['$$ || :'u2' || $$']::uuid[])$$, '42501');
select pg_temp.lik((select count(*) from public.competitions where name = 'Hannes'), 0::bigint,
                   'Hanne kan ikke trekke inn Anders, og ingenting ble lagret');
reset role;

-- === B. Meld meg på og av ======================================================
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.competitions where id = :'liga'), 1::bigint, 'Bjørn (medlem) ser ligaen');
select (public.join_competition(:'liga')).id as bjorn_liga \gset
select pg_temp.lik((select member_id::text || '/' || status from public.competition_participants where id = :'bjorn_liga'),
                   :'bjorn' || '/active', 'Bjørn melder seg på som medlem');
select pg_temp.lik((public.join_competition(:'liga')).id, :'bjorn_liga'::uuid, 'på igjen: samme rad (idempotent)');
select pg_temp.lik(public.leave_competition(:'liga'), true, 'Bjørn melder seg av');
select pg_temp.lik((select status from public.competition_participants where id = :'bjorn_liga'), 'withdrawn', 'raden står, meldt av');
select pg_temp.lik(public.leave_competition(:'liga'), false, 'av igjen: ingenting å gjøre');
select pg_temp.lik((public.join_competition(:'liga')).status, 'active', 'og på igjen');
select pg_temp.feil($$select public.join_competition('$$ || :'cup' || $$')$$, '55000');
select pg_temp.feil($$select public.join_competition('$$ || :'morro' || $$')$$, 'P0002');
select pg_temp.feil($$insert into public.competition_participants (competition_id, member_id) values ('$$ || :'cup' || $$', '$$ || :'bjorn' || $$')$$, '42501');
reset role;

select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.feil($$select public.join_competition('$$ || :'liga' || $$')$$, 'P0002');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil($$select public.join_competition('$$ || :'liga' || $$')$$, 'P0002');
select pg_temp.lik((select count(*) from public.competitions where id in (:'liga', :'cup', :'morro')), 0::bigint,
                   'Ola (annen klubb) ser ingen av dem');
reset role;
select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.feil($$select public.join_competition('$$ || :'morro' || $$')$$, 'P0002');
select pg_temp.feil($$select public.join_competition(gen_random_uuid())$$, 'P0002');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set status = 'finished' where id = :'liga';
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.join_competition('$$ || :'liga' || $$')$$, '55000');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set status = 'active' where id = :'liga';
select pg_temp.feil($$update public.competitions set signup_open = true where id = '$$ || :'jakke' || $$'$$, '23514');
reset role;

-- === C. «Teller også i …» (set_round_competitions) ===============================
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.set_round_competitions(:'r3', array[:'liga']::uuid[]), '{"added": 1, "removed": 0}'::jsonb,
                   'Thomas legger r3 i ligaen');
select pg_temp.lik(public.set_round_competitions(:'r3', array[:'liga']::uuid[]), '{"added": 0, "removed": 0}'::jsonb,
                   'samme liste igjen: ingenting endres');
select pg_temp.lik((select added_by from public.competition_rounds where competition_id = :'liga' and round_id = :'r3'),
                   :'u1'::uuid, 'hvem la til, settes av serveren');
select pg_temp.lik(public.set_round_competitions(:'r3', array[:'liga', :'cup']::uuid[]), '{"added": 1, "removed": 0}'::jsonb,
                   'og i cupen');
select pg_temp.lik(public.set_round_competitions(:'r3', array[:'cup']::uuid[]), '{"added": 0, "removed": 1}'::jsonb,
                   'tar r3 ut av ligaen');
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'r3' and competition_id = :'jakke'
                      and source = 'season'), 1::bigint, 'koblingen til jakkeracet står urørt');
select pg_temp.feil($$select public.set_round_competitions('$$ || :'r3' || $$', array['$$ || :'jakke' || $$']::uuid[])$$, '22023');
select pg_temp.feil($$select public.set_round_competitions('$$ || :'r3' || $$', array['$$ || :'morro' || $$']::uuid[])$$, '42501');
update public.competitions set status = 'finished' where id = :'liga';
select pg_temp.feil($$select public.set_round_competitions('$$ || :'r3' || $$', array['$$ || :'liga' || $$']::uuid[])$$, '22023');
update public.competitions set status = 'active' where id = :'liga';
reset role;

select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.set_round_competitions('$$ || :'r3' || $$', array['$$ || :'morro' || $$']::uuid[])$$, '42501');
select (public.create_loose_round(:'losby', 18, 1, 'stableford', 'course',
        jsonb_build_array(jsonb_build_object('profile_id', :'u1')))) ->> 'round_id' as los \gset
select pg_temp.lik(public.set_round_competitions(:'los', array[:'morro']::uuid[]), '{"added": 1, "removed": 0}'::jsonb,
                   'Anders legger sin løse runde med Thomas i morroturneringen');
select pg_temp.lik(public.set_round_competitions(:'los', '{}'), '{"added": 0, "removed": 1}'::jsonb,
                   'tom liste tar den ut igjen');
select pg_temp.lik(public.set_round_competitions(:'los', array[:'morro']::uuid[]), '{"added": 1, "removed": 0}'::jsonb,
                   'og inn igjen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.create_competition_with_entrants('fun', 'Thomas alene', null) as alene \gset
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.set_round_competitions('$$ || :'los' || $$', array['$$ || :'alene' || $$']::uuid[])$$, '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
-- Thomas styrer «Thomas alene», men eier ikke Anders sin runde.
select pg_temp.feil($$select public.set_round_competitions('$$ || :'los' || $$', array['$$ || :'alene' || $$']::uuid[])$$, '42501');
-- I klubben: r2 (låst) med bare medlemmer, og en liga der ingen av dem er påmeldt.
select public.create_competition_with_entrants('league', 'Tom liga', :'klubb', 'listed') as tom \gset
select pg_temp.feil($$select public.set_round_competitions('$$ || :'r2' || $$', array['$$ || :'tom' || $$']::uuid[])$$, '22023');
-- r2 lå i Thomas sin Høstcup (fra 017-prøven). Lista er hele svaret blant
-- konkurransene Thomas styrer, så Høstcup tas ut når den ikke står i lista.
select pg_temp.lik(public.set_round_competitions(:'r2', array[:'liga']::uuid[]), '{"added": 1, "removed": 1}'::jsonb,
                   'r2 har Anders og Bjørn, som er påmeldt ligaen (og Høstcup tas ut)');
select pg_temp.lik((select string_agg(c.name, ',' order by c.name) from public.competition_rounds cr
                    join public.competitions c on c.id = cr.competition_id where cr.round_id = :'r2'),
                   'Jakkeracet 2026,Torsdagsligaen', 'r2 teller nå i jakkeracet og ligaen');
reset role;

-- Bjørn ser den løse runden? Nei: han er ikke med i morroturneringen.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds where id = :'los'), 0::bigint, 'Bjørn ser ikke Anders sin løse runde');
reset role;

-- === D. Cup: trekning og resultater =============================================
select id as c_thomas from public.competition_participants where competition_id = :'cup' and member_id = :'thomas' \gset
select id as c_anders from public.competition_participants where competition_id = :'cup' and member_id = :'anders' \gset
select id as c_bjorn  from public.competition_participants where competition_id = :'cup' and member_id = :'bjorn' \gset
select id as c_carl   from public.competition_participants where competition_id = :'cup' and member_id = :'carl' \gset

select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$select public.draw_cup('$$ || :'cup' || $$', '[]')$$, '42501');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$select public.draw_cup('$$ || :'liga' || $$', '[]')$$, '22023');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', :'c_carl'),
                    jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', null))), '22023');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', :'c_carl'),
                    jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', :'c_thomas'))), '22023');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', :'c_carl'),
                    jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', :'c_bjorn'),
                    jsonb_build_object('slot', 2, 'a', :'c_anders', 'b', :'c_bjorn'))), '22023');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', null), jsonb_build_object('slot', 1, 'a', :'c_carl', 'b', null),
                    jsonb_build_object('slot', 2, 'a', :'c_anders', 'b', null), jsonb_build_object('slot', 3, 'a', :'c_bjorn', 'b', null))), '22023');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', 'ikke-en-id', 'b', :'c_carl'))), '22023');
select pg_temp.lik(public.draw_cup(:'cup', jsonb_build_array(
                     jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', :'c_carl'),
                     jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', :'c_bjorn'))), 2, 'Thomas trekker cupen: to semifinaler');
select pg_temp.lik(public.draw_cup(:'cup', jsonb_build_array(
                     jsonb_build_object('slot', 0, 'a', :'c_anders', 'b', :'c_carl'),
                     jsonb_build_object('slot', 1, 'a', :'c_thomas', 'b', :'c_bjorn'))), 2, 'og trekker på nytt før første resultat');
select pg_temp.lik((select count(*) from public.competition_matches where competition_id = :'cup'), 2::bigint,
                   'den gamle trekningen er borte');
select pg_temp.feil($$insert into public.competition_matches (competition_id, round_no, slot) values ('$$ || :'cup' || $$', 2, 0)$$, '42501');
select pg_temp.feil($$update public.competition_matches set winner = player_a where competition_id = '$$ || :'cup' || $$'$$, '42501');
reset role;

-- Bjørn trekker seg før kampen: arrangøren trekker på nytt med tre, og Thomas får bye.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.leave_competition(:'cup'), true, 'Bjørn melder seg av cupen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_anders', 'b', :'c_carl'),
                    jsonb_build_object('slot', 1, 'a', :'c_thomas', 'b', :'c_bjorn'))), '22023');
select pg_temp.lik(public.draw_cup(:'cup', jsonb_build_array(
                     jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', null),
                     jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', :'c_carl'))), 2, 'ny trekning med tre: Thomas får bye');
select pg_temp.lik((select winner from public.competition_matches where competition_id = :'cup' and round_no = 1 and slot = 0),
                   :'c_thomas'::uuid, 'byen er avgjort med én gang');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 0, %L)$$, :'cup', :'c_thomas'), '22023');
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, %L)$$, :'cup', :'c_thomas'), '55000');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'cup', :'c_thomas'), '22023');
select pg_temp.feil(format($$select public.record_cup_result(%L, 3, 0, %L)$$, :'cup', :'c_thomas'), '22023');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 2, %L)$$, :'cup', :'c_thomas'), '22023');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L, false, '2 opp', %L)$$, :'cup', :'c_carl', :'los'), '22023');
reset role;

-- Spillerne fører selv (besluttet 07.10.2026). Første førte resultat gjelder.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, null)$$, :'cup'), '42501');
select pg_temp.lik((public.record_cup_result(:'cup', 1, 1, :'c_anders', false, '1 opp', :'r3')).recorded_by, :'u2'::uuid,
                   'Anders (spiller i kampen) fører selv, og det logges hvem som førte');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'cup', :'c_carl'), '55000');
select pg_temp.lik((select winner from public.competition_matches where competition_id = :'cup' and round_no = 1 and slot = 1),
                   :'c_anders'::uuid, 'ny registrering fra en spiller etter resultatet avvises, første gjelder');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, null)$$, :'cup'), '42501');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
-- Bjørn har meldt seg av og er ikke i kampen.
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'cup', :'c_anders'), '42501');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.record_cup_result(:'cup', 1, 1, :'c_carl', false, '2 opp', :'r3')).winner, :'c_carl'::uuid,
                   'arrangøren retter: Carl slo Anders 2 opp i r3 (runden teller i cupen)');
select pg_temp.lik((select recorded_by from public.competition_matches where competition_id = :'cup' and round_no = 1 and slot = 1),
                   :'u1'::uuid, 'rettingen logger arrangøren');
select pg_temp.feil(format($$select public.draw_cup(%L, %L)$$, :'cup',
  jsonb_build_array(jsonb_build_object('slot', 0, 'a', :'c_thomas', 'b', null),
                    jsonb_build_object('slot', 1, 'a', :'c_anders', 'b', :'c_carl'))), '55000');
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, %L)$$, :'cup', :'c_anders'), '22023');
select pg_temp.lik((public.record_cup_result(:'cup', 2, 0, :'c_thomas', true)).walkover, true, 'finalen: Thomas på walkover');
select pg_temp.lik((select player_a::text || '/' || player_b::text from public.competition_matches
                    where competition_id = :'cup' and round_no = 2 and slot = 0),
                   :'c_thomas' || '/' || :'c_carl', 'finalen er Thomas mot Carl (vinnerne av kamp 0 og 1)');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'cup', :'c_anders'), '55000');
select pg_temp.lik((public.record_cup_result(:'cup', 2, 0, null)).round_no, 2::smallint, 'finaleresultatet fjernes');
select pg_temp.lik((select count(*) from public.competition_matches where competition_id = :'cup' and round_no = 2), 0::bigint,
                   'og finalen finnes ikke før neste resultat');
select pg_temp.lik((public.record_cup_result(:'cup', 1, 1, :'c_anders', false, '1 opp')).winner, :'c_anders'::uuid,
                   'semifinalen rettes: Anders vant');
select pg_temp.feil($$delete from public.competition_participants where id = '$$ || :'c_carl' || $$'$$, '23503');
reset role;

-- Finalen: Anders fører selv (raden lages av hans registrering).
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((public.record_cup_result(:'cup', 2, 0, :'c_anders', false, '3&2')).player_b, :'c_anders'::uuid,
                   'finalen er nå Thomas mot Anders, og Anders fører at han vant');
select pg_temp.lik((select recorded_by::text || '/' || result from public.competition_matches
                    where competition_id = :'cup' and round_no = 2 and slot = 0), :'u2' || '/3&2', 'finalen er ført av Anders');
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, %L)$$, :'cup', :'c_thomas'), '55000');
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, null)$$, :'cup'), '42501');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'cup', :'c_carl'), '55000');
select pg_temp.lik((select count(*) from public.competition_matches where competition_id = :'cup'), 3::bigint,
                   'Anders (medlem) ser kampene');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.competition_matches), 0::bigint, 'Ola ser ingen kamper');
reset role;
select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.lik((select count(*) from public.competition_matches), 0::bigint, 'Hanne ser ingen kamper');
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, %L)$$, :'cup', :'c_thomas'), 'P0002');
select pg_temp.feil(format($$select public.draw_cup(%L, '[]')$$, :'cup'), 'P0002');
select pg_temp.feil(format($$select public.set_round_competitions(%L, array[%L]::uuid[])$$, :'r3', :'cup'), 'P0002');
reset role;

-- Påmelding åpnes på en trukket cup: ingen nye.
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set signup_open = true where id = :'cup';
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil($$select public.join_competition('$$ || :'cup' || $$')$$, '55000');
reset role;

-- Cupen slettes: kampene og påmeldingene går med.
select pg_temp.som(:'u1'); set role authenticated;
delete from public.competitions where id = :'cup';
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.competition_matches where competition_id = :'cup')
                   + (select count(*) from public.competition_participants where competition_id = :'cup'), 0::bigint,
                   'arrangøren sletter cupen: kampene og påmeldingene går med');

-- === E. Uinnlogget (anon) og bakvei uten auth.uid() ==============================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.competition_matches$$, '42501');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'x')$$, '42501');
select pg_temp.feil($$select public.join_competition(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.leave_competition(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.set_round_competitions(gen_random_uuid(), '{}')$$, '42501');
select pg_temp.feil($$select public.draw_cup(gen_random_uuid(), '[]')$$, '42501');
select pg_temp.feil($$select public.record_cup_result(gen_random_uuid(), 1, 0, null)$$, '42501');
select pg_temp.feil($$select * from public.competition_invites$$, '42501');
select pg_temp.feil($$select public.competition_invite(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.competition_invite_preview('ABCDEFGH23')$$, '42501');
select pg_temp.feil($$select public.claim_competition_invite('ABCDEFGH23')$$, '42501');
reset role;

set role authenticated;
select pg_temp.feil($$select public.competition_round_entrants(gen_random_uuid(), gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.create_competition_with_entrants('fun', 'x')$$, '42501');
select pg_temp.feil($$select public.join_competition(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.set_round_competitions(gen_random_uuid(), '{}')$$, '42501');
select pg_temp.feil($$select public.record_cup_result(gen_random_uuid(), 1, 0, null)$$, '42501');
select pg_temp.feil($$select public.competition_invite(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.competition_invite_preview('ABCDEFGH23')$$, '42501');
select pg_temp.feil($$select public.claim_competition_invite('ABCDEFGH23')$$, '42501');
reset role;

-- === F. 017 står: jakkeracet og kontrollen ======================================
select pg_temp.lik((select count(*) from public.competitions where kind = 'season' and (signup_open or not is_main
                      or entry <> 'club')), 0::bigint, 'sesongkonkurransene er urørt, uten åpen påmelding');
select pg_temp.lik((select count(*) from pg_policies where schemaname = 'public'
                      and tablename in ('competitions', 'competition_participants', 'competition_rounds')), 11::bigint,
                   'policyene fra 017 er urørt');

-- === G. Invitasjon til en privat konkurranse (kode og lenke) =====================
-- Anders lager en privat cup med Thomas. Hanne (fremmed) og Bjørn blir med
-- med koden. Spillerne fører resultatene selv, og Anders (eier) retter.
select pg_temp.som('');
select display_name as anders_navn from public.profiles where id = :'u2' \gset
select pg_temp.som(:'u2'); set role authenticated;
select public.create_competition_with_entrants('cup', 'Vennecupen', null, 'listed', null, null, null, false,
                                               '{}', array[:'u1']::uuid[]) as venn \gset
select public.competition_invite(:'venn') ->> 'code' as kode \gset
select pg_temp.lik(:'kode' ~ '^[0-9A-HJKMNP-TV-Z]{10}$', true, 'koden er 10 tegn Crockford base32');
select pg_temp.lik(public.competition_invite(:'venn') ->> 'code', :'kode', 'samme kode igjen (idempotent)');
select pg_temp.lik((public.competition_invite(:'venn') ->> 'expires_at')::timestamptz between now() + interval '6 days 23 hours'
                     and now() + interval '7 days 1 hour', true, 'koden utløper om 7 dager');
reset role;

select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.competition_invite(:'venn') ->> 'code', :'kode', 'Thomas (påmeldt) får samme kode');
select pg_temp.lik((select count(*) from public.competition_invites where competition_id = :'venn'), 1::bigint,
                   'Thomas (påmeldt) ser koden');
select pg_temp.feil(format($$select public.competition_invite(%L)$$, :'liga'), '22023');
reset role;

select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.lik((select count(*) from public.competition_invites), 0::bigint, 'Hanne ser ingen koder');
select pg_temp.feil(format($$select public.competition_invite(%L)$$, :'venn'), 'P0002');
select pg_temp.feil($$insert into public.competition_invites (competition_id, code, expires_at) values ('$$ || :'venn' || $$', 'ABCDEFGH23', now() + interval '1 day')$$, '42501');
select public.competition_invite_preview(lower(substr(:'kode', 1, 5)) || '-' || substr(:'kode', 6)) as forh \gset
select pg_temp.lik((select string_agg(k, ',' order by k) from jsonb_object_keys(:'forh'::jsonb) k),
                   'competition_id,entered,entrants,kind,name,owner_name', 'forhåndsvisningen: navn, type, eier og antall, ikke mer');
select pg_temp.lik(:'forh'::jsonb ->> 'name' || '/' || (:'forh'::jsonb ->> 'kind') || '/' || (:'forh'::jsonb ->> 'entrants')
                   || '/' || (:'forh'::jsonb ->> 'entered'), 'Vennecupen/cup/2/false', 'Hanne ser Vennecupen, cup, 2 påmeldte');
select pg_temp.lik(:'forh'::jsonb ->> 'owner_name', :'anders_navn', 'og eieren');
select pg_temp.feil($$select public.competition_invite_preview('ABCDEFGH23')$$, 'P0002');
select pg_temp.feil($$select public.competition_invite_preview('')$$, 'P0002');
select pg_temp.lik((select count(*) from public.competitions where id = :'venn'), 0::bigint, 'Hanne ser ikke cupen før hun blir med');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Hanne blir med med koden');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'already', 'igjen: hun er med fra før');
select pg_temp.lik((select count(*) from public.competitions where id = :'venn'), 1::bigint, 'Hanne ser cupen');
select pg_temp.lik((select count(*) from public.competition_invites where competition_id = :'venn'), 1::bigint,
                   'og koden, så hun kan dele den videre');
select pg_temp.lik(public.leave_competition(:'venn'), true, 'Hanne melder seg av');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'rejoined', 'og på igjen med koden');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Bjørn blir med med koden');
reset role;

-- Koden går ut: ingen ser noe, og eieren får en ny.
select pg_temp.som('');
update public.competition_invites set expires_at = now() - interval '1 minute' where competition_id = :'venn';
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), 'P0002');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), 'P0002');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select public.competition_invite(:'venn') ->> 'code' as kode2 \gset
select pg_temp.lik(:'kode2' <> :'kode', true, 'ny kode når den gamle har gått ut');
reset role;

-- Trekning: Anders – Thomas og Hanne – Bjørn. Da tar cupen ingen nye.
select pg_temp.som('');
select id as v_anders from public.competition_participants where competition_id = :'venn' and profile_id = :'u2' \gset
select id as v_thomas from public.competition_participants where competition_id = :'venn' and profile_id = :'u1' \gset
select id as v_hanne  from public.competition_participants where competition_id = :'venn' and profile_id = :'u9' \gset
select id as v_bjorn  from public.competition_participants where competition_id = :'venn' and profile_id = :'u3' \gset
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.draw_cup(:'venn', jsonb_build_array(
                     jsonb_build_object('slot', 0, 'a', :'v_anders', 'b', :'v_thomas'),
                     jsonb_build_object('slot', 1, 'a', :'v_hanne', 'b', :'v_bjorn'))), 2, 'Anders trekker Vennecupen');
select pg_temp.feil(format($$select public.competition_invite(%L)$$, :'venn'), '55000');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode2'), '55000');
reset role;

-- Resultatene: spillerne fører sin egen kamp, én gang.
select pg_temp.som(:'u9'); set role authenticated;
select pg_temp.lik(public.claim_competition_invite(:'kode2') ->> 'joined', 'already', 'Hanne er med etter trekningen');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 0, %L)$$, :'venn', :'v_anders'), '42501');
select pg_temp.lik((public.record_cup_result(:'venn', 1, 1, :'v_hanne', false, '4&3')).recorded_by, :'u9'::uuid,
                   'Hanne fører sin egen kamp');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, %L)$$, :'venn', :'v_bjorn'), '55000');
select pg_temp.feil(format($$select public.record_cup_result(%L, 1, 1, null)$$, :'venn'), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.record_cup_result(:'venn', 1, 0, :'v_thomas', true)).walkover, true, 'Thomas fører walkover i sin kamp');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((public.record_cup_result(:'venn', 1, 1, :'v_bjorn', false, '1 opp')).recorded_by, :'u2'::uuid,
                   'Anders (eier) retter: Bjørn vant');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((public.record_cup_result(:'venn', 2, 0, :'v_bjorn', false, '2&1')).player_a, :'v_thomas'::uuid,
                   'Bjørn fører finalen mot Thomas');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($$select public.record_cup_result(%L, 2, 0, %L)$$, :'venn', :'v_thomas'), '55000');
reset role;

-- Ferdig: koden virker ikke lenger. Slettet: koden går med.
select pg_temp.som(:'u2'); set role authenticated;
update public.competitions set status = 'finished' where id = :'venn';
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode2'), '55000');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode2'), '55000');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
delete from public.competitions where id = :'venn';
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.competition_invites where competition_id = :'venn'), 0::bigint,
                   'eieren sletter cupen: koden går med');
