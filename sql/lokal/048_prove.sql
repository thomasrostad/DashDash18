\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 048_formater.sql. Kjøres på kopien med p034 + lokal/044_for.sql + 044 + 045 + 047 +
-- lokal/046_for.sql + 046 + 049 + 050 + 051 + 048 (to ganger). Alt rulles tilbake. Hver linje
-- skal starte med "ok"; ingen "FEIL". Datoene regnes fra current_date.
--
-- A: standardverdiene: ingen konkurranser, rundene som fantes er like, etterfyllingen er der.
-- K: round_competitions_set: flere konkurranser med én hoved, sjekkene, beholde id, slette.
-- M: speilingen av rounds.format begge veier (også fra gamle bygg).
-- R: rettigheter (rounds, ikke tournaments, ikke medlem, låst runde, ingen direkte skriving, RLS).
-- S: øyeblikksbildet: tomt i kladd, fryses ved start, endres ikke av regelsett, bane, tee eller
--    rundens hull etterpå, «Oppdater øyeblikksbildet», låst runde, 9 hull fra hull 10, tee-hull,
--    egen bane uten helt sett, løs runde, rett inn som aktiv.
-- D: side for lag mot lag i set_round_setup (gamle bygg visker ikke ut).
-- E: Tavla, TV (uten bruker-id) og «Samme som sist».
-- N: anon.
-- ===========================================================================

create function pg_temp.feil(p_sql text, p_kode text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FEIL (gikk gjennom): ' || p_sql;
exception when others then
  if sqlstate = p_kode then return 'ok ' || p_kode || ': ' || left(sqlerrm, 70);
  else return 'FEIL ' || sqlstate || ': ' || sqlerrm || ' <- ' || left(p_sql, 200); end if;
end $$;
create function pg_temp.lik(p_verdi anyelement, p_forventet anyelement, p_hva text) returns text language sql as $$
  select case when p_verdi is not distinct from p_forventet then 'ok ' || p_hva
              else 'FEIL ' || p_hva || ': fikk ' || coalesce(p_verdi::text, 'null') || ', forventet ' || coalesce(p_forventet::text, 'null') end
$$;
create function pg_temp.som(p_uid text) returns text language sql as $$
  select 'som ' || coalesce(nullif(set_config('request.jwt.claim.sub', p_uid, false), ''), 'ingen');
$$;
create function pg_temp.uten_brukere(p_json jsonb) returns boolean language sql as $$
  select not exists (select 1 from auth.users u where position(u.id::text in p_json::text) > 0);
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u4  '00000000-0000-0000-0000-000000000004'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set m9  '11111111-0000-0000-0000-000000000009'
\set S25 '31951801-360f-47b0-9fee-dcac5238325d'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set SES '5eeeeeee-0000-0000-0000-000000002026'
\set R1  'dddddddd-0000-0000-0000-000000000001'
\set R2  'dddddddd-0000-0000-0000-000000000002'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set R4  'dddddddd-0000-0000-0000-000000000004'
\set R5  'dddddddd-0000-0000-0000-000000000005'
\set MS  'cccccccc-0000-0000-0000-000000000001'
-- Nytt for prøven.
\set v7  '00000000-0000-0000-0000-000000004807'
\set v8  '00000000-0000-0000-0000-000000004808'
\set p7  '11111111-0000-0000-0000-000000004807'
\set p8  '11111111-0000-0000-0000-000000004808'
\set v9  '00000000-0000-0000-0000-000000004809'
\set p9  '11111111-0000-0000-0000-000000004809'
\set EP  'eeeeeeee-0000-0000-0000-0000000048e1'
\set EQ  'eeeeeeee-0000-0000-0000-0000000048e2'
\set RN  'dddddddd-0000-0000-0000-0000000048a1'
\set R9  'dddddddd-0000-0000-0000-0000000048a2'
\set RT  'dddddddd-0000-0000-0000-0000000048a3'
\set RO  'dddddddd-0000-0000-0000-0000000048a4'
\set RA  'dddddddd-0000-0000-0000-0000000048a5'
\set RL  'dddddddd-0000-0000-0000-0000000048a6'
\set SL  'cccccccc-0000-0000-0000-0000000048c1'
\set OB  'cccccccc-0000-0000-0000-0000000048c2'
\set TE  'cccccccc-0000-0000-0000-0000000048d1'

select current_date + 100 as d_ep, current_date + 107 as d_eq \gset

begin;

-- --- Verdenen --------------------------------------------------------------------
select pg_temp.som('');
insert into auth.users (id) values (:'v7'), (:'v8'), (:'v9');
insert into public.club_members (id, club_id, user_id, display_name, status) values
  (:'p7', :'G', :'v7', 'Rundeleder 48', 'active'), (:'p8', :'G', :'v8', 'Turneringsleder 48', 'active'),
  (:'p9', :'G', :'v9', 'Vanlig 48', 'active');
insert into public.club_roles (id, club_id, name, rights) values
  ('7a000000-0000-0000-0000-000000004801', :'G', 'Rundeleder 48', array['rounds']),
  ('7a000000-0000-0000-0000-000000004802', :'G', 'Turneringsleder 48', array['tournaments']);
insert into public.club_member_roles (club_id, member_id, role_id) values
  (:'G', :'p7', '7a000000-0000-0000-0000-000000004801'),
  (:'G', :'p8', '7a000000-0000-0000-0000-000000004802');
-- To nye kvelder i Sesong 2026 og en kladd på den første.
insert into public.events (id, club_id, competition_id, event_date) values
  (:'EP', :'G', :'S26', :'d_ep'), (:'EQ', :'G', :'S26', :'d_eq');
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, format)
values (:'RN', :'G', :'EP', :'MS', 1, 'draft', 18, 'stableford');
create temp table svar (navn text primary key, j jsonb);
grant all on svar to public;
create temp table for48 as select * from public.rounds;
grant select on for48 to public;

