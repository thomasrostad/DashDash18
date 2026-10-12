\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 051_kalender_regning.sql. Kjøres på kopien med 001–043, 034, 044, 045, 047, 046 og
-- 049, så 051 (to ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
-- Datoene regnes fra dagens dato i Oslo, så prøven virker uansett dag.
--
-- K: kalenderlenken: lages, er den samme, fornyes, skrus av; bare via funksjonene.
-- F: calendar_feed: bare bekreftede kvelder (ikke kanskje/nei/venteliste), tidsvinduet, opprykk,
--    slettet kveld, arkivert medlem, flere klubber, ingen personopplysninger, anon bare med token.
-- R: Del regningen: lage (nullsum, grenser, hvem), RLS (bare de som er med), Vipps-nummeret.
-- S: sendt, bekreftet og «kom ikke»: hvem, idempotens, aktivitet og push-gruppe.
-- D: sletting.
-- L: løs runde uten klubb.
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
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u5  '00000000-0000-0000-0000-000000000005'
\set u7  '00000000-0000-0000-0000-000000000007'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set AN  'aaaaaaaa-0000-0000-0000-000000000002'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set m9  '11111111-0000-0000-0000-000000000009'
\set o4  '22222222-0000-0000-0000-000000000004'
\set TL  'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set E3  'eeeeeeee-0000-0000-0000-000000000003'
\set E9  'eeeeeeee-0000-0000-0000-000000000009'
\set R3  'dddddddd-0000-0000-0000-000000000003'
-- Nytt for prøven: kvelder K1–K7 i Golfgutu, KA i Andre, en løs runde LR.
\set K1  'eeeeeeee-0000-0000-0000-000000005101'
\set K2  'eeeeeeee-0000-0000-0000-000000005102'
\set K3  'eeeeeeee-0000-0000-0000-000000005103'
\set K4  'eeeeeeee-0000-0000-0000-000000005104'
\set K5  'eeeeeeee-0000-0000-0000-000000005105'
\set K6  'eeeeeeee-0000-0000-0000-000000005106'
\set K7  'eeeeeeee-0000-0000-0000-000000005107'
\set KA  'eeeeeeee-0000-0000-0000-0000000051a1'
\set LR  'dddddddd-0000-0000-0000-000000005101'

select (now() at time zone 'Europe/Oslo')::date as idag \gset

begin;

-- --- Verdenen --------------------------------------------------------------------
select pg_temp.som('');
insert into public.events (id, club_id, competition_id, event_date, start_time, venue, note) values
  (:'K1', :'G', :'TL', :'idag'::date + 7, '18:00', 'Simsenteret, bås 3', 'Ta med sko; og godt humør'),
  (:'K2', :'G', null, :'idag'::date + 14, null, null, null),
  (:'K3', :'G', null, :'idag'::date + 400, '18:00', null, null),
  (:'K4', :'G', null, :'idag'::date - 40, '18:00', null, null),
  (:'K5', :'G', null, :'idag'::date - 10, '19:30', 'Bærum', null),
  (:'K6', :'G', null, :'idag'::date + 21, '18:00', null, null),
  (:'K7', :'G', null, :'idag'::date + 28, '18:00', null, null),
  (:'KA', :'AN', null, :'idag'::date + 7, '17:00', 'Andre-banen', null);
-- Thomas: ja på K1, K3 (for langt fram), K4 (for lenge siden), K5; kanskje på K2; nei på K6.
insert into public.signups (event_id, member_id, club_id, status) values
  (:'K1', :'m1', :'G', 'yes'), (:'K2', :'m1', :'G', 'maybe'), (:'K3', :'m1', :'G', 'yes'),
  (:'K4', :'m1', :'G', 'yes'), (:'K5', :'m1', :'G', 'yes'), (:'K6', :'m1', :'G', 'no'),
  (:'K1', :'m2', :'G', 'yes'), (:'KA', :'o4', :'AN', 'yes');
-- K7 har tak 1: Anders først, Thomas på venteliste.
update public.events set max_players = 1 where id = :'K7';
insert into public.signups (event_id, member_id, club_id, status) values (:'K7', :'m2', :'G', 'yes');
insert into public.signups (event_id, member_id, club_id, status) values (:'K7', :'m1', :'G', 'yes');
select pg_temp.lik((select waitlisted_at is not null from public.signups where event_id = :'K7' and member_id = :'m1'), true,
                   'F0 Thomas står på venteliste på K7');
create temp table svar (navn text primary key, t text, j jsonb);
grant all on svar to public;

-- --- K: kalenderlenken -----------------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
insert into svar (navn, t) select 'T1', public.calendar_token();
select pg_temp.lik((select t ~ '^[a-z2-7]{32}$' from svar where navn = 'T1'), true, 'K1 lenken er 32 tegn base32');
select pg_temp.lik(public.calendar_token(), (select t from svar where navn = 'T1'), 'K2 samme lenke neste gang');
select pg_temp.lik(public.calendar_token(false), (select t from svar where navn = 'T1'), 'K3 p_renew = false gir samme lenke');
select pg_temp.feil('select count(*) from public.calendar_tokens', '42501');
select pg_temp.feil(format('insert into public.calendar_tokens (user_id, token) values (%L, %L)', :'u2', repeat('a', 32)), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into svar (navn, t) select 'T2', public.calendar_token();
select pg_temp.lik((select count(distinct t) from svar where navn in ('T1', 'T2')), 2::bigint, 'K4 Anders får en annen lenke enn Thomas');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into svar (navn, t) select 'T4', public.calendar_token();
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.calendar_tokens), 3::bigint, 'K5 én rad per innlogging');

