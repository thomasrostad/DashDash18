\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 035_sesong_som_view.sql. Rekkefølge på en kopi av den lokale kjeden til og
-- med 054: lokal/035_for.sql, 035 (to ganger), så denne fila. Alt rulles tilbake.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
--
-- A: per innlogging (seks), før = etter for alt i lokal35.bilde(): det dagens app ser og
--    kan (lokal32.bilde, med seasons), Tavla (lokal31.tavla), tavla_data for alle sesonger,
--    037-RPC-ene, sesonglista fra seasons, sesonglista slik den nye appen leser den
--    (competitions med season_id) og veddemålene.
-- B: uten innlogging, før = etter: paritetskontrollen (10.2), veddemålene (alle og per
--    sesong), kveldene med sesong, turnering og updated_at, sesongene med opprettet-tid,
--    turneringsradene og bet_rule.
-- C: scenariet (lokal35.scenario), før = etter steg for steg: gamle bygg skriver seasons
--    (ny, navn og regler, activate_season med og uten hovedturnering, avslutt, slett
--    planlagt og ferdig, ikke lov for medlem og annen klubb, uten innlogging, kvelder
--    stopper, dobbel id, ukjent sesong, tomt navn), den nye appen skriver competitions,
--    create_bet uten kveld og delete_tournament med kvelder og veddemål.
-- D: den nye appens lesing (competitions) = gamle bygg (seasons), før og etter.
-- E: bare etter: viewet, nøklene, triggerne, ny sesong uten id, id kan ikke endres,
--    anon, importen (Packages/DashImport) som server, kaskaden for veddemål, kvelder
--    stopper sletting av turneringsraden, ligaer berøres ikke.
-- ===========================================================================

create function pg_temp.lik(p_verdi anyelement, p_forventet anyelement, p_hva text) returns text language sql as $$
  select case when p_verdi is not distinct from p_forventet then 'ok ' || p_hva
              else 'FEIL ' || p_hva || ': fikk ' || left(coalesce(p_verdi::text, 'null'), 400)
                   || ', forventet ' || left(coalesce(p_forventet::text, 'null'), 400) end
$$;

begin;

-- === A. Per innlogging ======================================================
create table lokal35.etter_bilde (uid uuid primary key, bilde jsonb);
grant insert on lokal35.etter_bilde to authenticated;
do $$
declare
  b record;
begin
  for b in select uid from lokal35.brukere order by uid loop
    perform set_config('request.jwt.claim.sub', b.uid::text, false);
    set role authenticated;
    insert into lokal35.etter_bilde (uid, bilde) select b.uid, lokal35.bilde();
    reset role;
  end loop;
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

select pg_temp.lik(e.bilde -> k, f.bilde -> k, 'A ' || right(f.uid::text, 2) || ' ' || k)
  from lokal35.for_bilde f
  join lokal35.etter_bilde e on e.uid = f.uid
  cross join lateral jsonb_object_keys(f.bilde || e.bilde) k
 order by f.uid, k;
select pg_temp.lik((select count(*) from lokal35.etter_bilde), 6::bigint, 'A seks innlogginger');
select pg_temp.lik((select count(*) from lokal35.etter_bilde e, lateral jsonb_each(e.bilde -> 'tavla_data') t
                     where jsonb_typeof(t.value) = 'object'), 9::bigint,
                   'A tavla_data svarer for medlemmene (9 par innlogging og sesong), resten P0002');

-- === B. Uten innlogging =====================================================
select pg_temp.lik(lokal35.server() -> k, f.bilde -> k, 'B ' || k)
  from lokal35.for_server f cross join lateral jsonb_object_keys(f.bilde) k
 order by k;
select pg_temp.lik((select bool_and((x ->> 'lik')::boolean) from jsonb_array_elements(lokal32.paritet()) x),
                   true, 'B paritet: via sesong = via turnering for alle sesonger');

-- === C. Scenariet ===========================================================
create temporary table etter_scenario as select lokal35.scenario() as svar;
select pg_temp.lik(e.svar -> k, f.svar -> k, 'C ' || k)
  from lokal35.for_scenario f cross join etter_scenario e
  cross join lateral jsonb_object_keys(f.svar || e.svar) k
 order by k;

-- === D. Den nye appens lesing = gamle bygg ==================================
select pg_temp.lik(
         (select jsonb_agg(x - 'created_at') from jsonb_array_elements(f.bilde -> 'ny_app') x),
         (select jsonb_agg(x - 'created_at') from jsonb_array_elements(f.bilde -> 'sesongliste') x),
         'D før ' || right(f.uid::text, 2) || ': competitions (ny app) = seasons')
  from lokal35.for_bilde f order by f.uid;
