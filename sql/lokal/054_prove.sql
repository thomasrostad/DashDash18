\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 054_folge.sql. Kjøres på kopien med kjeden til og med 052 og 054 (to ganger).
-- Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- S: standardverdiene og innstillingene.
-- A: forespørsel, godta, avslå, slutte å følge, fjerne følger, feil.
-- O: godkjenning av: følging med en gang, ventende godtas når den slås av.
-- Q: QR-koden: lage, samme, fornye, gammel død, følging med en gang, egen kode, grense.
-- F: navnesøk: minst tre tegn, søkbar av, blokkert begge veier, klubb, status, grense.
-- C: høyst 50 forespørsler i døgnet.
-- V: synlighet: can_see_profile og known_profiles, ventende gir ikke profilen.
-- P: «Følger»-fanen: sider på 1, 3 og 7 uten hull og dobbeltrader, bare låste runder fra dem du
--    følger (godtatt), egne runder, kortet, opplåsing, sletting.
-- R: reaksjoner og kommentarer på kortene, omtaler, varsler, sletting av eieren, rapport.
-- N: varslene og push: personlige linjer, audience person, gruppen Sosialt, ingen push for
--    round_finished, kartet.
-- B: blokkering rydder (begge veier, ventende), blokkere og rapportere en som spør.
-- D: sletting av konto.
-- L: RLS: ingen direkte skriving, koden og loggen kan ikke leses, appen kan ikke lage personlige
--    linjer eller sette actor_profile_id, anon.
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
-- Bla gjennom hele «Følger» med en gitt sidestørrelse. Svarer id-ene i rekkefølge.
create function pg_temp.bla(p_limit int) returns uuid[] language plpgsql as $$
declare
  v_ids  uuid[] := '{}';
  v_ts   timestamptz;
  v_id   uuid;
  v_n    int;
  v_rad  record;
  v_runder int := 0;
begin
  loop
    v_n := 0;
    for v_rad in select f.id, f.created_at from public.following_feed_page(v_ts, v_id, p_limit) f loop
      v_ids := v_ids || v_rad.id;
      v_ts := v_rad.created_at; v_id := v_rad.id; v_n := v_n + 1;
    end loop;
    v_runder := v_runder + 1;
    exit when v_n < p_limit or v_runder > 1000;
  end loop;
  return v_ids;
end $$;
-- Kall en RPC mange ganger og tell svarene (ok, eller feilkoden).
create function pg_temp.mange(p_sql text, p_n int) returns text language plpgsql as $$
declare
  v_ok int := 0; v_koder text := ''; i int;
begin
  for i in 1..p_n loop
    begin
      execute replace(p_sql, '$i', i::text);
      v_ok := v_ok + 1;
    exception when others then
      v_koder := v_koder || sqlstate || ' ';
    end;
  end loop;
  return v_ok || '|' || btrim(v_koder);
end $$;
-- Hendelser uten RLS.
create function pg_temp.hendelser(p_kind text, p_actor uuid, p_to uuid) returns bigint language sql security definer as $$
  select count(*) from public.activity a
   where a.kind = p_kind and a.actor_profile_id = p_actor
     and (p_to is null or p_to = any (a.recipients));
$$;
create function pg_temp.jobb(p_activity uuid) returns bigint language sql security definer as $$
  select id from public.push_queue where activity_id = p_activity;
$$;
create function pg_temp.siste(p_kind text, p_actor uuid, p_to uuid) returns uuid language sql security definer as $$
  select a.id from public.activity a where a.kind = p_kind and a.actor_profile_id = p_actor and p_to = any (a.recipients)
   order by a.created_at desc, a.id desc limit 1;
$$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set f1  '00000000-0000-0000-0000-0000000054a1'
\set f2  '00000000-0000-0000-0000-0000000054a2'
\set f3  '00000000-0000-0000-0000-0000000054a3'
\set f4  '00000000-0000-0000-0000-0000000054a4'
\set g1  '00000000-0000-0000-0000-0000000054b1'
\set g2  '00000000-0000-0000-0000-0000000054b2'
\set g3  '00000000-0000-0000-0000-0000000054b3'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set R1  'dddddddd-0000-0000-0000-000000000001'
\set R2  'dddddddd-0000-0000-0000-000000000002'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set R5  'dddddddd-0000-0000-0000-000000000005'
\set CO  'cccccccc-0000-0000-0000-0000000054c0'

begin;

-- --- Verdenen --------------------------------------------------------------------
-- f1 Frida, f2 Geir, f3 Hanne, f4 Ivar: ingen felles klubb med noen. g1–g3: egne brukere for
-- grensene. c001–c051: 51 søkbare profiler (grensen på 50 forespørsler). Anders (u2) og Bjørn
-- (u3) får navn; Bjørn er ikke søkbar. Geir har 25 løse runder (låst samtidig) og én som går.
select pg_temp.som('');
insert into auth.users (id) values (:'f1'), (:'f2'), (:'f3'), (:'f4'), (:'g1'), (:'g2'), (:'g3');
update public.profiles set display_name = 'Frida Følger' where id = :'f1';
update public.profiles set display_name = 'Geir Gåte' where id = :'f2';
update public.profiles set display_name = 'Hanne Hemmelig' where id = :'f3';
update public.profiles set display_name = 'Ivar Åpen' where id = :'f4';
update public.profiles set display_name = 'Grense ' || right(id::text, 2) where id in (:'g1', :'g2', :'g3');
update public.profiles set display_name = 'Anders' where id = :'u2';
update public.profiles set display_name = 'Bjørn', searchable = false where id = :'u3';
do $$
declare i int; v uuid;
begin
  for i in 1..51 loop
    v := ('00000000-0000-0000-0000-0000000541' || lpad(i::text, 2, '0'))::uuid;
    insert into auth.users (id) values (v);
    update public.profiles set display_name = 'Kvote ' || lpad(i::text, 3, '0') where id = v;
  end loop;
