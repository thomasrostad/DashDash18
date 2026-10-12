\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 049_gjenbruk.sql. Kjøres på kopien med 001–043, 034, 044, 045, 047 og 049 (to
-- ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
-- Datoene regnes fra current_date, så prøven virker uansett dag.
--
-- S: create_event_series: antall, ukedag, hver n-te uke, datoer som er tatt hoppes over, flere
--    turneringer samme dato (034), sesong får season_id, rettigheter og grenser.
-- U: update_event_series: 'one' mot 'future', passerte og startede kvelder røres ikke, flytting
--    med like mange dager (også fristene), kollisjon gir 23505 uten endring, rettigheter.
-- T: setup_templates: hvem ser hva (RLS), lagre og slette via RPC, rettighet per type,
--    personlige maler, størrelsesgrensen, unike navn, ingen direkte skriving.
-- P: previous_round_setup: siste startede vanlige runde (ikke playoff, ikke kladd), spillerne,
--    matchene og spillene, rettigheter.
-- A: anon.
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
create function pg_temp.som(p_uid text) returns text language sql as $$
  select 'som ' || coalesce(nullif(set_config('request.jwt.claim.sub', p_uid, false), ''), 'ingen');
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
\set E2  'eeeeeeee-0000-0000-0000-000000000002'
\set E3  'eeeeeeee-0000-0000-0000-000000000003'
\set E4  'eeeeeeee-0000-0000-0000-000000000004'
\set R2  'dddddddd-0000-0000-0000-000000000002'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set R5  'dddddddd-0000-0000-0000-000000000005'
\set TL  'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set TLE '74fe3341-e4a9-49dc-841d-a3ade34d96eb'
\set TLR '7ee971f0-5c23-4edf-84cd-f4fba14896a2'
\set MC  'c0000000-0000-0000-0000-00000000f001'
\set FR  '1e778277-c4e0-4454-9c88-590ba24b8388'
-- Nytt for prøven: v7 (bare rounds), v8 (bare tournaments), turnering uten klubb.
\set v7  '00000000-0000-0000-0000-000000004907'
\set v8  '00000000-0000-0000-0000-000000004908'
\set p7  '11111111-0000-0000-0000-000000004907'
\set p8  '11111111-0000-0000-0000-000000004908'
\set FK  'c0000000-0000-0000-0000-0000000049f1'

-- Datoene: en dag langt fram (S), og i dag minus tre uker (U).
select current_date + 40 as s_from, current_date - 21 as u_from,
       extract(isodow from current_date - 21)::int as u_wd \gset

begin;

-- --- Verdenen --------------------------------------------------------------------
select pg_temp.som('');
insert into auth.users (id) values (:'v7'), (:'v8');
insert into public.club_members (id, club_id, user_id, display_name, status) values
  (:'p7', :'G', :'v7', 'Rundeleder 49', 'active'), (:'p8', :'G', :'v8', 'Turneringsleder 49', 'active');
insert into public.club_roles (id, club_id, name, rights) values
  ('7a000000-0000-0000-0000-000000004901', :'G', 'Rundeleder 49', array['rounds']),
  ('7a000000-0000-0000-0000-000000004902', :'G', 'Turneringsleder 49', array['tournaments']);
insert into public.club_member_roles (club_id, member_id, role_id) values
  (:'G', :'p7', '7a000000-0000-0000-0000-000000004901'),
  (:'G', :'p8', '7a000000-0000-0000-0000-000000004902');
insert into public.competitions (id, kind, name, club_id, owner_id, status, entry)
values (:'FK', 'fun', 'Vennecup 49', null, :'u1', 'active', 'listed');
create temp table svar (navn text primary key, j jsonb);
grant all on svar to public;
create temp table for49 as select id, event_date, start_time, venue from public.events;
grant select on for49 to public;

select pg_temp.lik((select count(*) from public.events where series_id is not null), 0::bigint,
                   'S0 ingen kveld er i en serie før prøven');

-- --- S: create_event_series ----------------------------------------------------------
select pg_temp.som(:'v8'); set role authenticated;
insert into svar select 'S1', public.create_event_series(:'TL', :'s_from'::date, 4::smallint, 6::smallint, 1::smallint, '18:00', ' Simsenteret ');
select pg_temp.lik((select jsonb_array_length(j -> 'event_ids') from svar where navn = 'S1'), 6,
                   'S1 en rolle med bare tournaments lager seks kvelder');
select pg_temp.lik((select count(*) from public.events e, svar s
                     where s.navn = 'S1' and e.series_id = (s.j ->> 'series_id')::uuid
                       and extract(isodow from e.event_date) = 4 and e.start_time = '18:00'
                       and e.venue = 'Simsenteret' and e.competition_id = :'TL' and e.club_id = :'G'), 6::bigint,
                   'S2 alle er torsdager kl. 18 i Simsenteret (sted trimmet) i Torsdagsligaen');
select pg_temp.lik((select min(e.event_date) from public.events e, svar s
                     where s.navn = 'S1' and e.series_id = (s.j ->> 'series_id')::uuid),
                   (select d::date from generate_series(:'s_from'::date, :'s_from'::date + 6, '1 day') d
                     where extract(isodow from d) = 4),
                   'S3 første kveld er første torsdag fra og med startdatoen');
select pg_temp.lik((select max(e.event_date) - min(e.event_date) from public.events e, svar s
                     where s.navn = 'S1' and e.series_id = (s.j ->> 'series_id')::uuid), 35,
                   'S4 ukentlig: siste kveld fem uker etter første');
select pg_temp.lik((select weekday || '|' || every_weeks || '|' || count || '|' || start_time || '|' || venue
                       || '|' || (created_by = :'v8')
                      from public.event_series where id = (select (j ->> 'series_id')::uuid from svar where navn = 'S1')),
                   '4|1|6|18:00:00|Simsenteret|true', 'S5 serien er lagret med ukedag, frekvens, tid, sted og hvem');
-- Hver andre uke, og en dato som alt er tatt.
insert into svar select 'S6', public.create_event_series(:'TL', (select (j -> 'dates' ->> 5)::date + 14 from svar where navn = 'S1'),
                                                        4::smallint, 4::smallint, 2::smallint, null, null);
select pg_temp.lik((select string_agg(coalesce(diff::text, '-'), ',' order by n) from (
                       select n, d::date - lag(d::date) over (order by n) as diff
                         from svar, jsonb_array_elements_text(j -> 'dates') with ordinality x(d, n) where navn = 'S6') y),
                   '-,14,14,14', 'S6 hver andre uke: 14 dager mellom');
-- Overlapp: ny serie i samme turnering over datoene til S1 hopper over de som er tatt.
insert into svar select 'S7', public.create_event_series(:'TL', (select (j -> 'dates' ->> 4)::date from svar where navn = 'S1'),
                                                        4::smallint, 3::smallint);
select pg_temp.lik((select jsonb_array_length(j -> 'event_ids') || '|' || jsonb_array_length(j -> 'skipped') from svar where navn = 'S7'),
                   '1|2', 'S7 to datoer var tatt (S1) og hoppes over, én ny kveld');
select pg_temp.lik((select (j -> 'skipped') = (select jsonb_build_array(j -> 'dates' -> 4, j -> 'dates' -> 5) from svar where navn = 'S1')
                      from svar where navn = 'S7'), true, 'S8 svaret sier hvilke datoer som ble hoppet over');
-- Alt tatt: ingen kvelder, ingen serie igjen.
insert into svar select 'S9', public.create_event_series(:'TL', (select (j -> 'dates' ->> 0)::date from svar where navn = 'S1'),
                                                        4::smallint, 2::smallint);
select pg_temp.lik((select (j -> 'series_id') = 'null'::jsonb and jsonb_array_length(j -> 'event_ids') = 0 from svar where navn = 'S9'),
                   true, 'S9 alle datoene tatt: ingen kvelder og ingen serie');
select pg_temp.lik((select count(*) from public.event_series where competition_id = :'TL'), 3::bigint,
                   'S10 tre serier i Torsdagsligaen (den tomme er slettet)');
-- 034: en annen turnering i klubben kan ha kveld samme dato.
insert into svar select 'S11', public.create_event_series(:'FR', :'s_from'::date, 4::smallint, 6::smallint);
select pg_temp.lik((select jsonb_array_length(j -> 'event_ids') from svar where navn = 'S11'), 6,
                   'S11 Fredagsligaen får de samme datoene (flere kvelder per dato i klubben)');
reset role;
-- Sesong: kveldene får season_id.
select pg_temp.som(:'u1'); set role authenticated;
insert into svar select 'S12', public.create_event_series(:'S26', :'s_from'::date, 2::smallint, 2::smallint);
select pg_temp.lik((select count(*) from public.events e, svar s
                     where s.navn = 'S12' and e.series_id = (s.j ->> 'series_id')::uuid
                       and e.season_id = '5eeeeeee-0000-0000-0000-000000002026'), 2::bigint,
                   'S12 sesongens kvelder får season_id (speilingen fra 031)');
-- Grensene.
select pg_temp.feil(format('select public.create_event_series(%L, %L, 0::smallint, 3::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 8::smallint, 3::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 0::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 53::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint, 9::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint, 0::smallint)', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, null, 4::smallint, 3::smallint)', :'TL'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint, 1::smallint, null, repeat(''x'', 81))', :'TL', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'FK', :'s_from'), '22023');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'S25', :'s_from'), '55000');
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)',
                           'c0000000-0000-0000-0000-0000000049ff', :'s_from'), 'P0002');
