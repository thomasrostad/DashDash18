\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 031_turnering_kjerne_trinn1.sql. Rekkefølge i en tom, lokal
-- Postgres: lokal/stub.sql, lokal/stub_storage.sql, 001–030 (som i
-- sql/README.md), lokal/031_for.sql, 031 (to ganger), så denne fila.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Del A: dagens app merker ingenting (samme bilde og samme Tavla per
--        innlogging som før 031, og de gamle reglene gir fortsatt 23505).
-- Del B: det nye virker (spilledag ↔ sesong, aktivitet, stab, venteliste,
--        startliste, sjekkene på turneringen, app_config).
-- Del C: trinn 4 i det små: uten den gamle indeksen gir den nye «én aktiv
--        runde per spilledag og pulje» (rulles tilbake).
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

\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set anders  '11111111-0000-0000-0000-000000000002'
\set s2026   '5eeeeeee-0000-0000-0000-000000002026'
\set morro   'c0000000-0000-0000-0000-00000000f001'
\set kveld3  'eeeeeeee-0000-0000-0000-000000000003'
\set kveld4  'eeeeeeee-0000-0000-0000-000000000004'
\set kveld9  'eeeeeeee-0000-0000-0000-000000000009'
\set r2      'dddddddd-0000-0000-0000-000000000002'
\set r3      'dddddddd-0000-0000-0000-000000000003'
\set r4      'dddddddd-0000-0000-0000-000000000004'
\set r5      'dddddddd-0000-0000-0000-000000000005'

select pg_temp.som('');
select c.id as j2026 from public.competitions c where c.season_id = :'s2026' \gset

