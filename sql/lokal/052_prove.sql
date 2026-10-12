\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 052_veddemaal.sql. Kjøres på kopien med hele kjeden til og med 051 + 048, så 052 (to
-- ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
-- Etterfyllingen (veddemål fra før, banker og synlighet før og etter) prøves i lokal/052_etter.sql.
--
-- O: på og av (standard av, hvem som kan slå på, ny sesong arver, av stopper nye veddemål).
-- L: liga i klubben: bank per turnering, bare deltakere, medlem og profil, regelsettet, mot,
--    runden må høre til turneringen, avgjort for hånd av money.
-- P: privat turnering uten klubb: profiler, aktivitet uten klubb, staben avgjør, slettet konto.
-- R: enkeltrunder: bank per runde (løs runde og klubbrunde), på i oppsettet.
-- Q: køen når runden låses, og oppgjøret bare for service_role.
-- G: gamle bygg (create_bet, settle_bet, mark_bets_closed, bet_points) på samme kopi.
-- A: anon.
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
create function pg_temp.bank(p_c uuid, p_r uuid, p_m uuid, p_p uuid) returns text language sql as $$
  select b.balance || '/' || b.available from public.bet_points_for(p_c, p_r, p_m, p_p) b;
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set AN  'aaaaaaaa-0000-0000-0000-000000000002'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set SES '5eeeeeee-0000-0000-0000-000000002026'
\set TL  'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set MS  'cccccccc-0000-0000-0000-000000000001'
-- Nytt for prøven.
\set q1  '00000000-0000-0000-0000-0000000052a1'
\set pq1 '11111111-0000-0000-0000-0000000052a1'
\set x1  '00000000-0000-0000-0000-0000000052b1'
\set y1  '00000000-0000-0000-0000-0000000052c1'
\set y2  '00000000-0000-0000-0000-0000000052c2'
\set y3  '00000000-0000-0000-0000-0000000052c3'
\set y4  '00000000-0000-0000-0000-0000000052c4'
\set y5  '00000000-0000-0000-0000-0000000052c5'
\set z1  '00000000-0000-0000-0000-0000000052d1'
\set z2  '00000000-0000-0000-0000-0000000052d2'
\set PK  'c0000000-0000-0000-0000-0000000052c0'
\set EL  'eeeeeeee-0000-0000-0000-0000000052e1'
\set RL  'dddddddd-0000-0000-0000-0000000052e1'
\set LR  'dddddddd-0000-0000-0000-0000000052d1'
\set LR2 'dddddddd-0000-0000-0000-0000000052d2'
\set NS  '5eeeeeee-0000-0000-0000-000000005201'
\set NA  '5eeeeeee-0000-0000-0000-000000005202'

begin;

-- --- Verdenen --------------------------------------------------------------------
-- q1: vanlig medlem i Golfgutu uten rettigheter. x1: med i ligaen TL som profil, ikke medlem.
-- y1–y5: privat turnering PK uten klubb (eier y1; y2, y3 påmeldt; y4 utenfor; y5 i staben).
-- z1, z2: en løs runde LR (eier z1) med en gjest uten profil. RL: aktiv runde i ligaen TL.
select pg_temp.som('');
insert into auth.users (id) values (:'q1'), (:'x1'), (:'y1'), (:'y2'), (:'y3'), (:'y4'), (:'y5'), (:'z1'), (:'z2');
insert into public.club_members (id, club_id, user_id, display_name, status) values
  (:'pq1', :'G', :'q1', 'Vanlig 52', 'active');
insert into public.competition_participants (competition_id, member_id, profile_id) values
  (:'TL', :'m1', null), (:'TL', :'m3', null), (:'TL', null, :'x1');
insert into public.events (id, club_id, competition_id, event_date) values (:'EL', :'G', :'TL', current_date + 60);
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, format)
values (:'RL', :'G', :'EL', :'MS', 1, 'draft', 9, 'stableford');
insert into public.round_players (round_id, member_id, club_id, handicap_index) values
  (:'RL', :'m1', :'G', 14.2), (:'RL', :'m3', :'G', 20.1);
