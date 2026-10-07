\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 019_konto_og_moderering.sql. Rekkefølge i en tom, lokal
-- Postgres: lokal/stub.sql, lokal/stub_storage.sql, 001–018 (020 og 021 kan
-- være med), 019 (gjerne to ganger), så denne fila. Lager sin egen verden.
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
grant execute on all functions in schema pg_temp to public;

-- === Verdenen ================================================================
-- Klubb K: Anne (arrangør), Bo og Cato. Klubb K2: Eva (eneste arrangør) og
-- Gro. Frank er fremmed (ingen klubb). Løs runde LR (eier Anne) med Anne og
-- Cato på den felles banen Losby.
\set uA '0a000000-0000-0000-0000-00000000000a'
\set uB '0b000000-0000-0000-0000-00000000000b'
\set uC '0c000000-0000-0000-0000-00000000000c'
\set uE '0e000000-0000-0000-0000-00000000000e'
\set uF '0f000000-0000-0000-0000-00000000000f'
\set uG '06000000-0000-0000-0000-000000000006'
\set K   'a1900000-0000-0000-0000-000000000001'
\set K2  'a1900000-0000-0000-0000-000000000002'
\set mA  'b1900000-0000-0000-0000-00000000000a'
\set mB  'b1900000-0000-0000-0000-00000000000b'
\set mC  'b1900000-0000-0000-0000-00000000000c'
\set mE  'b1900000-0000-0000-0000-00000000000e'
\set mG  'b1900000-0000-0000-0000-000000000006'
\set e1  'e1900000-0000-0000-0000-000000000001'
\set msg1 'f1900000-0000-0000-0000-000000000001'
\set msg2 'f1900000-0000-0000-0000-000000000002'
\set L   'c1900000-0000-0000-0000-000000000001'
\set KC  'c1900000-0000-0000-0000-000000000002'
\set LR  'd1900000-0000-0000-0000-000000000001'
\set pA  'd2900000-0000-0000-0000-00000000000a'
\set pC  'd2900000-0000-0000-0000-00000000000c'

select pg_temp.som('');
insert into auth.users values (:'uA'), (:'uB'), (:'uC'), (:'uE'), (:'uF'), (:'uG');
update public.profiles set display_name = case id when :'uA' then 'Anne' when :'uB' then 'Bo' when :'uC' then 'Cato'
                                                 when :'uE' then 'Eva' when :'uF' then 'Frank' else 'Gro' end
 where id in (:'uA', :'uB', :'uC', :'uE', :'uF', :'uG');
insert into public.clubs (id, name) values (:'K', 'Klubben'), (:'K2', 'Klubb to');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status, avatar_path, created_at) values
  (:'mA', :'K',  :'uA', 'Anne', true,  'active', null, now() - interval '3 days'),
  (:'mB', :'K',  :'uB', 'Bo',   false, 'active', null, now() - interval '2 days'),
  (:'mC', :'K',  :'uC', 'Cato', false, 'active', :'mC' || '/0c000000-0000-0000-0000-000000000001.jpg', now() - interval '1 days'),
  (:'mE', :'K2', :'uE', 'Eva',  true,  'active', null, now() - interval '3 days'),
  (:'mG', :'K2', :'uG', 'Gro',  false, 'active', null, now() - interval '2 days');
insert into public.events (id, club_id, event_date) values (:'e1', :'K', '2026-10-08');
insert into public.thread_messages (id, club_id, event_id, member_id, body, image_path) values
  (:'msg1', :'K', :'e1', :'mC', 'Stygg melding', :'mC' || '/' || :'msg1' || '.jpg'),
  (:'msg2', :'K', :'e1', :'mB', 'Hei alle', null);
insert into public.activity (id, club_id, kind, category) values ('a2900000-0000-0000-0000-000000000001', :'K', 'note', 'club');
insert into public.activity_reactions (activity_id, member_id, club_id, emoji) values
  ('a2900000-0000-0000-0000-000000000001', :'mC', :'K', '👍'), ('a2900000-0000-0000-0000-000000000001', :'mB', :'K', '🔥');
