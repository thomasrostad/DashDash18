\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 045_pamelding_kveld.sql. Kjøres på kopien med 001–043, 034, 044 og 045
-- (to ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- A: uten tak og frister er alt som i dag: gamle bygg skriver med upsert, RPC-en gir
--    samme rad, ingen venteliste, påminnelsen teller som før. Arrangøren kan ikke
--    lenger skrive andres svar rett i tabellen, og ingen kan slette direkte.
-- B: tak og venteliste: rekkefølge, automatisk opprykk (nei, usikker, sletting),
--    varsel til den som rykker opp og til arrangørene, høyere/lavere/fjernet tak, og
--    mange påmeldinger etter hverandre gir aldri flere enn taket.
-- C: frister: medlemmet stoppes (DDB02, også gamle bygg), arrangøren kan endre, sen
--    avmelding merkes og logges. 044: en rolle med bare rounds (eller money) kan ikke
--    endre andres svar, en egen rolle med tournaments kan.
-- D: gjester: bare når kvelden tillater det, teller mot taket, venteliste, grenser,
--    hvem som kan fjerne, frister og opprykk av gjest.
-- E: «sett».
-- F: loggen leses av medlemmet selv og arrangøren.
-- G: rettigheter: anon, direkte skriving i de nye tabellene, kolonnene på signups.
-- H: låsen: RPC-en låser kvelden (for update) i transaksjonen. Ekte samtidighet med
--    flere økter: lokal/045_samtidig.sh.
-- I: invarianten etterpå: ingen venter mens det er ledig plass.
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
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u7  '00000000-0000-0000-0000-000000000007'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
-- Nye spillere (p1–p8, innlogging v1–v8) og kvelder for prøven.
\set v1  '00000000-0000-0000-0000-000000004501'
\set v2  '00000000-0000-0000-0000-000000004502'
\set v3  '00000000-0000-0000-0000-000000004503'
\set v4  '00000000-0000-0000-0000-000000004504'
\set v5  '00000000-0000-0000-0000-000000004505'
\set v6  '00000000-0000-0000-0000-000000004506'
\set v7  '00000000-0000-0000-0000-000000004507'
\set v8  '00000000-0000-0000-0000-000000004508'
\set p1  '11111111-0000-0000-0000-000000004501'
\set p2  '11111111-0000-0000-0000-000000004502'
\set p3  '11111111-0000-0000-0000-000000004503'
\set p4  '11111111-0000-0000-0000-000000004504'
\set p5  '11111111-0000-0000-0000-000000004505'
\set p6  '11111111-0000-0000-0000-000000004506'
\set p7  '11111111-0000-0000-0000-000000004507'
\set p8  '11111111-0000-0000-0000-000000004508'
\set EA  'eeeeeeee-0000-0000-0000-0000000045a1'
\set EB  'eeeeeeee-0000-0000-0000-0000000045b1'
\set EC  'eeeeeeee-0000-0000-0000-0000000045c1'
\set ED  'eeeeeeee-0000-0000-0000-0000000045d1'
\set EH  'eeeeeeee-0000-0000-0000-0000000045f1'
\set ER  'eeeeeeee-0000-0000-0000-0000000045e1'

begin;

-- --- Verdenen --------------------------------------------------------------------
select pg_temp.som('');
insert into auth.users (id)
select ('00000000-0000-0000-0000-00000000450' || n)::uuid from generate_series(1, 8) n;
insert into public.club_members (id, club_id, user_id, display_name, status)
select ('11111111-0000-0000-0000-00000000450' || n)::uuid, :'G', ('00000000-0000-0000-0000-00000000450' || n)::uuid,
       'Spiller ' || n, 'active'
  from generate_series(1, 8) n;
insert into public.events (id, club_id, event_date) values
  (:'EA', :'G', '2031-03-01'), (:'EB', :'G', '2031-03-08'), (:'EC', :'G', '2031-03-15'),
  (:'ED', :'G', '2031-03-22'), (:'EH', :'G', '2031-03-29'),
  (:'ER', :'G', (now() at time zone 'Europe/Oslo')::date + 7);
-- p7 har en rolle med bare rounds, p8 en rolle med bare tournaments.
insert into public.club_roles (id, club_id, name, rights) values
  ('7a000000-0000-0000-0000-000000004501', :'G', 'Rundeleder 45', array['rounds']),
  ('7a000000-0000-0000-0000-000000004502', :'G', 'Turneringsleder 45', array['tournaments']);
insert into public.club_member_roles (club_id, member_id, role_id) values
  (:'G', :'p7', '7a000000-0000-0000-0000-000000004501'),
  (:'G', :'p8', '7a000000-0000-0000-0000-000000004502');
select pg_temp.lik(private.club_members_with_right(:'G', 'tournaments') @> array[:'m1', :'m3', :'p8']::uuid[]
                   and not (private.club_members_with_right(:'G', 'tournaments') @> array[:'p7']::uuid[]), true,
                   '0 arrangørene (tournaments) er Thomas, Bjørn og p8, ikke p7 (rounds)');

-- --- A: uten tak og frister ---------------------------------------------------------
-- Gamle bygg: upsert rett i tabellen, som KveldModel.write.
select pg_temp.som(:'v1'); set role authenticated;
with u as (insert into public.signups (event_id, member_id, club_id, status, comment)
           values (:'EA', :'p1', :'G', 'yes', 'Gleder meg')
           on conflict (event_id, member_id) do update
             set event_id = excluded.event_id, member_id = excluded.member_id, club_id = excluded.club_id,
                 status = excluded.status, comment = excluded.comment
           returning status, comment, waitlisted_at, late)
select pg_temp.lik((select status || '|' || comment || '|' || (waitlisted_at is null) || '|' || late from u),
                   'yes|Gleder meg|true|false', 'A1 gammelt bygg: upsert gir raden tilbake som før');
with u as (insert into public.signups (event_id, member_id, club_id, status, comment)
           values (:'EA', :'p1', :'G', 'maybe', 'Gleder meg')
           on conflict (event_id, member_id) do update
             set event_id = excluded.event_id, member_id = excluded.member_id, club_id = excluded.club_id,
                 status = excluded.status, comment = excluded.comment
           returning status)
select pg_temp.lik((select status from u), 'maybe', 'A2 gammelt bygg: endrer svaret med upsert');
select pg_temp.feil(format($$insert into public.signups (event_id, member_id, club_id, status) values (%L, %L, %L, 'yes')$$,
                           :'EA', :'p2', :'G'), '42501');
select pg_temp.feil(format($$delete from public.signups where event_id = %L$$, :'EA'), '42501');
select pg_temp.feil(format($$update public.signups set waitlisted_at = now() where event_id = %L$$, :'EA'), '42501');
select pg_temp.feil(format($$update public.signups set event_id = %L where event_id = %L and member_id = %L$$,
                           :'EB', :'EA', :'p1'), '22023');
reset role;
select pg_temp.som(:'v2'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EA', 'yes', 'Klar') - 'event_id' - 'member_id',
                   jsonb_build_object('status', 'yes', 'waitlisted', false, 'place', null, 'late', false,
                                      'comment', 'Klar', 'confirmed', 1, 'waitlist', 0, 'max_players', null,
                                      'signup_deadline', null, 'withdraw_deadline', null),
                   'A3 RPC: kommer, ingen venteliste, ingen tak');
select pg_temp.lik(public.evening_signup(:'EA', 'no') ->> 'comment', 'Klar', 'A4 kommentar null beholder kommentaren');
select pg_temp.lik(public.evening_signup(:'EA', 'no', '') ->> 'comment', null, 'A5 tom kommentar tømmer den');
select pg_temp.lik((public.evening_signup(:'EA', 'yes') ->> 'late')::boolean, false, 'A6 nei → ja uten frister er ikke sent');
select pg_temp.lik(public.evening_signup(:'EA', null) ->> 'status', null, 'A7 status null fjerner svaret («ikke svart»)');
select pg_temp.feil(format($$select public.evening_signup(%L, 'kanskje')$$, :'EA'), '22023');
select pg_temp.feil(format($$select public.evening_signup(%L, 'yes', repeat('x', 81))$$, :'EA'), '22023');
reset role;
-- Arrangøren kan ikke lenger skrive andres svar rett i tabellen (bare med RPC-en).
select pg_temp.som(:'u1'); set role authenticated;
with u as (update public.signups set status = 'no' where event_id = :'EA' and member_id = :'p1' returning 1)
select pg_temp.lik((select count(*)::int from u), 0, 'A8 arrangøren: direkte update av andres svar gir 0 rader');
select pg_temp.feil(format($$insert into public.signups (event_id, member_id, club_id, status) values (%L, %L, %L, 'yes')$$,
                           :'EA', :'p3', :'G'), '42501');
select pg_temp.lik(public.evening_signup(:'EA', 'yes', null, :'p3') ->> 'status', 'yes', 'A9 arrangøren svarer for p3 med RPC-en');
reset role;
select pg_temp.lik((select string_agg(coalesce(l.note, '-') || ':' || l.old_status || '>' || l.new_status, ',' order by l.id)
                      from public.signup_log l where l.event_id = :'EA'),
                   'direct:none>yes,direct:yes>maybe,-:none>yes,-:yes>no,-:no>yes,-:yes>none,organizer:none>yes',
                   'A10 loggen: gamle bygg (direct), RPC (-), arrangøren (organizer); kommentar alene logges ikke');
select pg_temp.lik((select string_agg(data ->> 'member', ',') from public.activity where event_id = :'EA' and kind = 'signup_dropped'),
                   :'p2' || ',' || :'p2', 'A11 ja → nei og ja → ingen svar gir varsel til arrangørene (ja → usikker gir ikke)');
-- Påminnelsen: uten tak og gjester teller den som før (samme nøkler og tall).
select pg_temp.som('');
insert into public.signups (event_id, member_id, club_id, status) values
  (:'ER', :'p1', :'G', 'yes'), (:'ER', :'p2', :'G', 'yes'), (:'ER', :'p3', :'G', 'maybe'), (:'ER', :'p4', :'G', 'no');
select public.queue_evening_reminders(7) >= 1;
select pg_temp.lik((select data - 'event_date' from public.activity where event_id = :'ER' and kind = 'reminder'),
                   '{"coming": 2, "unsure": 1}'::jsonb, 'A12 påminnelsen uten tak: samme data som før 045');

-- --- B: tak og venteliste -----------------------------------------------------------
update public.events set max_players = 3 where id = :'EB';
select pg_temp.som(:'v1'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', 'yes') ->> 'waitlisted', 'false', 'B1 p1 kommer (1 av 3)');
reset role;
select pg_temp.som(:'v2'); set role authenticated; select public.evening_signup(:'EB', 'yes') is not null; reset role;
select pg_temp.som(:'v3'); set role authenticated; select public.evening_signup(:'EB', 'yes') is not null; reset role;
select pg_temp.som(:'v4'); set role authenticated;
select pg_temp.lik((select x ->> 'waitlisted' || '|' || (x ->> 'place') || '|' || (x ->> 'confirmed') || '|' || (x ->> 'waitlist')
                      from public.evening_signup(:'EB', 'yes', 'Venter') x),
                   'true|1|3|1', 'B2 p4 havner på ventelista som nr. 1 (3 av 3 bekreftet)');
reset role;
select pg_temp.som(:'v5'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', 'yes') ->> 'place', '2', 'B3 p5 er nr. 2');
reset role;
-- Gammelt bygg på full kveld: raden blir yes på ventelista (nr. 3).
select pg_temp.som(:'u3'); set role authenticated;
with u as (insert into public.signups (event_id, member_id, club_id, status)
           values (:'EB', :'m3', :'G', 'yes')
           on conflict (event_id, member_id) do update set status = excluded.status
           returning status, waitlisted_at is not null as w)
select pg_temp.lik((select status || '|' || w from u), 'yes|true', 'B4 gammelt bygg på full kveld: ventelista');
reset role;
select pg_temp.lik((select string_agg(w.member_id::text, ',' order by w.place) from private.evening_waitlist(:'EB') w),
                   :'p4' || ',' || :'p5' || ',' || :'m3', 'B5 ventelista i rekkefølge: p4, p5, Bjørn');
select pg_temp.lik(private.evening_confirmed(:'EB'), 3, 'B6 aldri mer enn taket');
-- p2 melder av: p4 rykker opp i samme transaksjon.
select pg_temp.som(:'v2'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', 'no') ->> 'confirmed', '3', 'B7 p2 melder av, plassen fylles med en gang');
reset role;
select pg_temp.lik((select waitlisted_at is null from public.signups where event_id = :'EB' and member_id = :'p4'), true,
                   'B8 p4 rykket opp automatisk');
select pg_temp.lik((select string_agg(w.member_id::text, ',' order by w.place) from private.evening_waitlist(:'EB') w),
                   :'p5' || ',' || :'m3', 'B9 p5 er nå nr. 1, Bjørn nr. 2');
select pg_temp.lik((select recipients from public.activity where event_id = :'EB' and kind = 'waitlist_promoted'
                      and data ->> 'member' = :'p4'), array[:'p4']::uuid[], 'B10 varsel waitlist_promoted bare til p4');
select pg_temp.lik((select category from public.activity where event_id = :'EB' and kind = 'waitlist_promoted'
                      and data ->> 'member' = :'p4'), 'signup', 'B11 kategori signup (finnes fra 008)');
select pg_temp.lik((select (select array_agg(x order by x) from unnest(recipients) x) from public.activity
                     where event_id = :'EB' and kind = 'signup_dropped' and data ->> 'member' = :'p2'),
                   (select array_agg(x order by x) from unnest(array[:'m1', :'m3', :'p8']::uuid[]) x),
                   'B12 signup_dropped til arrangørene (Thomas, Bjørn, p8)');
select pg_temp.lik((select actor_member_id from public.activity where event_id = :'EB' and kind = 'signup_dropped'
                      and data ->> 'member' = :'p2'), :'p2'::uuid, 'B13 aktøren er den som meldte av');
select pg_temp.lik((select note from public.signup_log where event_id = :'EB' and member_id = :'p4' and new_status = 'yes'),
                   'promoted', 'B14 opprykket logges (promoted)');
select pg_temp.som(:'v4'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.activity where kind = 'waitlist_promoted' and event_id = :'EB'), 1,
                   'B15 p4 ser varselet sitt');
reset role;
select pg_temp.som(:'v6'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.activity where kind in ('waitlist_promoted', 'signup_dropped')
                     and event_id = :'EB'), 0, 'B16 et vanlig medlem ser ikke varslene til andre');
reset role;
-- p5 (venter) blir usikker: ut av ventelista, ingen opprykk, ingen varsel. Ja igjen: bakerst.
select pg_temp.som(:'v5'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', 'maybe') ->> 'waitlisted', 'false', 'B17 venter → usikker: ut av ventelista');
select pg_temp.lik(public.evening_signup(:'EB', 'yes') ->> 'place', '2', 'B18 ja igjen: bakerst (nr. 2 etter Bjørn)');
reset role;
select pg_temp.lik((select count(*)::int from public.activity where event_id = :'EB' and kind = 'signup_dropped'
                     and data ->> 'member' = :'p5'), 0, 'B19 ingen varsel når en som venter går');
-- Bekreftet p1 blir usikker: opprykk (Bjørn), ingen signup_dropped (bare ja → nei).
select pg_temp.som(:'v1'); set role authenticated;
select public.evening_signup(:'EB', 'maybe') is not null;
reset role;
select pg_temp.lik((select waitlisted_at is null from public.signups where event_id = :'EB' and member_id = :'m3'), true,
                   'B20 ja → usikker gir opprykk (Bjørn)');
select pg_temp.lik((select count(*)::int from public.activity where event_id = :'EB' and kind = 'signup_dropped'
                     and data ->> 'member' = :'p1'), 0, 'B21 ja → usikker gir ikke signup_dropped');
-- Bekreftet p3 fjerner svaret (status null): opprykk (p5).
select pg_temp.som(:'v3'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', null) ->> 'status', null, 'B22 p3 fjerner svaret');
reset role;
select pg_temp.lik((select string_agg(member_id::text, ',' order by member_id) from public.signups
                     where event_id = :'EB' and status = 'yes' and waitlisted_at is null),
                   :'m3' || ',' || :'p4' || ',' || :'p5', 'B23 sletting gir opprykk (p5): Bjørn, p4, p5');
-- Lavere tak: ingen flyttes. Høyere: opprykk med en gang. Fjernet: alle inn.
select pg_temp.som(:'u1'); set role authenticated;
update public.events set max_players = 2 where id = :'EB';
reset role;
select pg_temp.lik(private.evening_confirmed(:'EB'), 3, 'B24 lavere tak (2): de tre bekreftede står');
select pg_temp.som(:'v6'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EB', 'yes') ->> 'place', '1', 'B25 ny på full kveld: ventelista');
reset role;
select pg_temp.som(:'v7'); set role authenticated; select public.evening_signup(:'EB', 'yes') is not null; reset role;
select pg_temp.som(:'v8'); set role authenticated; select public.evening_signup(:'EB', 'yes') is not null; reset role;
select pg_temp.som(:'u1'); set role authenticated;
update public.events set max_players = 5 where id = :'EB';
reset role;
select pg_temp.lik((select private.evening_confirmed(:'EB') || '|' || string_agg(w.member_id::text, ',')
                      from private.evening_waitlist(:'EB') w), '5|' || :'p8',
                   'B26 høyere tak (5): p6 og p7 rykker opp, p8 venter');
select pg_temp.som(:'u1'); set role authenticated;
update public.events set max_players = null where id = :'EB';
reset role;
select pg_temp.lik((select count(*)::int from private.evening_waitlist(:'EB')), 0, 'B27 uten tak: alle er inne');
-- Mange etter hverandre (alle 12 aktive i troppen, tak 4): aldri flere enn taket, ventelista i kallrekkefølgen.
select pg_temp.som('');
update public.events set max_players = 4 where id = :'EA';
delete from public.signups where event_id = :'EA';
select pg_temp.som(:'u1'); set role authenticated;
select count(*) = 12 from public.club_members m, lateral public.evening_signup(:'EA', 'yes', null, m.id) x
 where m.club_id = :'G' and m.status = 'active';
reset role;
select pg_temp.lik((select private.evening_confirmed(:'EA') || '|' || count(*) from private.evening_waitlist(:'EA')),
                   '4|8', 'B28 12 på rad med tak 4: 4 bekreftet, 8 på ventelista');
select pg_temp.lik((select bool_and(a.waitlisted_at < b.waitlisted_at) from private.evening_waitlist(:'EA') a
                      join private.evening_waitlist(:'EA') b on b.place = a.place + 1), true,
                   'B29 ventelista har strengt stigende tid (clock_timestamp)');

-- --- C: frister og 044-rettigheter ----------------------------------------------------
select pg_temp.som('');
insert into public.signups (event_id, member_id, club_id, status) values
  (:'EC', :'p1', :'G', 'yes'), (:'EC', :'p2', :'G', 'yes'), (:'EC', :'p4', :'G', 'no');
update public.events set signup_deadline = now() - interval '1 hour', withdraw_deadline = now() - interval '1 hour'
 where id = :'EC';
select pg_temp.som(:'v3'); set role authenticated;
select pg_temp.feil(format($$select public.evening_signup(%L, 'yes')$$, :'EC'), 'DDB02');
reset role;
select pg_temp.som(:'v1'); set role authenticated;
select pg_temp.feil(format($$select public.evening_signup(%L, 'no')$$, :'EC'), 'DDB02');
select pg_temp.feil(format($$select public.evening_signup(%L, null)$$, :'EC'), 'DDB02');
select pg_temp.feil(format($$insert into public.signups (event_id, member_id, club_id, status) values (%L, %L, %L, 'no')
                             on conflict (event_id, member_id) do update set status = excluded.status$$,
                           :'EC', :'p1', :'G'), 'DDB02');
select pg_temp.lik(public.evening_signup(:'EC', 'yes', 'Blir litt sen') ->> 'comment', 'Blir litt sen',
                   'C1 etter fristene: kommentar på «kommer» går');
reset role;
select pg_temp.som(:'v4'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EC', 'maybe') ->> 'status', 'maybe', 'C2 nei → usikker etter fristene går (ikke ja)');
reset role;
select pg_temp.som(:'v2'); set role authenticated;
select pg_temp.lik(pg_temp.feil(format($$select public.evening_signup(%L, 'maybe')$$, :'EC'), 'DDB02'),
                   'ok DDB02: Fristen er ute. Kontakt arrangøren.', 'C3 teksten og koden for medlemmet');
reset role;
-- Arrangøren (Bjørn) endrer etter fristen: går, merkes late, logges, varsel med late.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((public.evening_signup(:'EC', 'no', null, :'p1') ->> 'late')::boolean, true,
                   'C4 arrangøren melder av p1 etter fristen: late');
select pg_temp.lik(public.evening_signup(:'EC', 'yes', null, :'p3') ->> 'status', 'yes',
                   'C5 arrangøren melder på p3 etter påmeldingsfristen');
reset role;
select pg_temp.lik((select note from public.signup_log where event_id = :'EC' and member_id = :'p1' order by id desc limit 1),
                   'late', 'C6 loggen: late');
select pg_temp.lik((select changed_by from public.signup_log where event_id = :'EC' and member_id = :'p1' order by id desc limit 1),
                   :'u3'::uuid, 'C7 loggen: endret av Bjørn');
select pg_temp.lik((select data ->> 'late' from public.activity where event_id = :'EC' and kind = 'signup_dropped'),
                   'true', 'C8 signup_dropped sier late');
-- Arrangørens egen avmelding etter fristen: går, late.
select pg_temp.som(:'u3'); set role authenticated;
select public.evening_signup(:'EC', 'yes', null, :'m3') is not null;
select pg_temp.lik((public.evening_signup(:'EC', 'no') ->> 'late')::boolean, true, 'C9 arrangøren selv etter fristen: late');
reset role;
-- 044: bare rounds (p7) eller money (Anders) kan ikke endre andres svar. tournaments (p8) kan.
select pg_temp.som(:'v7'); set role authenticated;
select pg_temp.feil(format($$select public.evening_signup(%L, 'no', null, %L)$$, :'EC', :'p2'), '42501');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format($$select public.evening_signup(%L, 'no', null, %L)$$, :'EC', :'p2'), '42501');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'EC', 'maybe', null, :'p2') ->> 'late', 'true',
                   'C10 egen rolle med bare tournaments endrer p2 etter fristen');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format($$select public.evening_signup(%L, 'yes')$$, :'EC'), 'P0002');
reset role;
-- En som står på ventelista kan melde seg av etter fristen (holder ingen plass).
select pg_temp.som('');
update public.events set signup_deadline = null, withdraw_deadline = null, max_players = 1 where id = :'ED';
select pg_temp.som(:'v1'); set role authenticated; select public.evening_signup(:'ED', 'yes') is not null; reset role;
select pg_temp.som(:'v2'); set role authenticated; select public.evening_signup(:'ED', 'yes') is not null; reset role;
select pg_temp.som('');
update public.events set withdraw_deadline = now() - interval '1 minute' where id = :'ED';
select pg_temp.som(:'v2'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'ED', 'no') ->> 'late', 'false', 'C11 venter → nei etter fristen går, ikke sent');
reset role;
select pg_temp.som('');
update public.events set withdraw_deadline = null, max_players = null where id = :'ED';
delete from public.signups where event_id = :'ED';

-- --- D: gjester -----------------------------------------------------------------------
select pg_temp.som(:'v1'); set role authenticated;
select pg_temp.feil(format($$select public.evening_guest_add(%L, 'Gjest A')$$, :'ED'), '55000');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
update public.events set allow_guests = true, max_players = 3 where id = :'ED';
reset role;
select pg_temp.som(:'v1'); set role authenticated;
select public.evening_signup(:'ED', 'yes') is not null;
create temp table d_a as select (public.evening_guest_add(:'ED', ' Gjest A ') ->> 'guest_id')::uuid as id;
select pg_temp.lik((select name from public.event_guests where id = (select id from d_a)), 'Gjest A', 'D1 gjest lagt inn (navnet trimmet)');
reset role;
select pg_temp.som(:'v2'); set role authenticated;
select pg_temp.lik(public.evening_guest_add(:'ED', 'Gjest B') ->> 'confirmed', '3', 'D2 gjestene teller mot taket (3 av 3)');
select pg_temp.feil(format($$select public.evening_guest_add(%L, 'gjest b')$$, :'ED'), '23505');
select pg_temp.feil(format($$select public.evening_guest_add(%L, '  ')$$, :'ED'), '22023');
select pg_temp.feil(format($$select public.evening_guest_remove(%L)$$, (select id from d_a)), '42501');
select pg_temp.feil(format($$select public.evening_guest_add(%L, 'Gjest X', %L)$$, :'ED', :'p1'), '42501');
reset role;
select pg_temp.som(:'v3'); set role authenticated;
select pg_temp.lik(public.evening_signup(:'ED', 'yes') ->> 'place', '1', 'D3 p3 på full kveld: venteliste nr. 1');
reset role;
select pg_temp.som(:'v1'); set role authenticated;
create temp table d_c as select public.evening_guest_add(:'ED', 'Gjest C') as x;
select pg_temp.lik((select (x ->> 'waitlisted') || '|' || (x ->> 'place') from d_c), 'true|2', 'D4 gjest på full kveld: venteliste nr. 2');
select public.evening_guest_add(:'ED', 'Gjest D') is not null;
select pg_temp.feil(format($$select public.evening_guest_add(%L, 'Gjest E')$$, :'ED'), '54000');
-- p1 fjerner Gjest A: p3 (først i køen) rykker opp.
select pg_temp.lik(public.evening_guest_remove((select id from d_a)) ->> 'confirmed', '3', 'D5 gjest fjernet, plassen fylles');
reset role;
select pg_temp.lik((select waitlisted_at is null from public.signups where event_id = :'ED' and member_id = :'p3'), true,
                   'D6 p3 rykket opp da gjesten gikk');
-- p3 melder av: Gjest C (nå først) rykker opp, varselet går til p1 med navnet.
select pg_temp.som(:'v3'); set role authenticated;
select public.evening_signup(:'ED', 'no') is not null;
reset role;
select pg_temp.lik((select waitlisted_at is null from public.event_guests where event_id = :'ED' and name = 'Gjest C'), true,
                   'D7 gjesten rykker opp når et medlem melder av');
select pg_temp.lik((select recipients[1]::text || '|' || (data ->> 'guest_name') from public.activity
                     where event_id = :'ED' and kind = 'waitlist_promoted' and data ? 'guest_name'),
                   :'p1' || '|Gjest C', 'D8 varselet om gjesten går til den som inviterte');
select pg_temp.lik((select count(*)::int from public.signup_log where event_id = :'ED' and guest_id is not null), 6,
                   'D9 loggen har gjestene (A inn/ut, B, C inn/opp, D)');
-- Fristene for gjester: medlemmet stoppes, arrangøren kan (late).
select pg_temp.som('');
update public.events set signup_deadline = now() - interval '1 hour', withdraw_deadline = now() - interval '1 hour'
 where id = :'ED';
select pg_temp.som(:'v1'); set role authenticated;
select pg_temp.feil(format($$select public.evening_guest_add(%L, 'Sen gjest')$$, :'ED'), 'DDB02');
select pg_temp.feil(format($$select public.evening_guest_remove(%L)$$,
                           (select id from public.event_guests where event_id = :'ED' and name = 'Gjest C')), 'DDB02');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.evening_guest_remove((select id from public.event_guests where event_id = :'ED' and name = 'Gjest C')) ->> 'late',
                   'true', 'D10 arrangøren fjerner gjesten etter fristen: late');