-- --- F: calendar_feed ----------------------------------------------------------------------
select pg_temp.som(''); set role anon;
insert into svar (navn, j) select 'F1', public.calendar_feed((select t from svar where navn = 'T1'));
reset role;
select pg_temp.lik((select string_agg(e ->> 'id', ',' order by e ->> 'date') from svar, jsonb_array_elements(j -> 'events') e where navn = 'F1'),
                   :'K5' || ',' || :'K1', 'F1 anon med lenken: bare K5 og K1 (ja, i vinduet; ikke kanskje, nei, venteliste eller utenfor)');
select pg_temp.lik((select (select array_agg(k order by k) from jsonb_object_keys(e) k) from svar, jsonb_array_elements(j -> 'events') e
                     where navn = 'F1' and e ->> 'id' = :'K1'),
                   array['club_name', 'competition_kind', 'competition_name', 'date', 'id', 'note', 'start_time', 'updated_at', 'venue'],
                   'F2 en kveld har bare id, klubb, turnering, dato, tid, sted, notat og updated_at');
select pg_temp.lik((select array_agg(k order by k) from svar, jsonb_object_keys(j) k where navn = 'F1'),
                   array['events', 'generated_at', 'time_zone'], 'F3 toppen har bare events, generated_at og time_zone');
select pg_temp.lik((select e ->> 'club_name' || '|' || (e ->> 'competition_name') || '|' || (e ->> 'competition_kind') || '|'
                           || (e ->> 'start_time') || '|' || (e ->> 'venue') || '|' || (e ->> 'note')
                      from svar, jsonb_array_elements(j -> 'events') e where navn = 'F1' and e ->> 'id' = :'K1'),
                   'Golfgutu|Torsdagsligaen|league|18:00:00|Simsenteret, bås 3|Ta med sko; og godt humør',
                   'F4 K1 med klubb, turnering, tid, sted og notat');
select pg_temp.lik((select j::text ~* (:'u1' || '|' || :'u2' || '|' || :'m1' || '|' || :'m2' || '|Thomas|Anders|@|user_id|member_id')
                      from svar where navn = 'F1'), false,
                   'F5 ingen bruker-id, medlems-id, navn på personer eller e-post i svaret');
select pg_temp.lik((select (e ->> 'updated_at')::timestamptz from svar, jsonb_array_elements(j -> 'events') e
                     where navn = 'F1' and e ->> 'id' = :'K1'),
                   (select greatest(ev.updated_at, s.updated_at) from public.events ev join public.signups s on s.event_id = ev.id
                     where ev.id = :'K1' and s.member_id = :'m1'),
                   'F6 updated_at er det seneste av kvelden og påmeldingen');
-- Opprykk fra ventelista: K7 dukker opp.
select pg_temp.som(:'u2'); set role authenticated;
select public.evening_signup(:'K7', 'no', null, null) as _x \gset
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.lik((select count(*) from jsonb_array_elements(public.calendar_feed((select t from svar where navn = 'T1')) -> 'events') e
                     where e ->> 'id' = :'K7'), 1::bigint, 'F7 Thomas rykker opp på K7 og kvelden kommer i kalenderen');
reset role;
-- Thomas melder seg av K1: borte.
select pg_temp.som(:'u1'); set role authenticated;
select public.evening_signup(:'K1', 'maybe', null, null) as _x \gset
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.lik((select count(*) from jsonb_array_elements(public.calendar_feed((select t from svar where navn = 'T1')) -> 'events') e
                     where e ->> 'id' = :'K1'), 0::bigint, 'F8 «kanskje» på K1: kvelden forsvinner');
