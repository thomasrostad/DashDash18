\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 046_varsler.sql. Kjøres på kopien med 001–043, 034, 044, 045, 047,
-- lokal/046_for.sql (før 046) og 046 (to ganger). Alt rulles tilbake. Hver linje skal
-- starte med "ok"; ingen "FEIL".
--
-- A: gruppene dekker alle kategoriene (fra check-en på activity) og alle kind-ene.
-- X: klubbens push er som før: jobbene som fantes (mot lokal46.for_payload), og nye
--    jobber i en rikere verden (mot den gamle funksjonen, lokal46.push_job_payload_for).
--    round_started går ikke lenger i køen, alt annet gjør.
-- B: en gruppe av stopper bare den gruppen (Arrangør bare signup_dropped), ikke «Melding
--    til alle».
-- C: demping gjelder bare den kvelden (linjer på kvelden, via runden, tråden), ikke
--    «Melding til alle» og ikke andre kvelder.
-- D: ett «kvelden er i gang» per kveld.
-- E: turnering uten klubb: linja går i køen og mottakerne er turneringens.
-- F: notifications: push_log_result (bare service_role), RLS.
-- G: e-post til dem uten push.
-- H: tilgang: senderens funksjoner er stengt for appen og anon.
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
-- push_job_payload uten nøklene 046 la til (det som skal være likt med før).
create function pg_temp.gammel_form(p jsonb) returns jsonb language sql as $$
  select (p - 'group' - 'collapse' - 'event_id' - 'competition' - 'audience')
         || jsonb_build_object('members', (
              select coalesce(jsonb_agg(m - 'user_id' - 'disabled_groups' - 'email_fallback' - 'muted' - 'group_off'
                                        order by o), '[]'::jsonb)
                from jsonb_array_elements(p -> 'members') with ordinality as e (m, o)));
$$;
-- Ett medlem i svaret (id), og antall telefoner.
create function pg_temp.medlem(p_job bigint, p_id text) returns jsonb language sql as $$
  select m from jsonb_array_elements(public.push_job_payload(p_job) -> 'members') m where m ->> 'id' = p_id;
$$;
create function pg_temp.tlf(p_job bigint, p_id text) returns integer language sql as $$
  select jsonb_array_length(pg_temp.medlem(p_job, p_id) -> 'devices');
$$;
create function pg_temp.jobb(p_activity uuid) returns bigint language sql security definer as $$
  select id from public.push_queue where activity_id = p_activity;
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u5  '00000000-0000-0000-0000-000000000005'
\set u7  '00000000-0000-0000-0000-000000000007'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set E2  'eeeeeeee-0000-0000-0000-000000000002'
\set E3  'eeeeeeee-0000-0000-0000-000000000003'
\set E9  'eeeeeeee-0000-0000-0000-000000000009'
\set R2  'dddddddd-0000-0000-0000-000000000002'
\set R3  'dddddddd-0000-0000-0000-000000000003'
-- Nytt for prøven: kveld 5 med tre runder, turnering uten klubb, linjer.
\set E5  'eeeeeeee-0000-0000-0000-000000004605'
\set R51 'dddddddd-0000-0000-0000-000000004651'
\set R52 'dddddddd-0000-0000-0000-000000004652'
\set R53 'dddddddd-0000-0000-0000-000000004653'
\set FK  'c0000000-0000-0000-0000-0000000046f1'
\set a1  'a0460000-0000-0000-0000-000000000001'
\set a2  'a0460000-0000-0000-0000-000000000002'
\set a3  'a0460000-0000-0000-0000-000000000003'
\set a4  'a0460000-0000-0000-0000-000000000004'
\set a5  'a0460000-0000-0000-0000-000000000005'
\set a6  'a0460000-0000-0000-0000-000000000006'
\set a7  'a0460000-0000-0000-0000-000000000007'
\set a8  'a0460000-0000-0000-0000-000000000008'
\set a9  'a0460000-0000-0000-0000-000000000009'
\set a10 'a0460000-0000-0000-0000-000000000010'
\set a11 'a0460000-0000-0000-0000-000000000011'
\set a12 'a0460000-0000-0000-0000-000000000012'
\set t1  '70000000-0000-0000-0000-0000000046a1'