end $$;
select pg_temp.lik((select count(*) from public.profiles where display_name like 'Kvote %'), 51::bigint, 'S0 51 kvoteprofiler');

-- Geirs løse runder på Losby (felles bane, 18 hull, par 4 på 1 og 2): 25 låst på samme tid, én
-- aktiv. Hull 1 og 2 med slag.
insert into public.courses (id, club_id, name, kind) values (:'CO', null, 'Losby', 'course');
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select :'CO', h, case when h in (3, 7, 12, 16) then 3 when h in (5, 14) then 5 else 4 end, h from generate_series(1, 18) h;
do $$
declare
  v_r uuid; v_p uuid; i int;
begin
  for i in 0..25 loop
    v_r := ('dddddddd-0000-0000-0000-0000000540' || lpad(to_hex(i), 2, '0'))::uuid;
    v_p := ('99999999-0000-0000-0000-0000000540' || lpad(to_hex(i), 2, '0'))::uuid;
    insert into public.rounds (id, club_id, event_id, owner_id, status, course_id, hole_count)
    values (v_r, null, null, '00000000-0000-0000-0000-0000000054a2', 'active', 'cccccccc-0000-0000-0000-0000000054c0', 18);
    insert into public.round_participants (id, round_id, profile_id, display_name)
    values (v_p, v_r, '00000000-0000-0000-0000-0000000054a2', 'Geir Gåte');
    insert into public.round_players (round_id, member_id, club_id, playing_handicap) values (v_r, v_p, null, 12)
    on conflict (round_id, member_id) do update set playing_handicap = 12;
    insert into public.hole_scores (round_id, member_id, hole_index, strokes) values (v_r, v_p, 0, 5), (v_r, v_p, 1, 3);
    if i > 0 then
      update public.rounds set status = 'locked', locked_at = '2026-10-05 12:00+02' where id = v_r;
    end if;
  end loop;
end $$;
\set GR0  'dddddddd-0000-0000-0000-000000054000'
\set GR1  'dddddddd-0000-0000-0000-000000054001'
\set GP1  '99999999-0000-0000-0000-000000054001'
select pg_temp.lik((select count(*) from public.activity where kind = 'round_finished' and actor_profile_id = :'f2'), 25::bigint,
                   'S1 en round_finished per låst runde for Geir (den aktive gir ingen)');
select pg_temp.lik((select count(*) from public.activity
                     where kind = 'round_finished' and round_id in (:'R1', :'R2') and actor_profile_id in (:'u1', :'u2', :'u3')), 5::bigint,
                   'S2 etterfylt: én per spiller med innlogging i de låste klubbrundene (2 + 3)');
select pg_temp.lik((select count(*) from public.push_queue q join public.activity a on a.id = q.activity_id
                     where a.kind = 'round_finished'), 0::bigint, 'S3 round_finished går ikke i push-køen');

select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik((select follow_approval || '|' || searchable from public.profiles where id = :'f1'), 'true|true',
                   'S4 standard: godkjenning på, søkbar');
select pg_temp.lik(public.follow_settings(null, false), '{"searchable": false, "follow_approval": true}'::jsonb, 'S5 skjul fra søket');
select pg_temp.lik(public.follow_settings(null, true), '{"searchable": true, "follow_approval": true}'::jsonb, 'S6 synlig igjen');
reset role;

-- --- A: forespørsel og svar ---------------------------------------------------------------
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u1'), 'pending', 'A1 Frida spør Thomas: venter (godkjenning på)');
select pg_temp.lik((select status || '|' || source || '|' || (accepted_at is null) from public.follows
                     where follower_id = :'f1' and followee_id = :'u1'), 'pending|search|true', 'A2 raden, kilden');
select pg_temp.lik(public.follow_request(:'u1'), 'pending', 'A3 samme igjen: samme svar');
select pg_temp.lik(public.can_see_profile(:'u1'), false, 'A4 ventende gir ikke profilen');
reset role;
select pg_temp.lik(pg_temp.hendelser('follow_requested', :'f1', :'u1'), 1::bigint, 'A5 ett varsel follow_requested til Thomas');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'follow_requested' and actor_profile_id = :'f1'), 1::bigint,
                   'A6 Thomas ser varselet');
select pg_temp.lik((select data ->> 'actor_name' from public.activity where kind = 'follow_requested' and actor_profile_id = :'f1'),
                   'Frida Følger', 'A7 navnet i varselet');
select pg_temp.lik((select direction || '|' || status || '|' || display_name from public.my_follows()), 'follower|pending|Frida Følger',
                   'A8 my_follows: forespørsel til meg med navn');
