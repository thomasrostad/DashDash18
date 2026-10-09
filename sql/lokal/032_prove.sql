\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 032_turnering_kjerne_trinn2.sql. Rekkefølge i en tom, lokal
-- Postgres: lokal/stub.sql, lokal/stub_storage.sql, 001–030 (som i
-- sql/README.md), lokal/031_for.sql, 031, lokal/032_for.sql, 032 (to
-- ganger), så denne fila. Hver resultatlinje skal starte med "ok"; ingen
-- "FEIL".
--
-- Del A: dagens app merker ingenting (samme bilde og Tavla per innlogging
--        som før 032, paritetskontrollen lik, de gamle reglene står).
-- Del B: påmelding med tak, venteliste, tilbud (24 t), utløp, vindu, åpne
--        turneringer for alle innloggede (bare raden, ikke rundene).
-- Del C: staben (arrangør og funksjonær), startlista og føring for gruppene.
-- Del D: kontrollblokken fra fila.
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

\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'
\set u6 '00000000-0000-0000-0000-000000000006'
\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set carl    '11111111-0000-0000-0000-000000000009'
\set anders  '11111111-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set s2026   '5eeeeeee-0000-0000-0000-000000002026'
\set morro   'c0000000-0000-0000-0000-00000000f001'
\set r2      'dddddddd-0000-0000-0000-000000000002'
\set r3      'dddddddd-0000-0000-0000-000000000003'
\set r4      'dddddddd-0000-0000-0000-000000000004'

select pg_temp.som('');
select c.id as j2026 from public.competitions c where c.season_id = :'s2026' \gset

-- === A. Dagens app merker ingenting ===========================================
create table lokal32.etter_bilde (uid uuid primary key, bilde jsonb, tavla jsonb);
grant insert on lokal32.etter_bilde to authenticated;
select pg_temp.som(:'u1'); set role authenticated;
insert into lokal32.etter_bilde values (:'u1', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u2'); set role authenticated;
insert into lokal32.etter_bilde values (:'u2', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u3'); set role authenticated;
insert into lokal32.etter_bilde values (:'u3', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u4'); set role authenticated;
insert into lokal32.etter_bilde values (:'u4', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som(:'u5'); set role authenticated;
insert into lokal32.etter_bilde values (:'u5', lokal32.bilde(), lokal31.tavla()); reset role;
select pg_temp.som('');

select pg_temp.lik(e.bilde, f.bilde, 'A1 samme bilde før og etter 032 for ' || f.uid)
from lokal32.for_bilde f join lokal32.etter_bilde e using (uid) order by f.uid;
select pg_temp.lik(e.tavla, f.tavla, 'A2 samme Tavla før og etter 032 for ' || f.uid)
from lokal32.for_bilde f join lokal32.etter_bilde e using (uid) order by f.uid;
select pg_temp.lik(lokal32.paritet(), (select svar from lokal32.paritet_for),
                   'A3 paritetskontrollen (10.2) er lik før og etter 032');
select pg_temp.lik((select bool_and((x ->> 'lik')::boolean) from jsonb_array_elements(lokal32.paritet()) x), true,
                   'A4 via sesongen = via turneringen for alle sesonger');
-- De gamle reglene gir fortsatt 23505 (én aktiv runde per klubb).
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('update public.rounds set status = %L where id = %L', 'active', :'r4'), '23505');
reset role;
select pg_temp.som('');

-- === B. Påmelding, venteliste og tilbud =====================================
-- B1 Thomas (arrangør) åpner påmeldingen i Morrocupen: tak 2, venteliste.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((public.set_competition_signup(:'morro', true, 'members', false, 2, true, null, null) ->> 'entrants')::int,
                   1, 'B1 innstillingene lagres, Anders er påmeldt fra før');
reset role;

-- B2 Anders er påmeldt fra før: idempotent.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik(public.competition_signup(:'morro') ->> 'state', 'entered', 'B2 Anders påmeldt fra før (idempotent)');
reset role;

-- B3 Bjørn melder seg på: plass nr. 2 av 2.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.competition_signup(:'morro') ->> 'state', 'entered', 'B3 Bjørn påmeldt');
reset role;

-- B4 Ola (ikke medlem) finner ikke en turnering for medlemmer.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.feil(format('select public.competition_signup(%L)', :'morro'), 'P0002');
select pg_temp.lik((select count(*) from public.competition_signup_status(array[:'morro'::uuid]))::int, 0,
                   'B4 Ola ser ikke statusen i en turnering for medlemmer');
reset role;

-- B5 Åpen for alle. Ola og Dag (venter på godkjenning, regnes som ikke-medlem)
-- havner på ventelista, i rekkefølge.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.set_competition_signup(:'morro', true, 'anyone', false, 2, true, null, null) ->> 'signup_audience',
                   'anyone', 'B5 påmeldingen åpnes for alle');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(public.competition_signup(:'morro') ->> 'state', 'waitlisted', 'B6 Ola på ventelista');
select pg_temp.lik((select waitlist_position from public.competition_signup_status(array[:'morro'::uuid])), 1,
                   'B6 Ola er nr. 1 på ventelista');
select pg_temp.lik(public.can_read_round(:'r2'), false, 'B7 Ola på ventelista ser ikke rundene i turneringen');
select pg_temp.lik((select count(*) from public.competitions where id = :'morro')::int, 0,
                   'B7 Ola på ventelista får ikke turneringsraden fra tabellen (RLS uendret)');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik(public.competition_signup(:'morro') ->> 'waitlist_position', '2', 'B8 Dag er nr. 2 på ventelista');
reset role;

-- B9 Bjørn melder seg av: Ola får tilbud med frist om 48 timer, Dag venter.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.competition_withdraw(:'morro') ->> 'state', 'withdrawn', 'B9 Bjørn meldt av');
reset role;
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik((select state from public.competition_signup_status(array[:'morro'::uuid])), 'offered',
                   'B9 Ola har fått tilbud');