select pg_temp.lik(public.evening_guest_add(:'ED', 'Arrangørens gjest', :'p2') ->> 'invited_by', :'p2',
                   'D11 arrangøren legger inn gjest for p2 etter fristen');
reset role;
select pg_temp.som(:'v5'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.event_guests where event_id = :'ED'), 3, 'D12 alle medlemmer ser gjestene');
reset role;

-- --- E: «sett» ---------------------------------------------------------------------------
select pg_temp.som(:'v6'); set role authenticated;
create temp table e_sett as select public.evening_mark_seen(:'EH') as t;
select pg_temp.lik((select t is not null from e_sett), true, 'E1 sett: tidspunktet');
select pg_temp.lik(public.evening_mark_seen(:'EH'), (select t from e_sett), 'E2 andre gang: samme (første gang sett)');
select pg_temp.lik((select count(*)::int from public.event_views where event_id = :'EH'), 1, 'E3 p6 ser sin egen rad');
select pg_temp.lik((select count(*)::int from public.signups where event_id = :'EH'), 0, 'E4 sett er ikke svart (ingen rad i signups)');
reset role;
select pg_temp.som(:'v5'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.event_views where event_id = :'EH'), 0, 'E5 et annet medlem ser den ikke');
select public.evening_signup(:'EH', 'maybe') is not null;
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.event_views where event_id = :'EH'), 2, 'E6 arrangøren ser begge (svar gir også sett)');
reset role;
select pg_temp.som(:'u7'); set role authenticated;
select pg_temp.feil(format($$select public.evening_mark_seen(%L)$$, :'EH'), 'P0002');
reset role;

