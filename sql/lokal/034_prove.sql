\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 034_turnering_kjerne_trinn4.sql. Kjøres etter 033_prove-oppsettet
-- (hele kjeden 001–043) og 034 (to ganger). Alt rulles tilbake. Hver linje skal
-- starte med "ok"; ingen "FEIL".
--
-- A: en liga kan ha spilledag samme dato som jakkeracet, og en runde kan gå i
--    ligaen mens jakkeracets runde går. Samme spilledag og pulje gir fortsatt 23505.
-- B: bås 50 går, bås 100 avvises.
-- C: activate_season: med false står jakkeracet; standard avslutter
--    hovedturneringen og den nye tar over.
-- D: aktivitet uten klubb krever turnering, og leses bare av den som ser turneringen.
-- E: create_bet uten kveld velger hovedturneringen når flere serier er aktive.
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

\set u1     '00000000-0000-0000-0000-000000000001'
\set u5     '00000000-0000-0000-0000-000000000005'
\set klubb  'aaaaaaaa-0000-0000-0000-000000000001'
\set s2026  '5eeeeeee-0000-0000-0000-000000002026'
\set liga   'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set e3     'eeeeeeee-0000-0000-0000-000000000003'
\set r3     'dddddddd-0000-0000-0000-000000000003'

begin;

-- --- A: samme dato, to runder samtidig -------------------------------------
select pg_temp.lik((select status from public.rounds where id = :'r3'), 'active'::text, 'A0 jakkeracets runde går');
insert into public.events (id, club_id, event_date, competition_id)
values ('eeeeeeee-0000-0000-0000-0000000034a1', :'klubb', '2026-10-01', :'liga');
select 'ok A1 ligaen fikk spilledag samme dato som jakkeracet';
insert into public.rounds (id, club_id, event_id, status)
values ('dddddddd-0000-0000-0000-0000000034a1', :'klubb', 'eeeeeeee-0000-0000-0000-0000000034a1', 'draft');
update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-0000000034a1';
select pg_temp.lik((select count(*)::int from public.rounds where club_id = :'klubb' and status = 'active'), 2, 'A2 to aktive runder i klubben');
insert into public.rounds (id, club_id, event_id, status, round_no)
values ('dddddddd-0000-0000-0000-0000000034a2', :'klubb', 'eeeeeeee-0000-0000-0000-0000000034a1', 'draft', 2);
select pg_temp.feil($$update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-0000000034a2'$$, '23505');
select pg_temp.feil($$insert into public.events (club_id, event_date, competition_id)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-01', 'bd7acc4c-f21f-4b49-bc06-d84d915c2579')$$, '23505');

-- --- B: bås opp til 99 -------------------------------------------------------
update public.round_players set bay_no = 50, is_marker = false
 where round_id = :'r3' and member_id = (select member_id from public.round_players where round_id = :'r3' order by member_id limit 1);
select 'ok B1 bås 50';
select pg_temp.feil($$update public.round_players set bay_no = 100 where round_id = 'dddddddd-0000-0000-0000-000000000003'$$, '23514');

-- --- C: activate_season --------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (id, club_id, name, status, rules)
values ('5eeeeeee-0000-0000-0000-0000000034c1', :'klubb', 'Vinterserien', 'planned', '{"version": 2}');
select public.activate_season('5eeeeeee-0000-0000-0000-0000000034c1', false) is not null;
reset role;
select pg_temp.lik((select status from public.seasons where id = :'s2026'), 'active'::text, 'C1 jakkeracet står når serien aktiveres ved siden av');
select pg_temp.lik((select status from public.seasons where id = '5eeeeeee-0000-0000-0000-0000000034c1'), 'active'::text, 'C2 serien er aktiv');
select pg_temp.lik((select season_id from public.competitions where club_id = :'klubb' and is_main and status = 'active'), :'s2026'::uuid, 'C3 jakkeracet er fortsatt hovedturnering');

-- --- E: create_bet uten kveld (mens to serier er aktive) ------------------------
select pg_temp.som(:'u1'); set role authenticated;
create temp table e_bet as
  select public.create_bet(:'klubb', null, null, 'Thomas vinner jakkeracet', null, null, 'yes', 10) as svar;
reset role;
select pg_temp.lik((select b.season_id from public.bets b where b.question = 'Thomas vinner jakkeracet'), :'s2026'::uuid,
                   'E1 veddemål uten kveld havner i hovedturneringen');

-- C videre: standard avslutter hovedturneringen, og den nye tar over.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (id, club_id, name, status, rules)
values ('5eeeeeee-0000-0000-0000-0000000034c2', :'klubb', 'Sesong 2027', 'planned', '{"version": 2}');
select public.activate_season('5eeeeeee-0000-0000-0000-0000000034c2') is not null;
reset role;
select pg_temp.lik((select status from public.seasons where id = :'s2026'), 'finished'::text, 'C4 forrige hovedturnering er avsluttet');
select pg_temp.lik((select status from public.seasons where id = '5eeeeeee-0000-0000-0000-0000000034c1'), 'active'::text, 'C5 vinterserien står');
select pg_temp.lik((select season_id from public.competitions where club_id = :'klubb' and is_main and status = 'active'),
                   '5eeeeeee-0000-0000-0000-0000000034c2'::uuid, 'C6 den nye sesongen er hovedturnering');
select pg_temp.som(:'u5'); set role authenticated;
-- Den som ikke er med i klubben, ser ikke serien (RLS), og får «fant ikke».
select pg_temp.feil($$select public.activate_season('5eeeeeee-0000-0000-0000-0000000034c1')$$, 'P0002');
reset role;

-- --- D: aktivitet uten klubb ------------------------------------------------------
select pg_temp.feil($$insert into public.activity (club_id, competition_id, kind, category, data)
                      values (null, null, 'test', 'club', '{}')$$, '23514');
insert into public.activity (id, club_id, competition_id, kind, category, data)
values ('a0000000-0000-0000-0000-0000000034d1', null, :'liga', 'test', 'club', '{}');
select pg_temp.lik((select count(*)::int from public.push_queue where activity_id = 'a0000000-0000-0000-0000-0000000034d1'), 0, 'D0 hendelsen uten klubb går ikke i push-køen');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.activity where id = 'a0000000-0000-0000-0000-0000000034d1'), 1, 'D1 medlem som ser ligaen, ser hendelsen');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.activity where id = 'a0000000-0000-0000-0000-0000000034d1'), 0, 'D2 den som ikke ser ligaen, ser ikke hendelsen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$insert into public.activity (club_id, competition_id, kind, category, data)
                      values (null, 'bd7acc4c-f21f-4b49-bc06-d84d915c2579', 'test', 'club', '{}')$$, '42501');
reset role;

rollback;
