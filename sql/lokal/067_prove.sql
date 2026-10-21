\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Prøve for 067_varsel_ventende_medlem.sql. Kjøres på en kopi med hele kjeden til og med 066
-- (rekkefølgen i docs/prod-sjekkliste.md), så lokal/067_for.sql, så 067 (to ganger). Alt her
-- rulles tilbake. Hver linje skal starte med "ok"; ingen "FEIL".
--
-- F: de som ventet før 067 (lokal/067_for.sql): én linje til arrangøren, med tiden raden ble
--    laget (for gammel til push), og ingen linje i en klubb uten noen med rettigheten.
-- J: join_club med nytt navn gir én linje member_pending: kategori club, gruppe Arrangør,
--    data (member, name, club_name), aktøren er den ventende raden, mottakerne er eieren og de
--    med Medlemmer og invitasjon (ikke kasserer, ikke turneringer, ikke vanlige medlemmer,
--    ikke en annen klubb), og én jobb i push_queue. Samme kode på nytt gir ingen ny linje.
-- P: push_job_payload: gruppen, audience club, ingen collapse; Arrangør av gir group_off og
--    ingen telefoner.
-- E: push_email_recipients: bare mottakerne uten telefon og med e-post (ikke den med telefon,
--    ikke den med Arrangør av).
-- R: RLS: mottakerne ser linja, et vanlig medlem og den som venter gjør ikke.
-- G: godkjent, avvist og slettet: linja og jobben forsvinner. En arrangør som setter en rad
--    tilbake til pending, gir en ny linje.
-- I: ingen linje fra import eller SQL uten auth.uid() (pending eller active), fra en arrangør
--    som legger til et aktivt navn, eller for en deltaker (059).
-- K: klubb uten noen med rettigheten: join_club virker, ingen linje.
-- L: anon og authenticated får ikke kjøre hjelperne i private.
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
-- Linjene for en rad (som postgres, forbi RLS).
create function pg_temp.linjer(p_member uuid) returns bigint language sql as $$
  select count(*) from public.activity a where a.kind = 'member_pending' and a.data ->> 'member' = p_member::text;
$$;
create function pg_temp.jobb(p_member uuid) returns bigint language sql as $$
  select q.id from public.push_queue q join public.activity a on a.id = q.activity_id
   where a.kind = 'member_pending' and a.data ->> 'member' = p_member::text;
$$;
create function pg_temp.rad(p_club uuid, p_user uuid) returns uuid language sql as $$
  select m.id from public.club_members m where m.club_id = p_club and m.user_id = p_user;
$$;
grant execute on all functions in schema pg_temp to public;

-- Fra lokal/067_for.sql.
\set ug  '00000000-0000-0000-0000-0000000067f2'
\set uh  '00000000-0000-0000-0000-0000000067f3'
\set KF  'aaaaaaaa-0000-0000-0000-0000000067f1'
\set KU  'aaaaaaaa-0000-0000-0000-0000000067f2'

\set ua  '00000000-0000-0000-0000-0000000067a1'
\set ub  '00000000-0000-0000-0000-0000000067a2'
\set uc  '00000000-0000-0000-0000-0000000067a3'
\set ud  '00000000-0000-0000-0000-0000000067a4'
\set ue  '00000000-0000-0000-0000-0000000067a5'
\set uo  '00000000-0000-0000-0000-0000000067b1'
\set up  '00000000-0000-0000-0000-0000000067b2'
\set uq  '00000000-0000-0000-0000-0000000067b3'
\set ur  '00000000-0000-0000-0000-0000000067b4'
\set ux  '00000000-0000-0000-0000-0000000067b5'
\set K   'aaaaaaaa-0000-0000-0000-0000000067c1'
\set K2  'aaaaaaaa-0000-0000-0000-0000000067c2'
\set RM  'bbbbbbbb-0000-0000-0000-0000000067d1'
\set RT  'bbbbbbbb-0000-0000-0000-0000000067d2'