begin;

-- --- A: gruppene ---------------------------------------------------------------------
create temp table kategorier as
  select distinct (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as kategori
    from pg_constraint where conrelid = 'public.activity'::regclass and conname = 'activity_category_check';
insert into kategorier values ('thread');
grant select on kategorier to public;
select pg_temp.lik((select count(*) from kategorier), 14::bigint, 'A1 13 kategorier i activity-check-en, pluss tråden');
select pg_temp.lik((select count(*) from kategorier where public.push_group(kategori) is null), 0::bigint,
                   'A2 hver kategori har en gruppe');
select pg_temp.lik((select count(*) from unnest(public.push_player_categories() || public.push_club_categories()) c
                     where public.push_group(c) is null), 0::bigint, 'A3 hver push-kategori (010) har en gruppe');
select pg_temp.lik((select string_agg(kategori || '=' || public.push_group(kategori), ' ' order by kategori) from kategorier),
                   'announcement=evening bet=game club=social lead=game nudge=evening reminder=evening round=game '
                   'score=game setup=evening side_prize=game signup=evening social=social thread=social tips=game',
                   'A4 kartet per kategori');
select pg_temp.lik((select count(*) from unnest(array[
                      'round_started', 'round_locked', 'round_deleted', 'big_score', 'lead_changed', 'side_prize',
                      'score_corrected', 'signup', 'nudge', 'reminder', 'announcement', 'committee_drawn',
                      'member_joined', 'tips_king', 'bet_created', 'bet_challenge', 'bet_resolved', 'table_changed',
                      'waitlist_promoted', 'signup_dropped']) k
                     where not exists (select 1 from public.push_group_map() m where m.kind = k)), 0::bigint,
                   'A5 alle appens kjente kind (ActivityEvent.knownKinds) står i kartet');
select pg_temp.lik((select count(*) >= 22 from public.push_group_map()), true, 'A6 minst 22 rader i kartet (20 + evening_started + tråden; senere migreringer legger til)');
select pg_temp.lik((select count(*) from public.push_group_map() where not (group_key = any (public.push_groups()))
                     or not exists (select 1 from kategorier where kategori = category)), 0::bigint,
                   'A7 kartet har bare kjente grupper og kategorier');
select pg_temp.lik((select string_agg(kind, ',' order by kind) from public.push_group_map() where group_key = 'organizer'),
                   'signup_dropped', 'A8 Arrangør: signup_dropped');
select pg_temp.lik(public.push_group('round', 'evening_started') || '/' || public.push_group('signup', 'signup')
                   || '/' || public.push_group('signup', 'signup_dropped') || '/' || public.push_group('round', 'round_started'),
                   'evening/evening/organizer/game', 'A9 kind går foran kategorien');
select pg_temp.lik((select count(*) from public.activity a where public.push_group(a.category, a.kind) is null), 0::bigint,
                   'A10 alle linjene i testdataene har en gruppe');
select pg_temp.lik(public.push_group('ukjent'), null::text, 'A11 ukjent kategori gir ingen gruppe');

-- --- X1 før verdenen endres: jobbene som fantes, mot svaret før 046 -------------------
select pg_temp.lik((select count(*) from lokal46.for_payload f
                     where pg_temp.gammel_form(public.push_job_payload(f.job_id)) is distinct from f.payload), 0::bigint,
                   'X1 de ' || (select count(*) from lokal46.for_payload) || ' jobbene som fantes: samme svar som før 046 (uten de nye nøklene)');

-- --- Verdenen ------------------------------------------------------------------------
select pg_temp.som('');
alter table auth.users add column if not exists email text;
update auth.users set email = 'bruker' || right(id::text, 1) || '@eksempel.no';
insert into public.push_devices (user_id, device_id, token, environment) values
  (:'u1', 'tlf-thomas', repeat('a1', 32), 'production'),
  (:'u2', 'tlf-anders', repeat('b2', 32), 'sandbox'),
  (:'u4', 'tlf-ola', repeat('c4', 32), 'production'),
  (:'u7', 'tlf-siv', repeat('d7', 32), 'production');
-- Bjørn (u3) har ingen telefon (e-post, del G). Anders har slått av store scorer og vil ha hele tråden.
insert into public.push_preferences (member_id, club_id, disabled_categories, thread_mode)
values (:'m2', :'G', '{score}', 'all');
-- Kveld 5 i Golfgutu med to runder i pulje 1 og én i pulje 2.
insert into public.events (id, club_id, event_date) values (:'E5', :'G', '2026-11-05');
insert into public.rounds (id, club_id, event_id, round_no, status, wave_no) values
  (:'R51', :'G', :'E5', 1, 'draft', 1), (:'R52', :'G', :'E5', 2, 'draft', 1), (:'R53', :'G', :'E5', 3, 'draft', 2);
-- Nye linjer i klubben (som systemet, ingen innlogging).
insert into public.activity (id, club_id, kind, category, data, actor_member_id, event_id, round_id, recipients, created_at) values
  (:'a1', :'G', 'big_score', 'score', '{"member": "11111111-0000-0000-0000-000000000003", "hole": 5, "hole_index": 4, "name": "eagle", "strokes": 3, "par": 5}', :'m1', null, :'R3', null, now()),
  (:'a2', :'G', 'signup', 'signup', '{"member": "11111111-0000-0000-0000-000000000002", "status": "yes", "event_date": "2026-10-01"}', :'m2', :'E3', null, null, now()),
  (:'a3', :'G', 'announcement', 'announcement', '{"text": "Husk jakka"}', :'m1', :'E3', null, null, now()),
  (:'a4', :'G', 'nudge', 'nudge', '{"event_date": "2026-10-01"}', :'m1', :'E3', null, array[:'m3']::uuid[], now()),
  (:'a5', :'G', 'member_joined', 'club', '{"member": "11111111-0000-0000-0000-000000000002"}', null, null, null, null, now()),
  (:'a6', :'G', 'bet_created', 'bet', '{"question": "Birdie på 18?", "side": "yes", "points": 10}', :'m2', :'E3', :'R3', null, now()),
  (:'a7', :'G', 'signup_dropped', 'signup', '{"member": "11111111-0000-0000-0000-000000000002", "event_date": "2026-10-01"}', :'m2', :'E3', null, array[:'m1', :'m3']::uuid[], now()),
  (:'a8', :'G', 'reminder', 'reminder', '{"event_date": "2026-10-01", "coming": 3}', null, :'E3', null, null, now()),
  (:'a9', :'G', 'side_prize', 'side_prize', '{"kind": "drive", "member": "11111111-0000-0000-0000-000000000001", "hole": 7, "meters": 250}', :'m1', :'E2', :'R2', null, now()),
  (:'a10', :'G', 'round_started', 'round', '{"round_no": 1}', :'m1', null, :'R3', null, now());
insert into public.thread_messages (id, club_id, event_id, member_id, body) values (:'t1', :'G', :'E3', :'m1', 'Hei alle');

-- --- X: klubbens push er som før -----------------------------------------------------
select pg_temp.lik((select count(*) from public.push_queue q
                     where q.club_id is not null
                       and pg_temp.gammel_form(public.push_job_payload(q.id)) is distinct from lokal46.push_job_payload_for(q.id)),
                   0::bigint,
                   'X2 alle ' || (select count(*) from public.push_queue where club_id is not null)
                   || ' klubbjobbene i den rikere verdenen (telefoner, valg, nye linjer, tråd): som den gamle funksjonen');
select pg_temp.lik((select count(*) from public.push_queue q where q.activity_id in
                      (:'a1', :'a2', :'a3', :'a4', :'a5', :'a6', :'a7', :'a8', :'a9')), 9::bigint,
                   'X3 de ni nye linjene gikk i køen');
select pg_temp.lik(pg_temp.jobb(:'a10'), null::bigint, 'X4 round_started går ikke lenger i køen');
select pg_temp.lik((select count(*) from public.activity where id = :'a10'), 1::bigint, 'X5 round_started står i aktiviteten (Hjem og Varsler)');
select pg_temp.lik((select count(*) from public.push_queue where thread_message_id = :'t1'), 1::bigint, 'X6 trådmeldingen gikk i køen');
select pg_temp.lik((select count(*) from lokal46.for_queue f
                     where not exists (select 1 from public.push_queue q where q.id = f.job_id
                                         and q.activity_id is not distinct from f.activity_id
                                         and q.club_id = f.club_id)), 0::bigint, 'X7 køen fra før står uendret');
select pg_temp.lik(public.push_job_payload(pg_temp.jobb(:'a1')) ->> 'collapse',
                   'event-' || :'E3' || '-game', 'X8 collapse for en linje på kvelden (via runden)');
select pg_temp.lik(public.push_job_payload(pg_temp.jobb(:'a5')) ->> 'collapse', null::text, 'X9 ingen collapse uten kveld');
select pg_temp.lik(public.push_job_payload((select id from public.push_queue where thread_message_id = :'t1')) ->> 'collapse',
                   null::text, 'X10 ingen collapse for tråden');
select pg_temp.lik(public.push_job_payload(pg_temp.jobb(:'a1')) ->> 'audience', 'club', 'X11 klubbjobb: audience club');

-- --- B: grupper av -------------------------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.push_set_groups(array['game']), 1, 'B1 Anders slår av Spillet (ett medlemskap)');
select pg_temp.lik((select disabled_groups::text || '|' || email_fallback || '|' || disabled_categories::text || '|' || thread_mode
                      from public.push_preferences where member_id = :'m2'), '{game}|true|{score}|all',
                   'B2 lagret, kategoriene og tråden står');
