\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 033_turnering_kjerne_trinn3.sql. Rekkefølge i en tom, lokal
-- Postgres: lokal/stub.sql, lokal/stub_storage.sql, 001–030 (som i
-- sql/README.md), lokal/031_for.sql, 031, lokal/032_for.sql, 032, 036, 037,
-- 038, lokal/033_for.sql, 033 (to ganger), så denne fila. Hver
-- resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- Del A: Golfgutu og dagens app merker ingenting (samme bilde, Tavla og
--        svar fra 036/037/038 per innlogging, paritetskontrollen lik, de
--        gamle reglene gir fortsatt 23505).
-- Del B: dagens app skriver seasons (ny sesong, nytt navn, nye regler,
--        activate_season, avslutt, slett planlagt): turneringen følger, og
--        ingen ring (tellende triggere). Rulles tilbake.
-- Del C: den nye appen skriver competitions: sesongen følger, det som er
--        låst er låst, og ingen ring. Rulles tilbake.
-- Del D: en liga med egen spilledag: runden kobles til ligaen, Golfgutu er
--        uendret, flytting av spilledag og runde, utfyllingen, is_main i en
--        ny klubb, og den gamle «én kveld per dato» står.
-- Del E: kontrollblokken fra fila.
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
\set u7 '00000000-0000-0000-0000-000000000007'
\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb3  'aaaaaaaa-0000-0000-0000-000000000003'
\set s2025   '5eeeeeee-0000-0000-0000-000000002025'
\set s2026   '5eeeeeee-0000-0000-0000-000000002026'
\set morro   'c0000000-0000-0000-0000-00000000f001'
\set liga3   'c0000000-0000-0000-0000-0000000a0003'
\set r31     'dddddddd-0000-0000-0000-000000000031'
\set e3      'eeeeeeee-0000-0000-0000-000000000003'
\set e4      'eeeeeeee-0000-0000-0000-000000000004'
\set r4      'dddddddd-0000-0000-0000-000000000004'
\set bane    'cccccccc-0000-0000-0000-000000000001'

select pg_temp.som('');
select c.id as j2026 from public.competitions c where c.season_id = :'s2026' \gset
select c.id as j2025 from public.competitions c where c.season_id = :'s2025' \gset

-- Teller oppdateringer per rad på seasons og competitions (for «ingen ring»).
-- Lages og fjernes i hver transaksjon under.
create function pg_temp.antall(p_tabell text, p_id uuid) returns int language plpgsql as $$
begin
  return (select count(*)::int from lokal33.logg where tabell = p_tabell and id = p_id);
end $$;
grant execute on all functions in schema pg_temp to public;