begin;

-- --- F: de som ventet før 067 ------------------------------------------------------
select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'KF', :'ug')), 1::bigint, 'F1 Gamle Gunnar fikk én linje (067 kjørt to ganger)');
select pg_temp.lik((select a.created_at = m.created_at and a.created_at < now() - interval '1 hour'
                      from public.activity a join public.club_members m on m.id::text = a.data ->> 'member'
                     where a.kind = 'member_pending' and m.id = pg_temp.rad(:'KF', :'ug')), true,
                   'F2 linja har tiden raden ble laget (for gammel til push)');
select pg_temp.lik((select a.recipients = array[(select id from public.club_members where club_id = :'KF' and display_name = 'Frøydis')]
                           and a.data ->> 'name' = 'Gamle Gunnar' and a.data ->> 'club_name' = 'Før-klubben'
                      from public.activity a where a.kind = 'member_pending' and a.club_id = :'KF'), true,
                   'F3 til Frøydis, med navnet og klubben');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'KU', :'uh')), 0::bigint, 'F4 ingen linje i klubben uten noen med rettigheten');

-- --- Verdenen ----------------------------------------------------------------------
-- «Golfgutu Invitational» (K): Anne er eier, Bård kasserer (money), Cecilie har en egen rolle
-- med bare Medlemmer og invitasjon, Dag er vanlig medlem, Even har en rolle med bare
-- turneringer. «Nabo-klubben» (K2): Per er arrangør der (ikke i K). Ola (uo), Pål (up),
-- Quang (uq), Rita (ur) og Xander (ux) er nye.
alter table auth.users add column if not exists email text;
insert into auth.users (id, email) values
  (:'ua', 'anne@example.no'), (:'ub', 'bard@example.no'), (:'uc', 'cecilie@example.no'),
  (:'ud', 'dag@example.no'), (:'ue', 'even@example.no'), (:'uo', 'ola@example.no'),
  (:'up', 'per@example.no'), (:'uq', null), (:'ur', null), (:'ux', null);
insert into public.clubs (id, name, join_code) values (:'K', 'Golfgutu Invitational', 'GOLFGUTU67'),
                                                       (:'K2', 'Nabo-klubben', 'NABOKLUBB67');
insert into public.club_members (club_id, user_id, display_name, is_organizer, is_treasurer, status) values
  (:'K', :'ua', 'Anne', true, false, 'active'),
  (:'K', :'ub', 'Bård', false, true, 'active'),
  (:'K', :'uc', 'Cecilie', false, false, 'active'),
  (:'K', :'ud', 'Dag', false, false, 'active'),
  (:'K', :'ue', 'Even', false, false, 'active'),
  (:'K2', :'up', 'Per', true, false, 'active');
-- Anne blir eier (i stedet for Arrangør), Cecilie og Even får egne roller.
delete from public.club_member_roles where member_id = pg_temp.rad(:'K', :'ua');
insert into public.club_member_roles (member_id, role_id, club_id)
select pg_temp.rad(:'K', :'ua'), r.id, :'K' from public.club_roles r where r.club_id = :'K' and r.is_owner;
insert into public.club_roles (id, club_id, name, rights) values
  (:'RM', :'K', 'Medlemsansvarlig', array['members']), (:'RT', :'K', 'Turneringsleder', array['tournaments']);
insert into public.club_member_roles (member_id, role_id, club_id) values
  (pg_temp.rad(:'K', :'uc'), :'RM', :'K'), (pg_temp.rad(:'K', :'ue'), :'RT', :'K');
-- Cecilie har en telefon. Anne og Bård har ingen (e-post).
insert into public.push_devices (user_id, device_id, token, environment) values
  (:'uc', 'cecilie-iphone', repeat('c0', 32), 'production');