-- --- A: standardverdiene -------------------------------------------------------------
select pg_temp.lik((select count(*) from public.round_competitions), 0::bigint,
                   'A1 ingen konkurranser: hver runde har rounds.format som eneste (underforståtte) hovedkonkurranse');
select pg_temp.lik((select count(*) from public.rounds where status <> 'draft' and snapshot_source = 'backfill'),
                   (select count(*) from public.rounds where status <> 'draft'),
                   'A2 alle startede runder som fantes, er etterfylt (backfill)');
select pg_temp.lik((select count(*) from public.rounds where status <> 'draft'), 7::bigint, 'A3 (sju startede runder i verdenen)');
select pg_temp.lik((select count(*) from public.rounds where status = 'draft' and snapshot_source is null
                     and rules_snapshot is null and holes_snapshot is null and snapshot_at is null),
                   (select count(*) from public.rounds where status = 'draft'), 'A4 kladdene har ikke øyeblikksbilde');
select pg_temp.lik((select rules_snapshot from public.rounds where id = :'R1'),
                   (select rules from public.competitions where id = :'S25'), 'A5 runde 1 (2025): regelsettet til Sesong 2025');
select pg_temp.lik((select rules_snapshot from public.rounds where id = :'R5'), null::jsonb,
                   'A6 runde 5 (kveld uten turnering): ingen regelsett');
select pg_temp.lik((select (holes_snapshot ->> 'from') || '|' || jsonb_array_length(holes_snapshot -> 'holes') || '|'
                           || (select sum((h ->> 'par')::int) from jsonb_array_elements(holes_snapshot -> 'holes') h)
                      from public.rounds where id = :'R2'),
                   'course|18|' || (select sum(par) from public.course_holes where course_id = :'MS'),
                   'A7 runde 2: 18 hull fra egen bane (Marco Simone), par som banen');
select pg_temp.lik((select count(*) from jsonb_array_elements((select holes_snapshot -> 'holes' from public.rounds where id = :'R5')) h
                     where h -> 'par' = 'null'::jsonb and (h ->> 'cardIndex')::int = (h ->> 'hole')::int),
                   18::bigint, 'A8 runde 5 uten bane: 18 hull, par null (appen bruker standardpar), indeks = hullnummer');
select pg_temp.lik((select count(*) from public.round_players where side is not null), 0::bigint, 'A9 ingen spiller har side');
select pg_temp.lik((select count(*) from public.rounds r where r.format <> 'stableford'), 0::bigint,
                   'A10 formene er som før (stableford)');

-- --- K: flere konkurranser på samme runde --------------------------------------------
select pg_temp.som(:'v7'); set role authenticated;
insert into svar select 'K1', public.round_competitions_set(:'RN', jsonb_build_array(
  jsonb_build_object('name', 'Kveldens stableford', 'is_main', true, 'config', '{}'::jsonb),
  jsonb_build_object('name', 'Bestball', 'config', jsonb_build_object(
      'teamForm', '{"type": "pairs", "pairs": "fourball"}'::jsonb, 'scoring', '{"type": "strokePlay", "net": true}'::jsonb,
      'entrants', jsonb_build_array(jsonb_build_array(:'m1', :'m3'), jsonb_build_array(:'m2', :'m9')))),
  jsonb_build_object('name', 'Skins', 'config', '{"form": "skins"}'::jsonb),
  jsonb_build_object('name', 'Første ni', 'config', '{"form": "stableford", "holes": {"first": 0, "last": 8}, "allowance": 0.95}'::jsonb)));
reset role;
select pg_temp.lik((select jsonb_array_length(j) from svar where navn = 'K1'), 4, 'K1 fire konkurranser på samme runde');
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'RN' and is_main), 1::bigint,
                   'K2 nøyaktig én hovedkonkurranse');
select pg_temp.lik((select config ->> 'form' from public.round_competitions where round_id = :'RN' and is_main), 'stableford',
                   'K3 hovedkonkurransen uten form fikk rundens form');
select pg_temp.lik((select string_agg(name || ':' || sort_order || ':' || format_version, ',' order by sort_order)
                      from public.round_competitions where round_id = :'RN'),
                   'Kveldens stableford:0:1,Bestball:1:1,Skins:2:1,Første ni:3:1', 'K4 rekkefølgen og versjon 1');