-- === A. Dagens app merker ingenting ===========================================
create table lokal31.etter_bilde (uid uuid primary key, bilde jsonb, tavla jsonb);
grant insert on lokal31.etter_bilde to authenticated;
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal31.etter_bilde values (:'u1', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal31.etter_bilde values (:'u2', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal31.etter_bilde values (:'u3', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal31.etter_bilde values (:'u4', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal31.etter_bilde values (:'u5', lokal31.bilde(), lokal31.tavla()); reset role;
select pg_temp.som('');

select pg_temp.lik(a.bilde = f.bilde, true, 'A1 samme bilde før og etter 031 for ' || f.uid
                   || ' (rader, kolonner appen henter, updated_at på kveldene, kan lese/styre/føre)')
from lokal31.for_bilde f join lokal31.etter_bilde a using (uid) order by f.uid;
select pg_temp.lik(a.tavla = f.tavla, true, 'A2 samme Tavla (runder, scorer, spillere, matcher, sidepremier) for ' || f.uid)
from lokal31.for_bilde f join lokal31.etter_bilde a using (uid) order by f.uid;
select pg_temp.lik((select count(*)::int from lokal31.etter_bilde where tavla <> '{}'), 4,
                   'A3 fire av fem innlogginger ser minst én sesong (Dag venter)');

-- Dagens app legger en kveld i sesongen (season_id) og lager en runde, som før.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.events (id, club_id, season_id, event_date)
values ('eeeeeeee-0000-0000-0000-000000000005', :'klubb', :'s2026', '2026-10-22');
insert into public.rounds (id, club_id, event_id, round_no)
values ('dddddddd-0000-0000-0000-000000000006', :'klubb', 'eeeeeeee-0000-0000-0000-000000000005', 1);
reset role; select pg_temp.som('');
select pg_temp.lik((select competition_id from public.events where id = 'eeeeeeee-0000-0000-0000-000000000005'),
                   :'j2026'::uuid, 'A4 ny kveld i sesongen (dagens app) havner i sesongens turnering');
select pg_temp.lik((select count(*)::int from public.competition_rounds
                     where round_id = 'dddddddd-0000-0000-0000-000000000006' and competition_id = :'j2026' and source = 'season'),
                   1, 'A5 runden i den nye kvelden teller i jakkeracet, som før');

-- De gamle reglene står.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-000000000006'$$, '23505');
select pg_temp.feil($$insert into public.seasons (club_id, name, status) values ('aaaaaaaa-0000-0000-0000-000000000001', 'To aktive', 'active')$$, '23505');
select pg_temp.feil($$insert into public.events (club_id, event_date) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-01')$$, '23505');
reset role; select pg_temp.som('');
select pg_temp.lik((select indexdef like '%(club_id) WHERE (status = ''active''::text)%'
                      from pg_indexes where indexname = 'rounds_one_active_per_club'), true,
                   'A6 rounds_one_active_per_club er uendret');

-- === B. Det nye ===============================================================
-- B1. Spilledag ↔ sesong begge veier. Ny app legger kveld 4 (uten sesong) i
-- jakkeracet med competition_id: season_id følger, og runde 5 kobles.
select pg_temp.lik((select competition_id from public.events where id = :'kveld4'), null::uuid,
                   'B1 kveld uten sesong har ingen turnering');
select pg_temp.som(:'u1'); set role authenticated;
update public.events set competition_id = :'j2026' where id = :'kveld4';
reset role; select pg_temp.som('');
select pg_temp.lik((select season_id from public.events where id = :'kveld4'), :'s2026'::uuid,
                   'B2 competition_id = jakkeracet gir season_id = sesongen (dagens Tavla ser kvelden)');
select pg_temp.lik((select count(*)::int from public.competition_rounds where round_id = :'r5' and competition_id = :'j2026'),
                   1, 'B3 runden i kvelden følger med inn i jakkeracet');
select pg_temp.som(:'u1'); set role authenticated;
update public.events set competition_id = null where id = :'kveld4';
reset role; select pg_temp.som('');
select pg_temp.lik((select season_id from public.events where id = :'kveld4'), null::uuid,
                   'B4 tatt ut av turneringen: ut av sesongen');
select pg_temp.lik((select count(*)::int from public.competition_rounds where round_id = :'r5' and source = 'season'),
                   0, 'B5 og runden er ikke lenger koblet');
-- Spilledag i morroturneringen (ikke en sesong).
select pg_temp.som(:'u1'); set role authenticated;
update public.events set competition_id = :'morro' where id = :'kveld4';
reset role; select pg_temp.som('');
select pg_temp.lik((select season_id is null and competition_id = :'morro' from public.events where id = :'kveld4'),
                   true, 'B6 spilledag i morroturneringen: ingen sesong');
-- Sesongen vinner når dagens app flytter kvelden med season_id.
select pg_temp.som(:'u1'); set role authenticated;
update public.events set season_id = :'s2026' where id = :'kveld4';
reset role; select pg_temp.som('');
select pg_temp.lik((select competition_id from public.events where id = :'kveld4'), :'j2026'::uuid,
                   'B7 season_id satt av dagens app: turneringen følger sesongen');
-- En annen klubbs arrangør kan ikke legge sin kveld i klubbens turnering.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil($$update public.events set competition_id = 'c0000000-0000-0000-0000-00000000f001'
                      where id = 'eeeeeeee-0000-0000-0000-000000000009'$$, '23503');
reset role; select pg_temp.som('');
-- Én spilledag per dato per turnering (her stopper den gamle regelen først;
-- den nye prøves i del C).

-- B8. Aktivitet får turneringen.
select pg_temp.lik((select count(*)::int from public.activity
                     where kind = 'table_changed' and competition_id::text = data ->> 'competition'),
                   2, 'B8 plassbytte før 031 er koblet til riktig turnering (jakkeracet og morrocupen)');
select pg_temp.lik((select competition_id from public.activity where kind = 'round_started'), :'j2026'::uuid,
                   'B9 «ny runde» før 031 er koblet via kvelden');
select pg_temp.lik((select competition_id from public.activity where kind = 'signup'), :'j2026'::uuid,
                   'B10 påmelding før 031 er koblet via kvelden');
select pg_temp.som(:'u2'); set role authenticated;
insert into public.activity (club_id, kind, category, round_id, data)
values (:'klubb', 'big_score', 'score', :'r3', '{"member": "x", "hole_index": 1}');
reset role; select pg_temp.som('');
select pg_temp.lik((select competition_id from public.activity where kind = 'big_score'), :'j2026'::uuid,
                   'B11 ny hendelse fra dagens app får turneringen av triggeren');
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil($$insert into public.activity (club_id, kind, category, competition_id)
                      values ('aaaaaaaa-0000-0000-0000-000000000002', 'x', 'club', 'c0000000-0000-0000-0000-00000000f001')$$, '23503');
reset role; select pg_temp.som('');

-- B12. Stab: klubbens arrangør legger til, andre kan ikke, rettighetene er ikke koblet på ennå.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.competition_staff (competition_id, profile_id) values (:'morro', :'u2');
reset role; select pg_temp.som('');
select pg_temp.lik((select added_by from public.competition_staff where competition_id = :'morro' and profile_id = :'u2'),
                   :'u1'::uuid, 'B12 stab: added_by settes av serveren');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil($$insert into public.competition_staff (competition_id, profile_id)
                      values ('c0000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000000003')$$, '42501');
select pg_temp.lik(public.is_competition_staff(:'morro'), true, 'B13 is_competition_staff ser Anders');
select pg_temp.lik(public.is_competition_admin(:'morro'), false,
                   'B14 men staben har ingen nye rettigheter i 031 (is_competition_admin uendret)');
select pg_temp.lik(public.is_round_organizer(:'r2'), false, 'B15 og styrer ingen runder');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.competition_staff), 0, 'B16 fremmed klubb ser ikke staben');
select pg_temp.feil($$insert into public.competition_staff (competition_id, profile_id)
                      values ('c0000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000000004')$$, '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$insert into public.competition_staff (competition_id, profile_id)
                      values ('c0000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000000004')$$, '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
delete from public.competition_staff where competition_id = :'morro' and profile_id = :'u2';
reset role; select pg_temp.som('');
select pg_temp.lik((select count(*)::int from public.competition_staff), 0, 'B17 du kan gå ut av staben selv');

-- B18. Venteliste: bare lesing (egen rad og arrangøren), ingen skriving fra appen.
insert into public.competition_waitlist (competition_id, profile_id) values (:'morro', :'u3');
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.competition_waitlist), 1, 'B18 du ser din egen plass på ventelista');
select pg_temp.feil($$insert into public.competition_waitlist (competition_id, profile_id)
                      values ('c0000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-000000000003')$$, '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.competition_waitlist), 0, 'B19 andre ser ikke ventelista');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.competition_waitlist), 1, 'B20 arrangøren ser hele lista');
reset role; select pg_temp.som('');

-- B21. Startliste: arrangøren skriver, spillerne leser, fremmede ser ingenting.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.round_start_groups (round_id, group_no, starts_at, start_hole, resource_label)
values (:'r3', 1, '18:00', 1, 'Bås 1'), (:'r3', 2, '18:10', 10, 'Bås 2');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.round_start_groups where round_id = :'r3'), 2, 'B21 spilleren ser startlista');
select pg_temp.feil($$insert into public.round_start_groups (round_id, group_no)
                      values ('dddddddd-0000-0000-0000-000000000003', 3)$$, '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.round_start_groups), 0, 'B22 fremmed klubb ser ikke startlista');
reset role; select pg_temp.som('');
select pg_temp.feil($$insert into public.round_start_groups (round_id, group_no) values ('dddddddd-0000-0000-0000-000000000003', 100)$$, '23514');

-- B23. Turneringens nye felt: standard er som før, og sjekkene holder.
select pg_temp.lik((select bool_and(signup_audience = 'members' and not listed and max_entrants is null
                                    and not waitlist_enabled and venue is null) from public.competitions),
                   true, 'B23 alle turneringer har standardverdiene (som før)');
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set max_entrants = 24, waitlist_enabled = true, signup_audience = 'anyone',
       listed = true, venue = 'simulator', signup_opens_at = now(), signup_closes_at = now() + interval '7 days'
 where id = :'morro';
select pg_temp.feil($$update public.competitions set signup_audience = 'anyone'
                      where season_id = '5eeeeeee-0000-0000-0000-000000002026'$$, '23514');
select pg_temp.feil($$update public.competitions set waitlist_enabled = true, max_entrants = null
                      where id = 'c0000000-0000-0000-0000-00000000f001'$$, '23514');
select pg_temp.feil($$update public.competitions set signup_closes_at = signup_opens_at - interval '1 day'
                      where id = 'c0000000-0000-0000-0000-00000000f001'$$, '23514');
reset role; select pg_temp.som('');
select pg_temp.lik((select max_entrants from public.competitions where id = :'morro'), 24,
                   'B24 arrangøren kan sette tak, venteliste og åpen påmelding');
select pg_temp.feil($$insert into public.competitions (kind, name, status, entry, listed)
                      values ('fun', 'Uten klubb', 'active', 'listed', true)$$, '23514');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil($$update public.clubs set kind = 'stadion' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, '23514');
update public.clubs set kind = 'simulator_center' where id = :'klubb';
reset role; select pg_temp.som('');
select pg_temp.lik((select kind from public.clubs where id = :'klubb'), 'simulator_center', 'B25 klubben kan være et simulatorsenter');

-- B26. app_config: innloggede leser, anon får ingenting, appen skriver ikke.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select (value ->> 'build')::int from public.app_config where key = 'min_ios_build'), 0,
                   'B26 innloggede leser min_ios_build');