select pg_temp.feil('select public.push_set_groups(array[''tull''])', '22023');
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a6'), :'m2') || '|' || (pg_temp.medlem(pg_temp.jobb(:'a6'), :'m2') ->> 'group_off'),
                   '0|true', 'B3 Spillet av: ingen telefon for veddemålet (game), group_off');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a6'), :'m1'), 1, 'B4 Thomas får veddemålet');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a2'), :'m2'), 1, 'B5 Anders får fortsatt Kvelden (påmelding)');
select pg_temp.lik(pg_temp.tlf((select id from public.push_queue where thread_message_id = :'t1'), :'m2'), 1,
                   'B6 og tråden (Sosialt)');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.push_set_groups(array['evening', 'social'], false), 1, 'B7 Anders slår av Kvelden og Sosialt, og e-post');
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a2'), :'m2'), 0, 'B8 Kvelden av: ingen påmelding');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a3'), :'m2') || '|' || (pg_temp.medlem(pg_temp.jobb(:'a3'), :'m2') ->> 'group_off'),
                   '1|false', 'B9 «Melding til alle» kommer likevel');
select pg_temp.lik(pg_temp.tlf((select id from public.push_queue where thread_message_id = :'t1'), :'m2'), 0,
                   'B10 Sosialt av: ingen tråd, selv med thread_mode all');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a6'), :'m2'), 1, 'B11 Spillet er på igjen');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.push_set_groups('{}') || '|' || (select email_fallback from public.push_preferences where member_id = :'m2'),
                   '1|false', 'B12 null for e-post lar valget stå');