select pg_temp.lik((select offer_expires_at between now() + interval '47 hours 59 minutes' and now() + interval '48 hours 1 minute'
                     from public.competition_signup_status(array[:'morro'::uuid])), true,
                   'B9 tilbudet gjelder i 48 timer');
reset role;

-- B10 Bjørn vil inn igjen: plassen er lovet bort, så han havner bak i køen.
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.competition_signup(:'morro') ->> 'state', 'waitlisted',
                   'B10 Bjørn kan ikke ta plassen som er tilbudt Ola');
select pg_temp.lik((select waitlist_position from public.competition_signup_status(array[:'morro'::uuid])), 3,
                   'B10 Bjørn er nr. 3 på ventelista');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik((select string_agg(waitlist_position || ':' || (offered_at is not null), ',' order by waitlist_position)
                      from public.competition_waitlist_entries(:'morro')), '1:true,2:false,3:false',
                   'B11 arrangøren ser ventelista i rekkefølge, med tilbudet');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.competition_waitlist_entries(:'morro'))::int, 0,
                   'B11 en spiller ser ikke ventelista');
select pg_temp.feil(format('select public.competition_offer_respond(%L, true)', :'morro'), '55000');
reset role;

-- B12 Ola tar imot: påmeldt som profil, og ser nå rundene i turneringen.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(public.competition_offer_respond(:'morro', true) ->> 'state', 'entered', 'B12 Ola tar imot plassen');
select pg_temp.lik(public.can_read_round(:'r2'), true, 'B12 Ola (påmeldt, ikke medlem) ser runden i turneringen');
select pg_temp.lik((select count(*) from public.competitions where id = :'morro')::int, 1,
                   'B12 Ola ser turneringsraden som påmeldt');
reset role;
select pg_temp.lik((select count(*) from public.competition_participants
                     where competition_id = :'morro' and status = 'active')::int, 2, 'B12 to påmeldte (taket)');

-- B13 Taket opp til 3: Dag får tilbud med en gang.
select pg_temp.som(:'u1'); set role authenticated;
select public.set_competition_signup(:'morro', true, 'anyone', false, 3, true, null, null) is not null;
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select state from public.competition_signup_status(array[:'morro'::uuid])), 'offered',
                   'B13 høyere tak gir Dag tilbud');