select pg_temp.lik(public.can_see_profile(:'f1'), false, 'A9 Thomas ser ikke profilen før han godtar');
select pg_temp.lik((select count(*) from public.follows), 1::bigint, 'A10 Thomas ser raden');
select pg_temp.lik(public.follow_respond(:'f1', true), 'accepted', 'A11 Thomas godtar');
select pg_temp.feil(format($$select public.follow_respond(%L, true)$$, :'f1'), 'P0002');
select pg_temp.lik(public.can_see_profile(:'f1'), true, 'A12 Thomas ser Frida (følger ham)');
select pg_temp.lik((select count(*) from public.known_profiles() where id = :'f1'), 1::bigint, 'A13 og hun er i known_profiles');
reset role;
select pg_temp.lik(pg_temp.hendelser('follow_accepted', :'u1', :'f1'), 1::bigint, 'A14 varsel follow_accepted til Frida');
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.can_see_profile(:'u1'), true, 'A15 Frida ser Thomas');
select pg_temp.lik((select count(*) from public.known_profiles() where id = :'u1'), 1::bigint, 'A16 Thomas i Fridas known_profiles');
select pg_temp.lik((select count(*) from public.activity where kind = 'follow_accepted'), 1::bigint, 'A17 Frida ser varselet sitt');
select pg_temp.lik((select status || '|' || (accepted_at is not null) from public.follows where follower_id = :'f1'), 'accepted|true',
                   'A18 godtatt med tid');
reset role;
-- Avslag.
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u1', 'round'), 'pending', 'A19 Geir spør Thomas (etter en runde)');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.follow_respond(:'f2', false), 'denied', 'A20 Thomas avslår');
reset role;
select pg_temp.lik((select count(*) from public.follows where follower_id = :'f2') || '|' || pg_temp.hendelser('follow_requested', :'f2', :'u1'),
                   '0|0', 'A21 raden og varselet er borte');
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u1'), 'pending', 'A22 Geir spør igjen');
reset role;
select pg_temp.lik(pg_temp.hendelser('follow_requested', :'f2', :'u1'), 0::bigint, 'A23 ingen nytt varsel samme døgn');
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_remove(:'u1'), true, 'A24 Geir trekker forespørselen');
select pg_temp.lik(public.follow_remove(:'u1'), false, 'A25 ingenting å trekke');
-- Feil.
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'f2'), '22023');
select pg_temp.feil(format($$select public.follow_request(%L, 'qr')$$, :'u1'), '22023');
select pg_temp.feil(format($$select public.follow_request(%L, 'tull')$$, :'u1'), '22023');
select pg_temp.feil($$select public.follow_request('00000000-0000-0000-0000-0000000054ff')$$, 'P0002');
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'u3'), 'P0002');
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'u4'), 'P0002');
select pg_temp.feil(format($$select public.follow_respond(%L, null)$$, :'u1'), '22023');
reset role;
-- Bjørn er ikke søkbar, men Anders (felles klubb) kan spørre.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u3'), 'pending', 'A26 felles klubb: kan spørre en som ikke er søkbar');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.follower_remove(:'u2'), true, 'A27 Bjørn fjerner forespørselen (follower_remove)');
select pg_temp.lik(public.follower_remove(:'u2'), false, 'A28 ingenting å fjerne');
reset role;
-- Thomas fjerner Frida som følger, og hun følger igjen.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.follower_remove(:'f1'), true, 'A29 Thomas fjerner Frida');
select pg_temp.lik(public.can_see_profile(:'f1'), false, 'A30 og ser henne ikke lenger');
reset role;
select pg_temp.lik(pg_temp.hendelser('follow_accepted', :'u1', :'f1') + pg_temp.hendelser('follow_requested', :'f1', :'u1'), 0::bigint,
                   'A31 varslene mellom dem er borte');

-- --- O: godkjenning av ---------------------------------------------------------------------
select pg_temp.som(:'f4'); set role authenticated;
select pg_temp.lik(public.follow_settings(false, null), '{"searchable": true, "follow_approval": false}'::jsonb, 'O1 Ivar: åpen profil');
reset role;
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.follow_request(:'f4'), 'accepted', 'O2 Frida følger Ivar med en gang');
reset role;
select pg_temp.lik(pg_temp.hendelser('followed', :'f1', :'f4') || '|' || pg_temp.hendelser('follow_requested', :'f1', :'f4'), '1|0',
                   'O3 varselet er followed, ikke follow_requested');
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_request(:'f1'), 'pending', 'O4 Geir spør Frida');
reset role;
select pg_temp.som(:'f1'); set role authenticated;
update public.profiles set follow_approval = false where id = :'f1';
select pg_temp.lik((select status from public.follows where follower_id = :'f2' and followee_id = :'f1'), 'accepted',
                   'O5 Frida slår av godkjenning (vanlig update): ventende godtas');
update public.profiles set follow_approval = true where id = :'f1';
reset role;
select pg_temp.lik(pg_temp.hendelser('follow_accepted', :'f1', :'f2'), 1::bigint, 'O6 med varsel til Geir');
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_remove(:'f1'), true, 'O7 Geir slutter å følge Frida');
reset role;

-- --- Q: QR-koden ---------------------------------------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
select public.follow_code() as kode1 \gset
select pg_temp.lik(:'kode1' ~ '^[A-HJ-NP-Z2-9]{8}$', true, 'Q1 koden: 8 tegn uten I, O, 0, 1');
select pg_temp.lik(public.follow_code(), :'kode1', 'Q2 samme kode neste gang');
select public.follow_code(true) as kode2 \gset
select pg_temp.lik(:'kode2' <> :'kode1' and :'kode2' ~ '^[A-HJ-NP-Z2-9]{8}$', true, 'Q3 fornyet: ny kode');
select pg_temp.feil(format($$select public.follow_by_code(%L)$$, :'kode2'), '22023');
reset role;
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_by_code(:'kode1') ->> 'status', 'not_found', 'Q3b den gamle koden virker ikke');
select pg_temp.lik((public.follow_by_code(lower(left(:'kode2', 4)) || '-' || right(:'kode2', 4)) ->> 'status'), 'accepted',
                   'Q4 Geir skanner (små bokstaver og bindestrek går): følger med en gang, selv om Thomas krever godkjenning');