select pg_temp.lik((select count(*) from public.push_preferences), 1::bigint, 'B13 Anders ser bare sin egen rad');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.push_set_groups(array['organizer']), 1, 'B14 Thomas slår av Arrangør');
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a7'), :'m1'), 0, 'B15 Arrangør av: ingen signup_dropped');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a2'), :'m1'), 1, 'B16 men vanlig påmelding (samme kategori) kommer');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a7'), :'m3'), 0, 'B17 (Bjørn har ingen telefon)');
select pg_temp.som(:'u1'); set role authenticated;
select public.push_set_groups('{}') is not null;
reset role;
set role anon;
select pg_temp.feil('select public.push_set_groups(''{}'')', '42501');
reset role;

-- --- C: demping av én kveld ----------------------------------------------------------
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.push_mute_event(%L, true)', :'E3'), 'P0002');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.push_mute_event(:'E3', true), true, 'C1 Thomas demper kveld 3');
select pg_temp.lik(public.push_mute_event(:'E3', true), true, 'C2 to ganger går (idempotent)');
select pg_temp.lik((select count(*) from public.push_event_mutes), 1::bigint, 'C3 Thomas ser sin rad');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.push_event_mutes), 0::bigint, 'C4 Anders ser ikke Thomas sin demping');
select pg_temp.feil(format('insert into public.push_event_mutes (user_id, event_id) values (%L, %L)', :'u2', :'E3'), '42501');
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a2'), :'m1') || '|' || (pg_temp.medlem(pg_temp.jobb(:'a2'), :'m1') ->> 'muted'),
                   '0|true', 'C5 dempet: ingen påmelding på kveld 3');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a1'), :'m2'), 1, 'C6 (Anders får eagle-en på kveld 3)');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a6'), :'m1'), 0, 'C7 dempet: heller ikke linja med både kveld og runde');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a1'), :'m3') is null or pg_temp.tlf(pg_temp.jobb(:'a1'), :'m3') = 0, true,
                   'C8 (Bjørn har ingen telefon)');
