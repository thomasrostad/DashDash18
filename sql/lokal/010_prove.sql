\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 010_push.sql mot en lokal, midlertidig Postgres med
-- lokal/stub.sql og lokal/stub_storage.sql, etter 001, 008 og 010. Kjøres i
-- en tom base. Hver resultatlinje skal starte med "ok"; ingen "FEIL".
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

-- === Oppsett ================================================================
-- u1 Thomas (arrangør), u2 Anders (to klubber), u3 Bjørn, u4 Ola (annen klubb).
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004');

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set ledig   '11111111-0000-0000-0000-000000000009'
\set ola     '22222222-0000-0000-0000-000000000004'
\set anders2 '22222222-0000-0000-0000-000000000002'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'

insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status) values
  (:'thomas',  :'klubb',  :'u1', 'Thomas', true,  'active'),
  (:'anders',  :'klubb',  :'u2', 'Anders', false, 'active'),
  (:'bjorn',   :'klubb',  :'u3', 'Bjørn',  false, 'active'),
  (:'ledig',   :'klubb',  null,  'Carl',   false, 'active'),
  (:'ola',     :'klubb2', :'u4', 'Ola',    true,  'active'),
  (:'anders2', :'klubb2', :'u2', 'Anders', false, 'active');
insert into public.events (club_id, event_date, start_time) values
  (:'klubb', (now() at time zone 'Europe/Oslo')::date + 7, '17:00') returning id as uke \gset
insert into public.signups (event_id, member_id, club_id, status) values
  (:'uke', :'anders', :'klubb', 'yes'), (:'uke', :'bjorn', :'klubb', 'maybe'), (:'uke', :'thomas', :'klubb', 'yes');
insert into public.rounds (club_id, event_id, status) values (:'klubb', :'uke', 'draft') returning id as kladd \gset

-- === anon ===================================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.push_devices$$, '42501');
select pg_temp.feil($$select * from public.push_preferences$$, '42501');
select pg_temp.feil($$select * from public.push_queue$$, '42501');
select pg_temp.feil($$select * from public.register_push_device('d', repeat('a', 64), 'sandbox')$$, '42501');
select pg_temp.feil($$select public.unregister_push_device('d')$$, '42501');
select pg_temp.feil($$select * from public.push_status('$$ || :'klubb' || $$')$$, '42501');
select pg_temp.feil($$select * from public.claim_push_jobs(5)$$, '42501');
reset role;

-- === Enheter ================================================================
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-A', upper(repeat('ab', 32)), 'sandbox', 'no.dashdash18.app')), 1::bigint,
                   'Anders registrerer telefonen (én rad, uansett antall klubber)');
select pg_temp.lik((select token from public.push_devices), repeat('ab', 32), 'tokenet lagres med små bokstaver');
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-A', repeat('ab', 32), 'production')), 1::bigint,
                   'registrering er idempotent');
select pg_temp.lik((select environment from public.push_devices), 'production', 'miljøet oppdateres');
select pg_temp.feil($$select * from public.register_push_device('ENHET-A', 'ikke-heks', 'sandbox')$$, '22023');
select pg_temp.feil($$select * from public.register_push_device('ENHET-A', repeat('ab', 32), 'dev')$$, '22023');
select pg_temp.feil($$select * from public.register_push_device('', repeat('ab', 32), 'sandbox')$$, '22023');
select pg_temp.feil($$select * from public.register_push_device('ENHET-A', repeat('ab', 32), 'sandbox', 'ugyldig bundle!')$$, '22023');
select pg_temp.feil($$insert into public.push_devices (user_id, device_id, token, environment) values (auth.uid(), 'x', repeat('cd', 32), 'sandbox')$$, '42501');
select pg_temp.feil($$update public.push_devices set token = repeat('cd', 32)$$, '42501');
select pg_temp.feil($$delete from public.push_devices$$, '42501');
select pg_temp.feil($$select * from public.push_queue$$, '42501');
select pg_temp.feil($$select * from public.claim_push_jobs(5)$$, '42501');
select pg_temp.feil($$select public.push_job_payload(1)$$, '42501');
select pg_temp.feil($$select public.finish_push_job(1, true)$$, '42501');
select pg_temp.feil($$select public.queue_evening_reminders(7)$$, '42501');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select count(*) from public.push_devices), 0::bigint, 'Bjørn ser ikke Anders sin telefon');
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-A', repeat('ef', 32), 'production')), 1::bigint,
                   'Bjørn logger inn på samme telefon og tar den over');