reset role;

-- B14 Dags tilbud går ut; cron (service_role) gir plassen til Bjørn.
select pg_temp.som('');
update public.competition_waitlist set offered_at = now() - interval '25 hours', offer_expires_at = now() - interval '1 hour'
 where competition_id = :'morro' and offered_at is not null;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select state from public.competition_signup_status(array[:'morro'::uuid])), 'expired',
                   'B14 Dag ser at tilbudet har gått ut');
select pg_temp.feil(format('select public.competition_offer_respond(%L, true)', :'morro'), '55000');
select pg_temp.feil('select public.expire_competition_offers()', '42501');
reset role;
set role service_role;
select pg_temp.lik(public.expire_competition_offers(), 1, 'B14 cron: ett nytt tilbud');
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select state from public.competition_signup_status(array[:'morro'::uuid])), 'none',
                   'B14 Dag er ute av køen etter utløpt tilbud');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik((select state from public.competition_signup_status(array[:'morro'::uuid])), 'offered',
                   'B14 Bjørn har fått tilbudet');
-- B15 Bjørn avslår: ut av køen, ingen andre venter.
select pg_temp.lik(public.competition_offer_respond(:'morro', false) ->> 'state', 'withdrawn',
                   'B15 Bjørn avslår (står som meldt av fra før)');
reset role;
select pg_temp.lik((select count(*) from public.competition_waitlist where competition_id = :'morro')::int, 0,
                   'B15 ventelista er tom');

-- B16 Full uten venteliste, og vinduet.
select pg_temp.som(:'u1'); set role authenticated;
select public.set_competition_signup(:'morro', true, 'anyone', false, 2, false, null, null) is not null;
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.feil(format('select public.competition_signup(%L)', :'morro'), '55000');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.set_competition_signup(:'morro', true, 'anyone', false, null, false, now() + interval '2 days', null) is not null;
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.feil(format('select public.competition_signup(%L)', :'morro'), '55000');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.set_competition_signup(:'morro', true, 'anyone', false, null, false, null, now() - interval '1 minute') is not null;
reset role;
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.feil(format('select public.competition_signup(%L)', :'morro'), '55000');
reset role;

-- B17 Hvem kan endre, og sjekkene.
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.feil(format('select public.set_competition_signup(%L, true, %L, false, null, false, null, null)', :'morro', 'members'), '42501');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('select public.set_competition_signup(%L, true, %L, false, null, false, null, null)', :'j2026', 'members'), '55000');
select pg_temp.feil(format('select public.set_competition_signup(%L, true, %L, false, null, true, null, null)', :'morro', 'members'), '22023');
select pg_temp.feil(format('select public.set_competition_signup(%L, true, %L, false, 1, false, null, null)', :'morro', 'members'), '22023');
select pg_temp.feil(format('select public.set_competition_signup(%L, true, %L, false, null, false, now(), now() - interval %L)', :'morro', 'members', '1 day'), '22023');
select pg_temp.feil(format('select public.competition_signup(%L)', :'j2026'), '55000');
reset role;

-- B18 Åpne turneringer: alle innloggede ser raden via public_competitions,
-- men ikke tabellraden, rundene eller de påmeldte.
select pg_temp.som(:'u5'); set role authenticated;
select pg_temp.lik((select count(*) from public.public_competitions())::int, 0, 'B18 ikke i lista før den er offentlig');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
select public.set_competition_signup(:'morro', true, 'anyone', true, 10, true, null, null) is not null;
reset role;
select pg_temp.som(:'u6');
insert into auth.users values (:'u6');
set role authenticated;
select pg_temp.lik((select name || ':' || entrants || '/' || max_entrants || ':' || club_name
                      from public.public_competitions()), 'Morrocupen:2/10:Golfgutu',
                   'B18 en fremmed ser den åpne turneringen med plassene');
select pg_temp.lik((select count(*) from public.competitions where id = :'morro')::int, 0,
                   'B18 men får ikke raden fra tabellen');
select pg_temp.lik((select count(*) from public.competition_participants where competition_id = :'morro')::int, 0,
                   'B18 og ser ikke de påmeldte');