reset role;
-- Rettighetene.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'MC', :'s_from'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'MC', :'s_from'), '42501');
select pg_temp.lik((select count(*) from public.event_series), 5::bigint, 'S13 et medlem ser seriene i klubben');
select pg_temp.feil($$insert into public.event_series (club_id, competition_id, weekday, first_date, count)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-00000000f001', 1, current_date, 1)$$, '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'MC', :'s_from'), 'P0002');
select pg_temp.lik((select count(*) from public.event_series), 0::bigint, 'S14 en i en annen klubb ser ingen serier');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('update public.event_series set weekday = 1 where id = %L', (select j ->> 'series_id' from svar where navn = 'S1')), '42501');
reset role;

-- --- U: update_event_series ----------------------------------------------------------
-- Serie i Morrocupen: tre passerte kvelder, i dag, og to fram (dag 0, 7, 14, 21, 28, 35).
select pg_temp.som(:'u1'); set role authenticated;
insert into svar select 'U0', public.create_event_series(:'MC', :'u_from'::date, :'u_wd'::smallint, 6::smallint, 1::smallint, '18:00', 'Bane A');
reset role;
select pg_temp.som('');
create temp table ue as
  select row_number() over (order by e.event_date) - 1 as n, e.id, e.event_date
    from public.events e, svar s where s.navn = 'U0' and e.series_id = (s.j ->> 'series_id')::uuid;
