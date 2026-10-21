\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 066_rapporter_baner_turneringer.sql. Kjøres på en kopi med hele kjeden til og med
-- 065 (rekkefølgen i docs/prod-sjekkliste.md) og 066 (to ganger). Egen verden, uten data fra
-- andre prøver. Alt rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- Trenger en stub for Vault og pg_net der net.http_post skriver kallet til net.stub_calls, og
-- Vault har project_url og report_alert_secret (som i prod-prøven 20.10). Uten den tabellen
-- hoppes E-linjene over (de skriver "ok E hoppet over").
--
-- B: bane i det felles biblioteket: en annens bane kan rapporteres, utdraget er navnet, ingen
--    klubb eller turnering på rapporten; egen bane, klubbens bane, hentet bane og ukjent id
--    gir P0002; samme rapport på nytt oppdaterer raden.
-- T: turnering i «Finn turneringer»: listet og åpen for alle kan rapporteres (utdrag «navn ·
--    klubb», eieren som den innholdet er fra); ikke listet eller bare for medlemmer gir
--    P0002.
-- S: skjult for den som rapporterte: public_competitions og my_hidden_content, ikke for andre,
--    og synlig igjen når rapporten er avvist.
-- R: RLS og avgjøring: bare den som rapporterte, ser rapporten (ikke klubbens arrangør), og
--    resolve_report gir 42501 for arrangøren.
-- G: de gamle typene virker som før (profil), ukjent type gir 22023.
-- P: report_alert_payload: target_id, turneringens navn og klubb, banens navn.
-- E: e-postvarselet (063) fyrer for nye rapporter, ikke for en oppdatert.
-- L: anon får ikke kjøre RPC-ene.
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
-- Antall kall til report-alert i stuben (null uten stuben).
create function pg_temp.varsler() returns bigint language plpgsql security definer as $$
begin
  if to_regclass('net.stub_calls') is null then return null; end if;
  return (select count(*) from net.stub_calls where url like '%/functions/v1/report-alert');
end $$;
grant execute on all functions in schema pg_temp to public;

\set ua  '00000000-0000-0000-0000-0000000066a1'
\set ub  '00000000-0000-0000-0000-0000000066a2'
\set uc  '00000000-0000-0000-0000-0000000066a3'
\set K   'aaaaaaaa-0000-0000-0000-0000000066c1'
\set LB  'cccccccc-0000-0000-0000-0000000066b1'
\set LA  'cccccccc-0000-0000-0000-0000000066b2'
\set LK  'cccccccc-0000-0000-0000-0000000066b3'
\set LS  'cccccccc-0000-0000-0000-0000000066b4'
\set TO  'eeeeeeee-0000-0000-0000-0000000066d1'
\set TL  'eeeeeeee-0000-0000-0000-0000000066d2'
\set TM  'eeeeeeee-0000-0000-0000-0000000066d3'

begin;

-- --- Verdenen --------------------------------------------------------------------
-- Anne (ua) rapporterer. Bård (ub) la inn banen «Tullebanen» og er arrangør i klubben «Bryn
-- Studio», som har den åpne turneringen «Vinterserien» (TO), en som ikke er listet (TL) og en
-- bare for medlemmer (TM). Cecilie (uc) er en tredje bruker.
select pg_temp.som('');
insert into auth.users (id) values (:'ua'), (:'ub'), (:'uc');
update public.profiles set display_name = 'Anne' where id = :'ua';
update public.profiles set display_name = 'Bård' where id = :'ub';
update public.profiles set display_name = 'Cecilie', searchable = true where id = :'uc';
insert into public.clubs (id, name, kind) values (:'K', 'Bryn Studio', 'simulator_center');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status)
values (:'K', :'ub', 'Bård', true, 'active');
insert into public.courses (id, club_id, name, kind, created_by_profile) values
  (:'LB', null, 'Tullebanen', 'course', :'ub'),
  (:'LA', null, 'Annes bane', 'course', :'ua'),
  (:'LK', :'K', 'Klubbens bane', 'course', null);
insert into public.courses (id, club_id, name, kind, source, external_id) values
  (:'LS', null, 'Losby', 'course', 'slope', '66');
insert into public.competitions (id, kind, name, club_id, owner_id, status, venue, listed, signup_audience, signup_open)
values (:'TO', 'league', 'Vinterserien', :'K', :'ub', 'active', 'simulator', true, 'anyone', true),
       (:'TL', 'league', 'Hemmelig', :'K', :'ub', 'active', null, false, 'anyone', true),
       (:'TM', 'league', 'Bare medlemmer', :'K', :'ub', 'active', null, true, 'members', true);