select pg_temp.lik(public.can_read_round(:'r2'), false, 'B18 og ser ikke rundene (beslutning 3)');
select pg_temp.lik(public.competition_signup(:'morro') ->> 'state', 'entered', 'B18 den fremmede melder seg på');
select pg_temp.lik(public.can_read_round(:'r2'), true, 'B18 og ser rundene som påmeldt');
select pg_temp.lik(public.competition_withdraw(:'morro') ->> 'state', 'withdrawn', 'B18 og melder seg av igjen');
reset role;
set role anon;
select pg_temp.feil('select public.public_competitions()', '42501');
reset role;
select pg_temp.som('');

-- === C. Staben, startlista og føring ==========================================
-- C1 Bare folk du kjenner kan legges i staben.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.feil(format('insert into public.competition_staff (competition_id, profile_id, role) values (%L, %L, %L)',
                           :'j2026', :'u6', 'organizer'), '42501');
reset role;
-- Ola (ikke medlem i Golfgutu) settes som arrangør i jakkeracet (som postgres:
-- Thomas og Ola har ingen felles klubb eller runde i denne verdenen).
select pg_temp.som('');
insert into public.competition_staff (competition_id, profile_id, role) values (:'j2026', :'u4', 'organizer');

select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(public.is_competition_admin(:'j2026'), true, 'C2 Ola styrer jakkeracet som arrangør i staben');
select pg_temp.lik((select count(*) from public.competitions where id = :'j2026')::int, 1, 'C2 Ola ser turneringsraden');
select pg_temp.lik((select count(*) from public.events where competition_id = :'j2026')::int, 2, 'C2 Ola ser spilledagene');
select pg_temp.lik((select string_agg(right(id::text, 1), ',' order by id) from public.rounds
                     where event_id in (select id from public.events where competition_id = :'j2026')), '2,3,4',
                   'C2 Ola ser rundene, også kladden');
select pg_temp.lik(public.is_round_organizer(:'r3'), true, 'C2 Ola styrer runden');
select pg_temp.lik(public.can_score(:'r3', :'carl'), true, 'C2 Ola fører for alle');
select pg_temp.lik((select count(*) from public.round_players where round_id = :'r3')::int, 4, 'C2 Ola ser spillerne i runden');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r3',
                           '[{"group_no": 2, "scorer_id": "00000000-0000-0000-0000-000000000003"}]'), '22023');
reset role;

-- C3 Bjørn blir funksjonær for gruppe 2 (Carl, uten markør).
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.can_score(:'r3', :'carl'), false, 'C3 Bjørn fører ikke for Carl før han er funksjonær');
select pg_temp.lik(public.can_score(:'r3', :'anders'), true, 'C3 Bjørn fører for Anders som markør (som før)');
reset role;
select pg_temp.som(:'u1'); set role authenticated;
insert into public.competition_staff (competition_id, profile_id, role) values (:'j2026', :'u3', 'scorer');
select pg_temp.lik((select added_by from public.competition_staff where competition_id = :'j2026' and profile_id = :'u3'),
                   :'u1'::uuid, 'C3 added_by settes av serveren');
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.can_score(:'r3', :'carl'), false, 'C3 i staben, men ikke satt på en gruppe: fører ikke for Carl');
select pg_temp.lik(public.is_round_organizer(:'r3'), false, 'C3 en funksjonær styrer ikke runden');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r3', '[]'), '42501');
reset role;

-- C4 Ola lager startlista: to grupper med tid, starthull og bås, Bjørn på gruppe 2.
select pg_temp.som(:'u4'); set role authenticated;
select pg_temp.lik(public.save_start_list(:'r3', 1, format(
  '[{"group_no": 1, "starts_at": "18:00", "start_hole": 1, "resource_label": "Bås 1"},
    {"group_no": 2, "starts_at": "18:10", "start_hole": 5, "resource_label": " Bås 2 ", "scorer_id": "%s"}]', :'u3')::jsonb),
  2, 'C4 startlista lagret');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r3',
                           '[{"group_no": 1, "start_hole": 10}]'), '22023');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r3',
                           '[{"group_no": 1}, {"group_no": 1}]'), '22023');