grant select on ue to public;
-- Kveld 4 (+7 dager) har en runde som går. Kveld 5 har frister.
insert into public.rounds (id, club_id, event_id, round_no, status)
values ('dddddddd-0000-0000-0000-000000004901', :'G', (select id from ue where n = 4), 1, 'draft');
update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-000000004901';
update public.events set signup_deadline = (event_date - 2)::timestamptz + time '12:00',
                         withdraw_deadline = (event_date - 1)::timestamptz + time '12:00'
 where id = (select id from ue where n = 5);
select pg_temp.lik((select count(*) from ue where event_date < current_date), 3::bigint, 'U0 tre av seks kvelder er passert');

select pg_temp.som(:'v8'); set role authenticated;
-- 'one': bare kvelden.
select pg_temp.lik((public.update_event_series((select id from ue where n = 5), 'one', '19:00', 'Bane B') -> 'updated' ->> 0)::uuid,
                   (select id from ue where n = 5), 'U1 bare denne: svaret er kvelden');
select pg_temp.lik((select string_agg(coalesce(e.start_time::text, '-') || ' ' || coalesce(e.venue, '-'), ',' order by ue.n)
                      from ue join public.events e on e.id = ue.id),
                   '18:00:00 Bane A,18:00:00 Bane A,18:00:00 Bane A,18:00:00 Bane A,18:00:00 Bane A,19:00:00 Bane B',
                   'U2 bare kvelden ble endret');
