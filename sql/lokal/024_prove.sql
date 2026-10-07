\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 024_sikkerhet.sql. Rekkefølge i en tom, lokal Postgres:
-- lokal/stub.sql, lokal/stub_storage.sql, 001–021 (019 inkludert), 024
-- (gjerne to ganger), så denne fila. Lager sin egen verden.
-- Hver resultatlinje skal starte med "ok"; ingen "FEIL".
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

-- === Verdenen ================================================================
-- Klubb K: Anne (arrangør med innlogging), Bo (spiller) og et ledig navn med
-- arrangørrolle (Kommissær, fra importen). Klubb K3: bare et ledig
-- arrangørnavn (oppstart etter import). Frank er fremmed, Vera er offeret
-- (bare i klubb K2). Gro og Hans er nye innlogginger.
\set uA '24000000-0000-0000-0000-00000000000a'
\set uB '24000000-0000-0000-0000-00000000000b'
\set uF '24000000-0000-0000-0000-00000000000f'
\set uV '24000000-0000-0000-0000-000000000011'
\set uG '24000000-0000-0000-0000-000000000006'
\set uH '24000000-0000-0000-0000-000000000008'
\set K   '24100000-0000-0000-0000-000000000001'
\set K2  '24100000-0000-0000-0000-000000000002'
\set K3  '24100000-0000-0000-0000-000000000003'
\set mA  '24200000-0000-0000-0000-00000000000a'
\set mB  '24200000-0000-0000-0000-00000000000b'
\set mX  '24200000-0000-0000-0000-000000000099'
\set mV  '24200000-0000-0000-0000-000000000011'
\set mY  '24200000-0000-0000-0000-000000000098'
\set L   '24300000-0000-0000-0000-000000000001'

select pg_temp.som('');
insert into auth.users values (:'uA'), (:'uB'), (:'uF'), (:'uV'), (:'uG'), (:'uH');
insert into public.clubs (id, name, join_code) values
  (:'K', 'Klubben', 'KLUBBKODE1'), (:'K2', 'Veras klubb', 'VERAKODE22'), (:'K3', 'Importert', 'IMPORTKODE');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status) values
  (:'mA', :'K',  :'uA', 'Anne',      true,  'active'),
  (:'mB', :'K',  :'uB', 'Bo',        false, 'active'),
  (:'mX', :'K',  null,  'Kommissær', true,  'active'),
  (:'mV', :'K2', :'uV', 'Vera',      true,  'active'),
  (:'mY', :'K3', null,  'Sjefen',    true,  'active');
insert into public.courses (id, club_id, name) values (:'L', null, 'Losby');

-- === A. H1: ingen kobler en annens innlogging til et navn =====================
select pg_temp.som(:'uF'); set role authenticated;
select 'ok Frank lager sin egen klubb' from public.create_club('Franks klubb', 'Frank', null) c
 where c is not null;
select pg_temp.lik((select count(*)::int from public.club_members where user_id = :'uF' and is_organizer), 1,
                   'Frank er arrangør i sin egen klubb');
select pg_temp.feil(format($q$insert into public.club_members (club_id, user_id, display_name, status)
                              select club_id, %L, 'Vera', 'active' from public.club_members where user_id = %L$q$,
                           :'uV', :'uF'), '42501');
insert into public.club_members (club_id, display_name)
select club_id, 'Ledig' from public.club_members where user_id = :'uF'
returning 'ok arrangøren kan fortsatt lage ledige navn';
select pg_temp.feil(format($q$update public.club_members set user_id = %L where display_name = 'Ledig'$q$, :'uV'), '42501');
select pg_temp.lik(public.can_see_profile(:'uV'), false, 'Frank ser fortsatt ikke Veras profil');
reset role;

-- Arrangøren i K kan koble fra (tømme), men ikke koble til en annen.
select pg_temp.som(:'uA'); set role authenticated;
select pg_temp.feil(format($q$update public.club_members set user_id = %L where id = %L$q$, :'uV', :'mB'), '42501');
update public.club_members set user_id = null where id = :'mB' returning 'ok Anne kobler Bo fra navnet sitt';
reset role;
select pg_temp.som(''); update public.club_members set user_id = :'uB' where id = :'mB';

-- === B. H2: et ledig navn med rolle mister rollen når det tas =================
select pg_temp.som(:'uG'); set role authenticated;
select pg_temp.lik((public.join_club('KLUBBKODE1', :'mX', null, null) ->> 'status'), 'active',
                   'Gro tar det ledige kommissærnavnet i K');
select pg_temp.lik((select is_organizer from public.club_members where id = :'mX'), false,
                   'navnet mistet arrangørrollen (K har Anne)');
select pg_temp.lik(public.is_club_organizer(:'K'), false, 'Gro er ikke arrangør');
reset role;
-- Oppstart: K3 har ingen arrangør med innlogging. Den første beholder rollen.
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.lik((public.join_club('importkode', :'mY', null, null) ->> 'status'), 'active',
                   'Hans tar sjefsnavnet i K3');
select pg_temp.lik(public.is_club_organizer(:'K3'), true, 'K3 er ikke låst ute: Hans er arrangør');
reset role;
-- En spiller kan fortsatt ikke gi seg selv roller.
select pg_temp.som(:'uB'); set role authenticated;
select pg_temp.feil(format($q$update public.club_members set is_organizer = true where id = %L$q$, :'mB'), '42501');
update public.club_members set display_name = 'Bo B' where id = :'mB' returning 'ok Bo endrer sitt eget navn';
reset role;