select pg_temp.lik((select created_by from public.round_competitions where round_id = :'RN' and name = 'Skins'), :'v7'::uuid,
                   'K5 created_by er den som lagret');
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "is_main": true, "config": {}}, {"name": "B", "is_main": true, "config": {"form": "skins"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  (select jsonb_agg(jsonb_build_object('name', 'K' || i, 'config', '{"form": "skins"}'::jsonb)) from generate_series(1, 11) i)), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "skins", "note": "Bjørns bursdag"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "stableford", "holes": {"first": 9, "last": 18}}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "stableford", "holes": {"first": 5, "last": 2}}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "is_main": true, "config": {"allowance": 0.9}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "stableford", "allowance": 1.5}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "skins", "entrants": [["Bjørn", "Anders"]]}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"teamForm": {"type": "individual"}}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": {"form": "Stableford!"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "format_version": 2, "config": {"form": "skins"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "  ", "config": {"form": "skins"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"id": "00000000-0000-0000-0000-00000000dead", "name": "A", "config": {"form": "skins"}}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  '[{"name": "A", "config": "skins"}]'), '22023');
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN',
  (select jsonb_build_array(jsonb_build_object('name', 'Stor', 'config', jsonb_build_object('form', 'skins', 'entrants',
     (select jsonb_agg(jsonb_build_array(gen_random_uuid(), gen_random_uuid(), gen_random_uuid())) from generate_series(1, 200))))))), '22023');
reset role;
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'RN'), 4::bigint,
                   'K6 en avvist lagring endrer ingenting (fortsatt fire)');
-- Beholde to (med id), slette to, legge til en.
select pg_temp.som(:'v7'); set role authenticated;
insert into svar select 'K7', public.round_competitions_set(:'RN', jsonb_build_array(
  (select jsonb_build_object('id', id, 'name', name, 'is_main', true, 'config', config) from public.round_competitions
    where round_id = :'RN' and is_main),
  (select jsonb_build_object('id', id, 'name', 'Bestball (par)', 'config', config) from public.round_competitions
    where round_id = :'RN' and name = 'Bestball'),
  jsonb_build_object('name', 'Amerikaner', 'config', jsonb_build_object('form', 'amerikaner',
     'entrants', jsonb_build_array(jsonb_build_array(:'m1', :'m2', :'m3', :'m9'))))));
reset role;
select pg_temp.lik((select string_agg(c.name, ',' order by c.sort_order) from public.round_competitions c where c.round_id = :'RN'),
                   'Kveldens stableford,Bestball (par),Amerikaner', 'K7 to beholdt (ett nytt navn), to slettet, én ny');
select pg_temp.lik((select count(*) from public.round_competitions c
                     where c.round_id = :'RN' and c.id in (select (x ->> 'id')::uuid from svar s, jsonb_array_elements(s.j) x
                                                           where s.navn = 'K1')), 2::bigint,
                   'K8 de to som ble beholdt, har samme id som før');
-- Konkurranser på en annen runde kan ikke brukes her.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'R3',
  jsonb_build_array(jsonb_build_object('id', (select id from public.round_competitions where round_id = :'RN' and is_main),
                                       'name', 'Stjålet', 'config', '{"form": "skins"}'::jsonb))), '22023');
reset role;

-- --- M: speilingen av rounds.format ---------------------------------------------------
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik(jsonb_array_length(public.round_competitions_set(:'RN', jsonb_build_array(
  (select jsonb_build_object('id', id, 'name', name, 'is_main', true, 'config', '{"form": "slag-netto"}'::jsonb)
     from public.round_competitions where round_id = :'RN' and is_main),
  (select jsonb_build_object('id', id, 'name', name, 'config', config) from public.round_competitions
    where round_id = :'RN' and name = 'Bestball (par)')))), 2, 'M1 lagret med ny form på hovedkonkurransen');
reset role;
select pg_temp.lik((select format from public.rounds where id = :'RN'), 'slag-netto', 'M2 hovedkonkurransen → rounds.format');
-- Bytte hovedkonkurranse: den nye hovedkonkurransens form blir rundens.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik(jsonb_array_length(public.round_competitions_set(:'RN', jsonb_build_array(
  (select jsonb_build_object('id', id, 'name', name, 'config', config) from public.round_competitions
    where round_id = :'RN' and is_main),
  jsonb_build_object('name', 'Skins', 'is_main', true, 'config', '{"form": "skins"}'::jsonb),
  (select jsonb_build_object('id', id, 'name', name, 'config', config) from public.round_competitions
    where round_id = :'RN' and name = 'Bestball (par)')))), 3, 'M3 lagret med Skins som ny hovedkonkurranse');
reset role;
select pg_temp.lik((select format || '|' || (select string_agg(name, ',') from public.round_competitions where round_id = :'RN' and is_main)
                      from public.rounds where id = :'RN'), 'skins|Skins', 'M4 rounds.format = skins, bare Skins er hoved');
-- Gamle bygg: vanlig update på rounds.format → hovedkonkurransen følger, aksene tas bort.
select pg_temp.som('');
update public.round_competitions set config = config || '{"teamForm": {"type": "individual"}, "scoring": {"type": "skins"}}'
 where round_id = :'RN' and is_main;
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set format = 'match' where id = :'RN';
reset role;
select pg_temp.lik((select config from public.round_competitions where round_id = :'RN' and is_main), '{"form": "match"}'::jsonb,
                   'M5 gamle bygg endrer rounds.format: hovedkonkurransen får formen, uten de gamle aksene');
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'RN' and not is_main
                     and config ->> 'form' = 'match'), 0::bigint, 'M6 de andre konkurransene røres ikke');
