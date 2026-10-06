\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 008_sosialt.sql mot en lokal, midlertidig Postgres med
-- lokal/stub.sql og lokal/stub_storage.sql, etter 001 og 008. Kjøres i en tom
-- base (ikke etter 001_prove.sql). Hver resultatlinje skal starte med "ok";
-- ingen "FEIL". Slik kjøres den: se sql/README.md, «Lokal sjekk».
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

-- === Oppsett (som postgres, uten innlogging) ===============================
-- u1 Thomas (arrangør), u2 Anders, u3 Bjørn, u4 Ola (annen klubb), u5 Per (venter).
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004'),
 ('00000000-0000-0000-0000-000000000005');

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set per     '11111111-0000-0000-0000-000000000005'
\set ola     '22222222-0000-0000-0000-000000000004'
\set anders2 '22222222-0000-0000-0000-000000000002'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'

insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status) values
  (:'thomas',  :'klubb',  :'u1', 'Thomas', true,  'active'),
  (:'anders',  :'klubb',  :'u2', 'Anders', false, 'active'),
  (:'bjorn',   :'klubb',  :'u3', 'Bjørn',  false, 'active'),
  (:'per',     :'klubb',  :'u5', 'Per',    false, 'pending'),
  (:'ola',     :'klubb2', :'u4', 'Ola',    true,  'active'),
  (:'anders2', :'klubb2', :'u2', 'Anders', false, 'active');

insert into public.events (club_id, event_date, start_time) values (:'klubb', current_date + 7, '17:00') returning id as fram \gset
insert into public.events (club_id, event_date, start_time) values (:'klubb', current_date - 1, '17:00') returning id as forbi \gset
insert into public.events (club_id, event_date, start_time) values (:'klubb', current_date + 14, '18:30') returning id as spilt \gset
insert into public.events (club_id, event_date) values (:'klubb', current_date + 21) returning id as tom \gset
insert into public.events (club_id, event_date, start_time) values (:'klubb2', current_date + 7, '17:00') returning id as fremmed \gset
-- Fristen rundt sommertid (tippekupong-test.js).
insert into public.events (club_id, event_date, start_time) values (:'klubb', '2026-10-08', '17:00') returning id as okt8 \gset
insert into public.events (club_id, event_date) values (:'klubb', '2026-11-05') returning id as nov5 \gset
insert into public.events (club_id, event_date, start_time) values (:'klubb', '2026-10-25', '17:00') returning id as okt25 \gset
insert into public.events (club_id, event_date, start_time) values (:'klubb', '2026-03-29', '17:00') returning id as mar29 \gset

-- Kvelden «spilt» har frist om to uker, men en score er ført allerede.
insert into public.rounds (club_id, event_id, status) values (:'klubb', :'spilt', 'active') returning id as runde \gset
insert into public.round_players (round_id, member_id, club_id) values (:'runde', :'anders', :'klubb');
insert into public.hole_scores (round_id, member_id, hole_index, strokes) values (:'runde', :'anders', 0, 4);
insert into public.tips (event_id, member_id, club_id, birdie) values
  (:'spilt', :'thomas', :'klubb', true), (:'spilt', :'bjorn', :'klubb', false);

-- === anon ===================================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.activity$$, '42501');
select pg_temp.feil($$select * from public.thread_messages$$, '42501');
select pg_temp.feil($$select * from public.tips$$, '42501');
select pg_temp.feil($$select * from public.push_tokens$$, '42501');
select pg_temp.feil($$select public.tips_open('$$ || :'fram' || $$')$$, '42501');
select pg_temp.feil($$select * from public.register_push_token('d', repeat('a', 64), 'sandbox')$$, '42501');
reset role;

-- === Anders: aktivitet og reaksjoner =======================================
select pg_temp.som(:'u2');
set role authenticated;
insert into public.activity (club_id, kind, category, data, actor_member_id, created_at)
  values (:'klubb', 'eagle', 'score', '{"hole": 5}', :'bjorn', '2020-01-01') returning id as hendelse \gset