-- === A. Golfgutu og dagens app merker ingenting ==============================
create table lokal33.etter_bilde (uid uuid primary key, bilde jsonb, tavla jsonb, rpc jsonb);
grant insert on lokal33.etter_bilde to authenticated;
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal33.etter_bilde values (:'u1', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal33.etter_bilde values (:'u2', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal33.etter_bilde values (:'u3', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal33.etter_bilde values (:'u4', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal33.etter_bilde values (:'u5', lokal32.bilde(), lokal31.tavla(), lokal33.rpc()); reset role;
select pg_temp.som('');

select pg_temp.lik(e.bilde, f.bilde, 'A1 samme bilde før og etter 033 for ' || f.uid)
from lokal33.for_bilde f join lokal33.etter_bilde e using (uid) order by f.uid;
select pg_temp.lik(e.tavla, f.tavla, 'A2 samme Tavla før og etter 033 for ' || f.uid)
from lokal33.for_bilde f join lokal33.etter_bilde e using (uid) order by f.uid;
select pg_temp.lik(e.rpc, f.rpc, 'A3 samme svar fra tavla_data (036) og known_profiles/my_* (037) for ' || f.uid)
from lokal33.for_bilde f join lokal33.etter_bilde e using (uid) order by f.uid;
select pg_temp.lik((select count(*) from lokal33.for_bilde f, jsonb_each(f.rpc -> 'tavla_data') t
                     where jsonb_typeof(t.value) = 'object')::int, 7,
                   'A3 tavla_data ga data i 7 av 15 kall (medlemmer), feilkode ellers');
select pg_temp.lik(lokal32.paritet(), (select svar from lokal33.paritet_for),
                   'A4 paritetskontrollen (10.2) er lik før og etter 033');
select pg_temp.lik((select bool_and((x ->> 'lik')::boolean) from jsonb_array_elements(lokal32.paritet()) x), true,
                   'A4 via sesongen = via turneringen for alle sesonger');

begin;
select pg_temp.som(:'u1'); set role authenticated;
select public.delete_tournament(:'j2026', 'Sesong 2026')::text as slett_j2026 \gset
select public.delete_tournament(:'morro', 'Morrocupen')::text as slett_morro \gset
rollback;
select pg_temp.som('');
select pg_temp.lik(:'slett_j2026', (select svar from lokal33.slett where hva = 'j2026'),
                   'A5 delete_tournament (038) svarer det samme for jakkeracet 2026 (rullet tilbake)');
select pg_temp.lik(:'slett_morro', (select svar from lokal33.slett where hva = 'morro'),
                   'A5 delete_tournament (038) svarer det samme for Morrocupen (rullet tilbake)');

-- De gamle reglene gir fortsatt 23505.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('update public.rounds set status = %L where id = %L', 'active', :'r4'), '23505');
select pg_temp.feil(format('insert into public.seasons (club_id, name, status) values (%L, %L, %L)',
                           :'klubb', 'To aktive', 'active'), '23505');
select pg_temp.feil(format('insert into public.events (club_id, event_date) values (%L, %L)',
                           :'klubb', '2026-10-01'), '23505');
reset role;
select pg_temp.som('');


-- === B. Dagens app skriver seasons ===========================================
begin;
create table lokal33.logg (tabell text, id uuid);
grant insert, select on lokal33.logg to authenticated;
create function lokal33.logg() returns trigger language plpgsql as $$
begin
  insert into lokal33.logg values (tg_table_name, new.id);
  return null;
end $$;
create trigger zzz_logg after update on public.seasons for each row execute function lokal33.logg();
create trigger zzz_logg after update on public.competitions for each row execute function lokal33.logg();

-- B1 Ny sesong (planlagt), slik SesongAdminModel.create gjør det.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (club_id, name, status, rules)
values (:'klubb', 'Sesong 2027', 'planned', '{"version": 1, "preset": "golfgutu"}')
returning id as s2027 \gset
reset role;
select c.id as j2027 from public.competitions c where c.season_id = :'s2027' \gset
select pg_temp.lik((select kind || ' ' || entry || ' ' || status || ' ' || name || ' ' || rules::text || ' main=' || is_main
                      from public.competitions where id = :'j2027'),
                   'season club planned Sesong 2027 {"preset": "golfgutu", "version": 1} main=false',
                   'B1 ny sesong får turneringen sin; ikke hovedturnering når jakkeracet er aktivt');

-- B2 Nytt navn i seasons: turneringen følger, én oppdatering hver vei, ingen ring.
delete from lokal33.logg;
select pg_temp.som(:'u1'); set role authenticated;
update public.seasons set name = 'Sesong 2027 vår' where id = :'s2027';
reset role;
select pg_temp.lik((select name from public.competitions where id = :'j2027'), 'Sesong 2027 vår', 'B2 navnet følger');
select pg_temp.lik(pg_temp.antall('seasons', :'s2027') || '/' || pg_temp.antall('competitions', :'j2027'), '1/1',
                   'B2 ingen ring: sesongen oppdatert 1 gang, turneringen 1 gang');

-- B3 Nye regler i seasons.
delete from lokal33.logg;
select pg_temp.som(:'u1'); set role authenticated;
update public.seasons set rules = '{"version": 2, "preset": "golfgutu"}' where id = :'s2027';
reset role;
select pg_temp.lik((select rules ->> 'version' from public.competitions where id = :'j2027'), '2', 'B3 reglene følger');
select pg_temp.lik(pg_temp.antall('seasons', :'s2027') || '/' || pg_temp.antall('competitions', :'j2027'), '1/1',
                   'B3 ingen ring: 1/1');
-- Samme verdier igjen (appen lagrer uendret): turneringen røres ikke.
delete from lokal33.logg;
select pg_temp.som(:'u1'); set role authenticated;
update public.seasons set rules = '{"version": 2, "preset": "golfgutu"}' where id = :'s2027';
reset role;
select pg_temp.lik(pg_temp.antall('competitions', :'j2027'), 0, 'B3 uendret lagring rører ikke turneringen');

-- B4 activate_season (gammel app): 2026 avsluttes, 2027 blir aktiv og hovedturnering.
delete from lokal33.logg;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.activate_season(:'s2027')).status, 'active', 'B4 activate_season svarer med den aktive sesongen');
reset role;
select pg_temp.lik((select string_agg(s.name || ':' || s.status || ':' || c.status || ':' || c.is_main, ', ' order by s.name)
                      from public.seasons s join public.competitions c on c.season_id = s.id where s.club_id = :'klubb'),
                   'Sesong 2025:finished:finished:true, Sesong 2026:finished:finished:true, Sesong 2027 vår:active:active:true',
                   'B4 2026 avsluttet (fortsatt hovedturnering), 2027 aktiv og hovedturnering');
select pg_temp.lik((select count(*) from public.competitions where club_id = :'klubb' and is_main and status = 'active')::int,
                   1, 'B4 én aktiv hovedturnering i klubben');
select pg_temp.lik(pg_temp.antall('seasons', :'s2026') || '/' || pg_temp.antall('seasons', :'s2027') || '/'
                   || pg_temp.antall('competitions', :'j2026') || '/' || pg_temp.antall('competitions', :'j2027'),
                   '1/1/1/2', 'B4 ingen ring: sesongene 1 gang hver, 2026-turneringen 1, 2027-turneringen 2 (status + hovedturnering)');

-- B5 Avslutt i seasons: turneringen følger og beholder is_main.
select pg_temp.som(:'u1'); set role authenticated;
update public.seasons set status = 'finished' where id = :'s2027';
reset role;
select pg_temp.lik((select status || ' main=' || is_main from public.competitions where id = :'j2027'),
                   'finished main=true', 'B5 avsluttet i seasons: turneringen avsluttet, fortsatt hovedturnering');

-- B6 En ny planlagt sesong når ingen er aktiv, blir hovedturnering (som før).
-- Slettes igjen fra appen (bare planlagte): turneringen forsvinner med den.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (club_id, name) values (:'klubb', 'Sesong 2028') returning id as s2028 \gset
reset role;
select pg_temp.lik((select is_main from public.competitions where season_id = :'s2028'), true,
                   'B6 ny sesong uten aktiv hovedturnering i klubben blir hovedturnering');
select pg_temp.som(:'u1'); set role authenticated;
delete from public.seasons where id = :'s2028';
reset role;
select pg_temp.lik((select count(*) from public.competitions where season_id = :'s2028')::int, 0,
                   'B6 slettet planlagt sesong tar turneringen med seg');

-- B7 Dagens app lagrer en kveld (season_id i SET, uendret): koblingene står.
select pg_temp.som(:'u1'); set role authenticated;
update public.events set season_id = :'s2026', note = 'Ny tekst' where id = :'e3';
reset role;
select pg_temp.lik((select string_agg(right(cr.round_id::text, 1) || ':' || (cr.competition_id = :'j2026'), ',' order by cr.round_id)
                      from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
                     where r.event_id = :'e3' and cr.source = 'season'),
                   '3:true,4:true', 'B7 rundene på kvelden er fortsatt koblet til jakkeracet');
rollback;


-- === C. Den nye appen skriver competitions ===================================
begin;
create table lokal33.logg (tabell text, id uuid);
grant insert, select on lokal33.logg to authenticated;
create function lokal33.logg() returns trigger language plpgsql as $$
begin
  insert into lokal33.logg values (tg_table_name, new.id);
  return null;
end $$;
create trigger zzz_logg after update on public.seasons for each row execute function lokal33.logg();
create trigger zzz_logg after update on public.competitions for each row execute function lokal33.logg();

-- C1 Nytt navn på turneringen: sesongen følger, og dagens app ser det.
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set name = 'Jakkeracet 2026' where id = :'j2026';
reset role;
select pg_temp.lik(pg_temp.antall('seasons', :'s2026') || '/' || pg_temp.antall('competitions', :'j2026'), '1/1',
                   'C1 ingen ring: turneringen 1 gang, sesongen 1 gang');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select name from public.seasons where id = :'s2026'), 'Jakkeracet 2026',
                   'C1 dagens app (spiller) leser det nye navnet fra seasons');