-- --- F: loggen ----------------------------------------------------------------------------
select pg_temp.som(:'v4'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.signup_log where member_id is distinct from :'p4'::uuid), 0,
                   'F1 medlemmet ser bare sin egen logg');
select pg_temp.lik((select count(*)::int > 0 from public.signup_log), true, 'F2 … og den finnes');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.signup_log where member_id is distinct from :'m2'::uuid), 0,
                   'F3 kasserer (money) ser ikke andres logg (bare sin egen fra B28)');
reset role;
select pg_temp.som(:'v8'); set role authenticated;
select pg_temp.lik((select count(*)::int from public.signup_log) = (select count(*)::int from public.signup_log l
                     where l.club_id = :'G'), true, 'F4 tournaments ser hele klubbens logg');
select pg_temp.lik((select count(*)::int > 20 from public.signup_log), true, 'F5 … med alle radene');
reset role;

-- --- G: rettigheter -------------------------------------------------------------------------
select pg_temp.som(''); set role anon;
select pg_temp.feil(format($$select public.evening_signup(%L, 'yes')$$, :'EA'), '42501');
select pg_temp.feil(format($$select public.evening_mark_seen(%L)$$, :'EA'), '42501');
select pg_temp.feil($$select count(*) from public.event_guests$$, '42501');
select pg_temp.feil($$select count(*) from public.signup_log$$, '42501');
reset role;
select pg_temp.som(:'v1'); set role authenticated;
select pg_temp.feil(format($$insert into public.event_guests (event_id, club_id, name, invited_by) values (%L, %L, 'Snik', %L)$$,
                           :'ED', :'G', :'p1'), '42501');
