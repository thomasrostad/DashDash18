\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 025_blokkert_konkurranse.sql. Rekkefølge i en tom, lokal
-- Postgres: lokal/stub.sql, lokal/stub_storage.sql, 001–024 (009 er tatt med
-- i 011), 025 (gjerne to ganger), så denne fila. Lager sin egen verden.
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
create function pg_temp.melding(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlerrm;
end $$;
grant execute on all functions in schema pg_temp to public;

-- === Verdenen ================================================================
-- Klubb K med Olga, Petter, Rita, Siri, Tor og Una (alle aktive, så de ser
-- hverandre og kan blokkere). Olga eier den private konkurransen «Fredagsmoro»
-- (uten klubb) og deler koden. Olga blokkerer Petter og (senere) Tor. Rita
-- blokkerer Olga (motsatt retning). Siri blokkerer Tor (ikke eieren).
\set uO '25000000-0000-0000-0000-00000000000a'
\set uP '25000000-0000-0000-0000-00000000000b'
\set uR '25000000-0000-0000-0000-00000000000c'
\set uS '25000000-0000-0000-0000-00000000000d'
\set uT '25000000-0000-0000-0000-00000000000e'
\set uU '25000000-0000-0000-0000-00000000000f'
\set K  'a2500000-0000-0000-0000-000000000001'

select pg_temp.som('');
insert into auth.users values (:'uO'), (:'uP'), (:'uR'), (:'uS'), (:'uT'), (:'uU');
update public.profiles set display_name = case id when :'uO' then 'Olga' when :'uP' then 'Petter' when :'uR' then 'Rita'
                                                 when :'uS' then 'Siri' when :'uT' then 'Tor' else 'Una' end
 where id in (:'uO', :'uP', :'uR', :'uS', :'uT', :'uU');
insert into public.clubs (id, name) values (:'K', 'Klubb 025');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status) values
  (:'K', :'uO', 'Olga',   true,  'active'),
  (:'K', :'uP', 'Petter', false, 'active'),
  (:'K', :'uR', 'Rita',   false, 'active'),
  (:'K', :'uS', 'Siri',   false, 'active'),
  (:'K', :'uT', 'Tor',    false, 'active'),
  (:'K', :'uU', 'Una',    false, 'active');

-- Olga lager konkurransen og koden.
select pg_temp.som(:'uO'); set role authenticated;
select public.create_competition_with_entrants('fun', 'Fredagsmoro') as venn \gset
select public.competition_invite(:'venn') ->> 'code' as kode \gset

-- === A. Ingen blokkering: som før ============================================
select pg_temp.som(:'uT');
select pg_temp.lik(public.competition_invite_preview(:'kode') ->> 'name', 'Fredagsmoro', 'Tor ser forhåndsvisningen');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Tor blir med (ingen blokkering)');

-- === B. Eieren har blokkert deg ==============================================
select pg_temp.som(:'uO');
select pg_temp.lik(public.block_user(p_profile_id => :'uP')::text, :'uP', 'Olga blokkerer Petter');
select pg_temp.som(:'uP');
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), 'P0002');
select pg_temp.lik((select count(*) from public.competition_invites), 0::bigint, 'Petter ser ingen koder');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), 'DDB01');
select pg_temp.feil(format($$select public.claim_competition_invite(lower(%L))$$, :'kode'), 'DDB01');
select pg_temp.feil(format($$select public.join_competition(%L)$$, :'venn'), 'P0002');
-- Meldingen sier ikke «blokkert» (019: den blokkerte får ikke vite det).
select pg_temp.lik(pg_temp.melding(format($$select public.claim_competition_invite(%L)$$, :'kode')),
                   'Du kan ikke bli med i denne konkurransen', 'meldingen nevner ikke blokkering');
reset role; select pg_temp.som('');
select pg_temp.lik((select count(*) from public.competition_participants
                     where competition_id = :'venn' and profile_id = :'uP'), 0::bigint, 'Petter ble ikke påmeldt');
set role authenticated;

-- Eieren kan heller ikke melde ham på (som før, 017-vakta).
select pg_temp.som(:'uO');
select pg_temp.feil(format($$insert into public.competition_participants (competition_id, profile_id) values (%L, %L)$$,
                           :'venn', :'uP'), '42501');