update public.rounds set status = 'active', started_at = now() where id = :'RL';
insert into public.competitions (id, kind, name, club_id, owner_id, status, entry)
values (:'PK', 'fun', 'Vennecup 52', null, :'y1', 'active', 'listed');
insert into public.competition_participants (competition_id, profile_id) values (:'PK', :'y1'), (:'PK', :'y2'), (:'PK', :'y3');
insert into public.competition_staff (competition_id, profile_id, role) values (:'PK', :'y5', 'organizer');
insert into public.rounds (id, club_id, owner_id, status) values (:'LR', null, :'z1', 'active'), (:'LR2', null, :'z1', 'active');
insert into public.round_participants (round_id, profile_id, display_name) values
  (:'LR', :'z1', 'Zeb'), (:'LR', :'z2', 'Zara'), (:'LR', null, 'Gjest'), (:'LR2', :'z1', 'Zeb');
select id as zp2 from public.round_participants where round_id = :'LR' and profile_id = :'z2' \gset
create temp table svar (navn text primary key, j jsonb);
grant all on svar to public;
create temp table akt as select count(*) as n from public.activity;
grant select on akt to public;

-- --- O: på og av ------------------------------------------------------------------------
select pg_temp.lik((select bets_enabled from public.competitions where id = :'TL'), false, 'O1 ligaen har veddemål av (standard)');
select pg_temp.lik((select bets_enabled from public.competitions where id = :'S26'), true,
                   'O2 Sesong 2026 har veddemål på (hadde veddemål før 052)');
select pg_temp.lik((select count(*) from public.competitions where bets_enabled and club_id is distinct from :'G'), 0::bigint,
                   'O3 ingen turnering i andre klubber eller uten klubb fikk veddemål på');
select pg_temp.lik((select count(*) from public.rounds where bets_enabled), 0::bigint, 'O4 ingen runde har veddemål på');
set role authenticated;
select pg_temp.som(:'u1');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, null, null, %L, 10)', :'TL', 'Thomas vinner ligaen', 'yes'), '55000');
select pg_temp.som(:'q1');
select pg_temp.feil(format('select public.bets_set_enabled(%L, null, true)', :'TL'), '42501');
select pg_temp.som(:'u4');
select pg_temp.feil(format('select public.bets_set_enabled(%L, null, true)', :'TL'), 'P0002');
select pg_temp.som(:'u2');
select pg_temp.lik(public.bets_set_enabled(:'TL', null, true), true, 'O5 kassereren (money) slår på veddemål i ligaen');
select pg_temp.som(:'u1');
select pg_temp.lik(public.bets_set_enabled(:'TL', null, false), false, 'O6 arrangøren (tournaments) slår dem av');
select pg_temp.lik(public.bets_set_enabled(:'TL', null, true), true, 'O7 og på igjen');
select pg_temp.feil(format('select public.bets_set_enabled(%L, %L, true)', :'TL', :'RL'), '22023');
select pg_temp.som(:'q1');
with u as (update public.competitions set bets_enabled = false where id = :'S26' returning 1)
select pg_temp.lik((select count(*) from u), 0::bigint, 'O8 et medlem uten rettighet kan ikke slå av direkte (RLS)');
reset role;
select pg_temp.lik((select bets_enabled from public.competitions where id = :'S26'), true,
                   'O8b (Sesong 2026 har fortsatt veddemål på)');
-- En ny sesong i Golfgutu arver «på»; en ny sesong i Andre klubb (uten veddemål) gjør ikke.
insert into public.seasons (id, club_id, name, status) values (:'NS', :'G', 'Sesong 2027', 'planned'), (:'NA', :'AN', 'Sesong 2027', 'planned');
select pg_temp.lik((select bets_enabled from public.competitions where season_id = :'NS'), true,
                   'O9 ny sesong i Golfgutu arver veddemål på');
select pg_temp.lik((select bets_enabled from public.competitions where season_id = :'NA'), false,
                   'O10 ny sesong i Andre klubb: av');