select pg_temp.lik(pg_temp.medlem(pg_temp.jobb(:'a1'), :'m1') ->> 'muted', 'true', 'C9 dempet: linja med bare runden (kveld via runden)');
select pg_temp.lik(pg_temp.tlf((select id from public.push_queue where thread_message_id = :'t1'), :'m1') || '|'
                   || (pg_temp.medlem((select id from public.push_queue where thread_message_id = :'t1'), :'m1') ->> 'muted'),
                   '0|true', 'C10 dempet: kveldens tråd');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a3'), :'m1'), 1, 'C11 «Melding til alle» på kvelden kommer likevel');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a9'), :'m1') || '|' || (pg_temp.medlem(pg_temp.jobb(:'a9'), :'m1') ->> 'muted'),
                   '1|false', 'C12 en annen kveld (kveld 2) er ikke dempet');
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a5'), :'m1'), 1, 'C13 linje uten kveld er ikke dempet');
select pg_temp.lik((select count(*) from lokal46.for_payload f
                     where pg_temp.gammel_form(public.push_job_payload(f.job_id)) is distinct from lokal46.push_job_payload_for(f.job_id)
                       and (public.push_job_payload(f.job_id) ->> 'event_id') is distinct from :'E3'), 0::bigint,
                   'C14 jobbene fra før på andre kvelder er uendret');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.push_mute_event(:'E3', false), false, 'C15 Thomas slår kvelden på igjen');
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a2'), :'m1'), 1, 'C16 påmeldingen kommer igjen');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.push_mute_event(%L, true)', :'E9'), 'P0002');
select pg_temp.feil(format('select public.push_mute_event(%L, null)', :'E3'), '22023');
reset role;
set role anon;
select pg_temp.feil(format('select public.push_mute_event(%L, true)', :'E3'), '42501');
reset role;

-- --- D: ett «kvelden er i gang» ------------------------------------------------------
select pg_temp.lik((select count(*) from public.activity where kind = 'evening_started'), 0::bigint,
                   'D1 ingen evening_started i testdataene (ingen lages for kvelder som alt går)');
select pg_temp.som(:'u1'); set role authenticated;
update public.rounds set status = 'active' where id = :'R51';
reset role;
select pg_temp.lik((select count(*) from public.activity where kind = 'evening_started' and event_id = :'E5'), 1::bigint,
                   'D2 første runde startet: én evening_started');
select pg_temp.lik((select category || '|' || round_id || '|' || actor_member_id || '|' || (data ->> 'event_date') || '|' || (data ->> 'round_no')
                      from public.activity where kind = 'evening_started'),
                   'round|' || :'R51' || '|' || :'m1' || '|2026-11-05|1', 'D3 kategori round, runden, Thomas, datoen');