-- 'future' fra en passert kveld: passerte og den med startet runde hoppes over.
insert into svar select 'U3', public.update_event_series((select id from ue where n = 2), 'future', '20:00', 'Bane C');
select pg_temp.lik((select (select string_agg(ue.n::text, ',' order by ue.n) from ue
                             where ue.id::text in (select jsonb_array_elements_text(j -> 'updated')))
                           || ' / ' ||
                           (select string_agg(ue.n::text, ',' order by ue.n) from ue
                             where ue.id::text in (select jsonb_array_elements_text(j -> 'skipped')))
                      from svar where navn = 'U3'),
                   '3,5 / 2,4', 'U3 denne og fremtidige: i dag og kveld 5 endres; passert (2) og startet (4) hoppes over');
select pg_temp.lik((select string_agg(coalesce(e.start_time::text, '-') || ' ' || coalesce(e.venue, '-'), ',' order by ue.n)
                      from ue join public.events e on e.id = ue.id),
                   '18:00:00 Bane A,18:00:00 Bane A,18:00:00 Bane A,20:00:00 Bane C,18:00:00 Bane A,20:00:00 Bane C',
                   'U4 de passerte og den startede er urørt');
select pg_temp.lik((select start_time || ' ' || venue from public.event_series
                     where id = (select (j ->> 'series_id')::uuid from svar where navn = 'U0')),
                   '20:00:00 Bane C', 'U5 serien får ny tid og sted');
-- Flytting: fra i dag én dag fram (shift 1). Kveld 4 (startet) står.
insert into svar select 'U6', public.update_event_series((select id from ue where n = 3), 'future', '20:00', 'Bane C', current_date + 1);
select pg_temp.lik((select string_agg((e.event_date - ue.event_date)::text, ',' order by ue.n)
                      from ue join public.events e on e.id = ue.id),
                   '0,0,0,1,0,1', 'U6 i dag og kveld 5 flyttes én dag, resten står');
select pg_temp.lik((select signup_deadline = (ue.event_date - 2)::timestamptz + time '12:00' + interval '1 day'
                           and withdraw_deadline = (ue.event_date - 1)::timestamptz + time '12:00' + interval '1 day'
                      from public.events e join ue on ue.id = e.id where ue.n = 5),
                   true, 'U7 fristene flyttes like mange dager (samme klokkeslett)');
select pg_temp.lik((select weekday from public.event_series where id = (select (j ->> 'series_id')::uuid from svar where navn = 'U0')),
                   extract(isodow from current_date + 1)::smallint, 'U8 serien får ny ukedag');
-- Kollisjon: kveld 3 (nå i morgen) til dagen til kveld 4 (startet): 23505, ingenting endres.
select pg_temp.feil(format('select public.update_event_series(%L, ''future'', ''21:00'', ''Bane D'', %L)',
                           (select id from ue where n = 3), (select event_date from ue where n = 4)), '23505');
select pg_temp.lik((select string_agg(coalesce(e.start_time::text, '-'), ',' order by ue.n)
                      from ue join public.events e on e.id = ue.id),
                   '18:00:00,18:00:00,18:00:00,20:00:00,18:00:00,20:00:00', 'U9 etter kollisjonen er ingenting endret');