select pg_temp.lik((select status || '|' || source from public.follows where follower_id = :'f2' and followee_id = :'u1'), 'accepted|qr',
                   'Q5 raden: godtatt, qr');
select pg_temp.lik((public.follow_by_code(:'kode2') ->> 'already'), 'true', 'Q6 skann igjen: allerede');
select pg_temp.feil(format($$select public.follow_by_code(%L, 'search')$$, :'kode2'), '22023');
select pg_temp.lik(public.follow_by_code('ZZZZZZZZ') ->> 'status', 'not_found', 'Q6b ukjent kode');
reset role;
select pg_temp.lik(pg_temp.hendelser('followed', :'f2', :'u1'), 1::bigint, 'Q7 ett varsel followed til Thomas');
-- En ventende forespørsel blir godtatt av koden.
select pg_temp.som(:'f3'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u1'), 'pending', 'Q8 Hanne spør Thomas');
select pg_temp.lik(public.follow_by_code(:'kode2') ->> 'status', 'accepted', 'Q9 så skanner hun: godtatt');
select pg_temp.lik((select source from public.follows where follower_id = :'f3'), 'qr', 'Q10 kilden er qr');
select pg_temp.lik(public.follow_remove(:'u1'), true, 'Q11 Hanne slutter');
reset role;
-- Grensen: 20 forsøk i timen.
select pg_temp.som(:'g3'); set role authenticated;
select pg_temp.lik(pg_temp.mange($$select public.follow_by_code('AAAAAAA$i')$$, 22), '20|54000 54000',
                   'Q12 20 feil koder (svar uten feil, så de teller), så grensen (54000)');
reset role;

-- --- F: navnesøk ---------------------------------------------------------------------------
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.feil($$select * from public.search_people('Th')$$, '22023');
select pg_temp.feil($$select * from public.search_people('   Th  ')$$, '22023');
select pg_temp.feil($$select * from public.search_people(repeat('a', 41))$$, '22023');
select pg_temp.lik((select string_agg(display_name || '|' || coalesce(club_name, '-') || '|' || my_status || '|' || follows_me, ',')
                      from public.search_people('thom')), 'Thomas|Golfgutu|none|false', 'F1 finner Thomas med én klubb, status');
select pg_temp.lik((select count(*) from public.search_people('Bjør')), 0::bigint, 'F2 Bjørn er ikke søkbar');
select pg_temp.lik((select count(*) from public.search_people('Frida')), 0::bigint, 'F3 ikke deg selv');
select pg_temp.lik((select string_agg(display_name || '|' || my_status, ',') from public.search_people('Ivar')), 'Ivar Åpen|accepted',
                   'F4 min status: følger');
select pg_temp.lik((select count(*) from public.search_people('%%%')), 0::bigint, 'F5 % er bare et tegn');
select pg_temp.lik((select count(*) from public.search_people('Kvote')), 20::bigint, 'F6 20 treff som standard');
select pg_temp.lik((select count(*) from public.search_people('Kvote', 100)), 50::bigint, 'F7 høyst 50');
select pg_temp.lik((select display_name from public.search_people('ote 05', 5) limit 1), 'Kvote 050', 'F8 midt i navnet');
reset role;
select pg_temp.som(:'f4'); set role authenticated;
select pg_temp.lik((select my_status || '|' || follows_me from public.search_people('Frida')), 'none|true', 'F9 Ivar: Frida følger meg');
reset role;
-- Blokkering skjuler begge veier.
select pg_temp.som(:'f3'); set role authenticated;
select pg_temp.lik(public.block_user(:'f4'), :'f4'::uuid, 'F10 Hanne blokkerer Ivar (fra søket)');
select pg_temp.lik((select count(*) from public.search_people('Ivar')), 0::bigint, 'F11 Hanne finner ikke Ivar');
reset role;
select pg_temp.som(:'f4'); set role authenticated;
select pg_temp.lik((select count(*) from public.search_people('Hanne')), 0::bigint, 'F12 Ivar finner ikke Hanne');
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'f3'), 'P0002');
reset role;
-- Grensen: 60 søk i timen (feil lengde teller ikke).
select pg_temp.som(:'g2'); set role authenticated;
select pg_temp.lik(pg_temp.mange($$select * from public.search_people('ab')$$, 3), '0|22023 22023 22023', 'F13 for korte søk teller ikke');
select pg_temp.lik(pg_temp.mange($$select * from public.search_people('Kvote')$$, 62), '60|54000 54000', 'F14 60 søk, så grensen');
reset role;

-- --- C: høyst 50 forespørsler i døgnet ------------------------------------------------------
select pg_temp.som(:'g1'); set role authenticated;
select pg_temp.lik(pg_temp.mange($$select public.follow_request(('00000000-0000-0000-0000-0000000541' || lpad('$i', 2, '0'))::uuid)$$, 51),
                   '50|54000', 'C1 50 forespørsler, den 51. stoppes');
select pg_temp.lik(public.follow_request('00000000-0000-0000-0000-000000054101'), 'pending',
                   'C2 en du alt har spurt: svaret uten å telle');
select pg_temp.lik(public.follow_remove('00000000-0000-0000-0000-000000054101'), true, 'C3 trekk en');
select pg_temp.feil($$select public.follow_request('00000000-0000-0000-0000-000000054101')$$, '54000');
reset role;