select pg_temp.lik((select public.push_job_payload(q.id) ->> 'group' || '|' || (public.push_job_payload(q.id) ->> 'collapse')
                      from public.push_queue q join public.activity a on a.id = q.activity_id where a.kind = 'evening_started'),
                   'evening|event-' || :'E5' || '-evening', 'D4 i køen, gruppe Kvelden, collapse per kveld');
select pg_temp.lik((select pg_temp.tlf(q.id, :'m1') || '|' || pg_temp.tlf(q.id, :'m2')
                      from public.push_queue q join public.activity a on a.id = q.activity_id where a.kind = 'evening_started'),
                   '1|1', 'D5 begge med telefon står i svaret (push-send hopper over Thomas som startet)');
select pg_temp.som(:'u1'); set role authenticated;
insert into public.activity (club_id, kind, category, data, round_id) values (:'G', 'round_started', 'round', '{"round_no": 1}', :'R51');
update public.rounds set status = 'active' where id = :'R53';
update public.rounds set status = 'locked' where id = :'R51';
update public.rounds set status = 'active' where id = :'R52';
reset role;
select pg_temp.lik((select count(*) from public.activity where kind = 'evening_started' and event_id = :'E5'), 1::bigint,
                   'D6 pulje 2 og runde 2 samme kveld: fortsatt én');
select pg_temp.lik((select count(*) from public.activity a join public.push_queue q on q.activity_id = a.id
                     where a.kind = 'round_started' and a.round_id = :'R51'), 0::bigint, 'D7 round_started fra appen: ikke i køen');
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind in ('evening_started', 'round_started') and round_id = :'R51'),
                   2::bigint, 'D8 Anders ser begge i aktiviteten');
reset role;
select pg_temp.feil(format('insert into public.activity (club_id, kind, category, event_id) values (%L, ''evening_started'', ''round'', %L)',
                           :'G', :'E5'), '23505');
-- En kveld som alt hadde en runde i gang før 046 (kveld 3: runde 1 aktiv), gir ingen når runde 1 låses.
update public.rounds set status = 'locked' where id = :'R3';
select pg_temp.lik((select count(*) from public.activity where kind = 'evening_started' and event_id = :'E3'), 0::bigint,
                   'D9 kveld 3 (startet før 046): ingen ny linje');

-- --- E: turnering uten klubb ---------------------------------------------------------
select pg_temp.som('');
insert into public.competitions (id, kind, name, club_id, owner_id, status, entry)
values (:'FK', 'fun', 'Vennecup 46', null, :'u1', 'active', 'listed');
insert into public.competition_participants (competition_id, profile_id) values (:'FK', :'u2'), (:'FK', :'u3');
insert into public.competition_staff (competition_id, profile_id, role) values (:'FK', :'u4', 'scorer');
insert into public.activity (id, club_id, competition_id, kind, category, data, created_at)
values (:'a11', null, :'FK', 'table_changed', 'round',
        jsonb_build_object('competition', :'FK', 'competition_name', 'Vennecup 46',
                           'table', jsonb_build_array(jsonb_build_object('member', :'u2', 'place', 1))), now());
select pg_temp.lik((select coalesce(club_id::text, '-') || '|' || competition_id from public.push_queue where activity_id = :'a11'),
                   '-|' || :'FK', 'E1 linja uten klubb gikk i køen med turneringen');
select pg_temp.lik((select string_agg(m ->> 'id', ',' order by m ->> 'id')
                      from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'a11')) -> 'members') m),
                   :'u1' || ',' || :'u2' || ',' || :'u3' || ',' || :'u4',
                   'E2 mottakerne: eier, deltakerne og staben (profil-id), ikke Siv');
select pg_temp.lik((select string_agg((m ->> 'is_organizer') || '/' || jsonb_array_length(m -> 'devices'), ',' order by m ->> 'id')
                      from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'a11')) -> 'members') m),
                   'true/1,false/1,false/0,false/1', 'E3 eieren er arrangør, føreren ikke; telefonene');