reset role;

-- C2 Nye regler på turneringen: sesongen følger.
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set rules = '{"version": 3, "preset": "golfgutu"}' where id = :'j2026';
reset role;
select pg_temp.lik((select rules ->> 'version' from public.seasons where id = :'s2026'), '3', 'C2 reglene følger til seasons');

-- C3 Det som er låst, er fortsatt låst.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('update public.competitions set entry = %L where id = %L', 'listed', :'j2026'), '42501');
select pg_temp.feil(format('update public.competitions set is_main = false where id = %L', :'j2026'), '42501');
select pg_temp.feil(format('update public.competitions set kind = %L where id = %L', 'league', :'j2026'), '42501');
select pg_temp.feil(format('update public.competitions set season_id = null where id = %L', :'j2026'), '42501');
select pg_temp.feil(format('update public.competitions set is_main = true where id = %L', :'morro'), '42501');
reset role;

-- C4 En spiller kan ikke endre turneringen (RLS uendret), og sesongen står.
select pg_temp.som(:'u2'); set role authenticated;
update public.competitions set name = 'Hacket' where id = :'j2026';
reset role;
select pg_temp.lik((select s.name || '/' || c.name from public.seasons s join public.competitions c on c.season_id = s.id
                     where s.id = :'s2026'), 'Jakkeracet 2026/Jakkeracet 2026', 'C4 spilleren endret ingenting');

