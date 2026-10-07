\set ON_ERROR_STOP on
\pset footer off
\pset tuples_only on
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Rolleprøve for 012_veddemaal.sql mot en lokal, midlertidig Postgres med
-- lokal/stub.sql og lokal/stub_storage.sql, etter 001, 008, 010, 011 og 012.
-- Kjøres i en tom base. Hver resultatlinje skal starte med "ok"; ingen "FEIL".
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

-- === Oppsett (som postgres) =================================================
-- u1 Thomas (arrangør), u2 Anders, u3 Bjørn, u4 Ola (annen klubb). Carl er med
-- i klubben, men ikke i runden.
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004');

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set ola     '22222222-0000-0000-0000-000000000004'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'

insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status) values
  (:'thomas', :'klubb',  :'u1', 'Thomas', true,  'active'),
  (:'anders', :'klubb',  :'u2', 'Anders', false, 'active'),
  (:'bjorn',  :'klubb',  :'u3', 'Bjørn',  false, 'active'),
  (:'carl',   :'klubb',  null,  'Carl',   false, 'active'),
  (:'ola',    :'klubb2', :'u4', 'Ola',    true,  'active');
-- Poengbank med 300 i startbeholdning; resten av regelsettet er Golfgutu.
insert into public.seasons (club_id, name, status, rules)
  values (:'klubb', '2026', 'active', '{"version": 2, "bets": {"startingPoints": 300}}') returning id as sesong \gset
insert into public.events (club_id, season_id, event_date, start_time)
  values (:'klubb', :'sesong', '2026-10-08', '17:00') returning id as kveld \gset
insert into public.rounds (club_id, event_id, hole_count) values (:'klubb', :'kveld', 18) returning id as runde \gset
insert into public.round_players (round_id, member_id, club_id) values
  (:'runde', :'thomas', :'klubb'), (:'runde', :'anders', :'klubb'), (:'runde', :'bjorn', :'klubb');
update public.rounds set status = 'active' where id = :'runde';

-- === anon ===================================================================
select pg_temp.som('');
set role anon;
select pg_temp.feil($$select * from public.bets$$, '42501');
select pg_temp.feil($$select * from public.bet_stakes$$, '42501');
select pg_temp.feil($$select public.create_bet(null, null, null, 'påstand', null, null, 'yes', 50)$$, '42501');
select pg_temp.feil($$select public.place_bet_stake(gen_random_uuid(), 'yes', 50)$$, '42501');
select pg_temp.feil($$select public.resolve_bet(gen_random_uuid(), 'yes')$$, '42501');
reset role;

-- === Fri tekst: Anders utfordrer Bjørn ======================================
select pg_temp.som(:'u2');
set role authenticated;
select (public.create_bet(:'klubb', :'runde', null, 'Bjørn kommer på pallen', null, :'bjorn', 'no', 100)) ->> 'bet_id' as fri \gset
select pg_temp.lik((select count(*) from public.bets), 1::bigint, 'veddemålet finnes');
select pg_temp.lik((select count(*) from public.bet_stakes where bet_id = :'fri'), 1::bigint, 'første innsats i samme kall');
select pg_temp.lik((select season_id::text from public.bets where id = :'fri'), :'sesong', 'sesongen følger kvelden');
select pg_temp.lik((select kind || '/' || category from public.activity order by created_at desc limit 1), 'bet_challenge/bet',
                   'aktivitetslinja: utfordring i kategorien bet');