select pg_temp.lik((select p ->> 'audience' || '|' || (p -> 'club' ->> 'name') || '|' || coalesce(p -> 'club' ->> 'id', '-')
                           || '|' || (p -> 'competition' ->> 'id') || '|' || coalesce(p ->> 'collapse', '-')
                      from public.push_job_payload(pg_temp.jobb(:'a11')) p),
                   'competition|Vennecup 46|-|' || :'FK' || '|-', 'E4 audience, navnet i club, turneringen');
select pg_temp.som(:'u2'); set role authenticated;
select public.push_set_groups(array['game']) is not null;
reset role;
select pg_temp.lik(pg_temp.tlf(pg_temp.jobb(:'a11'), :'u2'), 0, 'E5 gruppene virker også uten klubb (Anders: Spillet av)');
select pg_temp.som(:'u2'); set role authenticated;
select public.push_set_groups('{}') is not null;
reset role;
-- entry = 'club': klubbens aktive medlemmer med innlogging (Sesong 2026: Thomas, Anders, Bjørn).
select pg_temp.lik((select string_agg(user_id::text, ',' order by user_id) from private.push_competition_audience(:'S26')),
                   :'u1' || ',' || :'u2' || ',' || :'u3', 'E6 entry club: klubbens aktive medlemmer');
select pg_temp.lik((select count(*) from public.push_queue where club_id is null and competition_id is null), 0::bigint,
                   'E7 hver jobb har klubb eller turnering');
select pg_temp.feil('insert into public.push_queue (activity_id) values (null)', '23514');

-- --- F: logg per mottaker ------------------------------------------------------------
set role service_role;
select pg_temp.lik(public.push_log_result(pg_temp.jobb(:'a2'), jsonb_build_array(
                     jsonb_build_object('member_id', :'m1', 'status', 'failed', 'reason', '500'),
                     jsonb_build_object('member_id', :'m1', 'status', 'sent'),
                     jsonb_build_object('member_id', :'m2', 'status', 'skipped', 'reason', 'group_off'),
                     jsonb_build_object('user_id', :'u3', 'channel', 'email', 'status', 'sent'),
                     jsonb_build_object('member_id', '11111111-0000-0000-0000-000000000009', 'status', 'skipped'))),
                   3, 'F1 tre rader: Thomas (to telefoner blir én), Anders, Bjørn på e-post; Carl uten innlogging hoppes over');
select pg_temp.lik((select string_agg(user_id || ':' || channel || ':' || status || ':' || (sent_at is not null), ',' order by user_id)
                      from public.notifications where activity_id = :'a2'),
                   :'u1' || ':push:sent:true,' || :'u2' || ':push:skipped:false,' || :'u3' || ':email:sent:true',
                   'F2 sent vinner over failed, sent_at satt');
select pg_temp.lik(public.push_log_result(pg_temp.jobb(:'a2'), jsonb_build_array(
                     jsonb_build_object('member_id', :'m1', 'status', 'failed'),
                     jsonb_build_object('member_id', :'m2', 'status', 'sent'))), 2, 'F3 ny runde på samme jobb');
select pg_temp.lik((select string_agg(status, ',' order by user_id) from public.notifications where activity_id = :'a2' and channel = 'push'),
                   'sent,sent', 'F4 sent står, skipped blir sent');
select pg_temp.feil(format('select public.push_log_result(%s, ''[{"user_id": "%s", "status": "tull"}]'')',
                           pg_temp.jobb(:'a2'), :'u1'), '23514');
select pg_temp.feil('select public.push_log_result(-1, ''[]'')', 'P0002');
select pg_temp.feil(format('select public.push_log_result(%s, ''{}'')', pg_temp.jobb(:'a2')), '22023');
select public.push_log_result((select id from public.push_queue where thread_message_id = :'t1'),
                              jsonb_build_array(jsonb_build_object('member_id', :'m2', 'status', 'sent'))) = 1;
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select string_agg(user_id::text, ',') from public.notifications), :'u1', 'F5 Thomas leser bare sine rader');
select pg_temp.feil(format('insert into public.notifications (user_id, activity_id, channel, status) values (%L, %L, ''push'', ''sent'')',
                           :'u1', :'a2'), '42501');