insert into public.push_devices (user_id, device_id, token, environment)
values (:'uC', 'cato-telefon', repeat('ab', 32), 'sandbox');
insert into storage.objects (bucket_id, name) values
  ('avatars', :'mC' || '/0c000000-0000-0000-0000-000000000001.jpg'),
  ('thread',  :'mC' || '/' || :'msg1' || '.jpg'),
  ('avatars', :'mB' || '/0b000000-0000-0000-0000-000000000001.jpg');
insert into public.courses (id, club_id, name) values (:'L', null, 'Losby'), (:'KC', :'K', 'Klubbens bane');
insert into public.course_holes (course_id, hole_number, par, stroke_index)
select :'L', h, 4, h from generate_series(1, 18) h;
insert into public.rounds (id, course_id, hole_count, owner_id) values (:'LR', :'L', 9, :'uA');
insert into public.round_participants (id, round_id, profile_id, display_name) values
  (:'pA', :'LR', :'uA', 'Anne'), (:'pC', :'LR', :'uC', 'Cato');
update public.rounds set status = 'active' where id = :'LR';
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select :'LR', p, h, 5 from (values (:'pA'::uuid), (:'pC'::uuid)) v(p), generate_series(0, 3) h;

-- === A. Banerettelser ========================================================
select pg_temp.som(:'uB'); set role authenticated;
insert into public.course_corrections (course_id, profile_id, hole_number, par, created_by)
values (:'L', :'uB', 1, 5, :'uF') returning 'ok Bo retter par på hull 1 i Losby for seg selv';
select pg_temp.lik((select created_by::text from public.course_corrections where profile_id = :'uB'), :'uB',
                   'created_by settes av serveren');
select pg_temp.feil($$insert into public.course_corrections (course_id, club_id, hole_number, par) values ('$$ || :'L' || $$', '$$ || :'K' || $$', 2, 3)$$, '42501');
select pg_temp.feil($$insert into public.course_corrections (course_id, profile_id, hole_number, par) values ('$$ || :'KC' || $$', '$$ || :'uB' || $$', 2, 3)$$, '22023');
select pg_temp.feil($$insert into public.course_corrections (course_id, profile_id, par) values ('$$ || :'L' || $$', '$$ || :'uB' || $$', 3)$$, '23514');
select pg_temp.feil($$insert into public.course_corrections (course_id, profile_id, hole_number, course_rating) values ('$$ || :'L' || $$', '$$ || :'uB' || $$', 3, 70)$$, '23514');
select pg_temp.feil($$insert into public.course_corrections (course_id, profile_id, hole_number, par) values ('$$ || :'L' || $$', '$$ || :'uB' || $$', 1, 3)$$, '23505');
select pg_temp.feil($$insert into public.course_corrections (course_id, profile_id, hole_number, par) values ('$$ || :'L' || $$', '$$ || :'uF' || $$', 4, 3)$$, '42501');
insert into public.course_corrections (course_id, profile_id, course_rating, slope_rating)
values (:'L', :'uB', 71.2, 128) returning 'ok Bo retter CR og slope for banen';
select pg_temp.feil($$update public.course_corrections set course_id = '$$ || :'KC' || $$' where profile_id = '$$ || :'uB' || $$' and hole_number = 1$$, '42501');
reset role;
select pg_temp.som(:'uA'); set role authenticated;
insert into public.course_corrections (course_id, club_id, hole_number, stroke_index)
values (:'L', :'K', 1, 7) returning 'ok Anne (arrangør) retter indeksen for klubben';
reset role;
select pg_temp.som(:'uB'); set role authenticated;
select pg_temp.lik((select count(*) from public.course_corrections), 3::bigint, 'Bo ser sine to og klubbens');
reset role;
select pg_temp.som(:'uF'); set role authenticated;
select pg_temp.lik((select count(*) from public.course_corrections), 0::bigint, 'Frank (fremmed) ser ingen rettelser');
update public.course_corrections set par = 3;
reset role;
select pg_temp.lik((select par from public.course_corrections where profile_id = :'uB' and hole_number = 1), 5::smallint,
                   'Frank fikk ikke endret Bos rettelse');
