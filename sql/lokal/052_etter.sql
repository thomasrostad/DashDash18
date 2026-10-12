\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Etterfyllingsprøven for 052_veddemaal.sql. Kjøres på kopien der lokal/052_for.sql ble kjørt
-- FØR 052, og 052 så (to ganger). Alt rulles tilbake. Hver linje skal starte med "ok".
--
-- V: veddemålene fra før har sesongens turnering, er uendret, ses av de samme, og banken er lik
--    (gammel og ny funksjon, og bet_bank som appen spør).
-- Q: runden som var låst med et åpent vilkår, står i køen; serveren kan gjøre den opp.
-- G: gamle bygg etter 052: create_bet, place_bet_stake, settle_bet, mark_bets_closed, bet_points.
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
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u5  '00000000-0000-0000-0000-000000000005'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set SES '5eeeeeee-0000-0000-0000-000000002026'
\set RF  'dddddddd-0000-0000-0000-0000000052f1'
\set R3  'dddddddd-0000-0000-0000-000000000003'

begin;
select pg_temp.som('');
create temp table svar (navn text primary key, j jsonb);
grant all on svar to public;

-- --- V: veddemålene fra før ----------------------------------------------------------
select pg_temp.lik((select count(*) from public.bets b join prove052.bets f on f.id = b.id), 7::bigint,
                   'V1 alle sju veddemålene fra før finnes');
select pg_temp.lik((select count(*) from public.bets where competition_id = :'S26' and round_scope is null), 7::bigint,
                   'V2 alle har Sesong 2026 som turnering (fra sesongens speilede rad)');
select pg_temp.lik((select count(*) from public.bets b join prove052.bets f on f.id = b.id
                     where row(b.club_id, b.season_id, b.event_id, b.round_id, b.creator_id, b.against_id, b.question,
                              b.condition, b.status, b.resolution, b.closed_at, b.resolved_by, b.resolved_at, b.created_at)
                           is distinct from
                           row(f.club_id, f.season_id, f.event_id, f.round_id, f.creator_id, f.against_id, f.question,
                               f.condition, f.status, f.resolution, f.closed_at, f.resolved_by, f.resolved_at, f.created_at)),
                   0::bigint, 'V3 ingen kolonne fra før er endret');
select pg_temp.lik((select count(*) from public.bet_stakes s join prove052.stakes f on f.id = s.id
                     where row(s.bet_id, s.club_id, s.member_id, s.side, s.points, s.created_at)
                           is not distinct from row(f.bet_id, f.club_id, f.member_id, f.side, f.points, f.created_at)
                       and s.person_key = s.member_id and s.profile_id is null), 13::bigint,
                   'V4 de 13 innsatsene er uendret, person = medlemmet');
select pg_temp.lik((select bets_enabled from public.competitions where id = :'S26'), true, 'V5 Sesong 2026 har veddemål på');
select pg_temp.lik((select count(*) from public.competitions where bets_enabled and id <> :'S26' and not is_main), 0::bigint,
                   'V6 ingen andre turneringer (liga, morro) fikk veddemål på');
select pg_temp.lik((select count(*) from prove052.banker f, public.bet_points_for(:'SES', f.member_id) n
                     where row(n.net, n.at_stake, n.balance, n.available) is distinct from row(f.net, f.at_stake, f.balance, f.available)),
                   0::bigint, 'V7 gamle bet_points_for(sesong, medlem) gir samme tall som før');
select pg_temp.lik((select count(*) from prove052.banker f, public.bet_points_for(:'S26', null, f.member_id, null) n
                     where row(n.net, n.at_stake, n.balance, n.available) is distinct from row(f.net, f.at_stake, f.balance, f.available)),
                   0::bigint, 'V8 nye bet_points_for(turnering, medlem) gir samme tall som før');
select pg_temp.lik((select string_agg(member_id || '=' || balance || '/' || available, ' ' order by member_id) from prove052.banker
                     where member_id in (:'m1', :'m2', :'m3')),
                   :'m1' || '=920/780 ' || :'m2' || '=947/797 ' || :'m3' || '=1133/1043',
                   'V9 (bankene før: Thomas 920/780, Anders 947/797, Bjørn 1133/1043)');

set role authenticated;
select pg_temp.som(:'u1');
select pg_temp.lik((select row(b.balance, b.available)::text from public.bet_bank(:'S26', null) b), '(920,780)',
                   'V10 bet_bank uten person gir din bank (Thomas)');
select pg_temp.lik((select row(b.balance, b.available)::text from public.bet_bank(:'S26', null, :'m3') b), '(1133,1043)',
                   'V11 bet_bank for et annet medlem (Bjørn)');
select pg_temp.lik((select row(b.balance, b.available)::text from public.bet_points(:'SES', :'m2') b), '(947,797)',
                   'V12 gamle bet_points (appen i dag) gir samme tall');
reset role;

-- Hva hver innlogging ser.
set role authenticated;
select pg_temp.som(:'u1');
select pg_temp.lik((select (count(*), (select count(*) from public.bet_stakes))::text from public.bets),
                   (select (bets, stakes)::text from prove052.synlig where uid = :'u1'), 'V13 Thomas ser det samme som før');