-- En annen turnering samme dato er ikke en kollisjon (034).
reset role;
select pg_temp.som('');
insert into public.events (club_id, competition_id, event_date) values (:'G', :'TL', current_date + 30);
reset role;
select pg_temp.som(:'v8'); set role authenticated;
-- Ukentlig serie flyttet en uke fram: kveldene kolliderer ikke med hverandre underveis.
insert into svar select 'U10', public.create_event_series(:'MC', current_date + 60, extract(isodow from current_date + 60)::smallint, 3::smallint);
insert into svar select 'U11', public.update_event_series((select (j -> 'event_ids' ->> 0)::uuid from svar where navn = 'U10'),
                                                          'future', null, null, current_date + 67);
select pg_temp.lik((select string_agg((e.event_date - current_date)::text, ',' order by e.event_date) from public.events e
                     where e.series_id = (select (j ->> 'series_id')::uuid from svar where navn = 'U10')),
                   '67,74,81', 'U11 en uke fram: 60/67/74 blir 67/74/81 uten kollisjon');
select pg_temp.lik((select count(*) from public.events e
                     where e.series_id = (select (j ->> 'series_id')::uuid from svar where navn = 'U10')
                       and e.start_time is null and e.venue is null), 3::bigint, 'U12 null tømmer tid og sted');
-- En uke tilbake igjen.
select pg_temp.lik((select jsonb_array_length(public.update_event_series(
                       (select e.id from public.events e where e.series_id = (select (j ->> 'series_id')::uuid from svar where navn = 'U10')
                         order by e.event_date limit 1), 'future', '17:00', null, current_date + 60) -> 'updated')),
                   3, 'U13 en uke tilbake: alle tre');
-- Feil.
select pg_temp.feil(format('select public.update_event_series(%L, ''future'', null, null)', :'TLE'), '22023');
select pg_temp.feil(format('select public.update_event_series(%L, ''alle'', null, null)', (select id from ue where n = 5)), '22023');
select pg_temp.feil(format('select public.update_event_series(%L, ''future'', null, null, current_date - 1)', (select id from ue where n = 5)), '22023');
select pg_temp.feil(format('select public.update_event_series(%L, ''one'', null, repeat(''x'', 81))', (select id from ue where n = 5)), '22023');
-- 'one' på en passert kveld er lov (retting).
select pg_temp.lik((public.update_event_series((select id from ue where n = 0), 'one', '17:30', 'Bane A') ->> 'shifted_days'),
                   '0', 'U14 bare denne på en passert kveld er lov');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format('select public.update_event_series(%L, ''one'', null, null)', (select id from ue where n = 5)), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.update_event_series(%L, ''future'', null, null)', (select id from ue where n = 5)), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.update_event_series(%L, ''one'', null, null)', (select id from ue where n = 5)), 'P0002');
reset role;
-- En kveld som flyttes til en annen turnering, slipper serien.
select pg_temp.som(:'u1'); set role authenticated;
with u as (update public.events set competition_id = :'TL' where id = (select id from ue where n = 5) returning series_id)
select pg_temp.lik((select series_id from u), null::uuid, 'U15 kvelden som flyttes til en annen turnering, slipper serien');
reset role;
select pg_temp.lik((select count(*) from public.events e join for49 f on f.id = e.id
                     where (e.event_date, e.start_time, e.venue) is distinct from (f.event_date, f.start_time, f.venue)), 0::bigint,
                   'U16 kveldene fra før prøven er urørt');

-- --- T: maler ------------------------------------------------------------------------
select pg_temp.som(:'v7'); set role authenticated;
insert into svar select 'T1', to_jsonb(public.setup_template_save(null, :'G', 'round', ' Torsdag 18 hull ',
  '{"course_id": "cccccccc-0000-0000-0000-000000000001", "hole_count": 18, "format": "stableford", "games": [{"kind": "skins", "settings": {}}]}'));
select pg_temp.lik((select (j ->> 'name') || '|' || (j ->> 'kind') || '|' || (j ->> 'club_id') || '|' || coalesce(j ->> 'owner_id', '-')
                      from svar where navn = 'T1'),
                   'Torsdag 18 hull|round|' || :'G' || '|-', 'T1 en rolle med bare rounds lagrer en rundemal i klubben');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''tournament'', ''Liga'', ''{}'')', :'G'), '42501');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