-- En ny henting av banen (serveren) rører ikke rettelsene.
select pg_temp.som('');
update public.courses set source = 'golfapi', external_id = 'losby-1', fetched_at = now() where id = :'L';
update public.course_holes set par = 4, stroke_index = hole_number where course_id = :'L';
select pg_temp.lik((select count(*) from public.course_corrections where course_id = :'L'), 3::bigint,
                   'rettelsene står etter en ny henting');

-- === B. Blokkering ===========================================================
select pg_temp.som(:'uB'); set role authenticated;
select pg_temp.lik((select count(*) from public.thread_messages), 2::bigint, 'Bo ser begge meldingene før blokkering');
select pg_temp.feil($$insert into public.user_blocks (blocker_id, blocked_id) values ('$$ || :'uB' || $$', '$$ || :'uC' || $$')$$, '42501');
select pg_temp.lik(public.block_user(p_member_id => :'mC')::text, :'uC', 'Bo blokkerer Cato fra tråden (via medlemmet)');
select pg_temp.lik(public.block_user(p_profile_id => :'uC')::text, :'uC', 'blokkering er idempotent');
select pg_temp.lik((select count(*) from public.thread_messages), 1::bigint, 'Bo ser ikke lenger Catos melding');
select pg_temp.lik((select count(*) from public.activity_reactions), 1::bigint, 'og ikke Catos reaksjon');
select pg_temp.lik((select display_name from public.my_blocks()), 'Cato', 'my_blocks viser navnet');
select pg_temp.lik(public.can_see_profile(:'uC'), false, 'Bo kan ikke lenger legge Cato til i noe');
select pg_temp.feil($$select public.block_user(p_profile_id => '$$ || :'uB' || $$')$$, '22023');
select pg_temp.feil($$select public.block_user('$$ || :'uA' || $$', '$$ || :'mA' || $$')$$, '22023');
reset role;
select pg_temp.som(:'uC'); set role authenticated;
select pg_temp.lik(public.can_see_profile(:'uB'), false, 'Cato kan heller ikke legge Bo til (begge retninger)');
select pg_temp.lik((select count(*) from public.user_blocks), 0::bigint, 'Cato ser ikke at hen er blokkert');
select pg_temp.lik((select count(*) from public.thread_messages), 2::bigint, 'Cato ser fortsatt tråden');
reset role;
select pg_temp.som(:'uA'); set role authenticated;
select pg_temp.lik((select count(*) from public.thread_messages), 2::bigint, 'Anne (ikke blokkert) ser begge');
select pg_temp.lik(public.can_see_profile(:'uC'), true, 'Anne ser Cato som før');
reset role;
select pg_temp.som(:'uF'); set role authenticated;
select pg_temp.feil($$select public.block_user(p_profile_id => '$$ || :'uB' || $$')$$, 'P0002');
select pg_temp.feil($$select public.block_user(p_member_id => '$$ || :'mB' || $$')$$, 'P0002');
reset role;
select pg_temp.som(:'uB'); set role authenticated;
delete from public.user_blocks where blocked_id = :'uC';
select pg_temp.lik((select count(*) from public.thread_messages), 2::bigint, 'Bo opphever blokkeringen og ser meldingen igjen');
select public.block_user(p_member_id => :'mC') is not null as blokkert_igjen \gset
reset role;

-- === C. Rapporter og moderering ==============================================
select pg_temp.som(:'uB'); set role authenticated;
select public.report_content('message', :'msg1', 'offensive', 'Ikke greit') as rapport1 \gset
select pg_temp.lik(public.report_content('message', :'msg1', 'harassment'), :'rapport1'::uuid,
                   'samme rapport på nytt oppdaterer den åpne');
select pg_temp.lik((select reason || ':' || coalesce(note, '-') from public.content_reports where id = :'rapport1'), 'harassment:-',
                   'grunnen er oppdatert');
select pg_temp.lik((select club_id::text || ':' || target_profile_id::text || ':' || snapshot from public.content_reports where id = :'rapport1'),
                   :'K' || ':' || :'uC' || ':Stygg melding', 'klubb, forfatter og kopi settes av serveren');