select pg_temp.som(:'ua');
select pg_temp.lik(private.has_club_right(:'K', 'members'), true, 'V1 Anne (eier) har members');
select pg_temp.som(:'uc');
select pg_temp.lik(private.has_club_right(:'K', 'members'), true, 'V2 Cecilie har members');
select pg_temp.som(:'ub');
select pg_temp.lik(private.has_club_right(:'K', 'members'), false, 'V3 Bård (kasserer) har ikke members');
select pg_temp.som(:'ue');
select pg_temp.lik(private.has_club_right(:'K', 'members'), false, 'V4 Even (turneringer) har ikke members');
select pg_temp.som('');
select array_agg(x order by x)::text as forventet
  from unnest(array[pg_temp.rad(:'K', :'ua'), pg_temp.rad(:'K', :'uc')]) x \gset

-- --- J: join_club --------------------------------------------------------------------
select pg_temp.som(:'uo'); set role authenticated;
select pg_temp.lik(public.join_club('GOLFGUTU67', null, '  Ola Nordmann ', 14.2) ->> 'status', 'pending',
                   'J1 Ola ber om å bli med (pending)');
reset role; select pg_temp.som('');
select pg_temp.rad(:'K', :'uo') as ola \gset
select pg_temp.lik(pg_temp.linjer(:'ola'), 1::bigint, 'J2 én linje member_pending');
select pg_temp.lik((select a.category || '|' || public.push_group(a.category, a.kind) || '|' || (a.data ->> 'name') || '|'
                           || (a.data ->> 'club_name') || '|' || (a.data ->> 'member') || '|' || a.actor_member_id
                           || '|' || coalesce(a.event_id::text, '-') || '|' || coalesce(a.competition_id::text, '-')
                      from public.activity a where a.kind = 'member_pending' and a.data ->> 'member' = :'ola'),
                   'club|organizer|Ola Nordmann|Golfgutu Invitational|' || :'ola' || '|' || :'ola' || '|-|-',
                   'J3 kategori, gruppe, navn, klubb, raden og aktøren');
select pg_temp.lik((select (select array_agg(x order by x) from unnest(a.recipients) x)::text
                      from public.activity a where a.kind = 'member_pending' and a.data ->> 'member' = :'ola'),
                   :'forventet', 'J4 mottakerne er Anne (eier) og Cecilie (Medlemmer og invitasjon)');
select pg_temp.lik(pg_temp.jobb(:'ola') is not null, true, 'J5 jobben ligger i push_queue');
select pg_temp.lik((select q.club_id from public.push_queue q where q.id = pg_temp.jobb(:'ola')), :'K'::uuid,
                   'J6 jobben er klubbens');
select pg_temp.som(:'uo'); set role authenticated;
select pg_temp.lik(public.join_club('GOLFGUTU67', null, 'Ola på nytt', null) ->> 'member_id', :'ola',
                   'J7 samme kode på nytt gir samme rad');
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(:'ola'), 1::bigint, 'J8 fortsatt én linje');

-- --- P: push_job_payload ---------------------------------------------------------------
select pg_temp.lik((select (p ->> 'group') || '|' || (p ->> 'audience') || '|' || coalesce(p ->> 'collapse', '-')
                           || '|' || (p -> 'activity' ->> 'kind') || '|' || (p -> 'club' ->> 'name')
                      from public.push_job_payload(pg_temp.jobb(:'ola')) p),
                   'organizer|club|-|member_pending|Golfgutu Invitational', 'P1 gruppe, audience, ingen collapse');
select pg_temp.lik((select jsonb_array_length(m -> 'devices')
                      from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'ola')) -> 'members') m
                     where m ->> 'user_id' = :'uc'), 1, 'P2 Cecilie har telefonen i svaret');
