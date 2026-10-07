\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 023_kjop.sql. Rekkefølge i en tom, lokal Postgres:
-- lokal/stub.sql, lokal/stub_storage.sql, 001–018 (019–021 kan være med),
-- 023 (gjerne to ganger), så denne fila. Lager sin egen verden.
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
-- Som Edge Function verify-purchase: service_role, uten auth.uid().
create function pg_temp.kjop(p jsonb) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  set local role service_role;
  v := public.record_purchase(p);
  reset role;
  return v;
end $$;
grant execute on all functions in schema pg_temp to public;

-- === Verdenen ================================================================
-- Hanne eier turneringer uten klubb. Ivar er arrangør i klubben KK, Jon er
-- spiller der. Kim er fremmed.
\set uH '23000000-0000-0000-0000-00000000000a'
\set uI '23000000-0000-0000-0000-00000000000b'
\set uJ '23000000-0000-0000-0000-00000000000c'
\set uK '23000000-0000-0000-0000-00000000000d'
\set KK '23a00000-0000-0000-0000-000000000001'
\set P  'no.dashdash.turnering.sesong'
\set PA 'no.dashdash.turnering.ar'

select pg_temp.som('');
insert into auth.users values (:'uH'), (:'uI'), (:'uJ'), (:'uK');
insert into public.clubs (id, name) values (:'KK', 'Kjøpsklubben');
insert into public.club_members (club_id, user_id, display_name, is_organizer, status) values
  (:'KK', :'uI', 'Ivar', true, 'active'), (:'KK', :'uJ', 'Jon', false, 'active');

-- === A. Nye turneringer krever kjøp ==========================================
select pg_temp.som(:'uH'); set role authenticated;
select public.create_competition('cup', 'Høstcupen') as cup \gset
select public.create_competition('game', 'Skins') as skins \gset
select public.create_competition('league', 'Ligaen') as liga \gset
select pg_temp.lik((select requires_purchase from public.competitions where id = :'cup'), true, 'en cup krever kjøp');
select pg_temp.lik((select requires_purchase from public.competitions where id = :'skins'), false, 'spill på runden er gratis');
select pg_temp.lik(public.competition_is_unlocked(:'skins'), true, 'gratis = låst opp');
select pg_temp.lik(public.competition_is_unlocked(:'cup'), false, 'cupen er låst før kjøp');
insert into public.competitions (kind, name, requires_purchase) values ('fun', 'Snik', false) returning id as snik \gset
select pg_temp.lik((select requires_purchase from public.competitions where id = :'snik'), true,
                   'appen kan ikke slippe unna kjøpskravet ved å sende false');
select pg_temp.feil($$insert into public.competitions (kind, name, requires_purchase) values ('fun', 'Snik', true)$$, '42501');
select pg_temp.feil($$update public.competitions set requires_purchase = false where id = '$$ || :'cup' || $$'$$, '42501');
select pg_temp.feil($$insert into public.entitlements (product_id, profile_id) values ('$$ || :'P' || $$', '$$ || :'uH' || $$')$$, '42501');
select pg_temp.feil($$select public.record_purchase('{}'::jsonb)$$, '42501');
reset role;
select pg_temp.som(:'uK'); set role authenticated;
select pg_temp.feil($$select public.competition_is_unlocked('$$ || :'cup' || $$')$$, 'P0002');
reset role;

-- === B. Kjøp registreres av serveren =========================================
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'P', 'original_transaction_id', 't1',
                                                   'transaction_id', 't1', 'environment', 'sandbox', 'competition_id', :'cup')) ->> 'competition_id',
                   :'cup', 'kjøpet kobles til cupen');
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.lik(public.competition_is_unlocked(:'cup'), true, 'cupen er låst opp');
select pg_temp.lik((select count(*) from public.entitlements), 1::bigint, 'Hanne ser kjøpet sitt');
reset role;
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'P', 'original_transaction_id', 't1',
                                                   'environment', 'sandbox')) ->> 'competition_id',
                   :'cup', 'samme kjøp på nytt uten turnering (gjenoppretting) beholder koblingen');
select pg_temp.feil($$select pg_temp.kjop('{"profile_id": "$$ || :'uK' || $$", "product_id": "x", "original_transaction_id": "t1"}')$$, '42501');
-- Et nytt kjøp for en turnering som alt er låst opp, blir en ledig kreditt.
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'P', 'original_transaction_id', 't2',
                                                   'competition_id', :'cup')) ->> 'competition_id',
                   null::text, 'et kjøp nummer to for cupen blir kreditt');