-- C5 Status via turneringen: avslutt 2026, aktiver 2025 igjen.
select pg_temp.som(:'u1'); set role authenticated;
update public.competitions set status = 'finished' where id = :'j2026';
update public.competitions set status = 'active' where id = :'j2025';
reset role;
select pg_temp.lik((select string_agg(s.name || ':' || s.status || ':' || c.is_main, ', ' order by s.name)
                      from public.seasons s join public.competitions c on c.season_id = s.id where s.club_id = :'klubb'),
                   'Jakkeracet 2026:finished:true, Sesong 2025:active:true', 'C5 status følger til seasons begge');

-- C6 Ny sesong (gammel vei) mens 2025 er aktiv: ikke hovedturnering. Å
-- aktivere den via turneringen mens 2025 er aktiv gir 23505 (gamle regel).
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (club_id, name) values (:'klubb', 'Vinterserien') returning id as svinter \gset
reset role;
select c.id as jvinter from public.competitions c where c.season_id = :'svinter' \gset
select pg_temp.lik((select is_main from public.competitions where id = :'jvinter'), false, 'C6 ny serie er ikke hovedturnering');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('update public.competitions set status = %L where id = %L', 'active', :'jvinter'), '23505');

-- C7 Avslutt 2025 og aktiver serien via turneringen: den tar over som hovedturnering.
update public.competitions set status = 'finished' where id = :'j2025';
reset role;
delete from lokal33.logg;
set role authenticated;
update public.competitions set status = 'active' where id = :'jvinter';
reset role;
select pg_temp.lik((select s.status || ' main=' || c.is_main from public.seasons s join public.competitions c on c.season_id = s.id
                     where s.id = :'svinter'), 'active main=true', 'C7 serien aktiv i seasons og hovedturnering');