select pg_temp.som(:'uc'); set role authenticated;
select public.push_set_groups(array['organizer'], null) > 0 as satt \gset
reset role; select pg_temp.som('');
select pg_temp.lik((select (m ->> 'group_off')::boolean and jsonb_array_length(m -> 'devices') = 0
                      from jsonb_array_elements(public.push_job_payload(pg_temp.jobb(:'ola')) -> 'members') m
                     where m ->> 'user_id' = :'uc'), true, 'P3 Arrangør av: group_off og ingen telefon');

-- --- E: e-post til dem uten push ---------------------------------------------------------
select pg_temp.lik((select string_agg(email, ',' order by email) from public.push_email_recipients(pg_temp.jobb(:'ola'))),
                   'anne@example.no', 'E1 bare Anne (ingen telefon, mottaker); ikke Cecilie (Arrangør av), Bård, Dag eller Ola');
select pg_temp.som(:'uc'); set role authenticated;
select public.push_set_groups(array[]::text[], null) > 0 as satt \gset
reset role; select pg_temp.som('');
select pg_temp.lik((select string_agg(email, ',' order by email) from public.push_email_recipients(pg_temp.jobb(:'ola'))),
                   'anne@example.no', 'E2 Cecilie har telefon og får push i stedet for e-post');
select pg_temp.som(:'ua'); set role authenticated;
select public.push_set_groups(array[]::text[], false) > 0 as satt \gset
reset role; select pg_temp.som('');
select pg_temp.lik((select count(*) from public.push_email_recipients(pg_temp.jobb(:'ola'))), 0::bigint,
                   'E3 Anne har slått av e-post: ingen');
select pg_temp.som(:'ua'); set role authenticated;
select public.push_set_groups(array[]::text[], true) > 0 as satt \gset
reset role; select pg_temp.som('');

-- --- R: hvem ser linja ---------------------------------------------------------------------
select pg_temp.som(:'ua'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending' and club_id = :'K'), 1::bigint,
                   'R1 Anne ser linja');
reset role; select pg_temp.som(:'uc'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending' and club_id = :'K'), 1::bigint,
                   'R2 Cecilie ser linja');
reset role; select pg_temp.som(:'ud'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending'), 0::bigint,
                   'R3 Dag (vanlig medlem) ser den ikke');
reset role; select pg_temp.som(:'uo'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending'), 0::bigint,
                   'R4 Ola (venter) ser den ikke');
reset role; select pg_temp.som(:'up'); set role authenticated;
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending'), 0::bigint,
                   'R5 Per (arrangør i en annen klubb) ser den ikke');
reset role; select pg_temp.som('');

-- --- G: godkjent, avvist, slettet, tilbake til pending -------------------------------------
select pg_temp.jobb(:'ola') as olajobb \gset
select pg_temp.som(:'uc'); set role authenticated;
update public.club_members set status = 'active' where id = :'ola';
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(:'ola'), 0::bigint, 'G1 Cecilie godkjente Ola: linja er borte');
select pg_temp.lik((select count(*) from public.push_queue where id = :'olajobb'), 0::bigint, 'G2 og jobben');
select pg_temp.lik((select status from public.club_members where id = :'ola'), 'active', 'G3 Ola er aktiv');

select pg_temp.som(:'uq'); set role authenticated;
select public.join_club('GOLFGUTU67', null, 'Quang', null) ->> 'member_id' as quang \gset
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(:'quang'), 1::bigint, 'G4 Quang venter: én linje');
select pg_temp.som(:'ua'); set role authenticated;
update public.club_members set status = 'archived', user_id = null where id = :'quang';
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(:'quang'), 0::bigint, 'G5 Anne avviste Quang: linja er borte');
select pg_temp.som(:'uq'); set role authenticated;
select public.join_club('GOLFGUTU67', null, 'Quang Nguyen', null) ->> 'member_id' as quang2 \gset
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(:'quang2'), 1::bigint, 'G6 Quang prøver igjen med riktig navn: ny linje');
delete from public.club_members where id = :'quang2';
select pg_temp.lik(pg_temp.linjer(:'quang2'), 0::bigint, 'G7 raden slettet: linja er borte');

