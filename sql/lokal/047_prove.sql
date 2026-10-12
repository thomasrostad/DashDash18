\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 047_runder_tabellregler.sql. Kjøres på kopien med 001–043, 034, 044, 045 og
-- 047 (to ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- A: standardverdiene: alle runder som fantes, er uendret (teller, normal, ingen tabell,
--    ingen skjulte hull), og en ny runde får det samme.
-- B: hvem setter counts, points_table og hide_last_holes: arrangør og en rolle med rounds
--    kan, et medlem og en rolle med bare tournaments kan ikke; grensene; kind og
--    playoff_holes kan ikke endres med update, og en playoff kan ikke lages med insert.
-- C: create_playoff_round: rettigheter, tieRule, kvelden, hullene (gjentak lov), spillerne
--    (bare fra turneringen), én aktiv playoff per turnering.
-- D: playoffen er ikke en vanlig runde: ikke koblet (sesong, auto_count, set_round_competitions),
--    stopper ikke og stoppes ikke av kveldens runde, teller aldri, ingen veddemål.
-- E: playoff_set_holes.
-- F: turnering uten klubb: løs playoff med profiler, lesing for de som er med i turneringen.
-- G: tavla_data og TV-funksjonene sender de nye feltene, TV-en har ingen bruker-id og ikke
--    scorene på skjulte hull før låsing.
-- H: anon.
-- ===========================================================================

create function pg_temp.feil(p_sql text, p_kode text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'FEIL (gikk gjennom): ' || p_sql;
exception when others then
  if sqlstate = p_kode then return 'ok ' || p_kode || ': ' || left(sqlerrm, 70);
  else return 'FEIL ' || sqlstate || ': ' || sqlerrm || ' <- ' || p_sql; end if;
end $$;
-- Kjører setningen og ruller den tilbake. Svaret er første kolonne, eller «err:SQLSTATE».
create function pg_temp.prov(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin
    execute p_sql into v;
    raise exception using errcode = 'DDT47', message = coalesce(v, 'null');
  exception when sqlstate 'DDT47' then
    return sqlerrm;
  end;
exception when others then
  return 'err:' || sqlstate || ' ' || left(sqlerrm, 60);
end $$;
create function pg_temp.lik(p_verdi anyelement, p_forventet anyelement, p_hva text) returns text language sql as $$
  select case when p_verdi is not distinct from p_forventet then 'ok ' || p_hva
              else 'FEIL ' || p_hva || ': fikk ' || coalesce(p_verdi::text, 'null') || ', forventet ' || coalesce(p_forventet::text, 'null') end
$$;
create function pg_temp.som(p_uid text) returns text language sql as $$
  select 'som ' || coalesce(nullif(set_config('request.jwt.claim.sub', p_uid, false), ''), 'ingen');
$$;
-- Ingen ekte bruker-id i et svar.
create function pg_temp.uten_brukere(p_json jsonb) returns boolean language sql as $$
  select not exists (select 1 from auth.users u where position(u.id::text in p_json::text) > 0);
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u7  '00000000-0000-0000-0000-000000000007'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set m5  '11111111-0000-0000-0000-000000000005'
\set m9  '11111111-0000-0000-0000-000000000009'
\set ola '22222222-0000-0000-0000-000000000004'
-- Sesong 2026 (Golfgutu), kveldene 2 (2026-09-03) og 3 (2026-10-01), kveld 4 uten turnering.
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set SES '5eeeeeee-0000-0000-0000-000000002026'
\set E2  'eeeeeeee-0000-0000-0000-000000000002'
\set E3  'eeeeeeee-0000-0000-0000-000000000003'
\set E4  'eeeeeeee-0000-0000-0000-000000000004'
\set R2  'dddddddd-0000-0000-0000-000000000002'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set R4  'dddddddd-0000-0000-0000-000000000004'
\set TL  'bd7acc4c-f21f-4b49-bc06-d84d915c2579'
\set MC  'c0000000-0000-0000-0000-00000000f001'
-- Nytt for prøven: p7 (bare rounds), p8 (bare tournaments), turnering uten klubb, felles bane.
\set v7  '00000000-0000-0000-0000-000000004707'
\set v8  '00000000-0000-0000-0000-000000004708'
\set p7  '11111111-0000-0000-0000-000000004707'
\set p8  '11111111-0000-0000-0000-000000004708'
\set FK  'c0000000-0000-0000-0000-0000000047f1'
\set FB  'cccccccc-0000-0000-0000-0000000047b1'

begin;

-- --- Verdenen --------------------------------------------------------------------
select pg_temp.som('');
insert into auth.users (id) values (:'v7'), (:'v8');
insert into public.club_members (id, club_id, user_id, display_name, status) values
  (:'p7', :'G', :'v7', 'Rundeleder', 'active'), (:'p8', :'G', :'v8', 'Turneringsleder', 'active');
insert into public.club_roles (id, club_id, name, rights) values
  ('7a000000-0000-0000-0000-000000004701', :'G', 'Rundeleder 47', array['rounds']),
  ('7a000000-0000-0000-0000-000000004702', :'G', 'Turneringsleder 47', array['tournaments']);
insert into public.club_member_roles (club_id, member_id, role_id) values
  (:'G', :'p7', '7a000000-0000-0000-0000-000000004701'),
  (:'G', :'p8', '7a000000-0000-0000-0000-000000004702');
-- Turnering uten klubb (Thomas eier), Anders og Bjørn påmeldt som profiler, Ola også.
insert into public.courses (id, club_id, name) values (:'FB', null, 'Fellesbanen 47');
insert into public.competitions (id, kind, name, club_id, owner_id, status, entry, rules)
values (:'FK', 'fun', 'Vennecup 47', null, :'u1', 'active', 'listed',
        '{"version": 1, "table": {"tieRule": "playoff"}}');
insert into public.competition_participants (competition_id, profile_id) values
  (:'FK', :'u1'), (:'FK', :'u2'), (:'FK', :'u3'), (:'FK', :'u4');
-- Lagre tallene fra før prøven endrer noe.
create temp table for47 as select id, counts, points_table, hide_last_holes, kind, playoff_for, playoff_holes from public.rounds;
grant select on for47 to public;

-- --- A: standardverdiene -------------------------------------------------------------
select pg_temp.lik((select count(*) from for47 where counts and points_table is null and hide_last_holes = 0
                    and kind = 'normal' and playoff_for is null and playoff_holes is null),
                   (select count(*) from for47), 'A1 alle runder som fantes: teller, normal, ingen tabell, ingen skjulte hull');
select pg_temp.lik((select count(*) from for47), 8::bigint, 'A2 åtte runder i verdenen');
select pg_temp.lik((select count(*) from public.competition_rounds), 8::bigint, 'A3 koblingene er som før (8)');
select pg_temp.som(:'u1'); set role authenticated;
with r as (insert into public.rounds (club_id, event_id, round_no) values (:'G', :'E4', 2)
           returning counts, points_table, hide_last_holes, kind, playoff_for, playoff_holes)
select pg_temp.lik((select counts || '|' || coalesce(points_table, '-') || '|' || hide_last_holes || '|' || kind
                           || '|' || coalesce(playoff_for::text, '-') || '|' || coalesce(playoff_holes::text, '-') from r),
                   'true|-|0|normal|-|-', 'A4 ny runde fra arrangøren får standardverdiene');

-- --- B: hvem setter feltene ----------------------------------------------------------
with u as (update public.rounds set counts = false, points_table = 'finale', hide_last_holes = 3
            where id = :'R2' returning counts, points_table, hide_last_holes)
select pg_temp.lik((select counts || '|' || points_table || '|' || hide_last_holes from u), 'false|finale|3',
                   'B1 arrangøren setter teller ikke, poengtabell og skjul tre hull');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
with u as (update public.rounds set counts = true, points_table = null, hide_last_holes = 0
            where id = :'R2' returning id)
select pg_temp.lik((select count(*) from u), 1::bigint, 'B2 en rolle med bare rounds kan endre feltene');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
with u as (update public.rounds set counts = false where id = :'R2' returning id)
select pg_temp.lik((select count(*) from u), 0::bigint, 'B3 en rolle med bare tournaments kan ikke (0 rader)');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
with u as (update public.rounds set counts = false, hide_last_holes = 3 where id = :'R2' returning id)
select pg_temp.lik((select count(*) from u), 0::bigint, 'B4 et medlem kan ikke (0 rader)');
select pg_temp.lik((select counts::text from public.rounds where id = :'R2'), 'true', 'B5 medlemmet ser runden uendret');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$update public.rounds set hide_last_holes = 10 where id = 'dddddddd-0000-0000-0000-000000000002'$$, '23514');
select pg_temp.feil($$update public.rounds set hide_last_holes = -1 where id = 'dddddddd-0000-0000-0000-000000000002'$$, '23514');
select pg_temp.feil($$update public.rounds set points_table = '   ' where id = 'dddddddd-0000-0000-0000-000000000002'$$, '23514');
select pg_temp.feil($$update public.rounds set points_table = repeat('x', 41) where id = 'dddddddd-0000-0000-0000-000000000002'$$, '23514');
select pg_temp.lik(pg_temp.prov($$update public.rounds set points_table = 'Finale (dobbel)' where id = 'dddddddd-0000-0000-0000-000000000002' returning points_table$$),
                   'Finale (dobbel)', 'B6 poengtabellen er fritt navn (som motoren), 1–40 tegn');
select pg_temp.feil($$update public.rounds set kind = 'playoff' where id = 'dddddddd-0000-0000-0000-000000000002'$$, '22023');
select pg_temp.feil($$insert into public.rounds (club_id, event_id, round_no, kind, playoff_for, playoff_holes, counts)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000004', 3,
                              'playoff', 'badcb270-4100-4fc8-ab14-b281af41cbbb', '{0}', false)$$, '42501');
reset role;

-- --- C: create_playoff_round ---------------------------------------------------------
-- Uten tieRule = playoff.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'')',
                           :'S26', :'m1', :'m2'), '55000');
