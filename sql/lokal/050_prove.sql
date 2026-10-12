\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 050_sosialt.sql. Kjøres på kopien med 001–043, 034, 044, 045, 047, lokal/046_for.sql,
-- 046, 049 og 050 (to ganger). Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- R: reaksjoner: hvilken som helst emoji på hendelse, melding og kommentar; gamle bygg via
--    activity_reactions (speiling begge veier); unikhet; grensen på 20; RLS; uten klubb (profil).
-- C: kommentarer: legge til, endre, myk sletting (forfatter og moderator), omtaler som må kunne se
--    målet, flate, varslene (comment_added, mentioned) og mottakerne, uten klubb, rapport og
--    resolve_report, ingen direkte skriving.
-- F: følg tråden.
-- B: blokkering (begge veier) for reaksjoner, kommentarer, omtaler, mottakere og hendelsens aktør.
-- V: can_read_target er lik activity_select for hver innlogging.
-- P: feed_page: sider uten hull og dobbeltrader med like tider, tall og mine reaksjoner, uten
--    klubb, mottakerlister, blokkering, grenser, anon.
-- H: bildeoppfordring: én per låst runde, spillerne som mottakere, ikke løse runder; push i gruppen
--    Sosialt (av = ingen telefoner), collapse.
-- D: sletting av konto tar kommentarene, reaksjonene og følgingen.
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
-- Alle hendelsene, uten RLS (for paritetsprøven V).
create function pg_temp.alle_hendelser() returns setof uuid language sql security definer as $$
  select id from public.activity
$$;
-- Bla gjennom hele feeden med en gitt sidestørrelse. Svarer id-ene i rekkefølge.
create function pg_temp.bla(p_clubs uuid[], p_limit int) returns uuid[] language plpgsql as $$
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
    for v_rad in select f.id, f.created_at from public.feed_page(p_clubs, v_ts, v_id, p_limit) f loop
      v_ids := v_ids || v_rad.id;
      v_ts := v_rad.created_at; v_id := v_rad.id; v_n := v_n + 1;
    end loop;
    v_runder := v_runder + 1;
    exit when v_n < p_limit or v_runder > 1000;
  end loop;
  return v_ids;
end $$;
grant execute on all functions in schema pg_temp to public;

\set u1  '00000000-0000-0000-0000-000000000001'
\set u2  '00000000-0000-0000-0000-000000000002'
\set u3  '00000000-0000-0000-0000-000000000003'
\set u4  '00000000-0000-0000-0000-000000000004'
\set u5  '00000000-0000-0000-0000-000000000005'
\set w1  '00000000-0000-0000-0000-000000005001'
\set w2  '00000000-0000-0000-0000-000000005002'
\set w3  '00000000-0000-0000-0000-000000005003'
\set G   'aaaaaaaa-0000-0000-0000-000000000001'
\set m1  '11111111-0000-0000-0000-000000000001'
\set m2  '11111111-0000-0000-0000-000000000002'
\set m3  '11111111-0000-0000-0000-000000000003'
\set m9  '11111111-0000-0000-0000-000000000009'
\set ola '22222222-0000-0000-0000-000000000004'
\set p1  '11111111-0000-0000-0000-000000005001'
\set p2  '11111111-0000-0000-0000-000000005002'
\set FK  'c0000000-0000-0000-0000-0000000050f1'
\set S26 'badcb270-4100-4fc8-ab14-b281af41cbbb'
\set E3  'eeeeeeee-0000-0000-0000-000000000003'
\set R3  'dddddddd-0000-0000-0000-000000000003'
\set RL  'dddddddd-0000-0000-0000-0000000050a1'
\set A1  'a0000000-0000-0000-0000-000000005001'
\set AP  'a0000000-0000-0000-0000-000000005002'
\set AF  'a0000000-0000-0000-0000-000000005003'
\set MSG '70000000-0000-0000-0000-0000000044a1'

begin;

-- --- Verdenen --------------------------------------------------------------------
-- w1 og w2: vanlige medlemmer i Golfgutu (p1, p2). w3: bare med i Vennecup 50 (uten klubb, eier u1).
-- A1: en sidepremie i Golfgutu (aktør Bjørn, m3). AP: en purring bare til p1 (aktør Thomas, m1).
-- AF: en hendelse i Vennecup 50 uten klubb. MSG: Bjørns melding i tråden (044_for).
select pg_temp.som('');
insert into auth.users (id) values (:'w1'), (:'w2'), (:'w3');
update public.profiles set display_name = 'Vanlig 1' where id = :'w1';
update public.profiles set display_name = 'Vanlig 2' where id = :'w2';
update public.profiles set display_name = 'Venn 3' where id = :'w3';
insert into public.club_members (id, club_id, user_id, display_name, status) values
  (:'p1', :'G', :'w1', 'Vanlig 1', 'active'), (:'p2', :'G', :'w2', 'Vanlig 2', 'active');