select pg_temp.lik((select actor_member_id::text from public.activity order by created_at desc limit 1), :'anders', 'aktøren er Anders');
select pg_temp.feil($$insert into public.bets (club_id, season_id, question) values ('$$ || :'klubb' || $$', '$$ || :'sesong' || $$', 'snik')$$, '42501');
select pg_temp.feil($$insert into public.bet_stakes (bet_id, club_id, member_id, side, points) values ('$$ || :'fri' || $$', '$$ || :'klubb' || $$', '$$ || :'anders' || $$', 'no', 5)$$, '42501');
select pg_temp.feil($$update public.bets set status = 'resolved', resolution = 'no'$$, '42501');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', null, null, 'Meg', null, '$$ || :'anders' || $$', 'yes', 50)$$, '22023');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', null, null, 'ja', null, null, 'yes', 50)$$, '22023');
-- Tak 200 (Golfgutu) summert over innsatsene, og alltid samme side.
select pg_temp.feil($$select public.place_bet_stake('$$ || :'fri' || $$', 'no', 150)$$, '22023');
select pg_temp.feil($$select public.place_bet_stake('$$ || :'fri' || $$', 'yes', 10)$$, '22023');
select pg_temp.feil($$select public.place_bet_stake('$$ || :'fri' || $$', 'no', 0)$$, '22023');
select pg_temp.lik(public.place_bet_stake(:'fri', 'no', 100) is not null, true, 'opp til taket (100 + 100)');
reset role;

select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik(public.place_bet_stake(:'fri', 'yes', 100) is not null, true, 'Bjørn satser JA');
reset role;

-- === Vilkår: par på hull 5, og sperra ======================================
select pg_temp.som(:'u2');
set role authenticated;
select (public.create_bet(:'klubb', :'runde', null, 'Bjørn holder par på hull 5',
        jsonb_build_object('kind', 'par', 'hole', 4, 'player', :'bjorn'), :'bjorn', 'no', 100)) ->> 'bet_id' as par5 \gset
select pg_temp.lik(public.bet_accepts_stakes(:'par5'), true, 'hull 5 er åpent før første slag');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', '$$ || :'runde' || $$', null, 'Carl får par',
  '{"kind":"par","hole":2,"player":"$$ || :'carl' || $$"}', null, 'yes', 50)$$, '23503');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', '$$ || :'runde' || $$', null, 'Ugyldig hull',
  '{"kind":"par","hole":18,"player":"$$ || :'bjorn' || $$"}', null, 'yes', 50)$$, '22023');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', null, null, 'Uten runde',
  '{"kind":"par","hole":2,"player":"$$ || :'bjorn' || $$"}', null, 'yes', 50)$$, '22023');
-- Banken: 300 i start, 200 + 100 står ute. Ingenting ledig.
select pg_temp.lik((select available from public.bet_points(:'sesong', :'anders')), 0::numeric, 'Anders har 0 ledige');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', null, null, 'Tom bank', null, null, 'yes', 50)$$, '22023');
select pg_temp.lik((select count(*) from public.bets), 2::bigint, 'avvist innsats ruller tilbake veddemålet');
reset role;

-- Bjørn fører hull 1–4 (som postgres). Han står på hull 5; hull 5 er stengt.
insert into public.hole_scores (round_id, member_id, hole_index, strokes)
select :'runde', :'bjorn', h, 4 from generate_series(0, 3) h;
select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik(public.bet_accepts_stakes(:'par5'), false, 'hull 5 stenger i det hull 4 er ført');
select pg_temp.feil($$select public.place_bet_stake('$$ || :'par5' || $$', 'yes', 50)$$, '55000');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', '$$ || :'runde' || $$', null, 'Bjørn slår Anders i runden',
  '{"kind":"beats","a":"$$ || :'bjorn' || $$","b":"$$ || :'anders' || $$"}', '$$ || :'anders' || $$', 'yes', 50)$$, '55000');
select (public.create_bet(:'klubb', :'runde', null, 'Bjørn får birdie på hull 6',
        jsonb_build_object('kind', 'birdie', 'hole', 5, 'player', :'bjorn'), null, 'yes', 50)) ->> 'bet_id' as hull6 \gset
select pg_temp.lik(public.bet_accepts_stakes(:'hull6'), true, 'hull 6 er det første åpne');
reset role;

-- === Avgjøring ==============================================================
select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.feil($$select public.resolve_bet('$$ || :'fri' || $$', 'no')$$, '42501');
select pg_temp.lik(public.mark_bets_closed(array[:'hull6']::uuid[]), 0, 'spiller stempler ingenting');
reset role;

select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.lik((public.resolve_bet(:'fri', 'no')).status, 'resolved', 'arrangøren avgjør: NEI vant');
select pg_temp.lik((select closed_at is not null and resolved_by::text = :'thomas' from public.bets where id = :'fri'), true,
                   'stempel og hvem som avgjorde');