reset role;
select pg_temp.som('');
update public.competitions set rules = jsonb_set(rules, '{table}', '{"tieRule": "playoff"}')
 where id in (:'S26', :'TL', :'MC');
-- Rettigheter.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'')',
                           :'S26', :'m1', :'m2'), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'')',
                           :'S26', :'m1', :'m2'), 'P0002');
reset role;
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.lik(pg_temp.prov(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'') ->> ''status''',
                                       :'S26', :'m1', :'m2')), 'active', 'C1 en rolle med bare rounds kan starte en playoff');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.lik(pg_temp.prov(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'') ->> ''status''',
                                       :'S26', :'m1', :'m2')), 'active', 'C2 en rolle med bare tournaments kan starte en playoff');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
-- Kvelden.
select pg_temp.lik(pg_temp.prov(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'') ->> ''event_id''',
                                       :'S26', :'m1', :'m2')), :'E3', 'C3 uten kveld: den siste kvelden i turneringen');
select pg_temp.lik(pg_temp.prov(format('select (public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'') ->> ''round_no'')',
                                       :'S26', :'m1', :'m2')), '3', 'C4 neste ledige rundenummer på kvelden');
select pg_temp.feil(format('select public.create_playoff_round(%L, %L, array[%L, %L]::uuid[], ''{8,0,8}'')',
                           :'S26', :'E4', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'')',
                           'c0000000-0000-0000-0000-0000000047ff', :'m1', :'m2'), 'P0002');
-- Hullene (runden har 9 hull som den siste runden i turneringen).
select pg_temp.lik(pg_temp.prov(format('select (public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8,0,8}'') ->> ''hole_count'')',
                                       :'S26', :'m1', :'m2')), '9', 'C5 samme antall hull som den siste runden som teller');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{}'')', :'S26', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], null)', :'S26', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{9}'')', :'S26', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{-1}'')', :'S26', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{0,NULL}'')', :'S26', :'m1', :'m2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{0,1,2,3,4,5,6,7,8,0}'')', :'S26', :'m1', :'m2'), '22023');
select pg_temp.lik(pg_temp.prov(format('select (public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{0,1,2,3,4,5,6,7,8}'') ->> ''playoff_holes'')',
                                       :'S26', :'m1', :'m2')), '[0, 1, 2, 3, 4, 5, 6, 7, 8]', 'C6 alle hullene én gang (høyst hole_count)');
-- Spillerne.
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L]::uuid[], ''{8}'')', :'S26', :'m1'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'S26', :'m2', :'u2'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'S26', :'m1', :'m5'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'S26', :'m1', :'ola'), '22023');
select pg_temp.lik(pg_temp.prov(format('select (public.create_playoff_round(%L, null, array[%L, %L, %L]::uuid[], ''{8}'') -> ''players'')::text',
                                       :'S26', :'u1', :'u2', :'m9')),
                   format('["%s", "%s", "%s"]', :'m1', :'m2', :'m9'),
                   'C7 profil-id blir medlemmet, Carl uten innlogging er med (troppen teller)');
-- Liga (entry listed): bare påmeldte eller de som har spilt i en runde som teller.
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'TL', :'m1', :'m9'), '22023');
select pg_temp.lik((select string_agg(rp.member_id::text, ',' order by rp.member_id) from public.round_players rp
                     join public.competition_rounds cr on cr.round_id = rp.round_id where cr.competition_id = :'TL'),
                   null, 'C8 ingen har spilt i Torsdagsligaen (derfor avvist over)');
reset role;

-- Den ekte playoffen for resten av prøven: Thomas og Anders, kveld 2, hull 9, 1, 9.
select pg_temp.som(:'u1'); set role authenticated;
create temp table po as
select (public.create_playoff_round(:'S26', :'E2', array[:'m1', :'m2']::uuid[], '{8,0,8}')) as svar;
reset role;
grant select on po to public;
select pg_temp.lik((select r.kind || '|' || r.status || '|' || r.counts || '|' || r.playoff_for || '|' || r.playoff_holes::text
                           || '|' || r.event_id || '|' || r.ld_enabled || r.kp_enabled || '|' || r.name || '|' || r.hole_count
                     from public.rounds r where r.id = (select (svar ->> 'round_id')::uuid from po)),
                   'playoff|active|false|' || :'S26' || '|{8,0,8}|' || :'E2' || '|falsefalse|Playoff|9',
                   'C9 playoffen: aktiv, teller ikke, turneringen, hullene, kveld 2, uten LD/KP');
select pg_temp.lik((select count(*) from public.round_players rp where rp.round_id = (select (svar ->> 'round_id')::uuid from po)
                    and rp.handicap_index is not null), 2::bigint, 'C10 to spillere med frosset handicap');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'S26', :'m1', :'m3'), '23505');
reset role;

-- --- D: ikke en vanlig runde ---------------------------------------------------------
select pg_temp.lik((select count(*) from public.competition_rounds cr
                     where cr.round_id = (select (svar ->> 'round_id')::uuid from po)), 0::bigint,
                   'D1 playoffen er ikke koblet (sesongkoblingen hoppet over den)');
-- auto_count: Morrocupen teller runder med påmeldte (Anders) av seg selv.
select pg_temp.som('');
update public.competitions set auto_count = true where id = :'MC';
select pg_temp.lik(public.competition_auto_count_round((select (svar ->> 'round_id')::uuid from po)), 0,
                   'D2 auto_count kobler ikke playoffen (Anders er påmeldt i Morrocupen)');
select pg_temp.lik((select count(*) from public.competition_rounds cr
                     where cr.round_id = (select (svar ->> 'round_id')::uuid from po)), 0::bigint, 'D3 fortsatt ingen kobling');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.set_round_competitions(%L, array[%L]::uuid[])',
                           (select svar ->> 'round_id' from po), :'MC'), '22023');
select pg_temp.feil(format('insert into public.competition_rounds (competition_id, round_id) values (%L, %L)',
                           :'MC', (select svar ->> 'round_id' from po)), '22023');
-- Kveld 2 har en låst runde. En ny vanlig runde kan starte ved siden av playoffen.
select pg_temp.lik(pg_temp.prov(format('with r as (insert into public.rounds (club_id, event_id, round_no, status) values (%L, %L, 5, ''active'') returning status) select status from r',
                                       :'G', :'E2')), 'active', 'D4 playoffen stopper ikke en vanlig runde på kvelden');
-- Kveld 3 har en aktiv runde (bølge 1). En playoff der kan likevel starte.
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.lik(pg_temp.prov(format('select public.create_playoff_round(%L, %L, array[%L, %L]::uuid[], ''{8}'') ->> ''status''',
                                       :'MC', :'E3', :'m1', :'m2')), 'err:22023 Kvelden hører ikke til turneringen',
                   'D5 kvelden må høre til turneringen (kveld 3 er sesongens)');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('update public.rounds set counts = true where id = %L', (select svar ->> 'round_id' from po)), '23514');