-- --- L: liga i klubben ------------------------------------------------------------------
set role authenticated;
select pg_temp.som(:'u1');
insert into svar select 'L1', public.create_bet_v2(:'TL', null, 'Thomas vinner ligaen', null, :'m3', null, 'yes', 100);
reset role;
select pg_temp.lik((select (b.club_id, b.competition_id, b.season_id, b.round_scope, b.creator_id, b.against_id)::text
                      from public.bets b where b.id = (select (j ->> 'bet_id')::uuid from svar where navn = 'L1')),
                   (:'G'::uuid, :'TL'::uuid, null::uuid, null::uuid, :'m1'::uuid, :'m3'::uuid)::text,
                   'L1 veddemålet hører til ligaen og klubben, uten sesong, laget av Thomas mot Bjørn');
select pg_temp.lik((select (data ->> 'against') || '|' || competition_id from public.activity
                     where kind = 'bet_challenge' and data ->> 'bet_id' = (select j ->> 'bet_id' from svar where navn = 'L1')),
                   :'m3' || '|' || :'TL', 'L2 aktiviteten bet_challenge har turneringen');
set role authenticated;
select pg_temp.som(:'u2');
select pg_temp.lik((select count(*) from public.bets where competition_id = :'TL'), 1::bigint,
                   'L3 Anders (medlem, ikke i ligaen) ser veddemålet (klubbens)');
select pg_temp.feil(format('select public.place_bet_stake(%L, %L, 50)', (select j ->> 'bet_id' from svar where navn = 'L1'), 'no'), '42501');
select pg_temp.som(:'x1');
select pg_temp.lik((select count(*) from public.bets where competition_id = :'TL'), 1::bigint,
                   'L4 x1 (påmeldt som profil) ser veddemålet');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'L1'), 'no', 60) is not null, true,
                   'L5 x1 satser som profil');
select pg_temp.lik((select count(*) from public.bets where competition_id = :'S26'), 0::bigint,
                   'L6 x1 ser ikke klubbens sesongveddemål');
select pg_temp.feil(format('select public.bet_bank(%L, null)', :'S26'), 'P0002');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'TL', null) b), '1000/940', 'L7 x1 sin bank i ligaen');
select pg_temp.som(:'u1');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'TL', null) b), '1000/900',
                   'L8 Thomas sin bank i ligaen (egen bank per turnering)');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'S26', null) b), '1000/1000',
                   'L9 Thomas sin bank i Sesong 2026 er urørt');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'TL', null, null, :'x1') b), '1000/940',
                   'L10 bet_bank for en profil i ligaen');
reset role;
select pg_temp.lik((select person_key || '|' || (member_id is null) || '|' || club_id from public.bet_stakes
                     where profile_id = :'x1'), :'x1' || '|true|' || :'G', 'L11 innsatsen: profil, person = profilen, klubben står');

-- Regelsettet: tak 50 og startbeholdning 500 i ligaen.
update public.competitions set rules = jsonb_set(rules, '{bets}', '{"startingPoints": 500, "maxStakePerBet": 50}') where id = :'TL';
set role authenticated;
select pg_temp.som(:'u3');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, null, %L, %L, 60)', :'TL', 'x1 slår Bjørn', :'x1', 'no'), '22023');
insert into svar select 'L12', public.create_bet_v2(:'TL', null, 'x1 slår Bjørn', null, null, :'x1', 'no', 50);
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'TL', null) b), '500/450',
                   'L12 tak og startbeholdning fra ligaens regelsett');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, %L, null, %L, 10)', :'TL', 'Anders taper', :'m2', 'no'), '23503');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, %L, null, %L, 10)', :'TL', 'Meg selv', :'m3', 'no'), '22023');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, %L, %L, %L, 10)', :'TL', 'To mot', :'m1', :'x1', 'no'), '22023');
-- Vilkår: runden må høre til turneringen.
insert into svar select 'L13', public.create_bet_v2(:'TL', :'RL', 'Thomas par på hull 4',
  jsonb_build_object('kind', 'par', 'hole', 3, 'player', :'m1'), :'m1', null, 'no', 20);