select pg_temp.feil($$update public.app_config set value = '{"build": 999}' where key = 'min_ios_build'$$, '42501');
reset role;
set role anon;
select pg_temp.feil($$select * from public.app_config$$, '42501');
reset role; select pg_temp.som('');

-- === C. Trinn 4 i det små (rulles tilbake) ======================================
-- Uten rounds_one_active_per_club: to runder kan gå i klubben samtidig, men
-- bare én per spilledag og pulje.
begin;
drop index public.rounds_one_active_per_club;
drop index public.seasons_one_active_per_club;
alter table public.events drop constraint events_one_per_date;
select pg_temp.lik((select count(*)::int from public.rounds where club_id = :'klubb' and status = 'active'), 1,
                   'C1 utgangspunkt: én runde går i klubben (r3, kveld 3)');
update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-000000000006';
select pg_temp.lik((select count(*)::int from public.rounds where club_id = :'klubb' and status = 'active'), 2,
                   'C2 to runder går i klubben samtidig (to spilledager)');
select pg_temp.feil($$update public.rounds set status = 'active' where id = 'dddddddd-0000-0000-0000-000000000004'$$, '23505');
update public.rounds set wave_no = 2 where id = :'r4';
update public.rounds set status = 'active' where id = :'r4';
select pg_temp.lik((select count(*)::int from public.rounds where event_id = :'kveld3' and status = 'active'), 2,
                   'C3 to puljer på samme spilledag kan gå samtidig');