select pg_temp.lik(e.bilde -> 'ny_app', e.bilde -> 'sesongliste',
                   'D etter ' || right(e.uid::text, 2) || ': competitions (ny app) = seasons, med opprettet-tid')
  from lokal35.etter_bilde e order by e.uid;

-- === E. Bare etter 035 ======================================================
select pg_temp.lik((select relkind::text from pg_class where oid = 'public.seasons'::regclass), 'v', 'E seasons er et view');
select pg_temp.lik((select reloptions from pg_class where oid = 'public.seasons'::regclass), array['security_invoker=true'],
                   'E security_invoker');
select pg_temp.lik((select confrelid::regclass::text from pg_constraint where conname = 'events_season_fk'), 'competitions',
                   'E events.season_id peker på competitions');
select pg_temp.lik((select confrelid::regclass::text from pg_constraint where conname = 'bets_season_fk'), 'competitions',
                   'E bets.season_id peker på competitions');
select pg_temp.lik((select count(*) from pg_constraint where conname = 'competitions_season_fk'), 0::bigint,
                   'E competitions_season_fk er borte');
select pg_temp.lik((select count(*) from pg_proc where proname in ('competitions_sync_season', 'competitions_sync_to_season')),
                   0::bigint, 'E speilingen er borte');
select pg_temp.lik(has_table_privilege('anon', 'public.seasons', 'select'), false, 'E anon kan ikke lese seasons');
select pg_temp.lik(lokal35.q(null, 'select count(*) as n from public.seasons'), '[{"n": 5}]'::jsonb,
                   'E fem sesonger i viewet');

\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u7 '00000000-0000-0000-0000-000000000007'
\set k1 '\'aaaaaaaa-0000-0000-0000-000000000001\''
\set k3 '\'aaaaaaaa-0000-0000-0000-000000000003\''

-- Ny sesong uten id (standardverdiene på viewet), turneringsraden følger.
create temporary table ny as
  select (lokal35.q(:'u7', 'insert into public.seasons (club_id, name) values (' || :'k3' || ', ''Uten id'') '
                    'returning id, status, rules, created_at is not null as tid, updated_at is not null as endret')
          -> 0) as rad;
select pg_temp.lik((select rad - 'id' from ny), '{"tid": true, "rules": {"version": 1}, "endret": true, "status": "planned"}'::jsonb,
                   'E ny sesong uten id: standardverdier');
select pg_temp.lik((select count(*) from public.competitions c, ny where c.season_id = (ny.rad ->> 'id')::uuid
                     and c.kind = 'season' and c.entry = 'club' and c.club_id = :k3::uuid),
                   1::bigint, 'E ny sesong: turneringsrad med season_id, kind season, entry club');
select pg_temp.lik(lokal35.q(:'u7', 'update public.seasons set id = gen_random_uuid() where id = '''
                                    || (select rad ->> 'id' from ny) || ''' returning id'),
                   '{"feil": "42501"}'::jsonb, 'E id kan ikke endres (42501)');
select pg_temp.lik(lokal35.q(:'u7', 'update public.seasons set club_id = ' || :'k1' || ' where id = '''
                                    || (select rad ->> 'id' from ny) || ''' returning id'),
                   '{"feil": "42501"}'::jsonb, 'E klubb kan ikke endres (42501)');
-- updated_at følger turneringsraden.
create temporary table endret as
  select lokal35.q(:'u7', 'update public.seasons set name = ''Nytt navn'' where id = ''' || (select rad ->> 'id' from ny)
                          || ''' returning name, updated_at') -> 0 as rad;
select pg_temp.lik((select (rad ->> 'updated_at')::timestamptz from endret),
                   (select c.updated_at from public.competitions c, ny where c.season_id = (ny.rad ->> 'id')::uuid),
                   'E update gir updated_at fra turneringsraden');
select pg_temp.lik((select rad ->> 'name' from endret), 'Nytt navn', 'E update via viewet gir det nye navnet');

-- Ligaer: status aktiv gjør ikke en liga til hovedturnering.
select pg_temp.lik(
  (lokal35.q(:'u1', 'update public.competitions set status = ''active'' where kind = ''league'' and club_id = '
                    || :'k1' || ' returning is_main') -> 0 ->> 'is_main'),
  'false', 'E liga aktiv blir ikke hovedturnering');

-- Kvelder stopper sletting av turneringsraden (restrict), veddemålene følger med (cascade).
savepoint s;
select pg_temp.lik(lokal35.q(null, 'delete from public.competitions where season_id = ''5eeeeeee-0000-0000-0000-000000002026'' returning id'),
                   '{"feil": "23503"}'::jsonb, 'E kvelder stopper sletting av sesongens turneringsrad (23503)');
delete from public.rounds where event_id in (select id from public.events where season_id = '5eeeeeee-0000-0000-0000-000000002026');
delete from public.events where season_id = '5eeeeeee-0000-0000-0000-000000002026';
delete from public.competitions where season_id = '5eeeeeee-0000-0000-0000-000000002026';
select pg_temp.lik((select count(*) from public.bets where season_id = '5eeeeeee-0000-0000-0000-000000002026'), 0::bigint,
                   'E veddemålene følger turneringsraden (cascade)');
rollback to savepoint s;

-- Kveld eller veddemål med ukjent sesong avvises (23503).
select pg_temp.lik(lokal35.q(null, 'insert into public.events (club_id, season_id, event_date) values ('
                                   || :'k1' || ', gen_random_uuid(), ''2027-01-01'') returning id'),
                   '{"feil": "23503"}'::jsonb, 'E kveld med ukjent sesong (23503)');
select pg_temp.lik(lokal35.q(null, 'insert into public.events (club_id, season_id, event_date) values ('
                                   || '''aaaaaaaa-0000-0000-0000-000000000002'', ''5eeeeeee-0000-0000-0000-000000002026'', ''2027-01-01'') returning id'),
                   '{"feil": "23503"}'::jsonb, 'E kveld med sesong fra en annen klubb (23503)');