select pg_temp.feil(format('update public.rounds set kind = ''normal'', playoff_for = null, playoff_holes = null where id = %L',
                           (select svar ->> 'round_id' from po)), '22023');
select pg_temp.feil(format('update public.rounds set playoff_holes = ''{1}'' where id = %L', (select svar ->> 'round_id' from po)), '42501');
select pg_temp.lik(pg_temp.prov(format('update public.rounds set hide_last_holes = 1 where id = %L returning hide_last_holes::text',
                                       (select svar ->> 'round_id' from po))), '1', 'D8 andre oppsettfelt kan endres på en playoff');
reset role;

-- Veddemål på en playoff stoppes av triggeren (også fra create_bet og SQL Editor).
select pg_temp.som('');
select pg_temp.feil(format('insert into public.bets (club_id, season_id, round_id, question) values (%L, %L, %L, ''Vinner Thomas?'')',
                           :'G', :'SES', (select svar ->> 'round_id' from po)), '22023');

-- --- E: playoff_set_holes ------------------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.playoff_set_holes(%L, ''{8,0,8,0}'')', (select svar ->> 'round_id' from po)), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select public.playoff_set_holes((select (svar ->> 'round_id')::uuid from po), '{8,0,8,0}') ->> 'playoff_holes'),
                   '[8, 0, 8, 0]', 'E1 arrangøren legger til et hull');