insert into public.competitions (id, kind, name, club_id, owner_id, status, entry)
values (:'FK', 'fun', 'Vennecup 50', null, :'u1', 'active', 'listed');
insert into public.competition_participants (competition_id, profile_id, status) values (:'FK', :'w3', 'active');
insert into public.activity (id, club_id, kind, category, data, actor_member_id, event_id, created_at) values
  (:'A1', :'G', 'side_prize', 'side_prize', '{"prize": "kp"}', :'m3', :'E3', '2026-10-01 20:00+02');
insert into public.activity (id, club_id, kind, category, data, actor_member_id, recipients, created_at) values
  (:'AP', :'G', 'nudge', 'nudge', '{}', :'m1', array[:'p1']::uuid[], '2026-10-01 20:01+02');
insert into public.activity (id, club_id, competition_id, kind, category, data, created_at) values
  (:'AF', null, :'FK', 'member_joined', 'club', '{}', '2026-10-01 20:02+02');
select pg_temp.lik((select count(*) from public.reactions), (select count(*) from public.activity_reactions),
                   'R0 reactions har like mange rader som activity_reactions før prøven');

-- --- R: reaksjoner ---------------------------------------------------------------------
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik(public.react('activity', :'A1', '🏌️‍♂️'), true, 'R1 fri emoji (ZWJ-sekvens) på en hendelse');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'A1'), 1::bigint, 'R2 én reaksjon');
select pg_temp.lik((select count(*) from public.activity_reactions where activity_id = :'A1'), 0::bigint,
                   'R3 en emoji utenfor fem-settet speiles ikke til gamle bygg');
select pg_temp.lik(public.react('activity', :'A1', '👍'), true, 'R4 en av de fem');
select pg_temp.lik((select member_id || '|' || emoji from public.activity_reactions where activity_id = :'A1'),
                   :'p1' || '|👍', 'R5 de fem speiles til activity_reactions (gamle bygg ser den)');
select pg_temp.lik(public.react('activity', :'A1', '👍'), true, 'R6 samme reaksjon igjen går fint');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'A1'), 2::bigint, 'R7 ingen dobbel rad');
select pg_temp.lik(public.react('activity', :'A1', '👍', false), false, 'R8 ta bort reaksjonen');
select pg_temp.lik((select count(*) from public.activity_reactions where activity_id = :'A1')
                   || '|' || (select count(*) from public.reactions where target_id = :'A1'), '0|1',
                   'R9 borte begge steder, den frie står');
-- Gamle bygg: rett inn i og ut av activity_reactions.
insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values (:'A1', :'p1', :'G', '🔥');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'A1' and member_id = :'p1' and emoji = '🔥'),
                   1::bigint, 'R10 gammelt bygg legger inn i activity_reactions: speiles til reactions');
delete from public.activity_reactions where activity_id = :'A1' and emoji = '🔥';
select pg_temp.lik((select count(*) from public.reactions where target_id = :'A1' and emoji = '🔥'),
                   0::bigint, 'R11 gammelt bygg sletter: borte i reactions');
select pg_temp.lik((select count(*) from public.activity_reactions where activity_id = :'A1'), 0::bigint,
                   'R12 gammelt bygg leser activity_reactions som før');
select pg_temp.feil(format($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values (%L, %L, %L, '🏌️')$$,
                           :'A1', :'p1', :'G'), '23514');
select pg_temp.feil(format($$select public.react('activity', %L, 'a')$$, :'A1'), '22023');
select pg_temp.feil(format($$select public.react('activity', %L, '👍👍')$$, :'A1'), '22023');
select pg_temp.feil(format($$select public.react('activity', %L, repeat('👍', 17))$$, :'A1'), '22023');
select pg_temp.feil(format($$select public.react('event', %L, '👍')$$, :'A1'), '22023');
select pg_temp.feil(format($$insert into public.reactions (target_kind, target_id, club_id, member_id, emoji) values ('activity', %L, %L, %L, '👍')$$,
                           :'A1', :'G', :'p1'), '42501');
select pg_temp.lik(public.react('message', :'MSG', '🤣'), true, 'R13 reaksjon på en melding i tråden');
-- Grensen: 20 forskjellige per person og mål.
select pg_temp.lik((select count(*) from unnest(array['😀','😃','😄','😁','😆','😅','😊','😇','🙂','🙃','😉','😌','😍','🥰','😘','😗','😙','😚','😋']) e
                     where public.react('message', :'MSG', e)), 19::bigint, 'R14 19 til (20 i alt)');
select pg_temp.feil(format($$select public.react('message', %L, '🤪')$$, :'MSG'), '22023');
select pg_temp.lik(public.react('message', :'MSG', '🤣'), true, 'R15 en du alt har, går fortsatt');
select pg_temp.lik(public.react('message', :'MSG', '😀', false), false, 'R16 ta bort en');
select pg_temp.lik(public.react('message', :'MSG', '🤪'), true, 'R17 så er det plass til en ny');
reset role;
select pg_temp.feil(format($$insert into public.reactions (target_kind, target_id, club_id, member_id, emoji) values ('activity', %L, %L, %L, '🏌️‍♂️')$$,
                           :'A1', :'G', :'p1'), '23505');