select pg_temp.lik((select (event_id, round_id)::text from public.bets where id = (select (j ->> 'bet_id')::uuid from svar where navn = 'L13')),
                   (:'EL'::uuid, :'RL'::uuid)::text, 'L13 vilkår i ligarunden: kvelden og runden fylles');
select pg_temp.feil(format('select public.create_bet_v2(%L, %L, %L, %L, null, null, %L, 10)', :'TL', :'R3', 'Feil runde',
                           jsonb_build_object('kind', 'par', 'hole', 3, 'player', :'m1'), 'no'), '22023');
select pg_temp.feil(format('select public.create_bet_v2(%L, %L, %L, %L, null, null, %L, 10)', :'TL', :'RL', 'Ikke med',
                           jsonb_build_object('kind', 'par', 'hole', 3, 'player', :'m2'), 'no'), '23503');
-- For hånd: money uten innsats.
select pg_temp.som(:'u1');
select pg_temp.feil(format('select public.resolve_bet(%L, %L)', (select j ->> 'bet_id' from svar where navn = 'L1'), 'yes'), '55000');
select pg_temp.som(:'u2');
select pg_temp.lik((public.resolve_bet((select (j ->> 'bet_id')::uuid from svar where navn = 'L1'), 'no')).resolved_by, :'m2'::uuid,
                   'L14 kassereren avgjør (NEI), resolved_by = Anders');
select pg_temp.som(:'x1');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'TL', null) b), '600/600',
                   'L15 x1 vant 100 fra Thomas (500 + 100; innsatsen i L12 var Bjørns)');
reset role;
select pg_temp.lik(pg_temp.bank(:'TL', null, :'m1', null) || ' ' || pg_temp.bank(:'TL', null, :'m3', null), '400/400 500/430',
                   'L16 Thomas: 500 − 100; Bjørn: 500, 50 + 20 stående');

-- --- P: privat turnering uten klubb ----------------------------------------------------
set role authenticated;
select pg_temp.som(:'y2');
select pg_temp.feil(format('select public.bets_set_enabled(%L, null, true)', :'PK'), '42501');
select pg_temp.som(:'y1');
select pg_temp.lik(public.bets_set_enabled(:'PK', null, true), true, 'P1 eieren slår på veddemål');
select pg_temp.som(:'y2');
insert into svar select 'P2', public.create_bet_v2(:'PK', null, 'y3 vinner cupen', null, null, :'y3', 'no', 100);
reset role;
select pg_temp.lik((select (b.club_id, b.season_id, b.competition_id, b.creator_id, b.creator_profile_id, b.against_profile_id)::text
                      from public.bets b where b.id = (select (j ->> 'bet_id')::uuid from svar where navn = 'P2')),
                   (null::uuid, null::uuid, :'PK'::uuid, null::uuid, :'y2'::uuid, :'y3'::uuid)::text,
                   'P2 uten klubb og sesong; laget av og mot profiler');
select pg_temp.lik((select (club_id is null) || '|' || competition_id || '|' || (data ->> 'against_profile') from public.activity
                     where data ->> 'bet_id' = (select j ->> 'bet_id' from svar where navn = 'P2')),
                   'true|' || :'PK' || '|' || :'y3', 'P3 aktiviteten ligger i turneringen (uten klubb)');
set role authenticated;
select pg_temp.som(:'y3');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'P2'), 'yes', 100) is not null, true,
                   'P4 y3 satser JA');
select pg_temp.som(:'y1');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'P2'), 'yes', 50) is not null, true,
                   'P5 eieren y1 satser JA');