-- --- V: synlighet ------------------------------------------------------------------------
-- Frida følger Thomas og Anders (godtatt) og spør Bjørn (venter).
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u1'), 'pending', 'V1 Frida spør Thomas igjen');
select pg_temp.lik(public.follow_request(:'u2'), 'pending', 'V2 og Anders');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.follow_respond(:'f1', true), 'accepted', 'V3 Thomas godtar');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.follow_respond(:'f1', true), 'accepted', 'V4 Anders godtar');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
update public.profiles set searchable = true where id = :'u3';
reset role;
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.follow_request(:'u3'), 'pending', 'V5 Frida spør Bjørn (venter)');
select pg_temp.lik((select string_agg(display_name, ',' order by display_name) from public.known_profiles()), 'Anders,Ivar Åpen,Thomas',
                   'V6 Fridas known_profiles: de hun følger (godtatt), ikke Bjørn');
select pg_temp.lik((select count(*) from public.profiles where id in (:'u1', :'u2', :'u3')), 2::bigint,
                   'V7 profiles_select: Thomas og Anders, ikke Bjørn');
select pg_temp.lik(public.can_see_profile(:'u3'), false, 'V8 can_see_profile(Bjørn) nei');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.can_see_profile(:'f1'), false, 'V9 Bjørn ser ikke Frida (bare en forespørsel)');
select pg_temp.lik((select display_name from public.my_follows() where direction = 'follower' and status = 'pending'), 'Frida Følger',
                   'V10 men navnet står i my_follows');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select string_agg(direction || ':' || status || ':' || display_name, ',' order by direction, display_name)
                      from public.my_follows()), 'follower:accepted:Frida Følger,follower:accepted:Geir Gåte',
                   'V11 Thomas: to følgere');
select pg_temp.lik((select count(*) from public.known_profiles() where id = :'f2'), 1::bigint, 'V12 følgeren er i velgeren (Ny runde)');
reset role;

-- --- P: «Følger»-fanen ----------------------------------------------------------------------
-- Frida følger Thomas, Anders og Ivar (godtatt), venter på Bjørn, og følger ikke Geir ennå.
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik((select string_agg(profile_id || ':' || round_id, ',' order by round_id, profile_id) from public.following_feed_page()),
                   :'u1' || ':' || :'R1' || ',' || :'u2' || ':' || :'R1' || ',' || :'u1' || ':' || :'R2' || ',' || :'u2' || ':' || :'R2',
                   'P1 de låste rundene til Thomas og Anders, ikke Bjørns (venter)');
select pg_temp.lik((select count(*) from public.activity where kind = 'round_finished'), 4::bigint,
                   'P2 RLS: Frida ser de samme fire hendelsene');
select pg_temp.lik((select is_mine from public.following_feed_page() limit 1), false, 'P3 ikke mine');
reset role;
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik(public.follow_settings(false, null) ->> 'follow_approval', 'false', 'P4 Geir: åpen profil');
reset role;
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.follow_request(:'f2'), 'accepted', 'P5 Frida følger Geir');
select pg_temp.lik(cardinality(pg_temp.bla(1)), 29, 'P6 29 kort (4 + Geirs 25) med sider på 1');
select pg_temp.lik(pg_temp.bla(1), pg_temp.bla(3), 'P7 sider på 3: samme rekkefølge');
select pg_temp.lik(pg_temp.bla(7), pg_temp.bla(100), 'P8 sider på 7: samme som alt på én side');
select pg_temp.lik((select count(distinct x) from unnest(pg_temp.bla(3)) x), 29::bigint, 'P9 ingen dobbeltrader');
select pg_temp.lik((select array_agg(id order by created_at desc, id desc) from public.following_feed_page(null, null, 100)),
                   pg_temp.bla(100), 'P10 nyeste først, nøkkel (created_at, id)');
select pg_temp.lik((select count(*) from public.following_feed_page(null, null, 0)), 1::bigint, 'P11 antall under 1 blir 1');
select pg_temp.lik((select count(*) from public.following_feed_page(null, null, 1000)), 29::bigint, 'P12 antall over 100 blir 100');
select pg_temp.lik((select count(*) from public.following_feed_page() where round_id = :'GR0'), 0::bigint, 'P13 runden som går, vises ikke');
-- Kortet: Geirs runde 1 (2 hull spilt: 5 og 3 slag på par 4 og 4).
select pg_temp.lik((select display_name || '|' || course_name || '|' || hole_count || '|' || playing_handicap || '|' || strokes || '|'
                           || holes_played || '|' || par_played || '|' || to_par || '|' || played_on || '|' || jsonb_array_length(holes)
                      from public.following_feed_page(null, null, 100) where round_id = :'GR1'),
                   'Geir Gåte|Losby|18|12|8|2|8|0|2026-10-05|18', 'P14 kortet: navn, bane, slag, par, dato, hullene');
select pg_temp.lik((select holes -> 0 from public.following_feed_page(null, null, 100) where round_id = :'GR1'),
                   '{"par": 4, "hole": 1, "strokes": 5, "strokeIndex": 1}'::jsonb, 'P15 hull 1 med par, indeks og slag');
-- Thomas sin runde 1: sjekk mot hole_scores direkte.
select pg_temp.lik((select strokes || '|' || holes_played from public.following_feed_page(null, null, 100)
                     where round_id = :'R1' and profile_id = :'u1'), '81|18', 'P16 Thomas i runde 1: 81 slag, 18 hull');
reset role;
select pg_temp.lik((select sum(strokes)::int || '|' || count(*) from public.hole_scores where round_id = :'R1' and member_id = :'m1'), '81|18',
                   'P17 (det samme rett fra hole_scores)');