-- En annen klubb ser ingenting og kan ikke reagere.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.reactions where target_id in (:'A1', :'MSG')), 0::bigint,
                   'R18 Ola (annen klubb) ser ingen reaksjoner');
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'A1'), 'P0002');
select pg_temp.feil(format($$select public.react('message', %L, '👍')$$, :'MSG'), 'P0002');
reset role;
-- Mottakerliste: bare p1 (og arrangørene) ser AP.
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'AP'), 'P0002');
select pg_temp.lik(public.react('activity', :'A1', '🔥'), true, 'R19 w2 reagerer på A1');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.react('activity', :'AP', '❤️'), true, 'R20 Anders (rettighet, ser alt) reagerer på AP');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik(public.react('activity', :'AP', '😂'), true, 'R21 mottakeren reagerer på AP');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'AP'), 2::bigint, 'R22 mottakeren ser begge');
reset role;
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.lik((select count(*) from public.reactions where target_id = :'AP'), 0::bigint,
                   'R23 den som ikke er mottaker, ser ingen reaksjoner på AP');
reset role;
-- Uten klubb: som profil.
select pg_temp.som(:'w3'); set role authenticated;
select pg_temp.lik(public.react('activity', :'AF', '🎉'), true, 'R24 deltaker uten klubb reagerer');
select pg_temp.lik((select (member_id is null) || '|' || profile_id || '|' || (club_id is null) || '|' || competition_id
                      from public.reactions where target_id = :'AF'),
                   'true|' || :'w3' || '|true|' || :'FK', 'R25 lagret som profil, med turneringen');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'AF'), 'P0002');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.react('activity', :'AF', '👍'), true, 'R26 eieren av turneringen reagerer (som profil)');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'AF'), 2::bigint, 'R27 eieren ser begge');
select pg_temp.lik((select count(*) from public.activity_reactions where activity_id = :'AF'), 0::bigint,
                   'R28 uten klubb speiles ikke til activity_reactions (krever klubb)');
reset role;

-- --- C: kommentarer -----------------------------------------------------------------
select pg_temp.som(:'w1'); set role authenticated;
select (public.comment_add('activity', :'A1', '  Bra slag, Bjørn! ', array[:'m3']::uuid[])).id as c1 \gset
select pg_temp.lik((select body || '|' || member_id || '|' || club_id || '|' || mentions::text || '|' || (profile_id is null)
                      from public.comments where id = :'c1'),
                   'Bra slag, Bjørn!|' || :'p1' || '|' || :'G' || '|{' || :'m3' || '}|true', 'C1 kommentar lagret, trimmet, som medlem');
reset role;
select pg_temp.som('');
select pg_temp.lik((select recipients from public.activity where kind = 'mentioned' and data ->> 'comment_id' = :'c1'),
                   array[:'m3']::uuid[], 'C2 mentioned til Bjørn');
select pg_temp.lik((select count(*) from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'c1'),
                   0::bigint, 'C3 ingen comment_added: forfatteren er nevnt (får mentioned), og den som skrev får ingen');
select pg_temp.lik((select category || '|' || actor_member_id || '|' || event_id || '|' || (data ->> 'preview') || '|' || (data ->> 'target_id')
                      from public.activity where kind = 'mentioned' and data ->> 'comment_id' = :'c1'),
                   'social|' || :'p1' || '|' || :'E3' || '|Bra slag, Bjørn!|' || :'A1', 'C4 varselet: social, aktør, kvelden, utdrag, målet');
select pg_temp.lik((select following from public.thread_follows where user_id = :'w1' and target_id = :'A1'), true,
                   'C5 den som kommenterer, følger tråden');
select pg_temp.som(:'w2'); set role authenticated;
select (public.comment_add('activity', :'A1', 'Enig')).id as c2 \gset
reset role;
select pg_temp.lik((select recipients from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'c2'),
                   array[:'m3', :'p1']::uuid[], 'C6 comment_added til forfatteren (m3) og den som følger (p1)');
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik(public.follow_thread('activity', :'A1', false), false, 'C7 w1 slutter å følge');
reset role;
select pg_temp.som(:'w2'); set role authenticated;
select (public.comment_add('activity', :'A1', 'Igjen')).id as c3 \gset
reset role;
select pg_temp.lik((select recipients from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'c3'),
                   array[:'m3']::uuid[], 'C8 bare forfatteren nå');
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.follow_thread('activity', :'A1', false), false, 'C9 forfatteren slår av tråden');
reset role;
select pg_temp.som(:'w2'); set role authenticated;
select (public.comment_add('activity', :'A1', 'Hallo?')).id as c4 \gset
reset role;
select pg_temp.lik((select count(*) from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'c4'),
                   0::bigint, 'C10 ingen mottakere: ingen linje');