select pg_temp.som(:'y4');
select pg_temp.lik((select count(*) from public.bets), 0::bigint, 'P6 y4 (utenfor) ser ingen veddemål');
select pg_temp.feil(format('select public.place_bet_stake(%L, %L, 10)', (select j ->> 'bet_id' from svar where navn = 'P2'), 'yes'), 'P0002');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, null, null, %L, 10)', :'PK', 'Jeg vil være med', 'yes'), 'P0002');
select pg_temp.som(:'y5');
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, null, null, %L, 10)', :'PK', 'Staben vedder', 'yes'), '42501');
select pg_temp.som(:'y2');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(:'PK', null) b), '1000/900', 'P7 y2 sin bank i cupen');
select pg_temp.feil(format('select public.resolve_bet(%L, %L)', (select j ->> 'bet_id' from svar where navn = 'P2'), 'yes'), '42501');
select pg_temp.som(:'y1');
select pg_temp.feil(format('select public.resolve_bet(%L, %L)', (select j ->> 'bet_id' from svar where navn = 'P2'), 'yes'), '55000');
select pg_temp.som(:'y5');
select pg_temp.lik((select (r.status, r.resolution, r.resolved_by, r.resolved_by_profile)::text
                      from public.resolve_bet((select (j ->> 'bet_id')::uuid from svar where navn = 'P2'), 'yes') r),
                   ('resolved', 'yes', null::uuid, :'y5'::uuid)::text, 'P8 arrangøren i staben (uten innsats) avgjør JA');
reset role;
select pg_temp.lik(pg_temp.bank(:'PK', null, null, :'y3') || ' ' || pg_temp.bank(:'PK', null, null, :'y1') || ' '
                   || pg_temp.bank(:'PK', null, null, :'y2'),
                   '1067/1067 1033/1033 900/900', 'P9 100 delt 100:50 i hele poeng (67 og 33), y2 taper 100');
-- y3 sletter kontoen: innsatsen står uten profil, de andres bank er uendret.
delete from auth.users where id = :'y3';
select pg_temp.lik((select count(*) from public.bet_stakes where person_key = :'y3' and profile_id is null and member_id is null), 1::bigint,
                   'P10 slettet konto: innsatsen står (uten profil, personen husket)');
select pg_temp.lik(pg_temp.bank(:'PK', null, null, :'y1') || ' ' || pg_temp.bank(:'PK', null, null, :'y2'), '1033/1033 900/900',
                   'P11 de andres bank er uendret');