-- === C. Du har blokkert eieren (motsatt retning) =============================
select pg_temp.som(:'uR');
select pg_temp.lik(public.block_user(p_profile_id => :'uO')::text, :'uO', 'Rita blokkerer Olga');
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), 'P0002');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), 'DDB01');

-- === D. Blokkering mot en annen påmeldt stopper deg ikke ======================
select pg_temp.som(:'uS');
select pg_temp.lik(public.block_user(p_profile_id => :'uT')::text, :'uT', 'Siri blokkerer Tor (påmeldt, ikke eier)');
select pg_temp.lik((public.competition_invite_preview(:'kode') ->> 'entrants')::int, 2, 'Siri ser forhåndsvisningen (Olga og Tor)');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Siri blir med');

-- === E. Påmeldt fra før, så blokkert =========================================
select pg_temp.som(:'uO');
select pg_temp.lik(public.block_user(p_profile_id => :'uT')::text, :'uT', 'Olga blokkerer Tor (påmeldt)');
select pg_temp.som(:'uT');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'already', 'Tor er fortsatt med (already)');
select pg_temp.lik((public.competition_invite_preview(:'kode') ->> 'entered')::boolean, true,
                   'Tor (påmeldt) ser forhåndsvisningen som før');
select pg_temp.lik(public.leave_competition(:'venn'), true, 'Tor melder seg av');
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), 'P0002');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), 'DDB01');
reset role; select pg_temp.som('');
select pg_temp.lik((select status from public.competition_participants
                     where competition_id = :'venn' and profile_id = :'uT'), 'withdrawn', 'Tor er fortsatt meldt av');
set role authenticated;

-- === F. Blokkeringen oppheves =================================================
select pg_temp.som(:'uO');
delete from public.user_blocks where blocked_id = :'uP';
select pg_temp.som(:'uP');
select pg_temp.lik(public.competition_invite_preview(:'kode') ->> 'owner_name', 'Olga', 'Petter ser den igjen');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Petter blir med etter opphevingen');

-- === G. Ferdig konkurranse: blokkert får samme svar som ukjent kode ===========
select pg_temp.som(:'uO');
select pg_temp.lik(public.block_user(p_profile_id => :'uP')::text, :'uP', 'Olga blokkerer Petter igjen');
reset role; select pg_temp.som('');
update public.competitions set status = 'finished' where id = :'venn';
set role authenticated;
select pg_temp.som(:'uU');
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), '55000');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), '55000');
select pg_temp.som(:'uR');
select pg_temp.feil(format($$select public.competition_invite_preview(%L)$$, :'kode'), 'P0002');
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), 'DDB01');
select pg_temp.som(:'uP');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'already', 'Petter (påmeldt) er fortsatt med');

-- === H. Eieren er slettet (owner_id tom): ingen å være blokkert av ===========
reset role; select pg_temp.som('');
update public.competitions set status = 'active', owner_id = null where id = :'venn';
set role authenticated;
select pg_temp.som(:'uR');
select pg_temp.lik(public.claim_competition_invite(:'kode') ->> 'joined', 'new', 'Rita blir med når eieren er borte');
reset role; select pg_temp.som('');
update public.competitions set owner_id = :'uO' where id = :'venn';

-- === I. Rettigheter ===========================================================
select pg_temp.lik(has_function_privilege('anon', 'public.competition_invite_preview(text)', 'execute'), false, 'anon kan ikke forhåndsvise');
select pg_temp.lik(has_function_privilege('anon', 'public.claim_competition_invite(text)', 'execute'), false, 'anon kan ikke bli med');
select pg_temp.lik(has_function_privilege('authenticated', 'public.competition_invite_preview(text)', 'execute'), true, 'authenticated kan forhåndsvise');
select pg_temp.lik(has_function_privilege('authenticated', 'public.claim_competition_invite(text)', 'execute'), true, 'authenticated kan bli med');
set role anon;
select pg_temp.feil(format($$select public.claim_competition_invite(%L)$$, :'kode'), '42501');
reset role;