select pg_temp.feil($$select public.resolve_bet('$$ || :'fri' || $$', 'yes')$$, '55000');
select pg_temp.feil($$select public.resolve_bet('$$ || :'par5' || $$', 'kanskje')$$, '22023');
select pg_temp.lik((select kind from public.activity order by created_at desc, kind limit 1), 'bet_resolved', 'aktivitetslinja for avgjort');
-- Anders: 200 på NEI mot Bjørns 100 på JA → +100. Bjørn −100.
select pg_temp.lik((select net from public.bet_points(:'sesong', :'anders')), 100::numeric, 'Anders netto +100');
select pg_temp.lik((select balance from public.bet_points(:'sesong', :'anders')), 400::numeric, 'saldo 300 + 100');
select pg_temp.lik((select available from public.bet_points(:'sesong', :'anders')), 300::numeric, 'ledig: 400 − 100 i par-veddemålet');
select pg_temp.lik((select net from public.bet_points(:'sesong', :'bjorn')), -100::numeric, 'Bjørn netto −100');
select pg_temp.lik((select available from public.bet_points(:'sesong', :'bjorn')), 150::numeric, 'Bjørn: 200 − 50 i hull 6');
-- Annullert: alle får innsatsen tilbake.
select pg_temp.lik((public.resolve_bet(:'par5', 'void')).status, 'void', 'par-veddemålet annulleres');
select pg_temp.lik((select resolution from public.bets where id = :'par5'), null::text, 'annullert har ikke utfall');
select pg_temp.lik((select at_stake from public.bet_points(:'sesong', :'anders')), 0::numeric, 'ingenting står ute for Anders');
select pg_temp.lik((select net from public.bet_points(:'sesong', :'anders')), 100::numeric, 'netto uendret av annulleringen');
select pg_temp.lik(public.mark_bets_closed(array[:'hull6', :'fri']::uuid[]), 1, 'arrangøren stempler bare det åpne');
select pg_temp.lik(public.bet_accepts_stakes(:'hull6'), false, 'stemplet veddemål tar ingen innsatser');
reset role;

-- Uten poengbank: startingPoints null. Bare taket gjelder.
update public.seasons set rules = '{"version": 2, "bets": {"startingPoints": null}}' where id = :'sesong';
select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select available from public.bet_points(:'sesong', :'bjorn')), null::numeric, 'uten bank er ledig null');
select pg_temp.lik((public.create_bet(:'klubb', null, :'kveld', 'Anders vinner kvelden', null, :'anders', 'no', 200)) ? 'bet_id', true,
                   'uten bank: 200 går inn selv med −100 i netto');
reset role;

-- === Annen klubb ============================================================
select pg_temp.som(:'u4');
set role authenticated;
select pg_temp.lik((select count(*) from public.bets), 0::bigint, 'Ola ser ingen veddemål i Golfgutu');
select pg_temp.lik((select count(*) from public.bet_stakes), 0::bigint, 'Ola ser ingen innsatser');
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', null, null, 'Inntrenger', null, null, 'yes', 50)$$, '42501');
select pg_temp.feil($$select public.place_bet_stake('$$ || :'fri' || $$', 'yes', 50)$$, 'P0002');
select pg_temp.feil($$select * from public.bet_points('$$ || :'sesong' || $$', '$$ || :'anders' || $$')$$, 'P0002');
reset role;

-- === Låst runde, og sletting av runden ======================================
update public.rounds set status = 'locked' where id = :'runde';
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.feil($$select public.create_bet('$$ || :'klubb' || $$', '$$ || :'runde' || $$', null, 'For sent', null, null, 'yes', 50)$$, '55000');
reset role;
update public.rounds set status = 'active' where id = :'runde';
select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.lik((public.delete_round(:'runde')) ->> 'players', '3', 'runden slettes');
select pg_temp.lik((select count(*) from public.bets where round_id is not null), 0::bigint, 'veddemålene om runden fulgte med');
select pg_temp.lik((select count(*) from public.bets where event_id = :'kveld' and round_id is null), 1::bigint, 'kveldens frie veddemål står');
reset role;