select pg_temp.feil($$select public.report_content('image', '$$ || :'msg2' || $$', 'inappropriate_image')$$, 'P0002');
select pg_temp.feil($$select public.report_content('message', '$$ || :'msg1' || $$', 'kjedelig')$$, '22023');
select pg_temp.feil($$select public.report_content('rounds', '$$ || :'msg1' || $$', 'spam')$$, '22023');
select pg_temp.feil($$insert into public.content_reports (reporter_id, kind, target_id, reason) values ('$$ || :'uB' || $$', 'message', '$$ || :'msg1' || $$', 'spam')$$, '42501');
select pg_temp.lik((select count(*) from public.content_reports), 1::bigint, 'Bo ser sin egen rapport');
select pg_temp.feil($$select public.resolve_report('$$ || :'rapport1' || $$', 'remove')$$, '42501');
reset role;
select pg_temp.som(:'uF'); set role authenticated;
select pg_temp.feil($$select public.report_content('message', '$$ || :'msg1' || $$', 'spam')$$, 'P0002');
select pg_temp.feil($$select public.report_content('profile', '$$ || :'uB' || $$', 'spam')$$, 'P0002');
reset role;
select pg_temp.som(:'uC'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports), 0::bigint, 'Cato ser ikke rapporten om seg');
select public.report_content('image', :'msg1', 'inappropriate_image') as rapport_egen \gset
reset role;
select pg_temp.som(:'uE'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports), 0::bigint, 'Eva (arrangør i en annen klubb) ser ingen');
select pg_temp.feil($$select public.resolve_report('$$ || :'rapport1' || $$', 'dismiss')$$, '42501');
reset role;
select pg_temp.som(:'uA'); set role authenticated;
select pg_temp.lik((select count(*) from public.content_reports where status = 'open'), 2::bigint, 'Anne (arrangør) ser klubbens to rapporter');
select pg_temp.feil($$select public.resolve_report('$$ || :'rapport1' || $$', 'slett')$$, '22023');
select pg_temp.lik(public.resolve_report(:'rapport1', 'remove'),
                   jsonb_build_object('status', 'removed', 'image_path', :'mC' || '/' || :'msg1' || '.jpg'),
                   'Anne fjerner meldingen og får bildestien tilbake');
select pg_temp.lik((select count(*) from public.thread_messages where id = :'msg1'), 0::bigint, 'meldingen er slettet');
select pg_temp.lik((select count(*) from public.content_reports where status = 'removed'), 2::bigint,
                   'begge rapportene om meldingen (tekst og bilde) er avgjort');
select pg_temp.feil($$select public.resolve_report('$$ || :'rapport1' || $$', 'dismiss')$$, '55000');
select public.report_content('profile', :'uC', 'impersonation') as rapport_profil \gset
select pg_temp.lik((select club_id from public.content_reports where id = :'rapport_profil'), null::uuid,
                   'en profilrapport fra en løs runde har ingen klubb (vi modererer)');
select pg_temp.feil($$select public.resolve_report('$$ || :'rapport_profil' || $$', 'dismiss')$$, '42501');
select public.report_content('member', :'mB', 'other', 'Feil navn') is not null as rapport_navn \gset
reset role;

-- === D. Vilkår ===============================================================
select pg_temp.som(:'uF'); set role authenticated;
select pg_temp.lik(public.accept_terms('2026-10') is not null, true, 'Frank godtar vilkårene');
select pg_temp.lik((select terms_version from public.profiles where id = :'uF'), '2026-10', 'versjonen er lagret');
select pg_temp.feil($$select public.accept_terms('ikke gyldig!')$$, '22023');
reset role;

-- === E. Sletting av konto ====================================================
select pg_temp.som(:'uC'); set role authenticated;
select pg_temp.feil($$select public.delete_account_data('$$ || :'uC' || $$')$$, '42501');
select pg_temp.feil($$select * from public.account_storage_objects('$$ || :'uC' || $$')$$, '42501');
reset role;

-- Serveren (Edge Function, service_role, uten auth.uid()).
select pg_temp.som(''); set role service_role;
select pg_temp.lik((select string_agg(bucket_id, ',' order by bucket_id) from public.account_storage_objects(:'uC')),
                   'avatars,thread', 'Catos portrett og trådbilde skal slettes (ikke Bos)');