select pg_temp.feil('insert into public.bet_stakes (bet_id, person_key, side, points) values ('''
                    || (select j ->> 'bet_id' from svar where navn = 'P2') || ''', gen_random_uuid(), ''yes'', 5)', '23514');

-- --- R: enkeltrunder (egen bank per runde) ---------------------------------------------
set role authenticated;
select pg_temp.som(:'z1');
select pg_temp.feil(format('select public.create_bet_v2(null, %L, %L, null, null, null, %L, 10)', :'LR', 'Zara vinner', 'yes'), '55000');
select pg_temp.som(:'z2');
select pg_temp.feil(format('select public.bets_set_enabled(null, %L, true)', :'LR'), '42501');
select pg_temp.som(:'z1');
select pg_temp.lik(public.bets_set_enabled(null, :'LR', true), true, 'R1 eieren slår på veddemål i den løse runden (oppsettet)');
insert into svar select 'R2', public.create_bet_v2(null, :'LR', 'Zara tar birdie på hull 3',
  jsonb_build_object('kind', 'birdie', 'hole', 2, 'player', :'zp2'), null, :'z2', 'no', 100);
reset role;
select pg_temp.lik((select (b.club_id, b.competition_id, b.round_scope, b.round_id, b.creator_profile_id)::text
                      from public.bets b where b.id = (select (j ->> 'bet_id')::uuid from svar where navn = 'R2')),
                   (null::uuid, null::uuid, :'LR'::uuid, :'LR'::uuid, :'z1'::uuid)::text, 'R2 rundens bank (round_scope), uten klubb');
select pg_temp.lik((select count(*) from public.activity) - (select n from akt),
                   (select count(*) from public.activity where kind like 'bet_%' and competition_id in (:'TL', :'PK')),
                   'R3 ingen aktivitet for den løse runden (verken klubb eller turnering)');
set role authenticated;
select pg_temp.som(:'z2');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'R2'), 'yes', 100) is not null, true,
                   'R4 Zara satser JA');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(null, :'LR') b), '1000/900', 'R5 Zaras bank i runden');
select pg_temp.som(:'z1');
select pg_temp.lik((select b.balance || '/' || b.available from public.bet_bank(null, :'LR2') b), '1000/1000',
                   'R6 en annen løs runde har egen bank');
select pg_temp.feil(format('select public.create_bet_v2(null, %L, %L, null, null, null, %L, 10)', :'LR2', 'Av her', 'yes'), '55000');
select pg_temp.som(:'y2');
select pg_temp.lik((select count(*) from public.bets where round_scope = :'LR'), 0::bigint, 'R7 utenforstående ser ikke rundens veddemål');
select pg_temp.feil(format('select public.bet_bank(null, %L)', :'LR'), 'P0002');
-- Klubbrunde med egen bank (R3 i Golfgutu): spillerne som medlemmer.
select pg_temp.som(:'u1');
select pg_temp.lik(public.bets_set_enabled(null, :'R3', true), true, 'R8 arrangøren slår på veddemål i klubbrunden R3');
insert into svar select 'R9', public.create_bet_v2(null, :'R3', 'Carl vinner runden', null, null, null, 'yes', 30);
select pg_temp.lik((select creator_id from public.bets where id = (select (j ->> 'bet_id')::uuid from svar where navn = 'R9')), :'m1'::uuid,
                   'R9 klubbrunde: laget av medlemmet Thomas');
select pg_temp.som(:'q1');
select pg_temp.feil(format('select public.place_bet_stake(%L, %L, 10)', (select j ->> 'bet_id' from svar where navn = 'R9'), 'no'), '42501');
select pg_temp.som(:'u1');
select pg_temp.feil(format('select public.create_bet_v2(null, null, %L, null, null, null, %L, 10)', 'Ingenting', 'yes'), '22023');
reset role;

-- --- Q: køen og oppgjøret på serveren --------------------------------------------------
-- Scorer i ligarunden RL: Thomas 4 på alle (par 4 på hull 4: par → L13 NEI taper).
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select :'RL', m, h, 4 from unnest(array[:'m1', :'m3']::uuid[]) m, generate_series(0, 8) h;
select pg_temp.lik((select count(*) from public.bet_settle_queue), 0::bigint, 'Q1 tom kø før noe låses');
update public.rounds set status = 'locked', locked_at = now() where id = :'RL';
select pg_temp.lik((select count(*) from public.bet_settle_queue where round_id = :'RL' and done_at is null and attempts = 0), 1::bigint,
                   'Q2 låst runde med åpent vilkår legges i køen');
update public.rounds set status = 'locked', locked_at = now() where id = :'LR2';
select pg_temp.lik((select count(*) from public.bet_settle_queue where round_id = :'LR2'), 0::bigint,
                   'Q3 låst runde uten veddemål med vilkår legges ikke i køen');
set role authenticated;
select pg_temp.som(:'u1');
select pg_temp.feil('select public.bet_settle_jobs(10)', '42501');
select pg_temp.feil(format('select public.settle_round_bets(%L, %L)', :'RL', '[]'), '42501');
select pg_temp.feil(format('select public.bet_settle_failed(%L, %L)', :'RL', 'x'), '42501');
select pg_temp.feil('select count(*) from public.bet_settle_queue', '42501');
reset role;
set role service_role;
insert into svar select 'Q4', public.bet_settle_jobs(10);
reset role;
select pg_temp.lik((select (j -> 0 ->> 'round_id') || '|' || (j -> 0 ->> 'attempts') || '|' || jsonb_array_length(j -> 0 -> 'bets')
                           || '|' || (j -> 0 -> 'bets' -> 0 -> 'condition' ->> 'kind') || '|' || jsonb_array_length(j -> 0 -> 'data' -> 'scores')
                           || '|' || jsonb_array_length(j -> 0 -> 'data' -> 'course_holes') || '|' || jsonb_array_length(j -> 0 -> 'data' -> 'events')
                      from svar where navn = 'Q4'),
                   :'RL' || '|1|1|par|18|18|1', 'Q4 service_role henter jobben: runden, forsøk 1, vilkåret, scorer, banen, kvelden');
select pg_temp.lik((select (j -> 0 -> 'bets' -> 0 -> 'rules' -> 'bets' ->> 'startingPoints') from svar where navn = 'Q4'), '500',
                   'Q5 veddemålet har ligaens regelsett med seg');
set role service_role;
select pg_temp.lik(jsonb_array_length(public.bet_settle_jobs(10)), 0, 'Q6 en hentet jobb hentes ikke igjen med en gang');
select pg_temp.feil(format('select public.settle_round_bets(%L, %L)', :'LR', '[]'), '55000');
select pg_temp.feil(format('select public.settle_round_bets(%L, %L)', :'RL', '[{"bet_id": "x"}]'), '22023');
select pg_temp.feil(format('select public.settle_round_bets(%L, %L)', :'RL', '{}'), '22023');
insert into svar select 'Q7', public.settle_round_bets(:'RL', jsonb_build_array(
  jsonb_build_object('bet_id', (select j ->> 'bet_id' from svar where navn = 'L13'), 'verdict', 'void'),
  jsonb_build_object('bet_id', (select j ->> 'bet_id' from svar where navn = 'P2'), 'verdict', 'no')));
reset role;
select pg_temp.lik((select j from svar where navn = 'Q7'), '{"settled": 0, "skipped": 2, "open_left": 1}'::jsonb,
                   'Q7 void på par og et veddemål fra en annen runde hoppes over');
select pg_temp.lik((select done_at is not null and claimed_at is null from public.bet_settle_queue where round_id = :'RL'), true,
                   'Q8 jobben er ferdig også når noe står åpent (arrangøren tar resten)');
-- Låses opp og låses igjen: i køen på nytt; så avgjøres vilkåret.
update public.rounds set status = 'active', locked_at = null where id = :'RL';
update public.rounds set status = 'locked', locked_at = now() where id = :'RL';
select pg_temp.lik((select done_at is null and attempts = 0 from public.bet_settle_queue where round_id = :'RL'), true,
                   'Q9 låst på nytt: i køen igjen');
set role service_role;
select pg_temp.lik(jsonb_array_length(public.bet_settle_jobs(10)), 1, 'Q10 jobben hentes');
select public.bet_settle_failed(:'RL', 'motoren feilet');
insert into svar select 'Q11', public.settle_round_bets(:'RL', jsonb_build_array(
  jsonb_build_object('bet_id', (select j ->> 'bet_id' from svar where navn = 'L13'), 'verdict', 'yes')));
reset role;
select pg_temp.lik((select j from svar where navn = 'Q11'), '{"settled": 1, "skipped": 0, "open_left": 0}'::jsonb,
                   'Q11 settle_round_bets avgjør vilkåret (JA)');
select pg_temp.lik((select (status, resolution, resolved_by, resolved_by_profile)::text from public.bets
                     where id = (select (j ->> 'bet_id')::uuid from svar where navn = 'L13')),
                   ('resolved', 'yes', null::uuid, null::uuid)::text, 'Q12 avgjort av scorene (ingen person)');
select pg_temp.lik((select (data ->> 'auto') || (data ->> 'server') || competition_id from public.activity
                     where kind = 'bet_resolved' and data ->> 'bet_id' = (select j ->> 'bet_id' from svar where navn = 'L13')),
                   'truetrue' || :'TL', 'Q13 aktiviteten bet_resolved (auto, server) i ligaen');
select pg_temp.lik(pg_temp.bank(:'TL', null, :'m3', null), '500/450', 'Q14 Bjørn: L13 avgjort uten motpart (ingen flytting), 50 stående');
-- Den løse runden låses: i køen, uten regelsett (Golfgutu).
update public.rounds set status = 'locked', locked_at = now() where id = :'LR';
set role service_role;
insert into svar select 'Q15', public.bet_settle_jobs(10);
reset role;
select pg_temp.lik((select (j -> 0 ->> 'round_id') || '|' || coalesce(j -> 0 -> 'bets' -> 0 ->> 'rules', 'null') || '|'
                           || jsonb_array_length(j -> 0 -> 'data' -> 'events') || '|' || jsonb_array_length(j -> 0 -> 'data' -> 'players')
                      from svar where navn = 'Q15'),
                   :'LR' || '|null|0|3', 'Q15 løs runde: jobben uten regelsett og kveld, tre spillere');
set role anon;
select pg_temp.feil('select public.bet_settle_jobs(10)', '42501');
select pg_temp.feil(format('select public.settle_round_bets(%L, %L)', :'LR', '[]'), '42501');
reset role;

-- --- G: gamle bygg ----------------------------------------------------------------------
set role authenticated;
select pg_temp.som(:'u2');
insert into svar select 'G1', public.create_bet(:'G', :'R3', null, 'Bjørn par på hull 9',
                                                jsonb_build_object('kind', 'par', 'hole', 8, 'player', :'m3'), :'m3', 'no', 40);
select pg_temp.lik((select (competition_id, season_id)::text from public.bets where id = (select (j ->> 'bet_id')::uuid from svar where navn = 'G1')),
                   (:'S26'::uuid, :'SES'::uuid)::text, 'G1 gamle create_bet: Sesong 2026 og sesongen fylles');
select pg_temp.feil(format('select public.create_bet(%L, %L, null, %L, null, null, %L, 10)', :'G', :'RL', 'Liga fra gamle bygg', 'yes'), '55000');
select pg_temp.som(:'u3');
select pg_temp.lik(public.place_bet_stake((select (j ->> 'bet_id')::uuid from svar where navn = 'G1'), 'yes', 40) is not null, true,
                   'G2 gamle place_bet_stake');
reset role;
insert into public.hole_scores (round_id, member_id, hole_index, strokes) values (:'R3', :'m3', 8, 4)
on conflict (round_id, member_id, hole_index) do update set strokes = 4;
set role authenticated;
select pg_temp.som(:'u1');
select pg_temp.lik((public.settle_bet((select (j ->> 'bet_id')::uuid from svar where navn = 'G1'), 'yes')).status, 'resolved',
                   'G3 gamle settle_bet (arrangørens telefon) virker');
select pg_temp.lik(public.mark_bets_closed(array[(select (j ->> 'bet_id')::uuid from svar where navn = 'R9')]), 1,
                   'G4 gamle mark_bets_closed');
select pg_temp.som(:'u2');
select pg_temp.lik((select balance || '/' || available from public.bet_points(:'SES', :'m2')), '960/960',
                   'G5 gamle bet_points: Anders tapte 40');
select pg_temp.lik((select balance || '/' || available from public.bet_bank(:'S26', null)), '960/960', 'G6 bet_bank sier det samme');
select pg_temp.som(:'y2');
select pg_temp.feil(format('select public.settle_bet(%L, %L)', (select j ->> 'bet_id' from svar where navn = 'P2'), 'yes'), 'P0002');
reset role;

-- --- A: anon ----------------------------------------------------------------------------
set role anon;
select pg_temp.feil(format('select public.create_bet_v2(%L, null, %L, null, null, null, %L, 10)', :'TL', 'Anon', 'yes'), '42501');
select pg_temp.feil(format('select public.bet_bank(%L, null)', :'TL'), '42501');
select pg_temp.feil(format('select public.bets_set_enabled(%L, null, true)', :'TL'), '42501');
select pg_temp.feil('select count(*) from public.bets', '42501');
reset role;

-- Til slutt: invariantene.
select pg_temp.lik((select count(*) from public.bets where num_nonnulls(competition_id, round_scope) <> 1), 0::bigint,
                   'Z1 hvert veddemål har nøyaktig én bank');
select pg_temp.lik((select count(*) from public.bet_stakes where num_nonnulls(member_id, profile_id) > 1), 0::bigint,
                   'Z2 ingen innsats har både medlem og profil');
select pg_temp.lik((select count(*) from public.bets b join public.competitions c on c.id = b.competition_id
                     where c.club_id is distinct from b.club_id), 0::bigint, 'Z3 veddemålets klubb er turneringens');

rollback;