select pg_temp.feil(format($$insert into public.signup_log (event_id, club_id, old_status, new_status) values (%L, %L, 'none', 'yes')$$,
                           :'ED', :'G'), '42501');
select pg_temp.feil(format($$insert into public.event_views (event_id, member_id, club_id) values (%L, %L, %L)$$,
                           :'ED', :'p1', :'G'), '42501');
select pg_temp.feil(format($$update public.signups set late = true where event_id = %L$$, :'EC'), '42501');
select pg_temp.feil($$select private.evening_fill('eeeeeeee-0000-0000-0000-0000000045a1')$$, '42501');
-- Server-aktivitet kan ikke lages av klienten: mottakerliste uten arrangør stoppes som før.
select pg_temp.feil(format($$insert into public.activity (club_id, kind, category, recipients) values (%L, 'waitlist_promoted', 'signup', array[%L]::uuid[])$$,
                           :'G', :'p2'), '42501');
reset role;

-- --- H: låsen -------------------------------------------------------------------------------
-- RPC-en låser kvelden med for update: raden har denne transaksjonens xid som xmax.
select pg_temp.som(:'v1'); set role authenticated;
select public.evening_signup(:'EH', 'yes') is not null;
reset role;
select pg_temp.lik((select xmax::text from public.events where id = :'EH'), (txid_current() % 4294967296)::text,
                   'H1 kvelden er låst av transaksjonen (select … for update)');

-- --- I: invarianten -----------------------------------------------------------------------
select pg_temp.lik((select count(*)::int from public.events e
                     where exists (select 1 from private.evening_waitlist(e.id))
                       and (e.max_players is null or private.evening_confirmed(e.id) < e.max_players)), 0,
                   'I1 ingen venter mens det er ledig plass');
select pg_temp.lik((select count(*)::int from public.events e
                     where e.max_players is not null and private.evening_confirmed(e.id) > e.max_players
                       and e.id <> :'EB'), 0, 'I2 ingen kveld over taket (unntatt EB, der taket ble senket med vilje)');

rollback;