select pg_temp.lik((select actor_member_id::text from public.activity where id = :'hendelse'), :'anders', 'aktør settes av serveren');
select pg_temp.lik((select created_at > now() - interval '1 minute' from public.activity where id = :'hendelse'), true, 'tid settes av serveren');
select pg_temp.feil($$insert into public.activity (club_id, kind, category) values ('$$ || :'klubb' || $$', 'hei', 'announcement')$$, '42501');
select pg_temp.feil($$insert into public.activity (club_id, kind, category, recipients) values ('$$ || :'klubb' || $$', 'x', 'signup', array['$$ || :'bjorn' || $$']::uuid[])$$, '42501');
select pg_temp.feil($$insert into public.activity (club_id, kind, category) values ('$$ || :'klubb' || $$', 'Ugyldig Type', 'score')$$, '23514');
select pg_temp.feil($$insert into public.activity (club_id, kind, category) values ('$$ || :'klubb' || $$', 'x', 'penger')$$, '23514');
select pg_temp.feil($$insert into public.activity (club_id, kind, category, data) values ('$$ || :'klubb' || $$', 'x', 'score', '[]')$$, '23514');
select pg_temp.feil($$insert into public.activity (club_id, kind, category, event_id) values ('$$ || :'klubb' || $$', 'x', 'score', '$$ || :'fremmed' || $$')$$, '23503');
select pg_temp.feil($$update public.activity set kind = 'endret'$$, '42501');
select pg_temp.feil($$delete from public.activity$$, '42501');

insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values (:'hendelse', :'anders', :'klubb', '👍');
insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values (:'hendelse', :'anders', :'klubb', '❤️');
select pg_temp.feil($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values ('$$ || :'hendelse' || $$', '$$ || :'anders' || $$', '$$ || :'klubb' || $$', '👍')$$, '23505');
select pg_temp.feil($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values ('$$ || :'hendelse' || $$', '$$ || :'anders' || $$', '$$ || :'klubb' || $$', '💩')$$, '23514');
select pg_temp.feil($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values ('$$ || :'hendelse' || $$', '$$ || :'bjorn' || $$', '$$ || :'klubb' || $$', '😂')$$, '42501');
select pg_temp.feil($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values ('$$ || :'hendelse' || $$', '$$ || :'anders2' || $$', '$$ || :'klubb2' || $$', '😂')$$, '23503');
delete from public.activity_reactions where emoji = '❤️';
reset role;

-- === Thomas (arrangør): melding til alle og purring =========================
select pg_temp.som(:'u1');
set role authenticated;
insert into public.activity (club_id, kind, category) values (:'klubb', 'message', 'announcement');
insert into public.activity (club_id, kind, category, recipients)
  values (:'klubb', 'nudge', 'nudge', array[:'anders', :'anders', :'bjorn']::uuid[]) returning id as purring \gset
select pg_temp.lik((select cardinality(recipients) from public.activity where id = :'purring'), 2, 'mottakerlista ryddes for dubletter');
select pg_temp.feil($$insert into public.activity (club_id, kind, category, recipients) values ('$$ || :'klubb' || $$', 'nudge', 'nudge', array['$$ || :'ola' || $$']::uuid[])$$, '23503');
insert into public.activity (club_id, kind, category, recipients) values (:'klubb', 'nudge', 'nudge', '{}') returning id as ingen \gset
select pg_temp.lik((select cardinality(recipients) from public.activity where id = :'ingen'), 0, 'tom mottakerliste står som tom (ingen), ikke alle');
select pg_temp.feil($$delete from public.activity$$, '42501');
reset role;

-- === Bjørn: ser loggen og reaksjonene, kan ikke fjerne andres ===============
select pg_temp.som(:'u3');
set role authenticated;
-- Bjørn ser de vanlige linjene og purringen han står på, men ikke purringen
-- med tom mottakerliste (den er til ingen).
select pg_temp.lik((select count(*) from public.activity), 3::bigint, 'medlem ser loggen unntatt linjer til andre');
select pg_temp.lik((select count(*) from public.activity where id = :'purring'), 1::bigint, 'mottaker ser purringen');
select pg_temp.lik((select count(*) from public.activity where id = :'ingen'), 0::bigint, 'linje til ingen vises ikke for medlem');
select pg_temp.lik((select count(*) from public.activity_reactions), 1::bigint, 'medlem ser reaksjonene');
with d as (delete from public.activity_reactions returning 1)
select pg_temp.lik((select count(*) from d), 0::bigint, 'kan ikke fjerne andres reaksjon');
-- Bjørn er bare med i Golfgutu (Anders er med i begge klubbene).
select pg_temp.feil($$insert into public.activity (club_id, kind, category) values ('$$ || :'klubb2' || $$', 'x', 'score')$$, '42501');
select pg_temp.lik(public.tips_deadline(:'fremmed'), null::timestamptz, 'frist for annen klubbs kveld er skjult');
reset role;