select pg_temp.lik(public.delete_account_data(:'uC'),
                   '{"messages": 0, "memberships": 1, "loose_rounds": 1, "organizers_promoted": 0}'::jsonb,
                   'Cato anonymiseres (meldingen var alt fjernet av arrangøren)');
reset role;
select pg_temp.lik((select display_name || ':' || status || ':' || (user_id is null) || ':' || (avatar_path is null)
                    from public.club_members where id = :'mC'), 'Slettet spiller:archived:true:true',
                   'troppen: «Slettet spiller», arkivert, uten innlogging og portrett');
select pg_temp.lik((select display_name from public.round_participants where id = :'pC'), 'Slettet spiller',
                   'løs runde: navnet er «Slettet spiller»');
select pg_temp.lik((select count(*) from public.hole_scores where member_id = :'pC'), 4::bigint, 'scorene står');
select pg_temp.lik((select count(*) from public.push_devices where user_id = :'uC'), 0::bigint, 'telefonen får ikke push');
select pg_temp.lik((select count(*) from public.activity_reactions where member_id = :'mC'), 0::bigint, 'reaksjonene er borte');
select pg_temp.lik((select count(*) from public.user_blocks where blocked_id = :'uC'), 0::bigint, 'blokkeringer er borte');
select pg_temp.lik((select display_name from public.profiles where id = :'uC'), null::text, 'profilen er tømt');
select pg_temp.som(''); set role service_role;
select pg_temp.lik(public.delete_account_data(:'uC') ->> 'memberships', '0', 'idempotent: andre gang er det ingenting igjen');
reset role;
-- Så auth.admin.deleteUser:
delete from auth.users where id = :'uC';
select pg_temp.lik((select count(*) from public.profiles where id = :'uC'), 0::bigint, 'profilen er slettet med kontoen');
select pg_temp.lik((select (profile_id is null)::text || ':' || display_name from public.round_participants where id = :'pC'),
                   'true:Slettet spiller', 'deltakeren står som gjest');
select pg_temp.lik((select (target_profile_id is null)::text from public.content_reports where id = :'rapport_profil'), 'true',
                   'rapporten om profilen står, uten kobling');
-- Navnet kan ikke tas av en ny innlogging (arkivert).
select pg_temp.som(:'uF'); set role authenticated;
select pg_temp.lik((select count(*) from public.club_members), 0::bigint, 'Frank ser fortsatt ingenting i klubben');
reset role;

-- Siste arrangør: Eva sletter kontoen, Gro overtar.
select pg_temp.som(''); set role service_role;
select pg_temp.lik(public.delete_account_data(:'uE') ->> 'organizers_promoted', '1', 'Eva var eneste arrangør');
reset role;
select pg_temp.lik((select is_organizer from public.club_members where id = :'mG'), true, 'Gro er arrangør i klubb to');
delete from auth.users where id = :'uE';
-- Anne har en rettelse for klubben; Bo sletter kontoen, og hans egne går med.
select pg_temp.som(''); set role service_role;
select public.delete_account_data(:'uB') is not null as bo_slettet \gset
reset role;
delete from auth.users where id = :'uB';
select pg_temp.lik((select count(*) from public.course_corrections where course_id = :'L'), 1::bigint,
                   'Bos rettelser går med kontoen, klubbens står');

-- === F. Uinnlogget (anon) ====================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.course_corrections$$, '42501');
select pg_temp.feil($$select * from public.user_blocks$$, '42501');
select pg_temp.feil($$select * from public.content_reports$$, '42501');
select pg_temp.feil($$select public.block_user(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.report_content('message', gen_random_uuid(), 'spam')$$, '42501');
select pg_temp.feil($$select public.resolve_report(gen_random_uuid(), 'dismiss')$$, '42501');
select pg_temp.feil($$select public.accept_terms('1')$$, '42501');
select pg_temp.feil($$select * from public.my_blocks()$$, '42501');
select pg_temp.feil($$select public.delete_account_data(gen_random_uuid())$$, '42501');
reset role;
-- Innlogget, men uten auth.uid() (bakvei): RPC-ene nekter.
set role authenticated;
select pg_temp.feil($$select public.block_user(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.report_content('message', gen_random_uuid(), 'spam')$$, '42501');
select pg_temp.feil($$select public.accept_terms('1')$$, '42501');
reset role;