-- Kim kan ikke koble et kjøp til Hannes cup.
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uK', 'product_id', :'P', 'original_transaction_id', 't9',
                                                   'competition_id', :'liga')) ->> 'competition_id',
                   null::text, 'Kim kan ikke låse opp Hannes liga (blir kreditt hos Kim)');
select id as kreditt from public.entitlements where original_transaction_id = 't2' \gset
select id as kims from public.entitlements where original_transaction_id = 't9' \gset

-- === C. Kreditt kobles i appen ===============================================
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.feil($$select public.assign_purchase('$$ || :'kreditt' || $$', '$$ || :'cup' || $$')$$, '23505');
select pg_temp.lik(public.assign_purchase(:'kreditt', :'liga'), true, 'Hanne kobler kreditten til ligaen');
select pg_temp.lik(public.competition_is_unlocked(:'liga'), true, 'ligaen er låst opp');
select pg_temp.feil($$select public.assign_purchase('$$ || :'kreditt' || $$', '$$ || :'liga' || $$')$$, '55000');
select pg_temp.feil($$select public.assign_purchase('$$ || :'kims' || $$', '$$ || :'liga' || $$')$$, 'P0002');
reset role;
select pg_temp.som(:'uK'); set role authenticated;
select pg_temp.feil($$select public.assign_purchase('$$ || :'kims' || $$', '$$ || :'cup' || $$')$$, '42501');
select pg_temp.lik((select count(*) from public.entitlements), 1::bigint, 'Kim ser bare sitt eget kjøp');
reset role;

-- === D. Refusjon og abonnement ===============================================
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'P', 'original_transaction_id', 't1',
                                                   'status', 'refunded', 'revoked_at', '2026-10-09T10:00:00Z')) ->> 'status',
                   'refunded', 'refusjon fra App Store registreres');
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.lik(public.competition_is_unlocked(:'cup'), false, 'cupen er låst igjen etter refusjon');
reset role;
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'PA', 'product_kind', 'subscription',
                                                   'original_transaction_id', 's1', 'expires_at', (now() + interval '300 days')::text)) ->> 'product_kind',
                   'subscription', 'Hanne tegner årsabonnement');
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.lik(public.competition_is_unlocked(:'cup'), true, 'abonnementet låser opp alle Hannes turneringer');
reset role;
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uH', 'product_id', :'PA', 'product_kind', 'subscription',
                                                   'original_transaction_id', 's1', 'status', 'expired',
                                                   'expires_at', (now() - interval '1 day')::text)) ->> 'status',
                   'expired', 'abonnementet utløper');
select pg_temp.som(:'uH'); set role authenticated;
select pg_temp.lik(public.competition_is_unlocked(:'cup'), false, 'og cupen er låst igjen');
reset role;

-- === E. Klubb ================================================================
select pg_temp.som(:'uI'); set role authenticated;
select public.create_competition('league', 'Klubbligaen', :'KK') as klubbliga \gset
select pg_temp.lik(public.competition_is_unlocked(:'klubbliga'), false, 'klubbligaen er låst');
reset role;
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uJ', 'product_id', :'PA', 'product_kind', 'subscription',
                                                   'original_transaction_id', 's2', 'club_id', :'KK',
                                                   'expires_at', (now() + interval '30 days')::text)) ->> 'club_id',
                   null::text, 'Jon (ikke arrangør) kan ikke kjøpe for klubben');
select pg_temp.lik(pg_temp.kjop(jsonb_build_object('profile_id', :'uI', 'product_id', :'PA', 'product_kind', 'subscription',
                                                   'original_transaction_id', 's3', 'club_id', :'KK',
                                                   'expires_at', (now() + interval '30 days')::text)) ->> 'club_id',
                   :'KK', 'Ivar (arrangør) tegner abonnement for klubben');
select pg_temp.som(:'uJ'); set role authenticated;
select pg_temp.lik(public.competition_is_unlocked(:'klubbliga'), true, 'Jon ser at klubbligaen er låst opp');
reset role;

-- === F. Uinnlogget (anon) ====================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select public.competition_is_unlocked(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.assign_purchase(gen_random_uuid(), gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.record_purchase('{}'::jsonb)$$, '42501');
select pg_temp.feil($$select * from public.entitlements$$, '42501');
reset role;
set role authenticated;
select pg_temp.feil($$select public.competition_is_unlocked(gen_random_uuid())$$, '42501');
select pg_temp.feil($$select public.assign_purchase(gen_random_uuid(), gen_random_uuid())$$, '42501');
reset role;