select pg_temp.lik(pg_temp.antall('seasons', :'svinter') || '/' || pg_temp.antall('competitions', :'jvinter'), '1/2',
                   'C7 ingen ring: sesongen 1 gang, turneringen 2 (status + hovedturnering)');
rollback;


-- === D. En liga med egne spilledager =========================================
-- D1 Thomas lager en liga i Golfgutu og en spilledag i den (ny app).
select pg_temp.som(:'u1'); set role authenticated;
select public.create_competition('league', 'Torsdagsligaen', :'klubb') as liga \gset
select public.create_competition('league', 'Fredagsligaen', :'klubb') as liga2 \gset
insert into public.events (club_id, competition_id, event_date) values (:'klubb', :'liga', '2026-10-22')
returning id as ldag \gset
select pg_temp.lik((select coalesce(season_id::text, 'ingen') || ' ' || (competition_id = :'liga')
                      from public.events where id = :'ldag'), 'ingen true', 'D1 spilledagen hører til ligaen, uten sesong');
select pg_temp.lik((select is_main from public.competitions where id = :'liga'), false, 'D1 ligaen er ikke hovedturnering');

-- D2 En runde på spilledagen kobles til ligaen (source = season), ikke til jakkeracet.
insert into public.rounds (club_id, event_id, course_id, round_no, hole_count)
values (:'klubb', :'ldag', :'bane', 1, 18) returning id as lrunde \gset
select pg_temp.lik((select string_agg(case cr.competition_id when :'liga'::uuid then 'liga' when :'j2026'::uuid then 'jakke' else 'annen' end
                                      || ':' || cr.source, ',')
                      from public.competition_rounds cr where cr.round_id = :'lrunde'),
                   'liga:season', 'D2 runden på ligaens spilledag er koblet til ligaen');
reset role;
select pg_temp.som('');
update public.rounds set status = 'locked' where id = :'lrunde';

-- D3 Golfgutu er uendret: Tavla per innlogging og paritetskontrollen.
select pg_temp.lik(lokal32.paritet(), (select svar from lokal33.paritet_for),
                   'D3 paritetskontrollen er lik med en låst ligarunde i klubben');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(lokal31.tavla(), (select tavla from lokal33.for_bilde where uid = :'u2'),
                   'D3 Anders ser samme Tavla (sesongene) som før');
select pg_temp.lik((select count(*) from public.competition_rounds where competition_id = :'liga')::int, 1,
                   'D3 Anders (medlem) ser ligaens kobling');
reset role;

-- D4 Dagens app lagrer spilledagen (season_id = null i SET): ligaen står.
select pg_temp.som(:'u1'); set role authenticated;
update public.events set season_id = null, note = 'Liga' where id = :'ldag';
select pg_temp.lik((select (competition_id = :'liga')::text from public.events where id = :'ldag'), 'true',
                   'D4 lagring fra dagens app tar ikke spilledagen ut av ligaen');

-- D5 Spilledagen flyttes til en annen liga: runden følger.
update public.events set competition_id = :'liga2' where id = :'ldag';
select pg_temp.lik((select string_agg(case cr.competition_id when :'liga2'::uuid then 'liga2' else 'annen' end, ',')
                      from public.competition_rounds cr where cr.round_id = :'lrunde' and cr.source = 'season'),
                   'liga2', 'D5 runden flytter med spilledagen til den andre ligaen');