select public.save_hole((select (svar ->> 'round_id')::uuid from po), 0,
                        jsonb_build_array(jsonb_build_object('member_id', :'m1', 'strokes', 4),
                                          jsonb_build_object('member_id', :'m2', 'strokes', 4)), now()) is not null as lagret \gset
select pg_temp.lik(:'lagret'::boolean, true, 'E2 score på posisjon 1 (hole_index 0) med save_hole');
select pg_temp.feil(format('select public.playoff_set_holes(%L, ''{7,0,8}'')', (select svar ->> 'round_id' from po)), '55000');
select pg_temp.feil(format('select public.playoff_set_holes(%L, ''{}'')', (select svar ->> 'round_id' from po)), '22023');
select pg_temp.lik((select public.playoff_set_holes((select (svar ->> 'round_id')::uuid from po), '{8,1}') ->> 'playoff_holes'),
                   '[8, 1]', 'E3 hull uten score kan byttes');
select pg_temp.feil(format('select public.playoff_set_holes(%L, ''{0}'')', :'R2'), '22023');
reset role;

-- --- F: turnering uten klubb ---------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, %L, array[%L, %L]::uuid[], ''{17}'')', :'FK', :'E2', :'u2', :'u3'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{17}'')', :'FK', :'u2', :'u3'), '22023');
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{17}'', %L)', :'FK', :'u2', :'u7', :'FB'), '22023');
create temp table pl as
select public.create_playoff_round(:'FK', null, array[:'u2', :'m3']::uuid[], '{17,0,17}', :'FB') as svar;
reset role;
grant select on pl to public;
select pg_temp.lik((select (r.club_id is null) || '|' || (r.event_id is null) || '|' || r.kind || '|' || r.status || '|' || r.owner_id
                     || '|' || (select count(*) from public.round_participants pa where pa.round_id = r.id and pa.profile_id in (:'u2', :'u3'))
                     || '|' || (select count(*) from public.round_players rp where rp.round_id = r.id)
                     from public.rounds r where r.id = (select (svar ->> 'round_id')::uuid from pl)),
                   'true|true|playoff|active|' || :'u1' || '|2|2',
                   'F1 løs playoff: eier Thomas, Anders og Bjørn (medlems-id ble profil) som deltakere');
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(public.can_read_round((select (svar ->> 'round_id')::uuid from pl)), true,
                   'F2 Ola (påmeldt, ikke i playoffen) kan lese den');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.lik(public.can_read_round((select (svar ->> 'round_id')::uuid from pl)), false,
                   'F3 Siv (ikke med i turneringen) kan ikke');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{17}'', %L)', :'FK', :'u2', :'u3', :'FB'), '42501');
