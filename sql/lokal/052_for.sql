\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Verdenen FØR 052 for etterfyllingsprøven (lokal/052_etter.sql). Kjøres på en egen kopi med
-- hele kjeden til og med 051 + 048, FØR 052. Lagres (commit), så 052 kan kjøres etterpå.
--
-- Gamle bygg lager veddemål i Sesong 2026 med de gamle RPC-ene (create_bet, place_bet_stake,
-- resolve_bet, settle_bet): fri tekst åpent, avgjort, annullert, et vilkår avgjort av arrangørens
-- telefon og et vilkår som står åpent i en runde som så låses. Banken (bet_points_for) og hva hver
-- innlogging ser, lagres i skjemaet prove052, så 052_etter.sql kan sammenligne etter 052.
-- ===========================================================================

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
\set m9  '11111111-0000-0000-0000-000000000009'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set SES '5eeeeeee-0000-0000-0000-000000002026'
\set MS  'cccccccc-0000-0000-0000-000000000001'
\set EF  'eeeeeeee-0000-0000-0000-0000000052f1'
\set RF  'dddddddd-0000-0000-0000-0000000052f1'

begin;

-- --- Verdenen: en kveld i Sesong 2026 med en runde (9 hull) for Thomas, Anders og Bjørn ------
select pg_temp.som('');
insert into public.events (id, club_id, competition_id, event_date) values (:'EF', :'G', :'S26', '2026-08-20');
insert into public.rounds (id, club_id, event_id, course_id, round_no, status, hole_count, format)
values (:'RF', :'G', :'EF', :'MS', 1, 'draft', 9, 'stableford');
insert into public.round_players (round_id, member_id, club_id, handicap_index) values
  (:'RF', :'m1', :'G', 14.2), (:'RF', :'m2', :'G', 9.8), (:'RF', :'m3', :'G', 20.1);
update public.rounds set status = 'active', started_at = now() where id = :'RF';

-- --- Veddemålene, som gamle bygg -------------------------------------------------------
set role authenticated;
select pg_temp.som(:'u1');
select (public.create_bet(:'G', null, null, 'Thomas vinner sesongen', null, null, 'yes', 100)) ->> 'bet_id' as f1 \gset
select pg_temp.som(:'u2');
select public.place_bet_stake(:'f1', 'no', 150);
select pg_temp.som(:'u3');
select public.place_bet_stake(:'f1', 'no', 50);

select pg_temp.som(:'u2');
select (public.create_bet(:'G', null, null, 'Anders slår Bjørn i sesongen', null, :'m3', 'yes', 100)) ->> 'bet_id' as f2 \gset
select pg_temp.som(:'u3');
select public.place_bet_stake(:'f2', 'no', 60);
select pg_temp.som(:'u1');
select (public.resolve_bet(:'f2', 'no')).status;

select pg_temp.som(:'u3');
select (public.create_bet(:'G', null, null, 'Noen tar birdie i sesongen', null, null, 'yes', 70)) ->> 'bet_id' as f3 \gset
select pg_temp.som(:'u2');
select public.place_bet_stake(:'f3', 'no', 33);
select pg_temp.som(:'u1');
select (public.resolve_bet(:'f3', 'yes')).status;

select pg_temp.som(:'u2');
select (public.create_bet(:'G', null, null, 'Det regner på torsdag', null, null, 'yes', 40)) ->> 'bet_id' as f4 \gset
select pg_temp.som(:'u3');
select public.place_bet_stake(:'f4', 'no', 40);
select pg_temp.som(:'u1');
select (public.resolve_bet(:'f4', 'void')).status;

-- Vilkår i runden: par på hull 5 for Anders (avgjøres av arrangørens telefon) og en hullduell
-- på hull 7 mellom Thomas og Bjørn (står åpen når runden låses).
select pg_temp.som(:'u1');
select (public.create_bet(:'G', :'RF', null, 'Anders holder par på hull 5',
        jsonb_build_object('kind', 'par', 'hole', 4, 'player', :'m2'), :'m2', 'no', 80)) ->> 'bet_id' as c1 \gset
select pg_temp.som(:'u2');
select public.place_bet_stake(:'c1', 'yes', 80);
select pg_temp.som(:'u3');
select (public.create_bet(:'G', :'RF', null, 'Thomas slår Bjørn på hull 7',
        jsonb_build_object('kind', 'hole', 'hole', 6, 'a', :'m1', 'b', :'m3'), :'m1', 'no', 40)) ->> 'bet_id' as c2 \gset
select pg_temp.som(:'u1');
select public.place_bet_stake(:'c2', 'yes', 40);
reset role;

-- Scorene (som markøren fører dem), så arrangørens telefon avgjør c1.
select pg_temp.som('');
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select :'RF', m, h, 4 from unnest(array[:'m1', :'m2', :'m3']::uuid[]) m, generate_series(0, 8) h;

set role authenticated;
select pg_temp.som(:'u1');
select (public.settle_bet(:'c1', 'yes')).status;
reset role;

-- Runden låses med c2 åpen (052 skal legge den i køen).
select pg_temp.som('');
update public.rounds set status = 'locked', locked_at = now() where id = :'RF';

-- --- Det 052 skal holde uendret ----------------------------------------------------------
create schema if not exists prove052;
drop table if exists prove052.banker, prove052.synlig, prove052.bets, prove052.stakes;
create table prove052.banker as
select m.id as member_id, b.net, b.at_stake, b.balance, b.available
  from public.club_members m, public.bet_points_for(:'SES', m.id) b
 where m.club_id = :'G';
create table prove052.bets as
select id, club_id, season_id, event_id, round_id, creator_id, against_id, question, condition, status,
       resolution, closed_at, resolved_by, resolved_at, created_at
  from public.bets;
create table prove052.stakes as select * from public.bet_stakes;
create table prove052.synlig (uid uuid, bets bigint, stakes bigint);
grant all on schema prove052 to public;
grant all on all tables in schema prove052 to public;

set role authenticated;
select pg_temp.som(:'u1');
insert into prove052.synlig select :'u1', (select count(*) from public.bets), (select count(*) from public.bet_stakes);
select pg_temp.som(:'u2');
insert into prove052.synlig select :'u2', (select count(*) from public.bets), (select count(*) from public.bet_stakes);
select pg_temp.som(:'u3');
insert into prove052.synlig select :'u3', (select count(*) from public.bets), (select count(*) from public.bet_stakes);
select pg_temp.som(:'u4');
insert into prove052.synlig select :'u4', (select count(*) from public.bets), (select count(*) from public.bet_stakes);
select pg_temp.som(:'u5');
insert into prove052.synlig select :'u5', (select count(*) from public.bets), (select count(*) from public.bet_stakes);
reset role;
select pg_temp.som('');

select 'før 052: ' || (select count(*) from public.bets) || ' veddemål, ' || (select count(*) from public.bet_stakes)
       || ' innsatser, banker ' || (select string_agg(member_id || '=' || balance || '/' || available, ' ' order by member_id) from prove052.banker);

commit;