reset role;
-- Slettet kveld: borte.
select pg_temp.som('');
delete from public.events where id = :'K5';
set role anon;
select pg_temp.lik((select string_agg(e ->> 'id', ',') from jsonb_array_elements(public.calendar_feed((select t from svar where navn = 'T1')) -> 'events') e),
                   :'K7', 'F9 slettet kveld (K5) forsvinner; igjen er K7');
-- Andre klubber: Ola ser bare Andre.
select pg_temp.lik((select string_agg(e ->> 'id', ',') from jsonb_array_elements(public.calendar_feed((select t from svar where navn = 'T4')) -> 'events') e),
                   :'KA', 'F10 Ola ser bare sin kveld i Andre');
-- Anders: ja på K1.
select pg_temp.lik((select string_agg(e ->> 'id', ',') from jsonb_array_elements(public.calendar_feed((select t from svar where navn = 'T2')) -> 'events') e),
                   :'K1', 'F11 Anders ser K1 (ikke K7, der han meldte seg av)');
reset role;
-- Arkivert medlem: ingen kvelder.
select pg_temp.som('');
update public.club_members set status = 'archived' where id = :'m2';
set role anon;
select pg_temp.lik((select jsonb_array_length(public.calendar_feed((select t from svar where navn = 'T2')) -> 'events')), 0,
                   'F12 arkivert medlem: tom kalender');
reset role;
update public.club_members set status = 'active' where id = :'m2';
-- Ugyldige tokens.
set role anon;
select pg_temp.feil(format('select public.calendar_feed(%L)', repeat('a', 32)), 'P0002');
select pg_temp.feil('select public.calendar_feed(null)', 'P0002');
select pg_temp.feil('select public.calendar_feed(''kort'')', 'P0002');
select pg_temp.feil(format('select public.calendar_feed(%L)', upper((select t from svar where navn = 'T1'))), 'P0002');
select pg_temp.feil('select public.calendar_token()', '42501');
select pg_temp.feil('select public.calendar_token_revoke()', '42501');
select pg_temp.feil('select count(*) from public.calendar_tokens', '42501');
reset role;
-- Fornyelse og avskruing.
select pg_temp.som(:'u1'); set role authenticated;
insert into svar (navn, t) select 'T1b', public.calendar_token(true);
select pg_temp.lik((select (select t from svar where navn = 'T1b') <> t from svar where navn = 'T1'), true, 'K6 ny lenke er en annen');
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.feil(format('select public.calendar_feed(%L)', (select t from svar where navn = 'T1')), 'P0002');
select pg_temp.lik((select jsonb_array_length(public.calendar_feed((select t from svar where navn = 'T1b')) -> 'events')), 1,
                   'K7 den nye lenken virker, den gamle gir P0002 (linja over)');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.calendar_token_revoke() as _x \gset
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.feil(format('select public.calendar_feed(%L)', (select t from svar where navn = 'T1b')), 'P0002');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
insert into svar (navn, t) select 'T1c', public.calendar_token();
select pg_temp.lik((select t not in (select t from svar where navn in ('T1', 'T1b')) from svar where navn = 'T1c'), true,
                   'K8 etter «skru av» gir calendar_token() en helt ny lenke');
reset role;
-- Uten innlogging i kallet.
set role authenticated;
select pg_temp.som('');
select pg_temp.feil('select public.calendar_token()', '42501');
reset role;
-- Konto slettet: lenken går.
select pg_temp.som('');
savepoint slett_konto;
delete from auth.users where id = :'u4';
select pg_temp.lik((select count(*) from public.calendar_tokens where user_id = :'u4'), 0::bigint, 'K9 slettet konto: lenken slettes');
rollback to savepoint slett_konto;

-- --- R: Del regningen, lage ----------------------------------------------------------------
-- Thomas la ut 1000 kr for simulatoren; Thomas, Anders, Bjørn og Carl (uten innlogging) deler likt.
select pg_temp.som(:'u1'); set role authenticated;
insert into svar (navn, j) select 'R1', public.bill_split_create(
  ' Simulatorleie ', 100000, 'Thomas',
  jsonb_build_array(jsonb_build_object('profile_id', :'u2', 'name', 'Anders', 'amount_ore', 25000),
                    jsonb_build_object('profile_id', :'u3', 'name', 'Bjørn', 'amount_ore', 25000),
                    jsonb_build_object('name', 'Carl', 'amount_ore', 25000)),
  :'u1', 25000, '+47 987 65 432', :'G', :'K2', null);