reset role;

-- --- D (forts.): playoff ved siden av kveldens runde ---------------------------------
-- Sesongens playoff låses. En ny playoff på kveld 3 starter mens runde 3 (bølge 1) går.
select pg_temp.som(:'u1'); set role authenticated;
update public.rounds set status = 'locked' where id = (select (svar ->> 'round_id')::uuid from po);
create temp table pe as
select public.create_playoff_round(:'S26', :'E3', array[:'m1', :'m2']::uuid[], '{8}') as svar;
reset role;
grant select on pe to public;
select pg_temp.lik((select r.status || '|' || r.round_no from public.rounds r where r.id = (select (svar ->> 'round_id')::uuid from pe)),
                   'active|3', 'D9 playoffen på kveld 3 er aktiv (rundenummer 3)');
select pg_temp.lik((select status from public.rounds where id = :'R3'), 'active', 'D10 kveldens runde går fortsatt i bølge 1');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('insert into public.rounds (club_id, event_id, round_no, status) values (%L, %L, 6, ''active'')', :'G', :'E3'), '23505');
reset role;

-- --- G: Tavla og TV ------------------------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
create temp table tv47 as select public.tavla_data(:'SES') as tavla;
reset role;
select pg_temp.lik((select count(*) from jsonb_array_elements(tavla -> 'rounds') r
                     where r ? 'counts' and r ? 'points_table' and r ? 'hide_last_holes' and r ? 'kind'
                       and r ? 'playoff_for' and r ? 'playoff_holes') = jsonb_array_length(tavla -> 'rounds'), true,
                   'G1 tavla_data: alle rundene har de seks nye feltene') from tv47;