update public.events set competition_id = :'liga' where id = :'ldag';
reset role;

-- D6 Flytt i en transaksjon som rulles tilbake: spilledagen inn i jakkeracet
-- (gammel vei, season_id), og runden til en kveld uten turnering.
begin;
select pg_temp.som(:'u1'); set role authenticated;
update public.events set season_id = :'s2026' where id = :'ldag';
select pg_temp.lik((select string_agg(case cr.competition_id when :'j2026'::uuid then 'jakke' else 'annen' end, ',')
                      from public.competition_rounds cr where cr.round_id = :'lrunde' and cr.source = 'season'),
                   'jakke', 'D6 spilledagen lagt i sesongen: runden teller i jakkeracet, ikke i ligaen');
update public.events set competition_id = :'liga' where id = :'ldag';
select pg_temp.lik((select coalesce(season_id::text, 'ingen') from public.events where id = :'ldag'), 'ingen',
                   'D6 tilbake i ligaen (competition_id): ut av sesongen');
reset role;
select pg_temp.som('');
update public.rounds set event_id = :'e4', round_no = 9 where id = :'lrunde';
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'lrunde' and source = 'season')::int, 0,
                   'D6 runden flyttet til en kveld uten turnering: ingen kobling');
update public.rounds set event_id = :'ldag' where id = :'lrunde';
select pg_temp.lik((select count(*) from public.competition_rounds where round_id = :'lrunde' and competition_id = :'liga')::int, 1,
                   'D6 og tilbake til ligaens spilledag: koblet igjen');
rollback;

-- D7 delete_tournament (038) virker for ligaen: spilledagen og runden (rulles tilbake).
begin;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.delete_tournament(:'liga', 'Torsdagsligaen') ->> 'rounds', '1',
                   'D7 delete_tournament sletter ligaens runde');
reset role;
rollback;
select pg_temp.som('');

-- D8 Den gamle «én kveld per dato per klubb» står til 034: en spilledag i ligaen
-- kan ikke ligge samme dag som en Golfgutu-kveld.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('insert into public.events (club_id, competition_id, event_date) values (%L, %L, %L)',
                           :'klubb', :'liga', '2026-10-01'), '23505');
reset role;
select pg_temp.som('');

-- D9 Utfyllingen: ligarunden fra før 033 i simulatorsenteret er koblet.
select pg_temp.lik((select string_agg((cr.competition_id = :'liga3') || ':' || cr.source, ',')
                      from public.competition_rounds cr where cr.round_id = :'r31'),
                   'true:season', 'D9 ligarunden fra før 033 er koblet til ligaen');

-- D10 is_main i et senter uten sesong: første sesong blir hovedturnering, og
-- en ny sesong mens den er aktiv blir det ikke.
select pg_temp.som(:'u7'); set role authenticated;
insert into public.seasons (club_id, name) values (:'klubb3', 'Vinter') returning id as sv3 \gset
select pg_temp.lik((select is_main from public.competitions where season_id = :'sv3'), true,
                   'D10 første sesong i senteret blir hovedturnering');
select pg_temp.lik((public.activate_season(:'sv3')).status, 'active', 'D10 activate_season i senteret');
insert into public.seasons (club_id, name) values (:'klubb3', 'Vår') returning id as sv3b \gset
select pg_temp.lik((select is_main from public.competitions where season_id = :'sv3b'), false,
                   'D10 ny sesong mens senteret har en aktiv hovedturnering, blir det ikke');
select pg_temp.lik((select is_main from public.competitions where id = :'liga3'), false, 'D10 ligaen er ikke hovedturnering');
reset role;
select pg_temp.som('');