reset role;

select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik((select count(*) from public.push_devices), 0::bigint, 'Anders mistet telefonen som byttet eier');
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-B', repeat('12', 32), 'sandbox')), 1::bigint, 'ny telefon');
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-C', repeat('12', 32), 'sandbox')), 1::bigint, 'samme token, ny enhets-id');
select pg_temp.lik((select string_agg(device_id, ',') from public.push_devices), 'ENHET-C', 'den gamle enhets-id-en er ryddet bort');
select pg_temp.lik(public.unregister_push_device('ENHET-A'), 0, 'kan ikke avregistrere andres telefon');
select pg_temp.lik(public.unregister_push_device('ENHET-C'), 1, 'logg ut: egen telefon avregistreres');
select pg_temp.lik((select count(*) from public.register_push_device('ENHET-C', repeat('12', 32), 'sandbox')), 1::bigint, 'registrert igjen');
reset role;

-- === Valg per spiller ======================================================
select pg_temp.som(:'u2');
set role authenticated;
insert into public.push_preferences (member_id, club_id, disabled_categories, thread_mode)
  values (:'anders', :'klubb', array['setup', 'signup'], 'all');
select pg_temp.lik((select thread_mode from public.push_preferences where member_id = :'anders'), 'all', 'egne valg lagres');
update public.push_preferences set disabled_categories = array['score'] where member_id = :'anders';
select pg_temp.lik((select disabled_categories from public.push_preferences where member_id = :'anders'), array['score'], 'egne valg endres');
select pg_temp.feil($$update public.push_preferences set disabled_categories = array['announcement'] where member_id = '$$ || :'anders' || $$'$$, '23514');
select pg_temp.feil($$update public.push_preferences set thread_mode = 'noen' where member_id = '$$ || :'anders' || $$'$$, '23514');
select pg_temp.feil($$insert into public.push_preferences (member_id, club_id) values ('$$ || :'bjorn' || $$', '$$ || :'klubb' || $$')$$, '42501');
select pg_temp.feil($$insert into public.push_preferences (member_id, club_id) values ('$$ || :'anders2' || $$', '$$ || :'klubb' || $$')$$, '23503');
insert into public.push_preferences (member_id, club_id, thread_mode) values (:'anders2', :'klubb2', 'off');
select pg_temp.lik((select count(*) from public.push_preferences), 2::bigint, 'ett valg per medlemskap');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select count(*) from public.push_preferences), 0::bigint, 'Bjørn ser ikke Anders sine valg');
with u as (update public.push_preferences set thread_mode = 'off' returning 1)
select pg_temp.lik((select count(*) from u), 0::bigint, 'Bjørn kan ikke endre Anders sine valg');
reset role;

-- === Klubbens valg ==========================================================
select pg_temp.som(:'u1');
set role authenticated;
update public.clubs set push_disabled_categories = array['setup', 'thread'] where id = :'klubb';
select pg_temp.lik((select push_disabled_categories from public.clubs where id = :'klubb'), array['setup', 'thread'], 'arrangøren slår av for klubben');
select pg_temp.feil($$update public.clubs set push_disabled_categories = array['nudge'] where id = '$$ || :'klubb' || $$'$$, '23514');
select pg_temp.feil($$update public.clubs set push_disabled_categories = array['announcement'] where id = '$$ || :'klubb' || $$'$$, '23514');
update public.clubs set push_disabled_categories = array['setup'] where id = :'klubb';
select pg_temp.lik((select count(*)::int from public.push_status(:'klubb')), 4, 'push_status: alle aktive i klubben');
select pg_temp.lik((select devices from public.push_status(:'klubb') where member_id = :'anders'), 1, 'push_status: Anders har én telefon');
select pg_temp.lik((select has_login from public.push_status(:'klubb') where member_id = :'ledig'), false, 'push_status: ledig navn uten innlogging');
reset role;

select pg_temp.som(:'u2');
set role authenticated;
with u as (update public.clubs set push_disabled_categories = '{}' where id = :'klubb' returning 1)
select pg_temp.lik((select count(*) from u), 0::bigint, 'spiller kan ikke endre klubbens valg');
select pg_temp.lik((select push_disabled_categories from public.clubs where id = :'klubb'), array['setup'], 'spiller leser klubbens valg');
select pg_temp.feil($$select * from public.push_status('$$ || :'klubb' || $$')$$, '42501');
reset role;