select pg_temp.lik((select string_agg(r ->> 'kind' || ':' || coalesce(r ->> 'playoff_holes', '-'), ',' order by r ->> 'playoff_holes')
                      from jsonb_array_elements(tavla -> 'rounds') r where r ->> 'kind' = 'playoff'),
                   'playoff:[8, 1],playoff:[8]', 'G2 tavla_data: begge playoffene på sesongens kvelder, med hullene') from tv47;
-- TV-kode for sesongen og for turneringen uten klubb (som superbruker).
select pg_temp.som('');
insert into public.tv_codes (code, competition_id) values ('TVKXDE4782', :'S26'), ('TVKXDE4783', :'FK');
-- Skjul de seks siste hullene i runde 3 (9 hull, går): TV-en får ikke hull 4–9.
update public.rounds set hide_last_holes = 6 where id = :'R3';
set role anon;
create temp table tvs as select public.tv_board_data('tvkxde4782') as tv, public.tv_board_data(' TVKXDE4783 ') as tvk;
reset role;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'rounds') r
                     where r ? 'counts' and r ? 'points_table' and r ? 'hide_last_holes' and r ? 'kind'
                       and r ? 'playoff_for' and r ? 'playoff_holes') = jsonb_array_length(tv -> 'rounds'), true,
                   'G3 tv_board_data (anon): alle rundene har de nye feltene') from tvs;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'rounds') r where r ->> 'kind' = 'playoff'), 2::bigint,
                   'G4 tv_board_data: playoffene er med') from tvs;