-- D11 Trinn 4 i det små (rulles tilbake): uten seasons_one_active_per_club kan
-- en ny aktiv serie gå ved siden av jakkeracet. Før 033 stoppet den på
-- competitions_one_main_active (031_prove C); nå blir den ikke hovedturnering.
begin;
drop index public.seasons_one_active_per_club;
select pg_temp.som(:'u1'); set role authenticated;
insert into public.seasons (club_id, name, status) values (:'klubb', 'Tirsdagsserien', 'active') returning id as stirs \gset
reset role;
select pg_temp.lik((select status || ' main=' || is_main from public.competitions where season_id = :'stirs'),
                   'active main=false', 'D11 ny aktiv serie ved siden av jakkeracet, ikke hovedturnering');
select pg_temp.lik((select string_agg(name, ',') from public.competitions
                     where club_id = :'klubb' and is_main and status = 'active'), 'Sesong 2026',
                   'D11 jakkeracet er fortsatt den ene aktive hovedturneringen');
rollback;
select pg_temp.som('');


-- === E. Kontrollblokken fra fila =============================================
select case when k.ok then 'ok ' else 'FEIL ' end || 'E' || k.nr || ' ' || k.sjekk from (
with f as (
  select p.proname,
         has_function_privilege('anon', p.oid, 'execute') as anon_kan,
         has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
         p.proconfig, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('competition_claim_main', 'competitions_sync_season', 'competitions_sync_to_season',
                      'guard_competitions', 'competition_rounds_sync_round', 'competition_rounds_sync_event')
)
select 1 as nr, 'Alle seks funksjonene finnes og har tom search_path' as sjekk,
       (select count(*) = 6 and bool_and('search_path=""' = any(proconfig)) from f) as ok
union all
select 2, 'Ingen av dem kan kalles av anon eller innloggede (bare triggere og interne)',
       (select bool_and(not anon_kan and not auth_kan) from f)
union all
select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
       (select count(*) = 4 from pg_indexes where schemaname = 'public'
         and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club',
                           'competitions_one_main_active', 'rounds_one_active_per_event_wave'))
       and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
                    and conrelid = 'public.events'::regclass)
union all
select 4, 'Triggerne finnes: begge veier sesong ↔ turnering, rundene følger spilledagen',
       (select count(*) = 4 from pg_trigger where not tgisinternal and tgname in
         ('competitions_sync_season', 'competitions_sync_to_season',
          'competition_rounds_sync_round', 'competition_rounds_sync_event'))
union all
select 5, 'Sperren mot ring er på plass (pg_trigger_depth i tilbakeskrivingen)',
       (select prosrc ~ 'pg_trigger_depth\(\) > 1' from f where proname = 'competitions_sync_to_season')
union all
select 6, 'Hver runde på en spilledag er koblet (season) til spilledagens turnering, og ingen annen season-kobling finnes',
       not exists (select 1 from public.rounds r join public.events e on e.id = r.event_id
                    where e.competition_id is not null
                      and not exists (select 1 from public.competition_rounds cr
                                       where cr.round_id = r.id and cr.competition_id = e.competition_id
                                         and cr.source = 'season'))
       and not exists (select 1 from public.competition_rounds cr
                        left join public.rounds r on r.id = cr.round_id
                        left join public.events e on e.id = r.event_id
                       where cr.source = 'season' and cr.competition_id is distinct from e.competition_id)
union all
select 7, 'Speilingen holder: hver sesong har turneringen sin med samme navn, status og regler',
       not exists (select 1 from public.seasons s
                    left join public.competitions c on c.season_id = s.id
                   where c.id is null or c.kind <> 'season' or c.entry <> 'club'
                      or (c.name, c.status, c.rules) is distinct from (s.name, s.status, s.rules))
union all
select 8, 'Hovedturnering: høyst én aktiv per klubb, og en aktiv sesong er hovedturneringen',
       not exists (select club_id from public.competitions where is_main and status = 'active'
                    group by club_id having count(*) > 1)
       and not exists (select 1 from public.seasons s join public.competitions c on c.season_id = s.id
                        where s.status = 'active' and not c.is_main)
union all
select 9, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
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
) k order by k.nr;