select pg_temp.som(:'ua'); set role authenticated;
update public.club_members set status = 'pending' where id = pg_temp.rad(:'K', :'ud');
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K', :'ud')), 1::bigint, 'G8 Anne satte Dag tilbake til pending: én linje');
select pg_temp.som(:'ua'); set role authenticated;
update public.club_members set display_name = 'Dag D.' where id = pg_temp.rad(:'K', :'ud');
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K', :'ud')), 1::bigint, 'G9 annen endring mens raden venter: fortsatt én');

-- --- I: ingen linje uten innlogget bak, eller for aktive navn og deltakere -----------------
select pg_temp.som('');
insert into public.club_members (club_id, user_id, display_name, status) values (:'K', :'ur', 'Rita fra import', 'pending');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K', :'ur')), 0::bigint, 'I1 import/SQL uten auth.uid(), pending: ingen linje');
update public.club_members set status = 'active' where id = pg_temp.rad(:'K', :'ur');
update public.club_members set status = 'pending' where id = pg_temp.rad(:'K', :'ur');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K', :'ur')), 0::bigint, 'I2 SQL uten auth.uid() setter pending: ingen linje');
insert into public.club_members (club_id, user_id, display_name, status) values (:'K', :'ux', 'Xander fra import', 'active');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K', :'ux')), 0::bigint, 'I3 import med active: ingen linje');
select pg_temp.som(:'ua'); set role authenticated;
insert into public.club_members (club_id, display_name, status) values (:'K', 'Ledig navn', 'active');
reset role; select pg_temp.som('');
select pg_temp.lik((select count(*) from public.activity where kind = 'member_pending' and club_id = :'K'), 1::bigint,
                   'I4 arrangøren la til et aktivt navn: ingen ny linje (bare Dag)');
-- En deltaker (059) som venter, finnes ikke i appen; triggeren hopper over den uansett.
select pg_temp.som(:'ux');
alter table public.club_members disable trigger club_members_guard;
insert into public.club_members (club_id, user_id, display_name, status, kind)
values (:'K2', :'ux', 'Xander deltaker', 'pending', 'participant');
alter table public.club_members enable trigger club_members_guard;
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'K2', :'ux')), 0::bigint, 'I5 deltaker: ingen linje');
select pg_temp.som('');

-- --- K: klubb uten noen med rettigheten ------------------------------------------------------
select pg_temp.som(:'ur'); set role authenticated;
select pg_temp.lik(public.join_club('UTENARR67', null, 'Rita', null) ->> 'status', 'pending', 'K1 join_club virker');
reset role; select pg_temp.som('');
select pg_temp.lik(pg_temp.linjer(pg_temp.rad(:'KU', :'ur')), 0::bigint, 'K2 ingen å varsle: ingen linje');

-- --- L: rettighetene -------------------------------------------------------------------------
select pg_temp.lik(has_function_privilege('authenticated', 'private.member_pending_activity(public.club_members, timestamptz)', 'execute')
                   or has_function_privilege('anon', 'private.member_pending_activity(public.club_members, timestamptz)', 'execute')
                   or has_function_privilege('authenticated', 'private.member_pending_recipients(uuid, uuid)', 'execute')
                   or has_function_privilege('anon', 'private.member_pending_recipients(uuid, uuid)', 'execute'), false,
                   'L1 hjelperne kan ikke kjøres av anon eller authenticated');
select pg_temp.som(:'ud'); set role authenticated;
select pg_temp.feil(format($$select private.member_pending_recipients(%L, null)$$, :'K'), '42501');
reset role; select pg_temp.som('');
select pg_temp.lik((select count(*) from public.push_group_map() where kind = 'member_pending' and group_key = 'organizer'),
                   1::bigint, 'L2 push_group_map har member_pending under Arrangør');

rollback;