reset role;
select (j ->> 'split_id') as rs from svar where navn = 'R1' \gset
select (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R1' and s ->> 'name' = 'Anders') as sh_a,
       (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R1' and s ->> 'name' = 'Bjørn') as sh_b,
       (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R1' and s ->> 'name' = 'Carl') as sh_c,
       (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R1' and (s ->> 'is_payee')::boolean) as sh_t \gset
select pg_temp.som('');
select pg_temp.lik((select title || '|' || total_ore || '|' || payee_name || '|' || payee_vipps || '|' || (created_by = :'u1')
                           || '|' || (club_id = :'G') || '|' || (event_id = :'K2')
                      from public.bill_splits where id = :'rs'),
                   'Simulatorleie|100000|Thomas|98765432|true|true|true',
                   'R1 regningen er lagret (tittel trimmet, nummeret normalisert)');
select pg_temp.lik((select string_agg(name || ':' || amount_ore || ':' || status, ',' order by is_payee desc, name)
                      from public.bill_split_shares where split_id = :'rs'),
                   'Thomas:25000:confirmed,Anders:25000:open,Bjørn:25000:open,Carl:25000:open',
                   'R2 fire deler; mottakerens egen er bekreftet, de andre åpne');
select pg_temp.lik((select sum(amount_ore) from public.bill_split_shares where split_id = :'rs'), 100000::bigint,
                   'R3 nullsum: delene er lik regningen');
-- Nullsum i RPC-en.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100000, 'Thomas', '[{"name":"A","amount_ore":50000}]', %L, 49999, null, %L)$f$, :'u1', :'G'), '23514');
reset role;
-- Nullsum i databasen (utsatt constraint-trigger), også for service_role/skript.
select pg_temp.som('');
select pg_temp.feil(format($f$do $x$ begin
  update public.bill_split_shares set amount_ore = amount_ore + 1 where id = %L;
  set constraints all immediate; end $x$$f$, :'sh_a'), '23514');
select pg_temp.feil(format($f$do $x$ begin
  insert into public.bill_splits (club_id, created_by, payee_name, title, total_ore) values (%L, %L, 'X', 'Y', 500);
  set constraints all immediate; end $x$$f$, :'G', :'u1'), '23514');
select pg_temp.feil(format($f$do $x$ begin
  delete from public.bill_split_shares where id = %L;
  set constraints all immediate; end $x$$f$, :'sh_c'), '23514');
-- Grenser og regler.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]')$f$), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 0, 'Thomas', '[{"name":"A","amount_ore":0}]', null, 0, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[]', null, 100, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":"mye"}]', null, 0, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","profile_id":"x","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 5100, 'Thomas', %L, null, 0, null, %L)$f$,
                           (select jsonb_agg(jsonb_build_object('name', 'P' || i, 'amount_ore', 100)) from generate_series(1, 51) i), :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', null, -5, null, %L)$f$, :'G'), '22023');
-- Ola (u4) er ikke i Golfgutu: kan ikke betale der.
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"Ola","profile_id":%s,"amount_ore":100}]', %L, 0, null, %L)$f$,
                           to_jsonb(:'u4'::text), :'u1', :'G'), '22023');
-- Samme person to ganger, og mottakeren som skyldner.
select pg_temp.feil(format($f$select public.bill_split_create('X', 200, 'Thomas', '[{"name":"A","profile_id":%s,"amount_ore":100},{"name":"A2","profile_id":%s,"amount_ore":100}]', %L, 0, null, %L)$f$,
                           to_jsonb(:'u2'::text), to_jsonb(:'u2'::text), :'u1', :'G'), '23505');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"T","profile_id":%s,"amount_ore":100}]', %L, 0, null, %L)$f$,
                           to_jsonb(:'u1'::text), :'u1', :'G'), '23505');
-- Mottaker som ikke er med, kveld i en annen klubb, runde i en annen klubb.
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Ola', '[{"name":"A","amount_ore":100}]', %L, 0, null, %L)$f$, :'u4', :'G'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', null, 0, null, %L, %L)$f$, :'G', :'E9'), 'P0002');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', null, 0, null, %L, null, %L)$f$, :'AN', :'R3'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', %L, 0, '12345', %L)$f$, :'u1', :'G'), '22023');
-- Runde i klubben gir klubben.
insert into svar (navn, j) select 'R4', public.bill_split_create('Greenfee', 300, 'Carl', '[{"name":"Thomas","amount_ore":150}]', null, 150, null, null, null, :'R3');
reset role;
select pg_temp.lik((select club_id = :'G' and round_id = :'R3' and payee_profile_id is null and payee_vipps is null
                      from public.bill_splits where id = (select (j ->> 'split_id')::uuid from svar where navn = 'R4')), true,
                   'R4 regning på en klubbrunde: klubben fra runden, mottaker uten innlogging');