-- Omtaler må kunne se målet.
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x', array[%L]::uuid[])$$, :'A1', :'ola'), '22023');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x', array[%L]::uuid[])$$, :'A1', :'m9'), '22023');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x', array[%L]::uuid[])$$, :'AP', :'p2'), '22023');
select pg_temp.lik((select cardinality(mentions) from public.comment_add('activity', :'AP', 'Til Anders', array[:'m2']::uuid[])),
                   1, 'C11 på AP kan Anders nevnes (han ser den)');
select (public.comment_add('activity', :'A1', 'meg', array[:'p1']::uuid[])).id as cmeg \gset
select pg_temp.lik((select mentions from public.comments where id = :'cmeg'), '{}'::uuid[], 'C12 å nevne seg selv tas bort');
select pg_temp.feil(format($$select public.comment_add('activity', %L, '')$$, :'A1'), '22023');
select pg_temp.feil(format($$select public.comment_add('activity', %L, '   ')$$, :'A1'), '22023');
select pg_temp.feil(format($$select public.comment_add('activity', %L, repeat('x', 1001))$$, :'A1'), '22023');
select pg_temp.lik((select char_length(body) from public.comment_add('message', :'MSG', repeat('x', 1000), '{}', false)),
                   1000, 'C13 1000 tegn går (uten å følge)');
select pg_temp.lik((select count(*) from public.thread_follows where user_id = :'w1' and target_kind = 'message'), 0::bigint,
                   'C14 p_follow = false: følger ikke');
select pg_temp.feil(format($$select public.comment_add('comment', %L, 'svar')$$, :'c1'), '22023');
select pg_temp.feil(format($$insert into public.comments (target_kind, target_id, club_id, member_id, body) values ('activity', %L, %L, %L, 'x')$$,
                           :'A1', :'G', :'p1'), '42501');
select pg_temp.feil(format($$update public.comments set body = 'x' where id = %L$$, :'c1'), '42501');
select pg_temp.feil(format($$delete from public.comments where id = %L$$, :'c1'), '42501');
-- Endre.
select pg_temp.lik((select body || '|' || (edited_at is not null) from public.comment_edit(:'c1', ' Endret ', array[:'m3', :'m2']::uuid[])),
                   'Endret|true', 'C15 forfatteren endrer');
reset role;
select pg_temp.lik((select string_agg(recipients::text, ';' order by recipients::text) from public.activity
                     where kind = 'mentioned' and data ->> 'comment_id' = :'c1'),
                   '{' || :'m2' || '};{' || :'m3' || '}', 'C16 bare den nye omtalen (Anders) får et nytt varsel');
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.feil(format($$select public.comment_edit(%L, 'kapret')$$, :'c1'), '42501');
select pg_temp.feil(format($$select public.comment_delete(%L)$$, :'c1'), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.comment_edit(%L, 'x')$$, :'c1'), 'P0002');
select pg_temp.feil(format($$select public.comment_delete(%L)$$, :'c1'), 'P0002');
select pg_temp.lik((select count(*) from public.comments where target_id = :'A1'), 0::bigint, 'C17 en annen klubb ser ingen kommentarer');
reset role;
-- Reaksjon på en kommentar, så myk sletting av en moderator (money).
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.react('comment', :'c3', '😂'), true, 'C18 reaksjon på en kommentar');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.comment_delete(:'c3'), true, 'C19 Anders (money) sletter w2 sin kommentar');
select pg_temp.lik(public.comment_delete(:'c2'), true, 'C20 og en til');
reset role;
select pg_temp.lik((select (deleted_at is not null) || '|' || deleted_by || '|' || body || '|' || mentions::text
                      from public.comments where id = :'c3'),
                   'true|' || :'u2' || '||{}', 'C21 myk sletting: raden står, tekst og omtaler tømt, hvem');
select pg_temp.lik((select count(*) from public.reactions where target_kind = 'comment' and target_id = :'c3'), 0::bigint,
                   'C22 reaksjonene på den slettede kommentaren er borte');
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.feil(format($$select public.react('comment', %L, '😂')$$, :'c3'), 'P0002');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik(public.comment_delete(:'c1'), true, 'C23 forfatteren sletter sin egen');
select pg_temp.lik(public.comment_delete(:'c1'), false, 'C24 en gang til: ingenting å slette');
select pg_temp.feil(format($$select public.comment_edit(%L, 'x')$$, :'c1'), 'P0002');
select pg_temp.lik((select count(*) || '|' || count(*) filter (where deleted_at is not null) from public.comments where target_id = :'A1'),
                   '5|3', 'C25 medlemmet ser alle fem på A1, tre er slettet');