-- === Ola (annen klubb) og Per (venter): ser ingenting ======================
select pg_temp.som(:'u4');
set role authenticated;
select pg_temp.lik((select count(*) from public.activity), 0::bigint, 'annen klubb ser ikke loggen');
select pg_temp.lik((select count(*) from public.activity_reactions), 0::bigint, 'annen klubb ser ikke reaksjonene');
reset role;
select pg_temp.som(:'u5');
set role authenticated;
select pg_temp.lik((select count(*) from public.activity), 0::bigint, 'ventende ser ikke loggen');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body) values ('$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'per' || $$', 'hei')$$, '42501');
reset role;

-- === Kveldens tråd ===========================================================
select pg_temp.som(:'u2');
set role authenticated;
insert into public.thread_messages (club_id, event_id, member_id, body, mentions, created_at, pushed_at)
  values (:'klubb', :'fram', :'anders', 'Kommer 10 min sent @Bjørn', array[:'bjorn', :'bjorn']::uuid[], '2020-01-01', now())
  returning id as melding \gset
select pg_temp.lik((select pushed_at from public.thread_messages where id = :'melding'), null::timestamptz, 'pushed_at kan ikke settes av klienten');
select pg_temp.lik((select created_at > now() - interval '1 minute' from public.thread_messages where id = :'melding'), true, 'meldingens tid settes av serveren');
select pg_temp.lik((select cardinality(mentions) from public.thread_messages where id = :'melding'), 1, 'nevnte ryddes for dubletter');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body) values ('$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'anders' || $$', '   ')$$, '23514');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body) values ('$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'anders' || $$', repeat('x', 501))$$, '23514');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body) values ('$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'bjorn' || $$', 'falsk')$$, '42501');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body, mentions) values ('$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'anders' || $$', 'hei', array['$$ || :'ola' || $$']::uuid[])$$, '23503');
select pg_temp.feil($$insert into public.thread_messages (club_id, event_id, member_id, body) values ('$$ || :'klubb' || $$', '$$ || :'fremmed' || $$', '$$ || :'anders' || $$', 'feil klubb')$$, '23503');
insert into public.thread_messages (id, club_id, event_id, member_id, image_path)
  values ('33333333-0000-0000-0000-000000000001', :'klubb', :'fram', :'anders', upper(:'anders') || '/33333333-0000-0000-0000-000000000001.JPG');
select pg_temp.lik((select image_path from public.thread_messages where id = '33333333-0000-0000-0000-000000000001'),
                   :'anders' || '/33333333-0000-0000-0000-000000000001.jpg', 'melding med bare bilde, stien med små bokstaver');
select pg_temp.feil($$insert into public.thread_messages (id, club_id, event_id, member_id, image_path) values ('33333333-0000-0000-0000-000000000002', '$$ || :'klubb' || $$', '$$ || :'fram' || $$', '$$ || :'anders' || $$', '$$ || :'bjorn' || $$/33333333-0000-0000-0000-000000000002.jpg')$$, '23514');
select pg_temp.feil($$update public.thread_messages set body = 'endret'$$, '42501');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select count(*) from public.thread_messages), 2::bigint, 'medlem ser tråden');
with d as (delete from public.thread_messages where id = :'melding' returning 1)
select pg_temp.lik((select count(*) from d), 0::bigint, 'kan ikke slette andres melding');
reset role;

select pg_temp.som(:'u4');
set role authenticated;
select pg_temp.lik((select count(*) from public.thread_messages), 0::bigint, 'annen klubb ser ikke tråden');
reset role;

select pg_temp.som(:'u1');
set role authenticated;
with d as (delete from public.thread_messages where id = :'melding' returning 1)
select pg_temp.lik((select count(*) from d), 1::bigint, 'arrangøren sletter andres melding');
reset role;

-- === Tippekupongen ===========================================================
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik(public.tips_deadline(:'okt8'),  '2026-10-08 15:00:00+00'::timestamptz, 'frist 8. okt. 17:00 = 15:00Z (sommertid)');
select pg_temp.lik(public.tips_deadline(:'nov5'),  '2026-11-05 16:00:00+00'::timestamptz, 'frist 5. nov. uten klokkeslett = 17:00 = 16:00Z');
select pg_temp.lik(public.tips_deadline(:'okt25'), '2026-10-25 16:00:00+00'::timestamptz, 'frist 25. okt. (vintertid samme natt) = 16:00Z');
select pg_temp.lik(public.tips_deadline(:'mar29'), '2026-03-29 15:00:00+00'::timestamptz, 'frist 29. mars (sommertid samme natt) = 15:00Z');
select pg_temp.lik(public.tips_open(:'fram'), true, 'kupongen er åpen før fristen');
select pg_temp.lik(public.tips_open(:'forbi'), false, 'kupongen er låst etter fristen');
select pg_temp.lik(public.tips_open(:'spilt'), false, 'kupongen er låst ved første score');