-- En runde uten konkurranser: update på formen lager ingen rader.
select pg_temp.som(:'u1'); set role authenticated;
update public.rounds set format = 'slag-brutto' where id = :'R4';
reset role;
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'R4'), 0::bigint,
                   'M7 runde uten konkurranser: formen endres som før, ingen rader lages');
select pg_temp.som('');
update public.rounds set format = 'stableford' where id = :'R4';
-- Tilbake til stableford på RN for resten.
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set format = 'stableford' where id = :'RN';
reset role;
select pg_temp.lik((select config ->> 'form' from public.round_competitions where round_id = :'RN' and is_main), 'stableford',
                   'M8 og tilbake');

-- --- R: rettigheter ------------------------------------------------------------------
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN', '[]'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'R3', '[]'), '42501');
reset role;
select pg_temp.som(:'v9'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'R3', '[]'), '42501');
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'RN'), 0::bigint,
                   'R1 et medlem ser ikke konkurransene i en kladd (som runden)');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'R3', '[]'), 'P0002');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'R2', '[{"name": "A", "config": {"form": "skins"}}]'), '55000');
select pg_temp.feil(format('insert into public.round_competitions (round_id, name) values (%L, %L)', :'R3', 'Direkte'), '42501');
select pg_temp.feil(format('update public.round_competitions set name = %L where round_id = %L', 'Direkte', :'RN'), '42501');
select pg_temp.feil(format('delete from public.round_competitions where round_id = %L', :'RN'), '42501');
insert into svar select 'R2', public.round_competitions_set(:'R3', '[{"name": "Skins", "config": {"form": "skins"}}]');
reset role;
select pg_temp.lik((select jsonb_array_length(j) from svar where navn = 'R2'), 1, 'R2 eieren (Arrangør) kan lagre på en aktiv runde');
select pg_temp.som(:'v9'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_competitions where round_id = :'R3'), 1::bigint,
                   'R3 et medlem ser konkurransene i en aktiv runde');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_competitions), 0::bigint, 'R4 en i en annen klubb ser ingen');
reset role;
-- Tom liste sletter alt, formen står.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.round_competitions_set(:'R3', '[]'), '[]'::jsonb, 'R5 tom liste: ingen konkurranser');
reset role;
select pg_temp.lik((select format from public.rounds where id = :'R3'), 'stableford', 'R6 rounds.format står når lista tømmes');

-- --- S: øyeblikksbildet ----------------------------------------------------------------
-- I kladd: tomt, også om noen prøver å sette det.
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set rules_snapshot = '{"version": 9}', holes_snapshot = '{"holes": []}', snapshot_source = 'start',
       snapshot_at = now() where id = :'RN';
reset role;
select pg_temp.lik((select row(rules_snapshot, holes_snapshot, snapshot_at, snapshot_source)::text from public.rounds where id = :'RN'),
                   '(,,,)', 'S1 en kladd har ikke øyeblikksbilde (update avvises stille)');
-- Start med start_round (rettigheten rounds), med sider.
select pg_temp.som(:'v7'); set role authenticated;
insert into svar select 'S2', public.start_round(:'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'bay_no', 1, 'is_marker', true, 'team_no', 1, 'side', 1),
  jsonb_build_object('member_id', :'m3', 'bay_no', 1, 'team_no', 1, 'side', 1),
  jsonb_build_object('member_id', :'m2', 'bay_no', 2, 'is_marker', true, 'team_no', 2, 'side', 2),
  jsonb_build_object('member_id', :'m9', 'bay_no', 2, 'team_no', 2, 'side', 2)));
reset role;
select pg_temp.lik((select status || '|' || snapshot_source || '|' || (snapshot_at is not null) from public.rounds where id = :'RN'),
                   'active|start|true', 'S2 start_round fryser øyeblikksbildet');
select pg_temp.lik((select rules_snapshot from public.rounds where id = :'RN'), (select rules from public.competitions where id = :'S26'),
                   'S3 regelsettet er turneringens (Sesong 2026)');
select pg_temp.lik((select string_agg((h ->> 'hole') || ':' || (h ->> 'par') || ':' || (h ->> 'cardIndex') || ':' || (h ->> 'strokeIndex'), ',' order by (h ->> 'hole')::int)
                      from jsonb_array_elements((select holes_snapshot -> 'holes' from public.rounds where id = :'RN')) h),
                   (select string_agg(hole_number || ':' || par || ':' || stroke_index || ':' || stroke_index, ',' order by hole_number)
                      from public.course_holes where course_id = :'MS'),
                   'S4 hullene: nummer, par, indeks og rang som banen (alle 18)');