-- Følgeren leser ikke runden selv.
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik((select count(*) from public.rounds where id in (:'R1', :'GR1')) + (select count(*) from public.hole_scores where round_id = :'R1'),
                   0::bigint, 'P18 Frida leser ikke rundene eller scorene (bare kortet)');
reset role;
-- Opplåsing: kortet forsvinner, og kommer tilbake én gang.
select pg_temp.som('');
update public.rounds set status = 'active' where id = :'GR1';
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik((select count(*) from public.following_feed_page(null, null, 100) where round_id = :'GR1'), 0::bigint, 'P19 låst opp: borte');
select pg_temp.lik((select count(*) from public.activity where round_id = :'GR1'), 0::bigint, 'P20 og hendelsen kan ikke leses');
reset role;
select pg_temp.som('');
update public.rounds set status = 'locked' where id = :'GR1';
select pg_temp.lik((select count(*) from public.activity where kind = 'round_finished' and round_id = :'GR1'), 1::bigint, 'P21 låst igjen: fortsatt én');
-- Egne runder.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select string_agg(round_id || ':' || is_mine, ',' order by round_id) from public.following_feed_page()),
                   :'R1' || ':true,' || :'R2' || ':true', 'P22 Thomas følger ingen: bare egne runder');
reset role;
-- Den som ikke følger, ser ingenting.
select pg_temp.som(:'f3'); set role authenticated;
select pg_temp.lik((select count(*) from public.following_feed_page()), 0::bigint, 'P23 Hanne følger ingen og har ingen runder');
select pg_temp.lik((select count(*) from public.activity where kind = 'round_finished'), 0::bigint, 'P24 og ser ingen round_finished');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select string_agg(actor_profile_id::text, ',') from public.activity where kind = 'round_finished'), :'u3' || ',' || :'u3',
                   'P25 Bjørn ser bare sine egne to (felles klubb gir ikke de andres kort)');
reset role;
-- Sletting av runden tar hendelsen.
\set GR2  'dddddddd-0000-0000-0000-000000054002'
select pg_temp.som('');
delete from public.rounds where id = :'GR2';
select pg_temp.lik((select count(*) from public.activity where round_id = :'GR2'), 0::bigint, 'P26 runden slettet: hendelsen også');

-- --- R: reaksjoner og kommentarer på kortene ---------------------------------------------
select id as kort from public.activity where kind = 'round_finished' and round_id = :'R1' and actor_profile_id = :'u1' \gset
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik(public.react('activity', :'kort', '🔥'), true, 'R1 Frida reagerer på Thomas sitt kort');
select pg_temp.lik((select (member_id is null) || '|' || profile_id || '|' || (club_id is null) || '|' || (competition_id is null)
                      from public.reactions where target_id = :'kort'), 'true|' || :'f1' || '|true|true', 'R2 lagret som profil uten klubb');
select (public.comment_add('activity', :'kort', 'Sterk runde!')).id as k1 \gset
select pg_temp.lik((select reactions::text || '|' || my_reactions::text || '|' || comment_count from public.following_feed_page(null, null, 100)
                     where id = :'kort'), '[{"count": 1, "emoji": "🔥"}]|{🔥}|1', 'R3 kortet: reaksjonen, min reaksjon, én kommentar');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'Hei', array[%L]::uuid[])$$, :'kort', :'f3'), '22023');
reset role;
select pg_temp.lik(pg_temp.hendelser('comment_added', :'f1', :'u1'), 1::bigint, 'R4 Thomas får comment_added (personlig, fra Frida)');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.comments where target_id = :'kort') || '|' || (select count(*) from public.reactions where target_id = :'kort'),
                   '1|1', 'R5 Thomas ser kommentaren og reaksjonen');
select pg_temp.lik((select count(*) from public.activity where kind = 'comment_added' and actor_profile_id = :'f1'), 1::bigint,
                   'R6 og varselet');
select pg_temp.lik((public.comment_add('activity', :'kort', 'Takk @Frida', array[:'f1']::uuid[])).id is not null, true,
                   'R7 Thomas svarer og nevner Frida');
reset role;
select pg_temp.lik(pg_temp.hendelser('mentioned', :'u1', :'f1'), 1::bigint, 'R8 Frida får mentioned');
-- Anders (klubbkamerat, følger ikke Thomas) ser ikke kortet.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'kort'), 'P0002');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'Hei')$$, :'kort'), 'P0002');
select pg_temp.lik((select count(*) from public.comments where target_id = :'kort'), 0::bigint, 'R9 Anders ser ingen kommentarer');
reset role;
-- Geir følger Thomas (QR fra før): kan nevnes, ser kommentarene.
select pg_temp.som(:'f1'); set role authenticated;
select pg_temp.lik((public.comment_add('activity', :'kort', 'Enig, @Geir?', array[:'f2']::uuid[])).id is not null, true,
                   'R10 Frida nevner Geir (følger Thomas)');
reset role;
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.lik((select count(*) from public.comments where target_id = :'kort'), 3::bigint, 'R11 Geir ser de tre kommentarene');
select pg_temp.feil(format($$select public.comment_delete(%L)$$, :'k1'), '42501');
reset role;
-- Eieren av kortet sletter Fridas kommentar.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.comment_delete(:'k1'), true, 'R12 Thomas (eier av kortet) sletter Fridas kommentar');
select pg_temp.lik(public.report_content('comment', (select id from public.comments where target_id = :'kort' and profile_id = :'f1' and deleted_at is null), 'spam') is not null,
                   true, 'R13 rapport på en kommentar på kortet');