insert into public.tips (event_id, member_id, club_id, winner, front_nine, most_pars, birdie, over_line, created_at)
  values (:'fram', :'anders', :'klubb', :'bjorn', :'anders', :'thomas', true, false, '2020-01-01');
select pg_temp.lik((select created_at > now() - interval '1 minute' from public.tips where event_id = :'fram' and member_id = :'anders'), true, 'tipsets tid settes av serveren');
update public.tips set over_line = true where event_id = :'fram' and member_id = :'anders';
select pg_temp.lik((select over_line from public.tips where event_id = :'fram' and member_id = :'anders'), true, 'eget tips kan endres mens kupongen er åpen');
select pg_temp.feil($$update public.tips set member_id = '$$ || :'bjorn' || $$' where event_id = '$$ || :'fram' || $$' and member_id = '$$ || :'anders' || $$'$$, '22023');
select pg_temp.feil($$insert into public.tips (event_id, member_id, club_id, birdie) values ('$$ || :'forbi' || $$', '$$ || :'anders' || $$', '$$ || :'klubb' || $$', true)$$, '42501');
select pg_temp.feil($$insert into public.tips (event_id, member_id, club_id, birdie) values ('$$ || :'spilt' || $$', '$$ || :'anders' || $$', '$$ || :'klubb' || $$', true)$$, '42501');
select pg_temp.feil($$insert into public.tips (event_id, member_id, club_id, birdie) values ('$$ || :'tom' || $$', '$$ || :'bjorn' || $$', '$$ || :'klubb' || $$', true)$$, '42501');
select pg_temp.feil($$insert into public.tips (event_id, member_id, club_id, winner) values ('$$ || :'tom' || $$', '$$ || :'anders' || $$', '$$ || :'klubb' || $$', '$$ || :'ola' || $$')$$, '23503');
select pg_temp.lik((select count(*) from public.tips where event_id = :'spilt'), 2::bigint, 'andres tips synlige når kupongen er låst');
with d as (delete from public.tips where event_id = :'spilt' returning 1)
select pg_temp.lik((select count(*) from d), 0::bigint, 'kan ikke trekke andres eller låste tips');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
insert into public.tips (event_id, member_id, club_id, birdie) values (:'fram', :'bjorn', :'klubb', false);
select pg_temp.lik((select count(*) from public.tips where event_id = :'fram'), 1::bigint, 'før låsing ser du bare ditt eget tips');
select pg_temp.lik((select count(*) from public.tips_submitted(:'fram')), 2::bigint, 'tips_submitted viser hvem som har levert');
reset role;

select pg_temp.som(:'u4');
set role authenticated;
select pg_temp.feil($$select * from public.tips_submitted('$$ || :'fram' || $$')$$, 'P0002');
select pg_temp.lik((select count(*) from public.tips), 0::bigint, 'annen klubb ser ingen tips');
reset role;

select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.feil($$update public.events set tips_stake_points = 100 where id = '$$ || :'fram' || $$'$$, '55000');
update public.events set tips_stake_points = 0, tips_line = 3.5 where id = :'tom';
select pg_temp.lik((select tips_stake_points from public.events where id = :'tom'), 0::smallint, 'innsats kan settes før første kupong (0 = for æra)');
select pg_temp.feil($$update public.events set tips_line = 3.0 where id = '$$ || :'tom' || $$'$$, '23514');
update public.events set venue = 'Bås 3' where id = :'fram';
select pg_temp.lik((select venue from public.events where id = :'fram'), 'Bås 3', 'andre felt på kvelden kan endres etter levering');
with d as (delete from public.tips where event_id = :'spilt' and member_id = :'bjorn' returning 1)
select pg_temp.lik((select count(*) from d), 1::bigint, 'arrangøren kan fjerne et tips når som helst');
reset role;

-- === Push-tokens ============================================================
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik((select count(*) from public.register_push_token('ENHET-A', upper(repeat('ab', 32)), 'sandbox')), 2::bigint,
                   'Anders registrerer enheten for begge klubbene');
select pg_temp.lik((select count(*) from public.register_push_token('ENHET-A', repeat('ab', 32), 'production')), 2::bigint,
                   'registrering er idempotent');