select pg_temp.lik((select holes_snapshot ->> 'from' from public.rounds where id = :'RN'), 'course', 'S5 kilden er banen');
create temp table bilde as select rules_snapshot, holes_snapshot, snapshot_at from public.rounds where id = :'RN';
grant select on bilde to public;
-- Endringer etter start: regelsettet, banens hull, rundens egne hull, update fra arrangøren.
select pg_temp.som('');
update public.competitions set rules = '{"version": 2, "evenings": 5}' where id = :'S26';
update public.course_holes set par = 5 where course_id = :'MS' and hole_number = 1;
insert into public.round_holes (round_id, hole_index, par, stroke_index) values (:'RN', 2, 4, 18);
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set rules_snapshot = '{"version": 1}', holes_snapshot = '{"holes": []}', snapshot_source = 'refresh'
 where id = :'RN';
reset role;
select pg_temp.lik((select (r.rules_snapshot, r.holes_snapshot, r.snapshot_at) = (b.rules_snapshot, b.holes_snapshot, b.snapshot_at)
                      from public.rounds r, bilde b where r.id = :'RN'), true,
                   'S6 regelsett, bane, rundens hull og update etter start endrer ikke øyeblikksbildet');
select pg_temp.lik((select snapshot_source from public.rounds where id = :'RN'), 'start', 'S7 kilden er fortsatt start');
-- «Oppdater øyeblikksbildet».
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'RN'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'RN'), '42501');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'R4'), '55000');
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'R2'), '55000');
insert into svar select 'S8', public.round_snapshot_refresh(:'RN');
reset role;
select pg_temp.lik((select j ->> 'snapshot_source' from svar where navn = 'S8'), 'refresh', 'S8 rettigheten rounds kan oppdatere i en aktiv runde');
select pg_temp.lik((select rules_snapshot from public.rounds where id = :'RN'), '{"version": 2, "evenings": 5}'::jsonb,
                   'S9 det nye regelsettet');
select pg_temp.lik((select (holes_snapshot -> 'holes' -> 0 ->> 'par') || '|' || (holes_snapshot -> 'holes' -> 2 ->> 'cardIndex')
                           || '|' || (holes_snapshot -> 'holes' -> 2 ->> 'strokeIndex') || '|' || (holes_snapshot -> 'holes' -> 17 ->> 'strokeIndex')
                      from public.rounds where id = :'RN'), '5|18|17|18',
                   'S10 nye par fra banen, rundens hull går foran (hull 3 indeks 18), rangen regnet på nytt (lik indeks: hullrekkefølgen)');
select pg_temp.lik((select j -> 'holes_snapshot' from svar where navn = 'S8'), (select holes_snapshot from public.rounds where id = :'RN'),
                   'S11 svaret er øyeblikksbildet som ble lagret');
-- Låst: endres aldri.
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set status = 'locked' where id = :'RN';
reset role;
create temp table bilde2 as select rules_snapshot, holes_snapshot, snapshot_at, snapshot_source from public.rounds where id = :'RN';
grant select on bilde2 to public;
select pg_temp.som('');
update public.competitions set rules = '{"version": 1}' where id = :'S26';
update public.course_holes set par = 4 where course_id = :'MS' and hole_number = 1;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'RN'), '55000');
update public.rounds set rules_snapshot = null where id = :'RN';
reset role;
select pg_temp.lik((select (r.rules_snapshot, r.holes_snapshot, r.snapshot_at, r.snapshot_source)
                           = (b.rules_snapshot, b.holes_snapshot, b.snapshot_at, b.snapshot_source)
                      from public.rounds r, bilde2 b where r.id = :'RN'), true,
                   'S12 låst runde: øyeblikksbildet står (lås, regelsett, bane, update og refresh)');
-- Satt tilbake til aktiv (gjenåpnet): fortsatt samme bilde, ikke frosset på nytt.
select pg_temp.som(:'v7'); set role authenticated;
update public.rounds set status = 'active' where id = :'RN';
reset role;
select pg_temp.lik((select (r.rules_snapshot, r.snapshot_source) = (b.rules_snapshot, b.snapshot_source)
                      from public.rounds r, bilde2 b where r.id = :'RN'), true, 'S13 gjenåpnet runde fryses ikke på nytt');
-- 9 hull fra hull 10 på en 18-hullsbane.
select pg_temp.som('');
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, first_hole, format, wave_no)
values (:'R9', :'G', :'EP', :'MS', 2, 'draft', 9, 10, 'stableford', 2);
update public.course_holes set stroke_index = case hole_number when 10 then 11 when 11 then 10 else stroke_index end
 where course_id = :'MS' and hole_number in (10, 11);
update public.rounds set status = 'active' where id = :'R9';
select pg_temp.lik((select string_agg((h ->> 'hole') || ':' || (h ->> 'par') || ':' || (h ->> 'cardIndex') || ':' || (h ->> 'strokeIndex'), ',')
                      from jsonb_array_elements((select holes_snapshot -> 'holes' from public.rounds where id = :'R9')) h),
                   (select string_agg(hole_number || ':' || par || ':' || stroke_index || ':' || rang, ',' order by hole_number)
                      from (select h.*, row_number() over (order by stroke_index, hole_number) as rang
                              from public.course_holes h where course_id = :'MS' and hole_number >= 10) x),
                   'S14 9 hull fra hull 10: hull 10–18 med banens par og indeks, rang 1–9 blant de ni');