-- En ny aktiv sesong stopper fortsatt, nå på hovedturneringen: speilingen fra
-- 017 gjør hver sesong til hovedturnering. Trinn 3 må endre det (se dokumentet).
select pg_temp.feil($$insert into public.seasons (club_id, name, status)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', 'Tirsdagsserien', 'active')$$, '23505');
insert into public.competitions (id, kind, name, club_id, status, entry)
values ('c0000000-0000-0000-0000-00000000f002', 'league', 'Tirsdagsserien', :'klubb', 'active', 'listed');
select pg_temp.lik((select count(*)::int from public.competitions where club_id = :'klubb' and status = 'active'
                      and kind in ('season', 'league')), 2, 'C4 to aktive serier i klubben (jakkeracet og en liga)');
select pg_temp.feil($$insert into public.events (club_id, competition_id, event_date)
                      values ('aaaaaaaa-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-00000000f002', '2026-10-29'),
                             ('aaaaaaaa-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-00000000f002', '2026-10-29')$$, '23505');
insert into public.events (club_id, competition_id, event_date)
values (:'klubb', 'c0000000-0000-0000-0000-00000000f002', '2026-10-01');
select pg_temp.lik((select count(*)::int from public.events where club_id = :'klubb' and event_date = '2026-10-01'), 2,
                   'C5 to turneringer kan ha spilledag samme dato');
rollback;

-- === Kontrollblokken fra 031 ====================================================
with f as (
  select p.proname,
         has_function_privilege('anon', p.oid, 'execute') as anon_kan,
         has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
         p.proconfig
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('guard_competition_staff', 'events_sync_competition',
                      'activity_fill_competition', 'is_competition_staff')
), t as (
  select unnest(array['app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups']) as tabell
), k as (
select 1 as nr, 'De nye kolonnene finnes (clubs, competitions, events, rounds, activity)' as sjekk,
       (select count(*) = 11 from information_schema.columns
         where table_schema = 'public'
           and (table_name, column_name) in (('clubs', 'kind'),
                ('competitions', 'signup_audience'), ('competitions', 'listed'),
                ('competitions', 'max_entrants'), ('competitions', 'waitlist_enabled'),
                ('competitions', 'signup_opens_at'), ('competitions', 'signup_closes_at'),
                ('competitions', 'venue'), ('events', 'competition_id'),
                ('rounds', 'wave_no'), ('activity', 'competition_id'))) as ok
union all
select 2, 'De fire nye tabellene har RLS på, og anon har ingenting',
       (select bool_and(c.relrowsecurity) from t join pg_class c on c.oid = ('public.' || t.tabell)::regclass)
       and not exists (select 1 from information_schema.role_table_grants g join t on g.table_name = t.tabell
                        where g.table_schema = 'public' and g.grantee in ('anon', 'PUBLIC'))
union all
select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
       (select count(*) = 3 from pg_indexes where schemaname = 'public'
         and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club', 'competitions_one_main_active'))
       and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
                    and conrelid = 'public.events'::regclass)
union all
select 4, 'De nye indeksene finnes',
       (select count(*) = 5 from pg_indexes where schemaname = 'public'
         and indexname in ('events_one_per_date_per_competition', 'rounds_one_active_per_event_wave',
                           'activity_competition_time_idx', 'rounds_club_locked_idx',
                           'competition_participants_competition_idx'))
union all
select 5, 'Paritet: hver kveld i en sesong hører til sesongens turnering, og ingen andre har en sesong',
       not exists (select 1 from public.events e
                   left join public.competitions c on c.season_id = e.season_id
                   where e.season_id is not null and e.competition_id is distinct from c.id)
       and not exists (select 1 from public.events e join public.competitions c on c.id = e.competition_id
                       where c.season_id is distinct from e.season_id)
union all
select 6, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
       not exists (
         (select e.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
           where e.season_id is not null
          except
          select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
            join public.competitions c on c.id = e.competition_id where c.season_id is not null)
         union all
         (select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
            join public.competitions c on c.id = e.competition_id where c.season_id is not null
          except
          select c.season_id, cr.round_id from public.competition_rounds cr
            join public.competitions c on c.id = cr.competition_id
           where cr.source = 'season' and c.season_id is not null))
union all
select 7, 'Ingen policy fra 001–030 bruker staben eller de nye kolonnene',
       not exists (select 1 from pg_policies where schemaname = 'public'
                    and tablename not in ('app_config', 'competition_staff', 'competition_waitlist', 'round_start_groups')
                    and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(competition_staff|is_competition_staff|signup_audience|listed|wave_no)')
union all
select 8, 'Triggerfunksjonene kan ikke kalles av appen; is_competition_staff av innloggede, ikke anon',
       (select bool_and(not auth_kan and not anon_kan) from f
         where proname in ('guard_competition_staff', 'events_sync_competition', 'activity_fill_competition'))
       and (select auth_kan and not anon_kan from f where proname = 'is_competition_staff')
union all
select 9, 'Alle fire funksjonene har tom search_path',
       (select count(*) = 4 and bool_and('search_path=""' = any(proconfig)) from f)
union all
select 10, 'Triggerne finnes (events begge veier, rundene følger kvelden, aktivitet, stab)',
       (select count(*) = 4 from pg_trigger where not tgisinternal and tgname in
         ('events_sync_competition', 'competition_rounds_sync_event', 'activity_fill_competition',
          'competition_staff_guard'))
union all
select 11, 'app_config har min_ios_build',
       exists (select 1 from public.app_config where key = 'min_ios_build' and value ? 'build')
union all
select 12, 'Plassbytte-linjer er koblet til turneringen sin',
       not exists (select 1 from public.activity a join public.competitions c
                     on c.id::text = a.data ->> 'competition' and c.club_id = a.club_id
                   where a.kind = 'table_changed' and a.competition_id is distinct from c.id)
)
select case when ok then 'ok ' else 'FEIL ' end || 'kontroll ' || nr || ': ' || sjekk from k order by nr;