reset role;
-- Kommentar på en melding: forfatteren av meldingen får varsel, med kvelden og turneringen.
select pg_temp.som(:'u1'); set role authenticated;
select (public.comment_add('message', :'MSG', 'Hyggelig kveld')).id as cm \gset
select pg_temp.lik((select competition_id from public.comments where id = :'cm'), :'S26'::uuid,
                   'C26 kommentaren på meldingen har kveldens turnering');
reset role;
select pg_temp.lik((select recipients::text || '|' || event_id from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'cm'),
                   '{' || :'m3' || '}|' || :'E3', 'C27 comment_added til Bjørn, på kvelden');
-- Uten klubb: profiler.
select pg_temp.som(:'w3'); set role authenticated;
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x', array[%L]::uuid[])$$, :'AF', :'u2'), '22023');
select (public.comment_add('activity', :'AF', 'Hei Thomas', array[:'u1']::uuid[])).id as cf \gset
select pg_temp.lik((select (club_id is null) || '|' || competition_id || '|' || profile_id from public.comments where id = :'cf'),
                   'true|' || :'FK' || '|' || :'w3', 'C28 kommentar uten klubb: profil og turnering');
reset role;
select pg_temp.lik((select recipients::text || '|' || (club_id is null) || '|' || competition_id
                      from public.activity where kind = 'mentioned' and data ->> 'comment_id' = :'cf'),
                   '{' || :'u1' || '}|true|' || :'FK', 'C29 mentioned uten klubb: profil-id som mottaker');
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'mentioned' and data ->> 'comment_id' = :'cf'), 1::bigint,
                   'C30 mottakeren ser linja (activity_select uten klubb med mottakerliste)');
select (public.comment_add('activity', :'AF', 'Hei selv')).id as cf2 \gset
reset role;
select pg_temp.lik((select recipients from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'cf2'),
                   array[:'w3']::uuid[], 'C31 comment_added uten klubb til den som følger (w3)');
select pg_temp.som(:'w3'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'cf2'), 1::bigint,
                   'C32 w3 ser sitt varsel');
select pg_temp.lik((select count(*) from public.activity where kind = 'mentioned' and data ->> 'comment_id' = :'cf'), 0::bigint,
                   'C33 w3 ser ikke varselet til u1 (bare aktør i klubb ser egne)');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.comments where target_id = :'AF')
                   + (select count(*) from public.activity where competition_id = :'FK'), 0::bigint,
                   'C34 en som ikke er med i turneringen, ser ingenting');
reset role;
-- Rapport og fjerning.
select pg_temp.som(:'u3'); set role authenticated;
select public.report_content('comment', :'c4', 'offensive', 'Stygt') as rep \gset
select pg_temp.lik((select kind || '|' || club_id || '|' || target_profile_id || '|' || snapshot from public.content_reports where id = :'rep'),
                   'comment|' || :'G' || '|' || :'w2' || '|Hallo?', 'C35 rapport på kommentar: klubb, forfatter, øyeblikksbilde');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.feil(format($$select public.resolve_report(%L, 'remove')$$, :'rep'), '42501');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.report_content('comment', %L, 'spam')$$, :'c4'), 'P0002');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select public.resolve_report(:'rep', 'remove') ->> 'status'), 'removed', 'C36 money fjerner');
reset role;
select pg_temp.lik((select (deleted_at is not null) || '|' || body from public.comments where id = :'c4'), 'true|',
                   'C37 kommentaren er mykt slettet');
select pg_temp.som(:'w3'); set role authenticated;
select public.report_content('comment', :'cf2', 'spam') as repf \gset
select pg_temp.feil(format($$select public.resolve_report(%L, 'dismiss')$$, :'repf'), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select (club_id is null) || '|' || competition_id from public.content_reports where id = :'repf'),
                   'true|' || :'FK', 'C38 rapport uten klubb: turneringen, og arrangøren ser den');
select pg_temp.lik((select public.resolve_report(:'repf', 'remove') ->> 'status'), 'removed', 'C39 turneringens arrangør fjerner');
reset role;
select pg_temp.lik((select deleted_at is not null from public.comments where id = :'cf2'), true, 'C40 slettet');

-- --- F: følg tråden -------------------------------------------------------------------
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format($$select public.follow_thread('activity', %L, true)$$, :'A1'), 'P0002');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.feil(format($$select public.follow_thread('comment', %L, true)$$, :'cmeg'), '22023');
select pg_temp.feil(format($$select public.follow_thread('activity', %L, null)$$, :'A1'), '22023');
select pg_temp.lik(public.follow_thread('message', :'MSG', true), true, 'F1 w1 følger meldingen');
select pg_temp.lik((select bool_and(user_id = :'w1') and count(*) > 0 from public.thread_follows), true,
                   'F2 bare egne rader i thread_follows');
select pg_temp.feil(format($$insert into public.thread_follows (user_id, target_kind, target_id) values (%L, 'activity', %L)$$, :'w1', :'A1'), '42501');
reset role;