-- Hentet bane med tee-hull (som 030): teens hull, og de samme som i round_holes.
insert into public.courses (id, club_id, name, kind, source, external_id) values (:'SL', null, 'Slopebanen 48', 'course', 'slopeno', 'sl48');
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select :'SL', n, 4, n from generate_series(1, 18) n;
insert into public.course_tees (id, course_id, source, external_id, name, gender, course_rating, slope_rating)
values (:'TE', :'SL', 'slopeno', 'te48', 'Gul', 'men', 70.1, 125);
insert into public.course_tee_holes (tee_id, hole_number, par, stroke_index, length_m)
select :'TE', n, case when n % 2 = 0 then 5 else 3 end, 19 - n, 300 + n from generate_series(1, 18) n;
insert into public.rounds (id, club_id, event_id, course_id, tee_id, round_no, status, hole_count, format, wave_no)
values (:'RT', :'G', :'EP', :'SL', :'TE', 3, 'draft', 18, 'stableford', 3);
update public.rounds set status = 'active' where id = :'RT';
select pg_temp.lik((select holes_snapshot ->> 'from' || '|' || (holes_snapshot ->> 'tee_id') from public.rounds where id = :'RT'),
                   'tee|' || :'TE', 'S15 hentet bane med tee: kilden er teen');
select pg_temp.lik((select count(*) from jsonb_array_elements((select holes_snapshot -> 'holes' from public.rounds where id = :'RT'))
                      with ordinality h(x, n)
                      join public.round_holes rh on rh.round_id = :'RT' and rh.hole_index = n - 1
                     where (x ->> 'par')::int = rh.par and (x ->> 'cardIndex')::int = rh.stroke_index
                       and (x ->> 'meters')::int = rh.length_m), 18::bigint,
                   'S16 alle 18 hullene er like de 030 frøs i round_holes (par, indeks, lengde)');
update public.course_tee_holes set par = 4 where tee_id = :'TE';
select pg_temp.lik((select count(*) from jsonb_array_elements((select holes_snapshot -> 'holes' from public.rounds where id = :'RT')) h
                     where (h ->> 'par')::int = 4), 0::bigint, 'S17 ny par hos kilden endrer ikke øyeblikksbildet');
-- Egen bane uten helt sett hull: ingen kilde (appen bruker heller ikke banens hull).
insert into public.courses (id, club_id, name) values (:'OB', :'G', 'Halvbanen 48');
insert into public.course_holes (course_id, hole_number, par, stroke_index) select :'OB', n, 5, n from generate_series(1, 5) n;
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, format, wave_no)
values (:'RO', :'G', :'EP', :'OB', 4, 'active', 18, 'stableford', 4);
select pg_temp.lik((select coalesce(holes_snapshot ->> 'from', '-') || '|' || (holes_snapshot -> 'holes' -> 0 ->> 'par') is null
                      from public.rounds where id = :'RO'), true, 'S18 egen bane med 5 hull: ingen kilde, par null');
select pg_temp.lik((select snapshot_source from public.rounds where id = :'RO'), 'start', 'S19 lagt inn rett som aktiv: frosset ved innlegging');
-- Løs runde: eieren starter, ingen turnering → ingen regelsett, hullene finnes.
select pg_temp.som(:'u2'); set role authenticated;
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, format)
values (:'RL', null, null, null, 1, 'draft', 9, 'stableford');
select pg_temp.lik(jsonb_array_length(public.round_competitions_set(:'RL', '[{"name": "Skins", "config": {"form": "skins"}}]')), 1,
                   'S20 eieren av en løs runde kan lagre konkurranser');
update public.rounds set status = 'active' where id = :'RL';
select pg_temp.lik((select (rules_snapshot is null) || '|' || snapshot_source || '|' || jsonb_array_length(holes_snapshot -> 'holes')
                      from public.rounds where id = :'RL'), 'true|start|9', 'S21 løs runde: frosset, uten regelsett, 9 hull');
select pg_temp.lik((public.round_snapshot_refresh(:'RL') ->> 'snapshot_source'), 'refresh', 'S22 eieren kan oppdatere sin løse runde');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'RL'), 'P0002');
reset role;
-- Etterfyllingen er der fortsatt for rundene som fantes.
select pg_temp.lik((select count(*) from public.rounds r join for48 f on f.id = r.id
                     where f.status <> 'draft' and r.snapshot_source = 'backfill'), 7::bigint,
                   'S23 de sju etterfylte rundene står som backfill');

-- --- D: side (lag mot lag) ------------------------------------------------------------
select pg_temp.lik((select string_agg(member_id::text || ':' || team_no || ':' || side, ',' order by member_id)
                      from public.round_players where round_id = :'RN'),
                   :'m1' || ':1:1,' || :'m2' || ':2:2,' || :'m3' || ':1:1,' || :'m9' || ':2:2',
                   'D1 start_round lagret lag og side');
-- Gamle bygg (uten side): sidene står.
select pg_temp.som(:'v7'); set role authenticated;
select public.set_round_setup(:'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'bay_no', 1, 'is_marker', true, 'team_no', 1),
  jsonb_build_object('member_id', :'m3', 'bay_no', 1, 'team_no', 1),
  jsonb_build_object('member_id', :'m2', 'bay_no', 2, 'is_marker', true, 'team_no', 2),
  jsonb_build_object('member_id', :'m9', 'bay_no', 2, 'team_no', 2))) is not null as x \gset