-- Ola er ikke medlem i Golfgutu.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Ola', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '42501');
reset role;
-- Dag er ventende i Golfgutu.
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Dag', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '42501');
reset role;
-- Anders lager en regning der Thomas er mottaker: kan ikke skrive nummeret til Thomas.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('Mat', 200, 'Thomas', '[{"name":"Anders","profile_id":%s,"amount_ore":100}]', %L, 100, '98765432', %L)$f$,
                           to_jsonb(:'u2'::text), :'u1', :'G'), '42501');
insert into svar (navn, j) select 'R5', public.bill_split_create('Mat', 200, 'Bjørn',
  jsonb_build_array(jsonb_build_object('profile_id', :'u1', 'name', 'Thomas', 'amount_ore', 100)), :'u3', 100, null, :'G');
-- Ingen direkte skriving.
select pg_temp.feil(format('insert into public.bill_splits (club_id, payee_name, title, total_ore) values (%L, ''X'', ''Y'', 1)', :'G'), '42501');
select pg_temp.feil(format('update public.bill_split_shares set confirmed_at = now() where id = %L', :'sh_a'), '42501');
select pg_temp.feil(format('delete from public.bill_splits where id = %L', :'rs'), '42501');
reset role;
select (j ->> 'split_id') as rs5 from svar where navn = 'R5' \gset
select (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R5' and s ->> 'name' = 'Thomas') as sh5_t \gset

-- RLS: hvem ser hva.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.bill_splits), 3::bigint, 'R6 Thomas ser sine tre (laget R1 og R4, skylder i R5)');
select pg_temp.lik((select count(*) from public.bill_split_shares), 8::bigint, 'R7 Thomas ser alle delene i de tre (4 + 2 + 2)');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select string_agg(title, ',' order by title) from public.bill_splits), 'Mat,Simulatorleie',
                   'R8 Anders ser R1 (skylder) og R5 (laget), ikke R4');
select pg_temp.lik((select count(*) from public.bill_split_shares where split_id = :'rs'), 4::bigint, 'R9 Anders ser alle delene i R1');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select string_agg(title, ',' order by title) from public.bill_splits), 'Mat,Simulatorleie',
                   'R10 Bjørn ser R1 (skylder) og R5 (mottaker)');
select pg_temp.lik((select payee_vipps from public.bill_splits where id = :'rs'), '98765432', 'R11 de som er med, ser Vipps-nummeret');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik((select count(*) from public.bill_splits) + (select count(*) from public.bill_split_shares), 0::bigint,
                   'R12 Siv (annen klubb) ser ingen regninger eller deler');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select count(*) from public.bill_splits) + (select count(*) from public.bill_split_shares), 0::bigint,
                   'R13 Dag (ventende i klubben) ser ingenting');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.bill_splits), 0::bigint, 'R14 Ola (arrangør i Andre) ser ingenting');
reset role;
-- Arrangøren i Golfgutu som ikke er med: lag en ny arrangør uten del.
select pg_temp.som('');
insert into auth.users (id) values ('00000000-0000-0000-0000-000000005108'), ('00000000-0000-0000-0000-000000005109');
insert into public.club_members (id, club_id, user_id, display_name, status) values
  ('11111111-0000-0000-0000-000000005108', :'G', '00000000-0000-0000-0000-000000005108', 'Eier 51', 'active'),
  ('11111111-0000-0000-0000-000000005109', :'G', '00000000-0000-0000-0000-000000005109', 'Vanlig 51', 'active');
insert into public.club_member_roles (club_id, member_id, role_id)
  select :'G', '11111111-0000-0000-0000-000000005108', r.id from public.club_roles r where r.club_id = :'G' and r.is_owner;
select pg_temp.som('00000000-0000-0000-0000-000000005108'); set role authenticated;
select pg_temp.lik((select count(*) from public.bill_splits) + (select count(*) from public.bill_split_shares), 0::bigint,
                   'R15 en eier i klubben som ikke er med i regningen, ser ingenting');
reset role;