select pg_temp.feil(format('select public.save_start_list(%L, 0, %L::jsonb)', :'r3', '[]'), '22023');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r2', '[]'), '55000');
reset role;
select pg_temp.lik((select string_agg(group_no || ' ' || starts_at || ' ' || start_hole || ' ' || resource_label
                                      || ' ' || coalesce(right(scorer_id::text, 1), '-'), ', ' order by group_no)
                      from public.round_start_groups where round_id = :'r3'),
                   '1 18:00:00 1 Bås 1 -, 2 18:10:00 5 Bås 2 3', 'C4 gruppene som lagret (bås trimmet)');

select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.can_score(:'r3', :'carl'), true, 'C5 Bjørn fører for Carl i gruppa si');
select pg_temp.lik(public.can_score(:'r3', :'thomas'), false, 'C5 men ikke for Thomas (ingen gruppe)');
reset role;
select pg_temp.som(:'u2'); set role authenticated;
select pg_temp.lik((select count(*) from public.round_start_groups where round_id = :'r3')::int, 2,
                   'C6 deltakerne ser startlista');
select pg_temp.feil(format('select public.save_start_list(%L, 1, %L::jsonb)', :'r3', '[]'), '42501');
select pg_temp.lik(public.can_score(:'r3', :'carl'), false, 'C6 Anders fører ikke for Carl (som før)');
reset role;

-- C7 Bjørn tas ut av staben: retten forsvinner med en gang.
select pg_temp.som(:'u1'); set role authenticated;
delete from public.competition_staff where competition_id = :'j2026' and profile_id = :'u3';
reset role;
select pg_temp.som(:'u3'); set role authenticated;
select pg_temp.lik(public.can_score(:'r3', :'carl'), false, 'C7 uten stab fører ikke Bjørn for Carl');
reset role;

-- C8 Pulje: kladden på samme kveld kan legges i pulje 2. Tom liste sletter gruppene.
select pg_temp.som(:'u1'); set role authenticated;
select pg_temp.lik(public.save_start_list(:'r4', 2, '[]'::jsonb), 0, 'C8 tom startliste for kladden');
select pg_temp.lik((select wave_no from public.rounds where id = :'r4')::int, 2, 'C8 kladden ligger i pulje 2');
select pg_temp.lik(public.save_start_list(:'r3', 1, '[{"group_no": 1}]'::jsonb), 1, 'C8 ny liste erstatter den gamle');
select pg_temp.lik((select count(*) from public.round_start_groups where round_id = :'r3')::int, 1,
                   'C8 gruppe 2 er slettet');
reset role;

-- C9 Tak i staben: høyst 50.
begin;
select pg_temp.som('');
insert into auth.users select ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid
  from generate_series(1, 60) i;
insert into public.profiles (id, display_name)
select ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid, 'Stab ' || i from generate_series(1, 60) i
    on conflict (id) do nothing;
insert into public.competition_staff (competition_id, profile_id, role)
select :'j2026', ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid, 'scorer'
  from generate_series(1, 49) i;
select pg_temp.lik((select count(*) from public.competition_staff where competition_id = :'j2026')::int, 50, 'C9 50 i staben');
select pg_temp.feil(format('insert into public.competition_staff (competition_id, profile_id, role) values (%L, %L, %L)',
                           :'j2026', '00000000-0000-0000-0000-000000000160', 'scorer'), '54000');
rollback;