insert into svar select 'T2', to_jsonb(public.setup_template_save(null, :'G', 'tournament', 'Torsdagsliga',
  '{"kind": "league", "rules": {"version": 1}, "schedule": {"weekday": 4, "every_weeks": 1, "count": 10, "start_time": "18:00"}}'));
select pg_temp.lik((select j ->> 'kind' from svar where navn = 'T2'), 'tournament', 'T2 en rolle med bare tournaments lagrer en turneringsmal');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Runde'', ''{}'')', :'G'), '42501');
select pg_temp.lik((select count(*) from public.setup_templates), 2::bigint, 'T3 tournaments ser begge klubbmalene');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik((select count(*) from public.setup_templates), 2::bigint, 'T4 rounds ser begge klubbmalene');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.setup_templates), 0::bigint, 'T5 et medlem uten rounds/tournaments ser ingen maler');
-- Personlig mal.
insert into svar select 'T6', to_jsonb(public.setup_template_save(null, null, 'round', 'Min runde', '{"hole_count": 9}'));
select pg_temp.lik((select (j ->> 'owner_id') || '|' || coalesce(j ->> 'club_id', '-') from svar where navn = 'T6'),
                   :'u2' || '|-', 'T6 alle kan lagre en personlig mal');
select pg_temp.lik((select count(*) from public.setup_templates), 1::bigint, 'T7 medlemmet ser bare sin egen');
select pg_temp.feil(format('select public.setup_template_save(%L, %L, ''round'', ''Overtatt'', ''{}'')',
                           (select j ->> 'id' from svar where navn = 'T1'), :'G'), 'P0002');
select pg_temp.feil(format('select public.setup_template_delete(%L)', (select j ->> 'id' from svar where navn = 'T1')), 'P0002');
-- Ingen direkte skriving.
select pg_temp.feil($$insert into public.setup_templates (owner_id, kind, name) values ('00000000-0000-0000-0000-000000000002', 'round', 'Rett inn')$$, '42501');
select pg_temp.feil(format('update public.setup_templates set name = ''x'' where id = %L', (select j ->> 'id' from svar where navn = 'T6')), '42501');
select pg_temp.feil(format('delete from public.setup_templates where id = %L', (select j ->> 'id' from svar where navn = 'T6')), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.setup_templates), 2::bigint, 'T8 eieren ser klubbmalene, ikke andres personlige');
-- Innholdet.
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Liste'', ''[1, 2]'')', :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Tall'', ''7'')', :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Tom'', null)', :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Stor'', jsonb_build_object(''x'', repeat(''a'', 32760)))', :'G'), '22023');
select pg_temp.lik((select octet_length(payload::text) from public.setup_template_save(null, :'G', 'round', 'Nesten stor',
                       jsonb_build_object('x', repeat('a', 32700)))), 32709, 'T9 32 709 byte er innenfor (høyst 32 768)');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''hole'', ''Feil type'', ''{}'')', :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''   '', ''{}'')', :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', repeat(''n'', 61), ''{}'')', :'G'), '22023');
-- Unikt navn per klubb og type (uten hensyn til store og små bokstaver).
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''TORSDAG 18 HULL'', ''{}'')', :'G'), '23505');
select pg_temp.lik((select kind from public.setup_template_save(null, :'G', 'tournament', 'Torsdag 18 hull', '{}')),
                   'tournament', 'T10 samme navn med annen type er lov');
select pg_temp.lik((select kind from public.setup_template_save(null, null, 'round', 'Torsdag 18 hull', '{}')),
                   'round', 'T11 samme navn som personlig mal er lov');
reset role;
-- Endre.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik((select name || '|' || (payload ->> 'hole_count') from public.setup_template_save(
                       (select (j ->> 'id')::uuid from svar where navn = 'T1'), :'G', 'round', 'Torsdag 9 hull', '{"hole_count": 9}')),
                   'Torsdag 9 hull|9', 'T12 rounds endrer navn og innhold på rundemalen');