-- Vipps-nummeret.
select pg_temp.som(:'u3'); set role authenticated;
select public.bill_split_set_vipps(:'rs5', '412 34 567') as _x \gset
select pg_temp.lik((select payee_vipps from public.bill_splits where id = :'rs5'), '41234567', 'R16 mottakeren legger inn nummeret sitt');
select pg_temp.feil(format('select public.bill_split_set_vipps(%L, ''98765432'')', :'rs'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.bill_split_set_vipps(%L, ''98765432'')', :'rs5'), '42501');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format('select public.bill_split_set_vipps(%L, ''98765432'')', :'rs5'), 'P0002');
reset role;

-- --- S: sendt, bekreftet, kom ikke --------------------------------------------------------
select pg_temp.som('');
select count(*) as akt0 from public.activity where kind like 'bill_share_%' \gset
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_a'), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_a'), '42501');
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_t'), '22023');
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_c'), '42501');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_a'), 'P0002');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((public.bill_share_mark_sent(:'sh_a')) ->> 'status', 'sent', 'S1 Anders kommer tilbake fra Vipps: delen er sendt');
select pg_temp.lik((public.bill_share_mark_sent(:'sh_a')) ->> 'status', 'sent', 'S2 en gang til (ny retur fra Vipps): fortsatt sendt');
select pg_temp.feil(format('select public.bill_share_confirm(%L, true)', :'sh_a'), '42501');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'bill_share_sent'), 1::bigint,
                   'S3 én linje bill_share_sent (ikke én per retur)');
select pg_temp.lik((select category || '|' || (recipients = array[:'m1'::uuid]) || '|' || (actor_member_id = :'m2') || '|' || (club_id = :'G')
                           || '|' || (data ->> 'title') || '|' || (data ->> 'name') || '|' || (data ? 'amount_ore')
                           || '|' || (data ->> 'split_id' = :'rs') || '|' || (data ->> 'share_id' = :'sh_a') || '|' || (event_id is null)
                      from public.activity where kind = 'bill_share_sent'),
                   'social|true|true|true|Simulatorleie|Anders|false|true|true|true',
                   'S4 linja går til Thomas, fra Anders, med tittel og navn, uten beløp og uten kveld');
select pg_temp.lik((select public.push_group(a.category, a.kind) from public.activity a where kind = 'bill_share_sent'), 'social',
                   'S5 push-gruppen er Sosialt');
select pg_temp.lik((select count(*) from public.push_queue q join public.activity a on a.id = q.activity_id where a.kind = 'bill_share_sent'), 1::bigint,
                   'S6 linja ligger i push-køen');
select (select q.id from public.push_queue q join public.activity a on a.id = q.activity_id where a.kind = 'bill_share_sent') as jobb \gset
select pg_temp.lik((select (p ->> 'group') || '|' || coalesce(p ->> 'collapse', 'ingen') from (select public.push_job_payload(:'jobb') p) x),
                   'social|ingen', 'S7 push_job_payload: gruppe social, ingen collapse (ingen kveld)');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'bill_share_sent'), 1::bigint, 'S8 Thomas (mottaker) ser linja');
reset role;
select pg_temp.som('00000000-0000-0000-0000-000000005109'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'bill_share_sent'), 0::bigint, 'S9 et vanlig medlem (ikke mottaker) ser den ikke');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) || '|' || bool_or(data ? 'amount_ore') from public.activity where kind = 'bill_share_sent'), '1|false',
                   'S9b Bjørn (arrangør) ser linja etter 001-regelen, men uten beløp');
reset role;
-- Thomas: «kom ikke» på Bjørn (ikke sendt) er feil; på Anders går det.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.bill_share_confirm(%L, false)', :'sh_b'), '22023');
select pg_temp.feil(format('select public.bill_share_confirm(%L, true)', :'sh_t'), '22023');
select pg_temp.feil(format('select public.bill_share_confirm(%L, null)', :'sh_a'), '22023');
select pg_temp.lik((public.bill_share_confirm(:'sh_a', false)) ->> 'status', 'disputed', 'S10 Thomas: Anders sin kom ikke');
select pg_temp.lik((public.bill_share_confirm(:'sh_a', false)) ->> 'status', 'disputed', 'S11 en gang til: fortsatt «kom ikke»');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) || '|' || bool_and(recipients = array[:'m2'::uuid]) || '|' || bool_and(actor_member_id = :'m1')
                           || '|' || bool_and(data ->> 'name' = 'Thomas')
                      from public.activity where kind = 'bill_share_disputed'),
                   '1|true|true|true', 'S12 én bill_share_disputed til Anders, fra Thomas');
select pg_temp.lik((select public.push_group(a.category, a.kind) from public.activity a where kind = 'bill_share_disputed'), 'social',
                   'S13 push-gruppen er Sosialt');