-- === C. M1: invitasjonskoden ==================================================
select pg_temp.lik((select join_code ~ '^[2-9A-HJ-NP-Z]{12}$' from public.clubs c
                     join public.club_members m on m.club_id = c.id where m.user_id = :'uF'), true,
                   'ny klubb får 12 tegn uten 0/O/1/I');
select pg_temp.lik((select count(distinct public.club_join_code())::int from generate_series(1, 2000)), 2000,
                   '2000 koder, ingen like');
select pg_temp.lik((select bool_and(public.club_join_code() ~ '^[A-Z0-9]{6,16}$') from generate_series(1, 200)), true,
                   'koden passer clubs_join_code_check');

-- === D. M2: kvoter ============================================================
select pg_temp.som(:'uF'); set role authenticated;
-- Felles baner: 30 per døgn.
insert into public.courses (club_id, name) select null, 'Bane ' || g from generate_series(1, 30) g;
select 'ok Frank legger inn 30 felles baner';
select pg_temp.feil($q$insert into public.courses (club_id, name) values (null, 'Bane 31')$q$, '54000');
-- Løse runder: 50 per døgn.
insert into public.rounds (course_id, hole_count) select :'L', 9 from generate_series(1, 50);
select 'ok Frank lager 50 løse runder';
select pg_temp.feil(format($q$insert into public.rounds (course_id, hole_count) values (%L, 9)$q$, :'L'), '54000');
-- Deltakere: 48 per runde (Frank selv + 47 gjester).
select id as rr from public.rounds where owner_id = :'uF' order by created_at, id limit 1 \gset
insert into public.round_participants (round_id, display_name) select :'rr', 'Gjest ' || g from generate_series(1, 48) g;
select 'ok 48 deltakere i én runde';
select pg_temp.feil(format($q$insert into public.round_participants (round_id, display_name) values (%L, 'Nr 49')$q$, :'rr'), '54000');
-- Konkurranser uten klubb: 30 per døgn.
insert into public.competitions (kind, name, entry, rules)
select 'fun', 'Moro ' || g, 'open', '{"version": 1}' from generate_series(1, 30) g;
select 'ok Frank lager 30 konkurranser';
select pg_temp.feil($q$insert into public.competitions (kind, name, entry, rules) values ('fun', 'Moro 31', 'open', '{"version": 1}')$q$, '54000');
-- Klubber: 10 per døgn (Frank har én fra før).
select count(*) from (select public.create_club('Klubb ' || g, 'Frank', null) from generate_series(2, 10) g) x;
select 'ok Frank har 10 klubber';
select pg_temp.feil($q$select public.create_club('Klubb 11', 'Frank', null)$q$, '54000');
reset role;

-- Meldinger (60 per 10 min) og hendelser (200 per 10 min) i Franks første klubb.
select pg_temp.som('');
select m.club_id as kf, m.id as mf from public.club_members m join public.clubs c on c.id = m.club_id
 where m.user_id = :'uF' and c.name = 'Franks klubb' \gset
insert into public.events (id, club_id, event_date) values ('24400000-0000-0000-0000-000000000001', :'kf', '2026-10-08');
select pg_temp.som(:'uF'); set role authenticated;
insert into public.thread_messages (club_id, event_id, member_id, body)
select :'kf', '24400000-0000-0000-0000-000000000001', :'mf', 'Hei ' || g from generate_series(1, 60) g;
select 'ok 60 meldinger';
select pg_temp.feil(format($q$insert into public.thread_messages (club_id, event_id, member_id, body)
                              values (%L, '24400000-0000-0000-0000-000000000001', %L, 'Nr 61')$q$, :'kf', :'mf'), '54000');
insert into public.activity (club_id, kind, category) select :'kf', 'note', 'club' from generate_series(1, 200);
select 'ok 200 hendelser';
select pg_temp.feil(format($q$insert into public.activity (club_id, kind, category) values (%L, 'note', 'club')$q$, :'kf'), '54000');
reset role;
-- Andre i klubben K merker ingenting.
select pg_temp.som(:'uB'); set role authenticated;
insert into public.activity (club_id, kind, category) values (:'K', 'note', 'club') returning 'ok Bo kan fortsatt skrive en hendelse';
reset role;
-- SQL Editor, importen og serveren (auth.uid() tom) telles ikke.
select pg_temp.som('');
insert into public.courses (club_id, name, created_by_profile) values (null, 'Bane fra importen', null)
returning 'ok uten innlogging: ingen kvote';

-- === E. L2: standardrettigheter for nye objekter ==============================
begin;
create table public.ny_tabell_024 (id int);
create function public.ny_funksjon_024() returns int language sql as 'select 1';
select pg_temp.lik(has_table_privilege('anon', 'public.ny_tabell_024', 'select'), false, 'ny tabell: anon får ikke select');
select pg_temp.lik(has_table_privilege('authenticated', 'public.ny_tabell_024', 'select'), true,
                   'ny tabell: authenticated har standardrettigheten som før');
select pg_temp.lik(has_function_privilege('anon', 'public.ny_funksjon_024()', 'execute'), false, 'ny funksjon: anon kan ikke kjøre');
rollback;
select pg_temp.lik((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')), 0,
                   'ingen funksjon i public kan kjøres av anon');
select pg_temp.lik((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('guard_club_members', 'club_join_code', 'quota_guard')
                      and has_function_privilege('authenticated', p.oid, 'execute')), 0,
                   'authenticated kan ikke kjøre vakta, kodegeneratoren eller kvotene');