select pg_temp.feil(format('select public.setup_template_save(%L, %L, ''tournament'', ''Bytte'', ''{}'')',
                           (select j ->> 'id' from svar where navn = 'T1'), :'G'), '22023');
select pg_temp.feil(format('select public.setup_template_save(%L, null, ''round'', ''Bytte'', ''{}'')',
                           (select j ->> 'id' from svar where navn = 'T1')), '22023');
select pg_temp.feil(format('select public.setup_template_save(%L, %L, ''tournament'', ''Bytte'', ''{}'')',
                           (select j ->> 'id' from svar where navn = 'T2'), :'G'), '42501');
select pg_temp.feil(format('select public.setup_template_delete(%L)', (select j ->> 'id' from svar where navn = 'T2')), '42501');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('select public.setup_template_delete(%L)', (select j ->> 'id' from svar where navn = 'T1')), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.setup_templates), 0::bigint, 'T13 en i en annen klubb ser ingen av malene');
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Inn'', ''{}'')', :'G'), 'P0002');
select pg_temp.feil(format('select public.setup_template_delete(%L)', (select j ->> 'id' from svar where navn = 'T1')), 'P0002');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik(public.setup_template_delete((select (j ->> 'id')::uuid from svar where navn = 'T1')), true, 'T14 rounds sletter rundemalen');
select pg_temp.feil(format('select public.setup_template_delete(%L)', (select j ->> 'id' from svar where navn = 'T1')), 'P0002');
reset role;
-- Grensene i tabellen og taket.
select pg_temp.som('');
select pg_temp.feil($$insert into public.setup_templates (club_id, kind, name, payload)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', 'round', 'Rå', jsonb_build_object('x', repeat('a', 40000)))$$, '23514');
select pg_temp.feil($$insert into public.setup_templates (club_id, owner_id, kind, name)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'round', 'To hjem')$$, '23514');
select pg_temp.feil($$insert into public.setup_templates (kind, name) values ('round', 'Uten hjem')$$, '23514');
insert into public.setup_templates (club_id, kind, name)
select :'G', 'round', 'Fyll ' || g from generate_series(1, 200 - (select count(*) from public.setup_templates where club_id = :'G')) g;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.setup_template_save(null, %L, ''round'', ''Nr 201'', ''{}'')', :'G'), '54000');
reset role;

-- --- P: previous_round_setup ---------------------------------------------------------
select pg_temp.som('');
-- På kveld 3: runde 1 går (R3, 9 hull), runde 2 er kladd (R4). Legg til en playoff (runde 3,
-- startet) og en ny kladd (runde 5), og et spill på R3.
insert into public.rounds (id, club_id, event_id, round_no, status, kind, playoff_for, playoff_holes, counts, course_id, hole_count)
values ('dddddddd-0000-0000-0000-0000000049f0', :'G', :'E3', 3, 'active', 'playoff', :'S26', '{0}', false,
        'cccccccc-0000-0000-0000-000000000001', 18);
insert into public.rounds (id, club_id, event_id, round_no, status) values ('dddddddd-0000-0000-0000-0000000049d0', :'G', :'E3', 5, 'draft');
insert into public.round_games (round_id, kind, settings) values (:'R3', 'skins', '{"carry": true}');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select (s ->> 'round_id') || '|' || (s ->> 'hole_count') || '|' || (s ->> 'event_date')
                      from (select public.previous_round_setup(:'E3') s) x),
                   :'R3' || '|9|2026-10-01', 'P1 kveld 3: runde 1 (ikke kladden, ikke playoffen)');
select pg_temp.lik((select jsonb_array_length(s -> 'players') || '|' || jsonb_array_length(s -> 'matches') || '|'
                           || (s -> 'games' -> 0 ->> 'kind') || '|' || (s -> 'games' -> 0 -> 'settings' ->> 'carry')
                      from (select public.previous_round_setup(:'E3') s) x),
                   '4|0|skins|true', 'P2 spillerne, matchene og spillene er med');