-- --- B: blokkering --------------------------------------------------------------------
select pg_temp.som('');
insert into public.user_blocks (blocker_id, blocked_id) values (:'w2', :'w1');
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.lik((select count(*) from public.reactions where member_id = :'p1'), 0::bigint,
                   'B1 w2 ser ingen reaksjoner fra w1 (som w2 blokkerte)');
select pg_temp.lik((select count(*) from public.comments where member_id = :'p1'), 0::bigint, 'B2 og ingen kommentarer');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x', array[%L]::uuid[])$$, :'A1', :'p1'), '22023');
select (public.comment_add('message', :'MSG', 'Hei alle')).id as cb \gset
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik((select count(*) from public.reactions where member_id = :'p2'), 0::bigint,
                   'B3 begge veier: w1 ser ingen reaksjoner fra w2');
select pg_temp.lik((select count(*) from public.comments where member_id = :'p2'), 0::bigint, 'B4 og ingen kommentarer');
reset role;
select pg_temp.lik((select recipients from public.activity where kind = 'comment_added' and data ->> 'comment_id' = :'cb'),
                   array[:'m1', :'m3']::uuid[], 'B5 mottakerne: Bjørn (forfatter) og Thomas (følger), ikke w1 (blokkert)');
-- Aktøren: w2 blokkerer Bjørn, som står bak A1.
select pg_temp.som('');
insert into public.user_blocks (blocker_id, blocked_id) values (:'w2', :'u3');
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'A1'), 'P0002');
select pg_temp.feil(format($$insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values (%L, %L, %L, '❤️')$$,
                           :'A1', :'p2', :'G'), '42501');
select pg_temp.lik((select count(*) from public.reactions where target_id = :'A1'), 0::bigint,
                   'B6 reaksjonene på en blokkert persons hendelse ses ikke');
select pg_temp.lik((select count(*) from public.comments where target_kind = 'message' and target_id = :'MSG'), 0::bigint,
                   'B7 kommentarene på en blokkert persons melding ses ikke');
reset role;

-- --- V: can_read_target er lik activity_select --------------------------------------------
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V1 u1');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V2 u2');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V3 u3');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V4 u4');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V5 w1');
reset role;
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V6 w2');
reset role;
select pg_temp.som(:'w3'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity a where not private.person_blocked(a.actor_member_id, null)),
                   (select count(*) from pg_temp.alle_hendelser() i where private.can_read_target('activity', i)), 'V7 w3');
reset role;

-- --- P: feed_page ------------------------------------------------------------------------
-- 25 hendelser med nøyaktig samme tid, i tillegg til alle som er laget i denne transaksjonen
-- (de har også samme tid, now()).
select pg_temp.som('');
insert into public.activity (club_id, kind, category, data, actor_member_id, created_at)
select :'G', 'member_joined', 'club', jsonb_build_object('n', n), :'m1', '2026-10-12 12:00+02'
  from generate_series(1, 25) n;
select pg_temp.som(:'w1'); set role authenticated;
create temp table forventet on commit drop as
  select a.id, a.created_at from public.activity a
   where a.club_id = :'G' and not private.person_blocked(a.actor_member_id, null);
select pg_temp.lik((select count(*) from forventet where created_at = '2026-10-12 12:00+02') >= 25, true,
                   'P0 minst 25 med samme tid');
select pg_temp.lik(pg_temp.bla(array[:'G']::uuid[], 7),
                   (select array_agg(id order by created_at desc, id desc) from forventet),
                   'P1 sider på 7: alle, i rekkefølge, uten hull eller dobbeltrader');
select pg_temp.lik(pg_temp.bla(array[:'G']::uuid[], 1),
                   (select array_agg(id order by created_at desc, id desc) from forventet), 'P2 sider på 1: det samme');
select pg_temp.lik((select cardinality(pg_temp.bla(array[:'G']::uuid[], 3))) = (select count(distinct id) from forventet)::int,
                   true, 'P3 sider på 3: like mange som forventet, ingen dobbel');
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], '2026-10-12 12:00+02', null, 100)
                     where created_at >= '2026-10-12 12:00+02'), 0::bigint, 'P4 uten id: bare eldre enn tiden');
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], null, null, 0)), 1::bigint, 'P5 antall minst 1');
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], null, null, 1000)),
                   least((select count(*) from forventet), 100), 'P6 antall høyst 100');
-- Tall og mine reaksjoner (w1 ser ikke w2 sin 🔥, og w2 sine kommentarer telles ikke).
select pg_temp.lik((select reactions::text || '|' || my_reactions::text || '|' || comment_count
                      from public.feed_page(array[:'G']::uuid[], '2026-10-01 20:00:01+02', null, 100) where id = :'A1'),
                   '[{"count": 1, "emoji": "🏌️‍♂️"}]|{🏌️‍♂️}|1', 'P7 A1 for w1: én reaksjon (min), én kommentar (cmeg)');