-- === Køen ===================================================================
select pg_temp.som(:'u2');
set role authenticated;
insert into public.activity (club_id, kind, category, data)
  values (:'klubb', 'big_score', 'score', '{"hole": 5}') returning id as eagle \gset
insert into public.activity (club_id, kind, category, round_id)
  values (:'klubb', 'round_started', 'round', :'kladd');
insert into public.thread_messages (club_id, event_id, member_id, body, mentions)
  values (:'klubb', :'uke', :'anders', 'Hei @Bjørn', array[:'bjorn']::uuid[]) returning id as melding \gset
reset role;

-- Senderen (service_role) har ingen innlogging: auth.uid() er null.
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.push_queue), 2::bigint, 'linja og meldingen er i køen (ikke kladden)');
select pg_temp.lik((select count(*) from public.push_queue where activity_id = :'eagle'), 1::bigint, 'eaglen er i køen');

set role service_role;
select pg_temp.lik((select count(*) from public.claim_push_jobs(10)), 2::bigint, 'senderen tar begge jobbene');
select pg_temp.lik((select count(*) from public.claim_push_jobs(10)), 0::bigint, 'låste jobber tas ikke to ganger');
select pg_temp.lik((select public.push_job_payload(id) ->> 'kind' from public.push_queue where activity_id = :'eagle'), 'activity', 'payload: aktivitet');
select pg_temp.lik((select jsonb_array_length(public.push_job_payload(id) -> 'members') from public.push_queue where activity_id = :'eagle'), 4, 'payload: alle i klubben');
select pg_temp.lik((select (select count(*) from jsonb_array_elements(public.push_job_payload(id) -> 'members') m
                            where jsonb_array_length(m -> 'devices') > 0)
                    from public.push_queue where activity_id = :'eagle'), 2::bigint, 'payload: telefonene til Anders og Bjørn');
select pg_temp.lik((select public.push_job_payload(id) -> 'club' -> 'disabled_categories' from public.push_queue where activity_id = :'eagle'),
                   '["setup"]'::jsonb, 'payload: klubbens valg');
select pg_temp.lik((select m -> 'thread_mode' from public.push_queue q,
                      jsonb_array_elements(public.push_job_payload(q.id) -> 'members') m
                    where q.activity_id = :'eagle' and m ->> 'id' = :'bjorn'), '"mentions"'::jsonb, 'payload: standard for tråden');
select public.finish_push_job(id, true, '{"sent": 1}', null, array[repeat('ef', 32)]) from public.push_queue where activity_id = :'eagle';
select pg_temp.lik((select done_at is not null from public.push_queue where activity_id = :'eagle'), true, 'jobben er ferdig');
select pg_temp.lik((select count(*) from public.push_devices where token = repeat('ef', 32)), 0::bigint, 'dødt token er fjernet');
select public.finish_push_job(id, false, null, 'APNs 500', '{}') from public.push_queue where thread_message_id = :'melding';
select pg_temp.lik((select (done_at is null and locked_until is null and last_error = 'APNs 500') from public.push_queue where thread_message_id = :'melding'),
                   true, 'feilet jobb slippes for nytt forsøk');
select pg_temp.lik((select count(*) from public.claim_push_jobs(10)), 1::bigint, 'feilet jobb tas igjen');
select public.finish_push_job(id, true, '{"sent": 0}') from public.push_queue where thread_message_id = :'melding';
select pg_temp.lik((select pushed_at is not null from public.thread_messages where id = :'melding'), true, 'meldingen er merket pushet');
select pg_temp.lik(public.queue_evening_reminders(7), 1, 'påminnelse for kvelden om en uke');
select pg_temp.lik(public.queue_evening_reminders(7), 0, 'påminnelsen skrives bare én gang');
select pg_temp.lik((select data from public.activity where kind = 'reminder'),
                   jsonb_build_object('event_date', to_char((now() at time zone 'Europe/Oslo')::date + 7, 'YYYY-MM-DD'), 'coming', 2, 'unsure', 1),
                   'påminnelsen har dato og antall');
select pg_temp.lik((select count(*) from public.push_queue q join public.activity a on a.id = q.activity_id where a.kind = 'reminder'), 1::bigint,
                   'påminnelsen er i køen');
reset role;