reset role;
select pg_temp.lik((select count(*) from public.round_players where round_id = :'RN' and side is not null), 4::bigint,
                   'D2 set_round_setup fra et gammelt bygg (uten side) visker ikke ut sidene');
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.set_round_setup(%L, %L)', :'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'team_no', 1, 'side', 3))), '22023');
select pg_temp.feil(format('select public.set_round_setup(%L, %L)', :'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'team_no', 1, 'side', 1), jsonb_build_object('member_id', :'m3', 'team_no', 1, 'side', 2),
  jsonb_build_object('member_id', :'m2', 'team_no', 2, 'side', 2), jsonb_build_object('member_id', :'m9', 'team_no', 2, 'side', 2))), '22023');
select public.set_round_setup(:'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'team_no', 1, 'side', null), jsonb_build_object('member_id', :'m3', 'team_no', 1, 'side', null),
  jsonb_build_object('member_id', :'m2', 'team_no', 2, 'side', 1), jsonb_build_object('member_id', :'m9', 'team_no', 2, 'side', 1))) is not null as x \gset
reset role;
select pg_temp.lik((select string_agg(coalesce(side::text, '-'), ',' order by member_id) from public.round_players where round_id = :'RN'),
                   '-,1,-,1', 'D3 side null tømmer, og sidene kan byttes');
select pg_temp.lik((select count(*) from public.round_players where round_id = :'RN'), 4::bigint, 'D4 (ingen spillere tapt)');
-- Tilbake til 1/1/2/2 for E.
select pg_temp.som(:'v7'); set role authenticated;
select public.set_round_setup(:'RN', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'bay_no', 1, 'is_marker', true, 'team_no', 1, 'side', 1),
  jsonb_build_object('member_id', :'m3', 'bay_no', 1, 'team_no', 1, 'side', 1),
  jsonb_build_object('member_id', :'m2', 'bay_no', 2, 'is_marker', true, 'team_no', 2, 'side', 2),
  jsonb_build_object('member_id', :'m9', 'bay_no', 2, 'team_no', 2, 'side', 2))) is not null as x \gset
reset role;

-- --- E: Tavla, TV og «Samme som sist» --------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
create temp table tv48 as select public.tavla_data(:'SES') as tavla;
reset role;
select pg_temp.lik((select count(*) from jsonb_array_elements(tavla -> 'rounds') r
                     where r ? 'rules_snapshot' and r ? 'holes_snapshot' and r ? 'snapshot_at' and r ? 'snapshot_source')
                   = jsonb_array_length(tavla -> 'rounds'), true, 'E1 tavla_data: alle rundene har øyeblikksbildet') from tv48;
select pg_temp.lik((select string_agg(c ->> 'name' || ':' || (c ->> 'is_main'), ',' order by (c ->> 'sort_order')::int)
                      from jsonb_array_elements(tavla -> 'round_competitions') c where c ->> 'round_id' = :'RN'),
                   'Kveldens stableford:false,Skins:true,Bestball (par):false', 'E2 tavla_data: konkurransene på runden') from tv48;
select pg_temp.lik((select count(*) from jsonb_array_elements(tavla -> 'players') p where p ->> 'round_id' = :'RN' and p ? 'side'
                       and (p ->> 'side') is not null), 4::bigint, 'E3 tavla_data: side på spillerne') from tv48;
select pg_temp.lik((select (r -> 'rules_snapshot') = (select to_jsonb(rules_snapshot) from public.rounds where id = :'RN')
                      from jsonb_array_elements(tavla -> 'rounds') r where r ->> 'id' = :'RN'), true,
                   'E4 tavla_data: regelsettet fra øyeblikksbildet, ikke dagens') from tv48;
select pg_temp.som('');
insert into public.tv_codes (code, competition_id) values ('TVKXDE4882', :'S26');
set role anon;
create temp table tvs48 as select public.tv_board_data('tvkxde4882') as tv;
reset role;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'rounds') r
                     where r ? 'rules_snapshot' and r ? 'holes_snapshot' and r ? 'snapshot_source')
                   = jsonb_array_length(tv -> 'rounds'), true, 'E5 tv_board_data (anon): øyeblikksbildet på rundene') from tvs48;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'round_competitions') c where c ->> 'round_id' = :'RN'), 3::bigint,
                   'E6 tv_board_data: konkurransene') from tvs48;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'round_competitions') c where c ? 'created_by'), 0::bigint,
                   'E7 TV: ingen created_by på konkurransene') from tvs48;
select pg_temp.lik(pg_temp.uten_brukere(tv), true, 'E8 TV-svaret har ingen ekte bruker-id') from tvs48;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'players') p where p ->> 'round_id' = :'RN' and (p ->> 'side') is not null),
                   4::bigint, 'E9 TV: side på spillerne') from tvs48;