select pg_temp.lik((select reactions::text || '|' || my_reactions::text
                      from public.feed_page(array[:'G']::uuid[], '2026-10-01 20:01:01+02', null, 100) where id = :'AP'),
                   '[{"count": 1, "emoji": "❤️"}, {"count": 1, "emoji": "😂"}]|{😂}', 'P8 AP for w1: to reaksjoner, min er 😂');
select pg_temp.lik((select count(*) from public.feed_page(null, null, null, 100) where id = :'AF'), 0::bigint,
                   'P9 w1 er ikke med i Vennecup: ingen hendelse uten klubb');
reset role;
select pg_temp.som(:'w2'); set role authenticated;
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], '2026-10-02 00:00+02', null, 100) where id in (:'A1', :'AP')),
                   0::bigint, 'P10 w2: ikke AP (ikke mottaker) og ikke A1 (blokkert aktør)');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select jsonb_array_length(reactions) || '|' || comment_count
                      from public.feed_page(array[:'G']::uuid[], '2026-10-01 20:00:01+02', null, 100) where id = :'A1'),
                   '2|1', 'P11 A1 for u1: to emojier (🏌️‍♂️ og 🔥), én kommentar som ikke er slettet');
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], null, null, 100) where id = :'AF' or competition_id = :'FK'),
                   (select count(*) from public.activity where club_id is null and competition_id = :'FK'),
                   'P12 u1 får også hendelsene uten klubb i Vennecup (de han kan se)');
select pg_temp.lik((select reactions::text || '|' || my_reactions::text from public.feed_page(null, '2026-10-01 20:02:01+02', null, 100) where id = :'AF'),
                   '[{"count": 1, "emoji": "🎉"}, {"count": 1, "emoji": "👍"}]|{👍}', 'P13 AF: tall og min reaksjon som profil');
reset role;
select pg_temp.som(:'w3'); set role authenticated;
select pg_temp.lik((select count(*) from public.feed_page(null, null, null, 100) where club_id is not null), 0::bigint,
                   'P14 w3 (ingen klubb) får ingen klubbhendelser');
select pg_temp.lik((select count(*) from public.feed_page(null, null, null, 100) where id = :'AF'), 1::bigint,
                   'P15 men hendelsen i Vennecup');
select pg_temp.lik((select count(*) from public.feed_page(null, null, null, 100)),
                   (select count(*) from public.activity), 'P16 w3: feeden er det samme som activity_select');
select pg_temp.lik((select count(*) from public.feed_page(array[:'G']::uuid[], null, null, 100) where club_id is not null), 0::bigint,
                   'P17 en klubb du ikke er med i, gir ingenting');
reset role;
select pg_temp.som(''); set role anon;
select pg_temp.feil('select * from public.feed_page(null)', '42501');
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'A1'), '42501');
select pg_temp.feil(format($$select public.comment_add('activity', %L, 'x')$$, :'A1'), '42501');
select pg_temp.feil('select count(*) from public.reactions', '42501');
select pg_temp.feil('select count(*) from public.comments', '42501');
reset role;
set role authenticated;
select pg_temp.lik((select count(*) from public.feed_page(null)), 0::bigint, 'P18 uten innlogging: tom feed');
select pg_temp.feil(format($$select public.react('activity', %L, '👍')$$, :'A1'), '42501');
reset role;

-- --- H: bildeoppfordring og push ---------------------------------------------------------
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.push_set_groups(array['social']), 1, 'H0 Anders slår av Sosialt');
reset role;
select pg_temp.som('');
insert into public.push_devices (user_id, device_id, token, environment) values
  (:'u1', 'dev-u1-50', repeat('a1', 32), 'sandbox'), (:'u2', 'dev-u2-50', repeat('b2', 32), 'sandbox');
select pg_temp.som(:'u1'); set role authenticated;
update public.rounds set status = 'locked' where id = :'R3';
reset role;
select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'photo_prompt' and round_id = :'R3'), 1::bigint,
                   'H1 én bildeoppfordring når runden låses');
select pg_temp.lik((select category || '|' || event_id || '|' || recipients::text || '|' || (actor_member_id is null)
                      from public.activity where kind = 'photo_prompt' and round_id = :'R3'),
                   'social|' || :'E3' || '|{' || :'m1' || ',' || :'m2' || ',' || :'m3' || ',' || :'m9' || '}|true',
                   'H2 kategori social, kvelden, spillerne som mottakere, ingen aktør');
update public.rounds set status = 'active' where id = :'R3';
update public.rounds set status = 'locked' where id = :'R3';
select pg_temp.lik((select count(*) from public.activity where kind = 'photo_prompt' and round_id = :'R3'), 1::bigint,
                   'H3 låst på nytt: fortsatt bare én');
-- Løs runde (uten klubb): ingen.
insert into public.rounds (id, club_id, event_id, owner_id, status) values (:'RL', null, null, :'u1', 'active');
update public.rounds set status = 'locked' where id = :'RL';
select pg_temp.lik((select count(*) from public.activity where kind = 'photo_prompt' and round_id = :'RL'), 0::bigint,
                   'H4 løs runde uten klubb: ingen bildeoppfordring');