select pg_temp.som(:'u2');
select pg_temp.lik((select (count(*), (select count(*) from public.bet_stakes))::text from public.bets),
                   (select (bets, stakes)::text from prove052.synlig where uid = :'u2'), 'V14 Anders ser det samme som før');
select pg_temp.som(:'u3');
select pg_temp.lik((select (count(*), (select count(*) from public.bet_stakes))::text from public.bets),
                   (select (bets, stakes)::text from prove052.synlig where uid = :'u3'), 'V15 Bjørn ser det samme som før');
select pg_temp.som(:'u4');
select pg_temp.lik((select (count(*), (select count(*) from public.bet_stakes))::text from public.bets),
                   (select (bets, stakes)::text from prove052.synlig where uid = :'u4'), 'V16 Ola (annen klubb) ser det samme (ingenting)');
select pg_temp.som(:'u5');
select pg_temp.lik((select (count(*), (select count(*) from public.bet_stakes))::text from public.bets),
                   (select (bets, stakes)::text from prove052.synlig where uid = :'u5'), 'V17 Dag (venter) ser det samme som før');
select pg_temp.lik((select bets from prove052.synlig where uid = :'u1'), 7::bigint, 'V18 (Thomas så 7: seks nye og ett fra verdenen)');
reset role;

-- --- Q: køen ------------------------------------------------------------------------
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.bet_settle_queue where round_id = :'RF' and done_at is null), 1::bigint,
                   'Q1 den låste runden med åpen hullduell står i køen');
set role service_role;
insert into svar select 'Q2', public.bet_settle_jobs(10);
select pg_temp.lik((select jsonb_array_length(j) from svar where navn = 'Q2'), 1, 'Q2 bet_settle_jobs gir én jobb');
select pg_temp.lik((select (j -> 0 ->> 'round_id') || '|' || jsonb_array_length(j -> 0 -> 'bets') || '|'
                           || jsonb_array_length(j -> 0 -> 'data' -> 'scores') || '|' || jsonb_array_length(j -> 0 -> 'data' -> 'players')
                           || '|' || (j -> 0 -> 'data' -> 'rounds' -> 0 ->> 'status')
                      from svar where navn = 'Q2'),
                   :'RF' || '|1|27|3|locked', 'Q3 jobben: runden, ett åpent vilkår, 27 scorer, 3 spillere, låst');
select pg_temp.lik((select j -> 0 -> 'bets' -> 0 -> 'rules' = (select rules from public.competitions where id = :'S26') from svar where navn = 'Q2'),
                   true, 'Q4 veddemålet har turneringens regelsett med seg');
-- Alle førte 4 på hull 7: delt hull → annullert (Golfgutu: voidTies).
insert into svar select 'Q5', public.settle_round_bets(:'RF',
  jsonb_build_array(jsonb_build_object('bet_id', (select id from prove052.bets where question = 'Thomas slår Bjørn på hull 7'),
                                       'verdict', 'void')));
reset role;
select pg_temp.lik((select j from svar where navn = 'Q5'), '{"settled": 1, "skipped": 0, "open_left": 0}'::jsonb,
                   'Q5 settle_round_bets avgjør hullduellen (annullert)');
select pg_temp.lik((select status from public.bets where question = 'Thomas slår Bjørn på hull 7'), 'void', 'Q6 status void');
select pg_temp.lik((select count(*) from public.bet_settle_queue where round_id = :'RF' and done_at is not null), 1::bigint,
                   'Q7 jobben er ferdig');
select pg_temp.lik((select balance - available from public.bet_points_for(:'S26', null, :'m1', null)), 100::numeric,
                   'Q8 Thomas har bare fri tekst-veddemålet (100) stående etter annulleringen');

-- --- G: gamle bygg etter 052 ----------------------------------------------------------
set role authenticated;
select pg_temp.som(:'u2');
insert into svar select 'G1', public.create_bet(:'G', :'R3', null, 'Bjørn tar par på hull 9',
                                                jsonb_build_object('kind', 'par', 'hole', 8, 'player', :'m3'), :'m3', 'no', 50);
reset role;
select pg_temp.lik((select (b.competition_id, b.season_id, b.round_scope)::text from public.bets b
                     where b.id = (select (j ->> 'bet_id')::uuid from svar where navn = 'G1')),
                   (:'S26', :'SES', null::uuid)::text, 'G1 gamle create_bet: turneringen og sesongen fylles');
set role authenticated;
select pg_temp.som(:'u3');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'G1'), 'yes', 50) is not null, true,
                   'G2 gamle place_bet_stake virker');
select pg_temp.som(:'u1');
select pg_temp.lik(public.mark_bets_closed(array[(select (j ->> 'bet_id')::uuid from svar where navn = 'G1')]), 1,
                   'G3 mark_bets_closed (arrangørens telefon) virker');
select pg_temp.som(:'u2');
select pg_temp.lik((select available from public.bet_points(:'SES', :'m2')), 797::numeric - 50,
                   'G4 gamle bet_points ser det nye veddemålet (50 mindre ledig)');
reset role;

-- Av i turneringen: gamle create_bet stoppes.
select pg_temp.som('');
update public.competitions set bets_enabled = false where id = :'S26';
set role authenticated;
select pg_temp.som(:'u2');
select pg_temp.feil(format('select public.create_bet(%L, null, null, %L, null, null, %L, 10)', :'G', 'Noe nytt', 'yes'), '55000');
reset role;

rollback;