select pg_temp.lik(private.can_moderate(:'K', null), false, 'S0 som ingen: ingen moderator');
select pg_temp.som(:'ub');
select pg_temp.lik(private.has_club_right(:'K', 'money'), true, 'S0 Bård har pengerettigheten (modererer klubben)');
select pg_temp.som('');
select pg_temp.varsler() as varsler_for \gset

-- --- B: banen --------------------------------------------------------------------
select pg_temp.som(:'ua'); set role authenticated;
select public.report_content('course', :'LB', 'offensive', '  Stygt navn  ') as rb \gset
reset role;
select pg_temp.lik((select kind || '|' || coalesce(club_id::text, '-') || '|' || coalesce(competition_id::text, '-') || '|'
                           || snapshot || '|' || target_profile_id || '|' || note || '|' || status
                      from public.content_reports where id = :'rb'),
                   'course|-|-|Tullebanen|' || :'ub' || '|Stygt navn|open', 'B1 rapport på en annens bane, uten klubb og turnering');
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.feil(format($$select public.report_content('course', %L, 'spam')$$, :'LA'), 'P0002');
select pg_temp.feil(format($$select public.report_content('course', %L, 'spam')$$, :'LK'), 'P0002');
select pg_temp.feil(format($$select public.report_content('course', %L, 'spam')$$, :'LS'), 'P0002');
select pg_temp.feil(format($$select public.report_content('course', %L, 'spam')$$, gen_random_uuid()), 'P0002');
select pg_temp.lik(public.report_content('course', :'LB', 'spam', null), :'rb'::uuid, 'B2 samme rapport på nytt gir samme rad');
reset role;
select pg_temp.lik((select reason || '|' || coalesce(note, '-') from public.content_reports where id = :'rb'),
                   'spam|-', 'B3 grunnen og kommentaren er oppdatert');
select pg_temp.lik((select count(*) from public.content_reports where kind = 'course'), 1::bigint, 'B4 én rad for banen');

-- --- T: turneringen --------------------------------------------------------------
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.lik((select count(*) from public.public_competitions() where id = :'TO'), 1::bigint,
                   'T0 Vinterserien står i «Finn turneringer» før rapporten');
select public.report_content('competition', :'TO', 'impersonation', null) as rt \gset
select pg_temp.feil(format($$select public.report_content('competition', %L, 'spam')$$, :'TL'), 'P0002');
select pg_temp.feil(format($$select public.report_content('competition', %L, 'spam')$$, :'TM'), 'P0002');
select pg_temp.feil(format($$select public.report_content('competition', %L, 'spam')$$, gen_random_uuid()), 'P0002');
reset role;
select pg_temp.lik((select kind || '|' || coalesce(club_id::text, '-') || '|' || coalesce(competition_id::text, '-') || '|'
                           || snapshot || '|' || target_profile_id || '|' || reason
                      from public.content_reports where id = :'rt'),
                   'competition|-|-|Vinterserien · Bryn Studio|' || :'ub' || '|impersonation',
                   'T1 rapport på turneringen med navn og klubb');

-- --- S: skjult for den som rapporterte ---------------------------------------------
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.lik((select count(*) from public.public_competitions() where id = :'TO'), 0::bigint,
                   'S1 Vinterserien er borte fra lista for Anne');
select pg_temp.lik((select string_agg(kind || ':' || target_id, ',' order by kind) from public.my_hidden_content(array['course', 'competition'])),
                   'competition:' || :'TO' || ',course:' || :'LB', 'S2 my_hidden_content gir banen og turneringen');
select pg_temp.lik((select count(*) from public.my_hidden_content(array['message'])), 0::bigint, 'S3 filteret på type');
select pg_temp.lik((select count(*) from public.my_hidden_content()), 2::bigint, 'S4 uten filter: alle typer');
reset role;
select pg_temp.som(:'uc'); set role authenticated;
select pg_temp.lik((select count(*) from public.public_competitions() where id = :'TO'), 1::bigint,
                   'S5 Cecilie ser fortsatt Vinterserien');