-- tv_competition_data (turnering uten sesong): Torsdagsligaen, konkurransen lagt inn som superbruker
-- (runden er låst, så RPC-en sier nei).
insert into public.tv_codes (code, competition_id) values ('TVKXDE4883', 'bd7acc4c-f21f-4b49-bc06-d84d915c2579');
insert into public.round_competitions (round_id, name, config)
values ('7ee971f0-5c23-4edf-84cd-f4fba14896a2', 'Skins', '{"form": "skins"}');
set role anon;
create temp table tvl48 as select public.tv_board_data('TVKXDE4883') as tv;
reset role;
select pg_temp.lik((select (r ? 'rules_snapshot') and (r ->> 'snapshot_source') = 'backfill'
                      from jsonb_array_elements(tv -> 'rounds') r where r ->> 'id' = '7ee971f0-5c23-4edf-84cd-f4fba14896a2'), true,
                   'E10 tv_competition_data: øyeblikksbildet (etterfylt) på runden') from tvl48;
select pg_temp.lik((select string_agg(c ->> 'name', ',') from jsonb_array_elements(tv -> 'round_competitions') c), 'Skins',
                   'E11 tv_competition_data: konkurransene') from tvl48;
select pg_temp.lik(pg_temp.uten_brukere(tv), true, 'E12 tv_competition_data: ingen ekte bruker-id') from tvl48;
-- «Samme som sist» på neste kveld: RN er siste startede runde (EP).
select pg_temp.som(:'v7'); set role authenticated;
insert into svar select 'E13', public.previous_round_setup(:'EQ');
reset role;
select pg_temp.lik((select j ->> 'round_id' from svar where navn = 'E13'), (select max(id::text) from public.rounds
                     where event_id = :'EP' and round_no = (select max(round_no) from public.rounds where event_id = :'EP')),
                   'E13 previous_round_setup: siste runde på forrige kveld');
-- Den siste runden på EP er RO (round_no 4). Gi den konkurranser og sider og hent igjen.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik(jsonb_array_length(public.round_competitions_set(:'RO', jsonb_build_array(
  jsonb_build_object('name', 'Hoved', 'is_main', true, 'config', '{}'::jsonb),
  jsonb_build_object('name', 'Bestball', 'config', jsonb_build_object('teamForm', '{"type": "pairs", "pairs": "fourball"}'::jsonb,
     'scoring', '{"type": "stableford", "net": true}'::jsonb, 'entrants', jsonb_build_array(jsonb_build_array(:'m1', :'m3'))))))), 2,
  'E14 (konkurranser på RO)');
select public.set_round_setup(:'RO', jsonb_build_array(
  jsonb_build_object('member_id', :'m1', 'team_no', 1, 'side', 2), jsonb_build_object('member_id', :'m3', 'team_no', 1, 'side', 2))) is not null as x \gset
insert into svar select 'E15', public.previous_round_setup(:'EQ');
reset role;
select pg_temp.lik((select j -> 'competitions' from svar where navn = 'E15'),
                   (select jsonb_agg(jsonb_build_object('name', name, 'is_main', is_main, 'format_version', format_version,
                                                        'config', config, 'sort_order', sort_order) order by sort_order)
                      from public.round_competitions where round_id = :'RO'),
                   'E15 «Samme som sist» kopierer konkurransene (navn, hoved, versjon, config, rekkefølge)');
select pg_temp.lik((select string_agg(p ->> 'side', ',') from svar, jsonb_array_elements(j -> 'players') p where navn = 'E15'), '2,2',
                   'E16 «Samme som sist» har side på spillerne');
select pg_temp.lik((select (j -> 'competitions' -> 0) ? 'id' from svar where navn = 'E15'), false, 'E17 uten id (nye rader lages)');
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('select public.previous_round_setup(%L)', :'EQ'), '42501');
reset role;

-- --- N: anon --------------------------------------------------------------------------
set role anon;
select pg_temp.feil(format('select public.round_competitions_set(%L, %L)', :'RN', '[]'), '42501');
select pg_temp.feil(format('select public.round_snapshot_refresh(%L)', :'RN'), '42501');
select pg_temp.feil('select count(*) from public.round_competitions', '42501');
reset role;

-- Til slutt: kontrollens invarianter holder.
select pg_temp.lik((select count(*) from public.round_competitions c join public.rounds r on r.id = c.round_id
                     where c.is_main and (c.config ->> 'form') is distinct from r.format), 0::bigint,
                   'Z1 hver hovedkonkurranse har rundens form');
select pg_temp.lik((select count(*) from (select round_id from public.round_competitions where is_main group by round_id
                                           having count(*) > 1) x), 0::bigint, 'Z2 høyst én hoved per runde');
select pg_temp.lik((select count(*) from public.rounds where (status = 'draft') <> (snapshot_source is null)), 0::bigint,
                   'Z3 alle startede runder har øyeblikksbilde, ingen kladd har');
select pg_temp.lik((select count(*) from public.rounds r join for48 f on f.id = r.id
                     where r.id not in (:'RN', :'R3', :'R4')
                       and row(r.format, r.status, r.updated_at, r.handicap_allowance, r.counts)
                           is distinct from row(f.format, f.status, f.updated_at, f.handicap_allowance, f.counts)), 0::bigint,
                   'Z4 rundene prøven ikke rørte, er uendret');

rollback;