select pg_temp.lik(pg_temp.uten_brukere(tv) and pg_temp.uten_brukere(tvk), true, 'G5 TV-svarene har ingen ekte bruker-id') from tvs;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'scores') s where s ->> 'round_id' = :'R3'),
                   (select count(*) from public.hole_scores where round_id = :'R3' and hole_index < 3),
                   'G6 TV-en får ikke scorene på de skjulte hullene i runden som går') from tvs;
select pg_temp.lik((select count(*) from public.hole_scores where round_id = :'R3' and hole_index >= 3) > 0, true,
                   'G7 (runde 3 har score på skjulte hull)');
select pg_temp.lik((select count(*) from jsonb_array_elements(tavla -> 'scores') s where s ->> 'round_id' = :'R3'),
                   (select count(*) from public.hole_scores where round_id = :'R3'),
                   'G8 tavla_data sender alle scorene (appen skjuler)') from tv47;
select pg_temp.lik((select count(*) from jsonb_array_elements(tv -> 'scores') s where s ->> 'round_id' = :'R2'),
                   (select count(*) from public.hole_scores where round_id = :'R2'),
                   'G9 en låst runde viser alle hull på TV') from tvs;
select pg_temp.lik((select string_agg(r ->> 'kind' || ':' || (r ->> 'playoff_for') || ':' || (r ->> 'playoff_holes'), ',')
                      from jsonb_array_elements(tvk -> 'rounds') r),
                   'playoff:' || :'FK' || ':[17, 0, 17]', 'G10 tv_competition_data: den løse playoffen er med (uten kobling)') from tvs;
select pg_temp.lik((select count(*) from jsonb_array_elements(tvk -> 'round_participants') p
                     where p ->> 'profile_id' in (:'u2', :'u3')), 0::bigint,
                   'G11 tv_competition_data: profil-id-ene er maskert') from tvs;

-- --- H: anon -------------------------------------------------------------------------
set role anon;
select pg_temp.feil(format('select public.create_playoff_round(%L, null, array[%L, %L]::uuid[], ''{8}'')', :'S26', :'m1', :'m2'), '42501');
select pg_temp.feil(format('select public.playoff_set_holes(%L, ''{8}'')', (select svar ->> 'round_id' from po)), '42501');
select pg_temp.feil(format('select public.tavla_data(%L)', :'SES'), '42501');
reset role;

-- Til slutt: kontrollen i 047 holder fortsatt (ingen playoff koblet, reglene på alle rader).
select pg_temp.lik((select count(*) from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
                     where r.kind = 'playoff'), 0::bigint, 'I1 ingen playoff er koblet');
select pg_temp.lik((select count(*) from public.rounds r join for47 f on f.id = r.id
                     where r.id not in (:'R2', :'R3') and (r.counts, r.points_table, r.hide_last_holes, r.kind)
                           is distinct from (f.counts, f.points_table, f.hide_last_holes, f.kind)), 0::bigint,
                   'I2 rundene prøven ikke rørte, er uendret');

rollback;