reset role;
select pg_temp.lik((select (club_id is null) || '|' || (competition_id is null) || '|' || target_profile_id from public.content_reports where kind = 'comment'
                     and reporter_id = :'u1'), 'true|true|' || :'f1', 'R14 rapporten uten klubb og turnering, med forfatteren');

-- --- N: varsler og push --------------------------------------------------------------------
select pg_temp.som('');
select pg_temp.siste('follow_requested', :'f1', :'u3') as fr \gset
select pg_temp.lik((select p ->> 'audience' || '|' || (p ->> 'group') || '|' || coalesce(p ->> 'collapse', '-') || '|' || coalesce(p ->> 'event_id', '-')
                           || '|' || (p -> 'club' ->> 'name') || '|' || (p -> 'activity' ->> 'actor_profile_id')
                           || '|' || (select string_agg(m ->> 'user_id', ',') from jsonb_array_elements(p -> 'members') m)
                      from public.push_job_payload(pg_temp.jobb(:'fr')) p),
                   'person|social|-|-|Atten|' || :'f1' || '|' || :'u3', 'N1 follow_requested til Bjørn: person, Sosialt, mottakeren');
select pg_temp.lik((select count(*) from public.push_queue q join public.activity a on a.id = q.activity_id
                     where a.kind in ('follow_requested', 'follow_accepted', 'followed', 'comment_added', 'mentioned')
                       and a.club_id is null and a.competition_id is null) > 5, true, 'N2 de personlige varslene går i køen');
select pg_temp.siste('comment_added', :'f1', :'u1') as ca \gset
select pg_temp.lik((select p ->> 'audience' || '|' || coalesce(p ->> 'event_id', '-') || '|' || (p ->> 'group')
                           || '|' || (select string_agg(m ->> 'user_id', ',') from jsonb_array_elements(p -> 'members') m)
                      from public.push_job_payload(pg_temp.jobb(:'ca')) p),
                   'person|-|social|' || :'u1', 'N3 kommentar på kortet: til Thomas, uten kveld');
-- Thomas slår av Sosialt: ingen telefoner, group_off.
insert into public.push_devices (user_id, device_id, token, environment) values (:'u1', 'dev-u1-54', repeat('c3', 32), 'sandbox');
select pg_temp.lik(jsonb_array_length((select m -> 'devices' from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'ca')) -> 'members') m)) >= 1,
                   true, 'N4 med telefon: sendes');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.push_set_groups(array['social']) >= 1, true, 'N5 Thomas slår av Sosialt');
reset role;
select pg_temp.som('');
select pg_temp.lik((select (m ->> 'group_off') || '|' || jsonb_array_length(m -> 'devices')
                      from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'ca')) -> 'members') m),
                   'true|0', 'N6 gruppen av: ingen telefoner');
select pg_temp.lik((select string_agg(kind || '=' || group_key, ',' order by kind) from public.push_group_map()
                     where kind in ('follow_requested', 'follow_accepted', 'followed', 'round_finished')),
                   'follow_accepted=social,follow_requested=social,followed=social,round_finished=game', 'N7 kartet: de nye kindene');
select pg_temp.lik((select count(*) from public.push_group_map()), 31::bigint, 'N8 31 rader (27 fra 050 + 4)');
select pg_temp.lik((select count(*) from public.push_group_map() where kind in ('bill_share_sent', 'bill_share_disputed')), 2::bigint,
                   'N9 bill_share_* står fortsatt');
select pg_temp.lik((select count(*) from public.push_queue where public.push_job_payload(id) is null), 0::bigint, 'N10 alle jobber gir svar');
-- Klubbjobber er uendret (ingen actor_profile_id, audience club).
select pg_temp.lik((select count(*) from public.push_queue q where q.club_id is not null
                     and (public.push_job_payload(q.id) ->> 'audience' <> 'club'
                          or public.push_job_payload(q.id) -> 'activity' ? 'actor_profile_id')), 0::bigint,
                   'N11 klubbjobbene: audience club, ingen ny nøkkel');

-- --- B: blokkering -------------------------------------------------------------------------
-- Thomas blokkerer Geir (følger ham via QR): følgingen begge veier og varslene forsvinner.
select pg_temp.som(:'u1'); set role authenticated;
select public.follow_request(:'f2') as t_geir \gset
select pg_temp.lik(:'t_geir'::text, 'accepted', 'B1 Thomas følger Geir (åpen profil)');
select pg_temp.lik(public.block_user(:'f2'), :'f2'::uuid, 'B2 Thomas blokkerer Geir');
select pg_temp.lik((select count(*) from public.my_follows() where profile_id = :'f2'), 0::bigint, 'B3 ingen følging igjen');
select pg_temp.lik((select count(*) from public.search_people('Geir')), 0::bigint, 'B4 Thomas finner ikke Geir');
reset role;
select pg_temp.lik((select count(*) from public.follows where (follower_id = :'u1' and followee_id = :'f2') or (follower_id = :'f2' and followee_id = :'u1')),
                   0::bigint, 'B5 begge veier borte');
select pg_temp.lik(pg_temp.hendelser('followed', :'f2', :'u1') + pg_temp.hendelser('followed', :'u1', :'f2'), 0::bigint, 'B6 varslene borte');
select pg_temp.som(:'f2'); set role authenticated;
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'u1'), 'P0002');
select pg_temp.lik(public.follow_by_code(:'kode2') ->> 'status', 'not_found', 'B6b koden til den som blokkerte, virker ikke');
select pg_temp.lik((select count(*) from public.search_people('Thomas')), 0::bigint, 'B7 Geir finner ikke Thomas');
select pg_temp.lik((select count(*) from public.following_feed_page(null, null, 100) where profile_id = :'u1'), 0::bigint,
                   'B8 ingen kort fra Thomas');