-- Anders sender på nytt.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((public.bill_share_mark_sent(:'sh_a')) ->> 'status', 'sent', 'S14 Anders sender på nytt etter «kom ikke»');
select pg_temp.lik((select disputed_at is null from public.bill_split_shares where id = :'sh_a'), true, 'S15 «kom ikke» er fjernet');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'bill_share_sent'), 2::bigint, 'S16 ny bill_share_sent til Thomas');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.bill_share_confirm(:'sh_a', true)) ->> 'status', 'confirmed', 'S17 Thomas bekrefter Anders sin');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((public.bill_share_mark_sent(:'sh_a')) ->> 'status', 'confirmed', 'S18 bekreftet står når Anders kommer tilbake fra Vipps igjen');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'bill_share_sent'), 2::bigint, 'S19 ingen ny linje for en bekreftet del');
-- Bjørn betalte kontant: bekreftes uten «sendt». Carl (uten innlogging) også.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.bill_share_confirm(:'sh_b', true)) ->> 'status', 'confirmed', 'S20 bekreftet uten «sendt» (kontant)');
select pg_temp.lik((select payee_vipps from public.bill_splits where id = :'rs'), '98765432', 'S21 nummeret står så lenge noen ikke har betalt');
select pg_temp.lik((public.bill_share_confirm(:'sh_c', true)) ->> 'status', 'confirmed', 'S22 Carl (uten innlogging) bekreftes av mottakeren');
select pg_temp.lik((select payee_vipps from public.bill_splits where id = :'rs'), null::text, 'S23 alle har betalt: Vipps-nummeret er slettet');
-- Feil om: bekreftet kan endres til «kom ikke» av mottakeren.
select pg_temp.lik((public.bill_share_confirm(:'sh_b', false)) ->> 'status', 'disputed', 'S24 mottakeren kan angre en bekreftelse («kom ikke»)');
select pg_temp.lik((public.bill_share_confirm(:'sh_b', true)) ->> 'status', 'confirmed', 'S25 og bekrefte igjen');
reset role;
-- Mottaker uten innlogging (R4): den som laget regningen, bekrefter.
select (select s ->> 'id' from svar, jsonb_array_elements(j -> 'shares') s where navn = 'R4' and not (s ->> 'is_payee')::boolean) as sh4 \gset
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.bill_share_confirm(%L, true)', :'sh4'), 'P0002');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.bill_share_confirm(:'sh4', true)) ->> 'status', 'confirmed', 'S26 mottaker uten innlogging: den som laget regningen, bekrefter');
reset role;
-- Mottakeren sletter kontoen: nummeret går.
select pg_temp.som('');
update public.bill_splits set payee_profile_id = null where id = :'rs5';
select pg_temp.lik((select payee_vipps from public.bill_splits where id = :'rs5'), null::text, 'S27 mottakeren er borte (konto slettet): nummeret slettes');

-- --- D: sletting -----------------------------------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.bill_split_delete(%L)', :'rs'), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.bill_split_delete(%L)', :'rs'), '22023');
select pg_temp.feil(format('select public.bill_split_delete(%L)', :'rs5'), '42501');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format('select public.bill_split_delete(%L)', :'rs5'), 'P0002');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select public.bill_split_delete(:'rs5') as _x \gset
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.bill_splits where id = :'rs5') + (select count(*) from public.bill_split_shares where split_id = :'rs5'),
                   0::bigint, 'D1 Anders sletter R5 (ingen bekreftet): regningen og delene er borte');
-- En regning med en sendt (ikke bekreftet) del kan slettes.
select pg_temp.som(:'u1'); set role authenticated;
insert into svar (navn, j) select 'D2', public.bill_split_create('Pott', 200, 'Thomas',
  jsonb_build_array(jsonb_build_object('profile_id', :'u2', 'name', 'Anders', 'amount_ore', 200)), :'u1', 0, null, :'G');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select public.bill_share_mark_sent((select (s ->> 'id')::uuid from svar, jsonb_array_elements(j -> 'shares') s
                                     where navn = 'D2' and not (s ->> 'is_payee')::boolean)) as _x \gset
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.bill_split_delete((select (j ->> 'split_id')::uuid from svar where navn = 'D2')) as _x \gset
select pg_temp.lik((select count(*) from public.bill_splits where title = 'Pott'), 0::bigint,
                   'D2 sendt men ikke bekreftet: kan slettes (mottakerens egen del teller ikke)');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.bill_splits where id = :'rs'), 1::bigint, 'D3 R1 (bekreftede deler) står');