-- Importen (Packages/DashImport, SQLWriter): samme blokk som den skriver, som server.
savepoint s;
do $season$
begin
  if exists (select 1 from public.seasons where id = '5eeeeeee-0000-0000-0000-0000000035d0') then
    update public.seasons set name = 'Import', status = 'active' where id = '5eeeeeee-0000-0000-0000-0000000035d0';
  else
    insert into public.seasons (id, club_id, name, status, rules)
    values ('5eeeeeee-0000-0000-0000-0000000035d0', 'aaaaaaaa-0000-0000-0000-000000000004', 'Import', 'active', '{"version": 1}'::jsonb);
  end if;
end
$season$;
do $season$
begin
  if exists (select 1 from public.seasons where id = '5eeeeeee-0000-0000-0000-0000000035d0') then
    update public.seasons set name = 'Import 2', status = 'active' where id = '5eeeeeee-0000-0000-0000-0000000035d0';
  else
    insert into public.seasons (id, club_id, name, status, rules)
    values ('5eeeeeee-0000-0000-0000-0000000035d0', 'aaaaaaaa-0000-0000-0000-000000000004', 'Import 2', 'active', '{"version": 1}'::jsonb);
  end if;
end
$season$;
select pg_temp.lik((select jsonb_build_object('navn', c.name, 'status', c.status, 'hoved', c.is_main)
                      from public.competitions c where c.season_id = '5eeeeeee-0000-0000-0000-0000000035d0'),
                   '{"navn": "Import 2", "hoved": true, "status": "active"}'::jsonb,
                   'E importen som server: ny og oppdatert sesong, hovedturnering');
rollback to savepoint s;

-- Medlem uten rettighet kan ikke lage sesong via viewet, heller ikke i en annen klubb.
select pg_temp.lik(lokal35.q(:'u2', 'insert into public.seasons (club_id, name) values (' || :'k3' || ', ''X'') returning id'),
                   '{"feil": "42501"}'::jsonb, 'E sesong i en annen klubb (42501)');

-- Kjent endring: stab i en klubbserie som ikke er medlem av klubben (u4 i Golfgutu), ser nå
-- sesongraden (turneringsraden så hen fra før). tavla_data og skriving er som før.
savepoint s;
insert into public.competition_staff (competition_id, profile_id, role)
select c.id, '00000000-0000-0000-0000-000000000004', 'organizer'
  from public.competitions c where c.season_id = '5eeeeeee-0000-0000-0000-000000002026';
select pg_temp.lik(lokal35.q('00000000-0000-0000-0000-000000000004',
                             'select id, name from public.seasons where id = ''5eeeeeee-0000-0000-0000-000000002026'''),
                   '[{"id": "5eeeeeee-0000-0000-0000-000000002026", "name": "Sesong 2026"}]'::jsonb,
                   'E stab uten medlemskap ser sesongraden (kjent endring, som turneringsraden)');
select pg_temp.lik(lokal35.q('00000000-0000-0000-0000-000000000004',
                             'select public.tavla_data(''5eeeeeee-0000-0000-0000-000000002026'') is not null as x'),
                   '{"feil": "P0002"}'::jsonb, 'E stab uten medlemskap: tavla_data som før (P0002)');
select pg_temp.lik(lokal35.q('00000000-0000-0000-0000-000000000004',
                             'update public.seasons set name = ''Stab'' where id = ''5eeeeeee-0000-0000-0000-000000002026'' returning id'),
                   '[]'::jsonb, 'E stab uten medlemskap kan ikke endre sesongen via viewet (0 rader)');
rollback to savepoint s;

rollback;