-- Hvem ser den.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'photo_prompt' and round_id = :'R3'), 1::bigint, 'H5 spilleren ser den');
reset role;
select pg_temp.som(:'w1'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'photo_prompt'), 0::bigint, 'H6 en som ikke spilte, ser den ikke');
reset role;
-- Push.
select pg_temp.som('');
select q.id as job from public.push_queue q join public.activity a on a.id = q.activity_id
 where a.kind = 'photo_prompt' and a.round_id = :'R3' \gset
select pg_temp.lik((select p ->> 'group' || '|' || (p ->> 'collapse') from (select public.push_job_payload(:job) p) x),
                   'social|event-' || :'E3' || '-social', 'H7 jobben: gruppen Sosialt, collapse per kveld');
select pg_temp.lik((select (m ->> 'group_off') || '|' || jsonb_array_length(m -> 'devices')
                      from (select public.push_job_payload(:job) p) x, jsonb_array_elements(p -> 'members') m
                     where m ->> 'id' = :'m2'),
                   'true|0', 'H8 Sosialt av: ingen telefoner for Anders');
select pg_temp.lik((select (m ->> 'group_off') || '|' || jsonb_array_length(m -> 'devices')
                      from (select public.push_job_payload(:job) p) x, jsonb_array_elements(p -> 'members') m
                     where m ->> 'id' = :'m1'),
                   'false|1', 'H9 Sosialt på: Thomas har telefonen sin');
select q.id as jobc from public.push_queue q join public.activity a on a.id = q.activity_id
 where a.kind = 'comment_added' and a.data ->> 'comment_id' = :'cm' \gset
select pg_temp.lik((select (p ->> 'group') || '|' || coalesce(p ->> 'collapse', 'ingen') from (select public.push_job_payload(:jobc) p) x),
                   'social|ingen', 'H10 comment_added: Sosialt, ingen collapse (hver kommentar står)');
select pg_temp.lik((select (m ->> 'group_off') from (select public.push_job_payload(:jobc) p) x, jsonb_array_elements(p -> 'members') m
                     where m ->> 'id' = :'m2'), 'true', 'H11 comment_added: Sosialt av gjelder også');
select q.id as jobf from public.push_queue q join public.activity a on a.id = q.activity_id
 where a.kind = 'mentioned' and a.data ->> 'comment_id' = :'cf' \gset
select pg_temp.lik((select (p ->> 'audience') || '|' || (p -> 'activity' -> 'recipients')::text
                      || '|' || exists (select 1 from jsonb_array_elements(p -> 'members') m where m ->> 'id' = :'u1')
                      from (select public.push_job_payload(:jobf) p) x),
                   'competition|["' || :'u1' || '"]|true', 'H12 uten klubb: jobben for turneringen, mottakeren er profil-id i members');
select pg_temp.lik((select string_agg(kind || '=' || group_key, ',' order by kind) from public.push_group_map()
                     where kind in ('comment_added', 'mentioned', 'photo_prompt')),
                   'comment_added=social,mentioned=social,photo_prompt=social', 'H13 push_group_map: de nye kindene i Sosialt');
select pg_temp.lik((select count(*) from public.activity a where public.push_group(a.category, a.kind) is null), 0::bigint,
                   'H14 alle linjer har en gruppe');

-- --- D: sletting av konto og opprydding --------------------------------------------------
select pg_temp.som('');
select pg_temp.lik((select (public.delete_account_data(:'w2') ->> 'comments')::int > 0), true, 'D1 sletting av w2 tar kommentarene');
select pg_temp.lik((select count(*) from public.comments where member_id = :'p2')
                   + (select count(*) from public.reactions where member_id = :'p2')
                   + (select count(*) from public.thread_follows where user_id = :'w2'), 0::bigint,
                   'D2 ingen kommentarer, reaksjoner eller følging igjen');
delete from public.thread_messages where id = :'MSG';
select pg_temp.lik((select count(*) from public.comments where target_kind = 'message' and target_id = :'MSG')
                   + (select count(*) from public.reactions where target_kind = 'message' and target_id = :'MSG')
                   + (select count(*) from public.thread_follows where target_kind = 'message' and target_id = :'MSG'), 0::bigint,
                   'D3 meldingen slettet: kommentarer, reaksjoner og følging på den er borte');
delete from public.activity where id = :'A1';
select pg_temp.lik((select count(*) from public.comments where target_id = :'A1')
                   + (select count(*) from public.reactions where target_id = :'A1'), 0::bigint,
                   'D4 hendelsen slettet: det samme');
select pg_temp.lik((select count(*) from public.reactions r where r.target_kind = 'comment'
                     and not exists (select 1 from public.comments c where c.id = r.target_id)), 0::bigint,
                   'D5 ingen reaksjoner på kommentarer som ikke finnes');

rollback;