select pg_temp.lik((select string_agg(coalesce(p ->> 'bay_no', '-') || ':' || (p ->> 'is_marker'), ',')
                      from (select public.previous_round_setup(:'E3') s) x, jsonb_array_elements(s -> 'players') p),
                   '1:true,1:false,2:false,-:false', 'P3 båsene med markør først');
select pg_temp.lik((select (s ->> 'round_id') || '|' || (s -> 'matches' -> 0 ->> 'player_a')
                      from (select public.previous_round_setup(:'E2') s) x),
                   :'R2' || '|' || :'m1', 'P4 kveld 2: runde 1 med matchen');
select pg_temp.lik((select s ->> 'round_id' from (select public.previous_round_setup(
                       (select (j -> 'event_ids' ->> 0)::uuid from svar where navn = 'S12')) s) x),
                   :'R3', 'P5 en senere sesongkveld (uten runder): den siste startede runden før den');
select pg_temp.lik((select s ->> 'round_id' from (select public.previous_round_setup(
                       (select (j -> 'event_ids' ->> 0)::uuid from svar where navn = 'S1')) s) x),
                   :'TLR', 'P6 Torsdagsligaen: bare runder i samme turnering');
select pg_temp.lik(public.previous_round_setup((select (j -> 'event_ids' ->> 0)::uuid from svar where navn = 'S11')),
                   null::jsonb, 'P7 Fredagsligaen uten runder: null');
select pg_temp.lik((select s ->> 'round_id' from (select public.previous_round_setup(:'E4') s) x),
                   :'R5', 'P8 kveld uten turnering: runder på kvelder uten turnering');
reset role;
-- En runde som ikke teller, er fortsatt «sist». En låst playoff er det ikke.
select pg_temp.som('');
update public.rounds set counts = false, points_table = 'finale', hide_last_holes = 3 where id = :'R3';
update public.rounds set status = 'locked' where id = 'dddddddd-0000-0000-0000-0000000049f0';
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik((select (s ->> 'round_id') || '|' || (s ->> 'counts') || '|' || (s ->> 'points_table') || '|' || (s ->> 'hide_last_holes')
                      from (select public.previous_round_setup(:'E3') s) x),
                   :'R3' || '|false|finale|3', 'P9 rounds kan hente; runde som ikke teller er med, med feltene');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.feil(format('select public.previous_round_setup(%L)', :'E3'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.previous_round_setup(%L)', :'E3'), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.previous_round_setup(%L)', :'E3'), 'P0002');
reset role;
-- Arkivert spiller er ikke med i forslaget.
select pg_temp.som('');
update public.club_members set status = 'archived' where id = :'m9';
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select jsonb_array_length(s -> 'players') from (select public.previous_round_setup(:'E3') s) x), 3,
                   'P10 arkivert spiller er ikke med i forslaget');
reset role;

-- --- A: anon -------------------------------------------------------------------------
select pg_temp.som('');
set role anon;
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'TL', :'s_from'), '42501');
select pg_temp.feil(format('select public.update_event_series(%L, ''one'', null, null)', :'TLE'), '42501');
select pg_temp.feil(format('select public.setup_template_save(null, null, ''round'', ''x'', ''{}'')'), '42501');
select pg_temp.feil(format('select public.setup_template_delete(%L)', :'TLE'), '42501');
select pg_temp.feil(format('select public.previous_round_setup(%L)', :'E3'), '42501');
select pg_temp.feil('select count(*) from public.setup_templates', '42501');
select pg_temp.feil('select count(*) from public.event_series', '42501');
reset role;
-- Innlogget uten bruker-id i kallet.
set role authenticated;
select pg_temp.feil(format('select public.create_event_series(%L, %L, 4::smallint, 3::smallint)', :'TL', :'s_from'), '42501');
reset role;

rollback;