select pg_temp.lik((select count(*) from public.my_hidden_content()), 0::bigint, 'S6 Cecilie har ingenting skjult');
select pg_temp.lik((select count(*) from public.courses where id = :'LB'), 1::bigint, 'S7 banen kan fortsatt leses (runder på den virker)');
reset role;
-- Avvist: vises igjen. Fjernet: står skjult.
update public.content_reports set status = 'dismissed', handled_at = now() where id = :'rt';
update public.content_reports set status = 'removed', handled_at = now() where id = :'rb';
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.lik((select count(*) from public.public_competitions() where id = :'TO'), 1::bigint,
                   'S8 avvist rapport: Vinterserien vises igjen');
select pg_temp.lik((select string_agg(kind, ',') from public.my_hidden_content()), 'course', 'S9 fjernet bane står skjult');
-- En ny rapport etter en avvist er en ny rad.
select pg_temp.lik(public.report_content('competition', :'TO', 'spam', null) <> :'rt'::uuid, true, 'S10 ny rapport etter avvist er en ny rad');
reset role;

-- --- R: hvem ser og avgjør ---------------------------------------------------------
select pg_temp.som(:'ub'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports where kind in ('course', 'competition')), 0::bigint,
                   'R1 Bård (arrangør i klubben, eier av innholdet) ser ingen av rapportene');
select pg_temp.feil(format($$select public.resolve_report(%L, 'dismiss')$$,
                    (select id from public.content_reports where kind = 'competition' and status = 'open')), '42501');
reset role;
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports where kind in ('course', 'competition')), 3::bigint,
                   'R2 Anne ser sine tre rapporter');
reset role;
select pg_temp.som(:'uc'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports), 0::bigint, 'R3 Cecilie ser ingen');
reset role;

-- --- G: de gamle typene -------------------------------------------------------------
select pg_temp.som(:'ua'); set role authenticated;
select public.report_content('profile', :'uc', 'spam', null) as rp \gset
select pg_temp.lik((select kind || '|' || target_profile_id from public.content_reports where id = :'rp'),
                   'profile|' || :'uc', 'G1 profil kan rapporteres som før');
select pg_temp.feil(format($$select public.report_content('club', %L, 'spam')$$, :'K'), '22023');
reset role;

-- --- P: e-posten ------------------------------------------------------------------
set role service_role;
select pg_temp.lik((select (p ->> 'kind') || '|' || (p ->> 'target_id') || '|' || (p ->> 'competition_name') || '|'
                           || (p ->> 'club_name') || '|' || (p ->> 'target_name') || '|' || (p ->> 'reporter_name')
                      from (select public.report_alert_payload(:'rt') as p) x),
                   'competition|' || :'TO' || '|Vinterserien|Bryn Studio|Bård|Anne', 'P1 payload for turneringen');
select pg_temp.lik((select (p ->> 'kind') || '|' || (p ->> 'target_id') || '|' || (p ->> 'excerpt') || '|'
                           || coalesce(p ->> 'club_name', '-') || '|' || coalesce(p ->> 'competition_name', '-')
                      from (select public.report_alert_payload(:'rb') as p) x),
                   'course|' || :'LB' || '|Tullebanen|-|-', 'P2 payload for banen');
reset role;

-- --- E: varselet fra 063 ------------------------------------------------------------
-- Nye rader: banen, turneringen, turneringen på nytt etter avvist, og profilen. Oppdateringen
-- av banen (B2) er ingen ny rad.
select case when pg_temp.varsler() is null then 'ok E hoppet over (ingen net.stub_calls)'
            else pg_temp.lik(pg_temp.varsler() - :varsler_for, 4::bigint, 'E1 fire nye rapporter gir fire kall til report-alert') end;
select case when to_regclass('net.stub_calls') is null then 'ok E hoppet over'
            else pg_temp.lik((select count(*) from net.stub_calls
                               where url like '%/functions/v1/report-alert'
                                 and body ->> 'report_id' in (:'rb', :'rt')), 2::bigint, 'E2 kallene har report_id') end;

-- --- L: anon -----------------------------------------------------------------------
select pg_temp.som(''); set role anon;
select pg_temp.feil(format($$select public.report_content('course', %L, 'spam')$$, :'LB'), '42501');
select pg_temp.feil($$select * from public.my_hidden_content()$$, '42501');
select pg_temp.feil($$select * from public.public_competitions()$$, '42501');
reset role;
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.feil(format($$select public.report_alert_payload(%L)$$, :'rb'), '42501');
reset role;

rollback;