select pg_temp.lik((select count(*) from public.comments where target_id = :'kort'), 0::bigint, 'B9 og ingen kommentarer');
reset role;
-- Blokkere og rapportere en som bare har spurt (Frida venter på Bjørn).
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.report_content('profile', :'f1', 'harassment') is not null, true, 'B10 Bjørn rapporterer Frida (forespørsel)');
select pg_temp.lik(public.block_user(:'f1'), :'f1'::uuid, 'B11 og blokkerer henne');
select pg_temp.lik((select count(*) from public.my_follows()), 0::bigint, 'B12 forespørselen er borte');
select pg_temp.lik((select count(*) from public.activity where kind = 'follow_requested'), 0::bigint, 'B13 og varselet');
reset role;
-- En fremmed som ikke er søkbar, kan ikke blokkeres eller rapporteres via id.
select pg_temp.som(:'g2'); set role authenticated;
select pg_temp.feil(format($$select public.block_user(%L)$$, :'u4'), 'P0002');
select pg_temp.feil(format($$select public.report_content('profile', %L, 'spam')$$, :'u4'), 'P0002');
reset role;

-- --- D: sletting av konto ------------------------------------------------------------------
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.follows where follower_id = :'f1' or followee_id = :'f1') > 0, true, 'D0 Frida har følging');
select pg_temp.som(:'f1'); set role authenticated;
select public.follow_code() is not null as harkode \gset
reset role;
select pg_temp.som('');
select public.delete_account_data(:'f1') as slett \gset
select pg_temp.lik((:'slett'::jsonb ->> 'follows')::int >= 3, true, 'D1 sletting svarer antall følginger');
select pg_temp.lik((select count(*) from public.follows where follower_id = :'f1' or followee_id = :'f1')
                   + (select count(*) from public.follow_codes where user_id = :'f1')
                   + (select count(*) from private.people_rate_log where user_id = :'f1'), 0::bigint,
                   'D2 ingen følging, kode eller logg igjen');
select pg_temp.lik((select count(*) from public.activity where actor_profile_id = :'f1')
                   + (select count(*) from public.activity where :'f1' = any (recipients) and club_id is null and competition_id is null),
                   0::bigint, 'D3 ingen personlige linjer fra eller til Frida');
select pg_temp.lik((select count(*) from public.reactions where profile_id = :'f1') + (select count(*) from public.comments where profile_id = :'f1'),
                   0::bigint, 'D4 reaksjonene og kommentarene er borte');
select pg_temp.lik((select searchable::text || '|' || coalesce(display_name, '-') from public.profiles where id = :'f1'), 'false|-',
                   'D5 profilen: ikke søkbar, uten navn');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.search_people('Frida')), 0::bigint, 'D6 finnes ikke i søket');
reset role;
-- Slettet runde-spiller: Thomas sine kort står, Geir har sine.
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'round_finished' and actor_profile_id = :'u1'), 2::bigint,
                   'D7 andres kort står');

-- --- L: RLS og anon ------------------------------------------------------------------------
select pg_temp.som(:'f4'); set role authenticated;
select pg_temp.feil(format($$insert into public.follows (follower_id, followee_id, status, source, accepted_at) values (%L, %L, 'accepted', 'qr', now())$$,
                           :'f4', :'u1'), '42501');
select pg_temp.feil($$update public.follows set status = 'accepted'$$, '42501');
select pg_temp.feil($$delete from public.follows$$, '42501');
select pg_temp.feil($$select * from public.follow_codes$$, '42501');
select pg_temp.feil($$select * from private.people_rate_log$$, '42501');
select pg_temp.feil(format($$insert into public.activity (club_id, competition_id, kind, category, actor_profile_id, recipients) values (null, null, 'followed', 'social', %L, array[%L]::uuid[])$$,
                           :'f4', :'u1'), '42501');
select pg_temp.lik((select count(*) from public.follows where follower_id <> :'f4' and followee_id <> :'f4'), 0::bigint,
                   'L1 Ivar ser bare sine egne følgerader');
reset role;
-- Appen kan ikke sette actor_profile_id på en klubbhendelse.
select pg_temp.som(:'u1'); set role authenticated;
insert into public.activity (club_id, kind, category, data, actor_profile_id) values (:'G', 'member_joined', 'club', '{"x": 54}', :'u2');
reset role;
select pg_temp.lik((select (actor_profile_id is null) || '|' || actor_member_id from public.activity where data ->> 'x' = '54'),
                   'true|' || :'m1', 'L2 actor_profile_id tømmes, aktøren er medlemmet');
select pg_temp.som(''); set role anon;
select pg_temp.feil(format($$select public.follow_request(%L)$$, :'u1'), '42501');
select pg_temp.feil($$select * from public.search_people('Thomas')$$, '42501');
select pg_temp.feil($$select * from public.following_feed_page()$$, '42501');
select pg_temp.feil($$select public.follow_by_code('AAAAAAAA')$$, '42501');
select pg_temp.feil($$select * from public.follows$$, '42501');
reset role;
select pg_temp.som(:'f4'); set role authenticated;
select pg_temp.lik(public.follow_code(null) ~ '^[A-HJ-NP-Z2-9]{8}$', true, 'L3 follow_code(null) er som false');
reset role;

rollback;