select pg_temp.lik((select string_agg(distinct environment, ',') from public.push_tokens), 'production', 'miljøet oppdateres');
select pg_temp.feil($$select * from public.register_push_token('ENHET-A', 'ikke-heks', 'sandbox')$$, '22023');
select pg_temp.feil($$select * from public.register_push_token('ENHET-A', repeat('ab', 32), 'dev')$$, '22023');
select pg_temp.feil($$insert into public.push_tokens (user_id, member_id, club_id, device_id, token, environment) values (auth.uid(), '$$ || :'anders' || $$', '$$ || :'klubb' || $$', 'x', repeat('ab', 32), 'sandbox')$$, '42501');
select pg_temp.feil($$update public.push_tokens set token = repeat('cd', 32)$$, '42501');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select count(*) from public.push_tokens), 0::bigint, 'Bjørn ser ikke Anders sine tokens');
select pg_temp.lik((select count(*) from public.register_push_token('ENHET-A', repeat('ef', 32), 'production')), 1::bigint,
                   'Bjørn tar over enheten');
reset role;

select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik((select count(*) from public.push_tokens), 0::bigint, 'Anders mistet enheten som byttet eier');
select pg_temp.lik((select count(*) from public.register_push_token('ENHET-B', repeat('12', 32), 'sandbox')), 2::bigint, 'ny enhet');
select pg_temp.lik((select count(*) from public.register_push_token('ENHET-C', repeat('12', 32), 'sandbox')), 2::bigint, 'samme token, ny enhets-id');
select pg_temp.lik((select count(*) from public.push_tokens), 2::bigint, 'den gamle enhets-id-en er ryddet bort');
with d as (delete from public.push_tokens where device_id = 'ENHET-C' returning 1)
select pg_temp.lik((select count(*) from d), 2::bigint, 'logg ut: egne tokens slettes');
reset role;

-- === Storage ================================================================
\set bilde1 '44444444-0000-0000-0000-000000000001'
select pg_temp.som(:'u2');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('avatars', :'anders' || '/' || :'bilde1' || '.jpg');
select pg_temp.lik((select count(*) from storage.objects where bucket_id = 'avatars'), 1::bigint, 'eget portrett lastet opp');
select pg_temp.feil($$insert into storage.objects (bucket_id, name) values ('avatars', '$$ || :'bjorn' || $$/$$ || :'bilde1' || $$.jpg')$$, '42501');
select pg_temp.feil($$insert into storage.objects (bucket_id, name) values ('avatars', 'abc/$$ || :'bilde1' || $$.jpg')$$, '42501');
select pg_temp.feil($$insert into storage.objects (bucket_id, name) values ('avatars', '$$ || :'anders' || $$/$$ || :'bilde1' || $$.png')$$, '42501');
select pg_temp.feil($$insert into storage.objects (bucket_id, name) values ('avatars', 'x/$$ || :'anders' || $$/$$ || :'bilde1' || $$.jpg')$$, '42501');
insert into storage.objects (bucket_id, name) values ('thread', :'anders' || '/33333333-0000-0000-0000-000000000001.jpg');
update public.club_members set avatar_path = :'anders' || '/' || :'bilde1' || '.jpg' where id = :'anders';
select pg_temp.lik((select avatar_path from public.club_members where id = :'anders'), :'anders' || '/' || :'bilde1' || '.jpg', 'egen rad peker på eget portrett');
select pg_temp.feil($$update public.club_members set avatar_path = '$$ || :'bjorn' || $$/$$ || :'bilde1' || $$.jpg' where id = '$$ || :'anders' || $$'$$, '23514');
with u as (update storage.objects set name = name returning 1)
select pg_temp.lik((select count(*) from u), 0::bigint, 'ingen kan overskrive en fil');
reset role;

select pg_temp.som(:'u1');
set role authenticated;
insert into storage.objects (bucket_id, name) values ('avatars', :'bjorn' || '/' || :'bilde1' || '.jpg');
select pg_temp.lik((select count(*) from storage.objects where bucket_id = 'avatars'), 2::bigint, 'arrangøren laster opp portrett for andre');
select pg_temp.feil($$insert into storage.objects (bucket_id, name) values ('thread', '$$ || :'bjorn' || $$/$$ || :'bilde1' || $$.jpg')$$, '42501');
with d as (delete from storage.objects where bucket_id = 'thread' returning 1)
select pg_temp.lik((select count(*) from d), 1::bigint, 'arrangøren sletter andres trådbilde');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select count(*) from storage.objects), 2::bigint, 'medlem ser klubbens bilder');
with d as (delete from storage.objects where name like :'anders' || '%' returning 1)
select pg_temp.lik((select count(*) from d), 0::bigint, 'kan ikke slette andres portrett');
reset role;

select pg_temp.som(:'u4');
set role authenticated;
select pg_temp.lik((select count(*) from storage.objects), 0::bigint, 'annen klubb ser ingen bilder');
reset role;

select pg_temp.som('');
set role anon;
select pg_temp.lik((select count(*) from storage.objects), 0::bigint, 'anon ser ingen bilder');
reset role;