select pg_temp.feil('update public.notifications set status = ''failed''', '42501');
select pg_temp.feil(format('select public.push_log_result(%s, ''[]'')', pg_temp.jobb(:'a2')), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.notifications), 2::bigint, 'F6 Anders leser sine to (linja og tråden)');
reset role;
set role anon;
select pg_temp.feil('select count(*) from public.notifications', '42501');
select pg_temp.feil(format('select public.push_log_result(%s, ''[]'')', pg_temp.jobb(:'a2')), '42501');
reset role;

-- --- G: e-post til dem uten push -----------------------------------------------------
set role service_role;
select pg_temp.lik((select string_agg(user_id || '/' || member_id || '/' || email, ',') from public.push_email_recipients(pg_temp.jobb(:'a8'))),
                   :'u3' || '/' || :'m3' || '/bruker3@eksempel.no',
                   'G1 påminnelsen: bare Bjørn (aktiv, innlogget, uten telefon); ikke Dag (venter) eller Carl (uten innlogging)');
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'a1'))), 0::bigint, 'G2 ingen e-post for en eagle');
select pg_temp.lik((select count(*) from public.push_email_recipients((select id from public.push_queue where thread_message_id = :'t1'))),
                   0::bigint, 'G3 ingen e-post for tråden');
select pg_temp.lik((select string_agg(user_id::text, ',') from public.push_email_recipients(pg_temp.jobb(:'a4'))), :'u3',
                   'G4 purringen (mottakerlista: Bjørn) går til Bjørn');
select pg_temp.lik((select string_agg(user_id::text, ',') from public.push_email_recipients(pg_temp.jobb(:'a3'))), :'u3',
                   'G5 «Melding til alle»: Bjørn, ikke Thomas som skrev den');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select public.push_mute_event(:'E3', true);
reset role;
set role service_role;
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'a8'))), 0::bigint, 'G6 dempet kveld: ingen e-post');
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'a3'))), 1::bigint, 'G7 men «Melding til alle» kommer');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select public.push_mute_event(:'E3', false) = false;
select public.push_set_groups('{}', false) is not null;
reset role;
set role service_role;
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'a8'))), 0::bigint, 'G8 e-post av: ingen');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select public.push_set_groups('{}', true) is not null;
reset role;
set role service_role;
select public.push_log_result(pg_temp.jobb(:'a8'), jsonb_build_array(jsonb_build_object('user_id', :'u3', 'channel', 'email', 'status', 'sent'))) = 1;
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'a8'))), 0::bigint, 'G9 sendt én gang: ikke igjen');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select * from public.push_email_recipients(%s)', pg_temp.jobb(:'a8')), '42501');
reset role;
set role anon;
select pg_temp.feil(format('select * from public.push_email_recipients(%s)', pg_temp.jobb(:'a8')), '42501');
reset role;

-- --- H: tilgang ----------------------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.push_job_payload(%s)', pg_temp.jobb(:'a8')), '42501');
select pg_temp.feil('select * from public.claim_push_jobs(1)', '42501');
select pg_temp.lik((select count(*) >= 22 from public.push_group_map()), true, 'H1 appen kan lese kartet');
reset role;
set role anon;
select pg_temp.feil(format('select public.push_job_payload(%s)', pg_temp.jobb(:'a8')), '42501');
select pg_temp.feil('select * from public.push_group_map()', '42501');
select pg_temp.feil('select count(*) from public.push_event_mutes', '42501');
reset role;
select pg_temp.lik((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public'
                       and p.proname in ('push_job_payload', 'push_log_result', 'push_email_recipients', 'claim_push_jobs', 'finish_push_job')
                       and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
                   0::bigint, 'H2 senderens fem funksjoner: verken anon eller authenticated');

rollback;