-- === D. Kontrollblokken fra fila =============================================
select case when k.ok then 'ok ' else 'FEIL ' end || 'D' || k.nr || ' ' || k.sjekk from (
with f as (
  select p.proname,
         has_function_privilege('anon', p.oid, 'execute') as anon_kan,
         has_function_privilege('authenticated', p.oid, 'execute') as auth_kan,
         has_function_privilege('service_role', p.oid, 'execute') as service_kan,
         p.proconfig, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('waitlist_offer_hours', 'my_member_ids', 'my_entered_competition_ids',
                      'my_staff_competition_ids', 'my_competition_event_ids', 'is_round_staff',
                      'is_group_scorer', 'is_competition_participant', 'is_competition_admin',
                      'can_read_competition', 'is_round_organizer', 'can_read_round', 'can_score',
                      'guard_competition_staff', 'competition_fill', 'competition_signup_status',
                      'competition_signup_json', 'competition_signup', 'competition_withdraw',
                      'competition_offer_respond', 'competition_waitlist_entries',
                      'set_competition_signup', 'public_competitions', 'expire_competition_offers',
                      'save_start_list')
)
select 1 as nr, 'Alle 25 funksjonene finnes og har tom search_path' as sjekk,
       (select count(*) = 25 and bool_and('search_path=""' = any(proconfig)) from f) as ok
union all
select 2, 'anon kan ikke kalle noen av dem',
       (select bool_and(not anon_kan) from f)
union all
select 3, 'De gamle reglene står: én aktiv runde og sesong per klubb, én kveld per dato, én hovedturnering',
       (select count(*) = 4 from pg_indexes where schemaname = 'public'
         and indexname in ('rounds_one_active_per_club', 'seasons_one_active_per_club',
                           'competitions_one_main_active', 'rounds_one_active_per_event_wave'))
       and exists (select 1 from pg_constraint where conname = 'events_one_per_date'
                    and conrelid = 'public.events'::regclass)
union all
select 4, 'Interne funksjoner kan ikke kalles av appen; utløp bare av service_role',
       (select bool_and(not auth_kan) from f
         where proname in ('competition_fill', 'competition_signup_json', 'guard_competition_staff',
                           'expire_competition_offers'))
       and (select service_kan from f where proname = 'expire_competition_offers')
union all
select 5, 'RPC-ene og hjelperne kan kalles av innloggede',
       (select bool_and(auth_kan) from f
         where proname not in ('competition_fill', 'competition_signup_json', 'guard_competition_staff',
                               'expire_competition_offers'))
union all
select 6, 'Hjelperne fra 017 har grenene for staben',
       (select count(*) = 5 from f
         where proname in ('is_competition_admin', 'can_read_competition', 'is_round_organizer',
                           'can_read_round', 'can_score')
           and prosrc ~ '(competition_staff|is_round_staff|is_group_scorer)')
union all
select 7, 'De tre nye policyene finnes, og ingen annen policy fra før bruker staben',
       (select count(*) = 3 from pg_policies where schemaname = 'public'
         and policyname in ('competitions_select_staff', 'events_select_competition', 'rounds_select_competition'))
       and not exists (select 1 from pg_policies where schemaname = 'public'
                        and tablename not in ('app_config', 'competition_staff', 'competition_waitlist',
                                              'round_start_groups')
                        and policyname not in ('competitions_select_staff', 'events_select_competition',
                                               'rounds_select_competition')
                        and (coalesce(qual, '') || coalesce(with_check, ''))
                            ~ '(competition_staff|my_staff_competition_ids|my_entered_competition_ids|my_competition_event_ids|signup_audience|listed|wave_no)')
union all
select 8, 'round_start_groups.scorer_id og app_config.waitlist_offer_hours finnes',
       exists (select 1 from information_schema.columns where table_schema = 'public'
                and table_name = 'round_start_groups' and column_name = 'scorer_id')
       and exists (select 1 from public.app_config where key = 'waitlist_offer_hours' and value ? 'hours')
union all
select 9, 'Ingen står på ventelista med et tilbud som har gått ut for mer enn en time siden (cron går)',
       not exists (select 1 from public.competition_waitlist where offer_expires_at < now() - interval '1 hour')
union all
select 10, 'Paritet (Tavla): rundene via sesongens kvelder = rundene via turneringens spilledager = koblingene',
       not exists (
         (select e.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
           where e.season_id is not null
          except
          select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
            join public.competitions c on c.id = e.competition_id where c.season_id is not null)
         union all
         (select c.season_id, r.id from public.rounds r join public.events e on e.id = r.event_id
            join public.competitions c on c.id = e.competition_id where c.season_id is not null
          except
          select c.season_id, cr.round_id from public.competition_rounds cr
            join public.competitions c on c.id = cr.competition_id
           where cr.source = 'season' and c.season_id is not null))
) k order by k.nr;