-- Mange regninger slettes på en gang (som når klubben slettes): nullsum-triggeren stopper ikke det.
savepoint slett_klubb;
select pg_temp.feil($q$do $x$ begin delete from public.bill_splits where club_id = 'aaaaaaaa-0000-0000-0000-000000000001';
  set constraints all immediate; raise exception 'slettet uten nullsumfeil' using errcode = 'P0099'; end $x$$q$, 'P0099');
rollback to savepoint slett_klubb;

-- --- L: løs runde uten klubb ------------------------------------------------------------------
select pg_temp.som('');
insert into public.rounds (id, club_id, owner_id, status) values (:'LR', null, :'u4', 'active');
insert into public.round_participants (round_id, profile_id, display_name) values
  (:'LR', :'u4', 'Ola'), (:'LR', :'u7', 'Siv'), (:'LR', null, 'Gjest');
select pg_temp.som(:'u7'); set role authenticated;
insert into svar (navn, j) select 'L1', public.bill_split_create('Greenfee', 90000, 'Ola',
  jsonb_build_array(jsonb_build_object('profile_id', :'u7', 'name', 'Siv', 'amount_ore', 30000),
                    jsonb_build_object('name', 'Gjest', 'amount_ore', 30000)), :'u4', 30000, null, null, null, :'LR');
select pg_temp.lik((select club_id is null and round_id = :'LR' from public.bill_splits where id = (select (j ->> 'split_id')::uuid from svar where navn = 'L1')),
                   true, 'L1 Siv lager en regning i den løse runden (uten klubb)');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Ola', '[{"name":"T","profile_id":%s,"amount_ore":100}]', %L, 0, null, null, null, %L)$f$,
                           to_jsonb(:'u1'::text), :'u4', :'LR'), '22023');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Ola', '[{"name":"A","amount_ore":100}]', %L, 0, null, %L, null, %L)$f$,
                           :'u4', :'AN', :'LR'), '22023');
select pg_temp.lik((public.bill_share_mark_sent((select (s ->> 'id')::uuid from svar, jsonb_array_elements(j -> 'shares') s
                                                  where navn = 'L1' and s ->> 'name' = 'Siv'))) ->> 'status', 'sent',
                   'L2 Siv merker sin del sendt');
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind like 'bill_share_%' and club_id is null), 0::bigint,
                   'L3 ingen aktivitetslinje uten klubb (statusen står i regningen)');
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select status from public.bill_split_shares where name = 'Siv'), 'sent', 'L4 Ola (mottaker) ser at Siv har sendt');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Thomas', '[{"name":"A","amount_ore":100}]', null, 0, null, null, null, %L)$f$, :'LR'), 'P0002');
select pg_temp.lik((select count(*) from public.bill_splits where round_id = :'LR'), 0::bigint, 'L5 Thomas (ikke med i runden) ser den ikke');
reset role;

-- Grensen: 50 regninger i døgnet.
select pg_temp.som('');
savepoint grense;
insert into public.bill_splits (club_id, created_by, payee_name, title, total_ore)
  select :'G', :'u3', 'Bjørn', 'G' || i, 100 from generate_series(1, 50) i;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'Bjørn', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '54000');
reset role;
rollback to savepoint grense;

-- --- A: anon ------------------------------------------------------------------------------------
select pg_temp.som('');
set role anon;
select pg_temp.feil('select count(*) from public.bill_splits', '42501');
select pg_temp.feil('select count(*) from public.bill_split_shares', '42501');
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'A', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '42501');
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_a'), '42501');
select pg_temp.feil(format('select public.bill_share_confirm(%L, true)', :'sh_a'), '42501');
select pg_temp.feil(format('select public.bill_split_delete(%L)', :'rs'), '42501');
select pg_temp.feil(format('select public.bill_split_set_vipps(%L, null)', :'rs'), '42501');
reset role;
-- Innlogget uten bruker-id i kallet.
set role authenticated;
select pg_temp.feil(format($f$select public.bill_split_create('X', 100, 'A', '[{"name":"A","amount_ore":100}]', null, 0, null, %L)$f$, :'G'), '42501');
select pg_temp.feil(format('select public.bill_share_mark_sent(%L)', :'sh_a'), '42501');
reset role;

-- Nullsum til slutt: alle regningene som står, går i null (constraint-triggerne kjøres nå).
set constraints all immediate;
select pg_temp.lik((select count(*) from public.bill_splits s
                     where s.total_ore <> (select sum(x.amount_ore) from public.bill_split_shares x where x.split_id = s.id)), 0::bigint,
                   'Z1 alle regningene går i null');

rollback;
