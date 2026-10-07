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
-- u1 Thomas (arrangør), u2 Anders, u3 Bjørn, u4 Ola (annen klubb), u5 Dag. Carl
-- og Dag er med i klubben, men ikke i runden.
insert into auth.users values
 ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
 ('00000000-0000-0000-0000-000000000003'), ('00000000-0000-0000-0000-000000000004'),
 ('00000000-0000-0000-0000-000000000005');

\set klubb   'aaaaaaaa-0000-0000-0000-000000000001'
\set klubb2  'aaaaaaaa-0000-0000-0000-000000000002'
\set thomas  '11111111-0000-0000-0000-000000000001'
\set anders  '11111111-0000-0000-0000-000000000002'
\set bjorn   '11111111-0000-0000-0000-000000000003'
\set carl    '11111111-0000-0000-0000-000000000009'
\set dag     '11111111-0000-0000-0000-000000000005'
\set ola     '22222222-0000-0000-0000-000000000004'
\set u1 '00000000-0000-0000-0000-000000000001'
\set u2 '00000000-0000-0000-0000-000000000002'
\set u3 '00000000-0000-0000-0000-000000000003'
\set u4 '00000000-0000-0000-0000-000000000004'
\set u5 '00000000-0000-0000-0000-000000000005'

insert into public.clubs (id, name) values (:'klubb', 'Golfgutu'), (:'klubb2', 'Andre');
insert into public.club_members (id, club_id, user_id, display_name, is_organizer, status) values
  (:'thomas', :'klubb',  :'u1', 'Thomas', true,  'active'),
  (:'anders', :'klubb',  :'u2', 'Anders', false, 'active'),
  (:'bjorn',  :'klubb',  :'u3', 'Bjørn',  false, 'active'),
  (:'carl',   :'klubb',  null,  'Carl',   false, 'active'),
  (:'dag',    :'klubb',  :'u5', 'Dag',    false, 'active'),
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
select pg_temp.feil($$select public.settle_bet(gen_random_uuid(), 'yes')$$, '42501');
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

-- === Feiingen: settle_bet (vilkåret avgjør, delt annulleres) =================
-- Bjørn har ført hull 1–4. hull6 (birdie hull 6, Bjørn JA 50) er stemplet, men åpent.
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.feil($$select public.settle_bet('$$ || :'hull6' || $$', 'yes')$$, '42501');
-- Duell på hull 8 (indeks 7): Bjørn har ført hull 1–4 og Anders ingenting, så hull 6 og senere er åpne.
select (public.create_bet(:'klubb', :'runde', null, 'Bjørn slår Anders netto på hull 8',
        jsonb_build_object('kind', 'hole', 'hole', 7, 'a', :'bjorn', 'b', :'anders'), :'bjorn', 'no', 50)) ->> 'bet_id' as duell \gset
reset role;
select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.lik(public.place_bet_stake(:'duell', 'yes', 50) is not null, true, 'arrangøren kan satse (bare avgjøringen er sperret)');
select pg_temp.feil($$select public.settle_bet('$$ || :'hull6' || $$', 'yes')$$, '55000');
select pg_temp.feil($$select public.settle_bet('$$ || :'hull6' || $$', 'void')$$, '22023');
select (select id::text from public.bets where condition is null and status = 'open' limit 1) as fritekst \gset
select pg_temp.feil($$select public.settle_bet('$$ || :'fritekst' || $$', 'yes')$$, '22023');
reset role;
-- Hull 6 føres for Bjørn (5 slag), hull 7 og 8 for Bjørn og Anders (4 og 4: delt).
insert into public.hole_scores (round_id, member_id, hole_index, strokes) values
  (:'runde', :'bjorn', 4, 4), (:'runde', :'bjorn', 5, 5), (:'runde', :'bjorn', 6, 4),
  (:'runde', :'bjorn', 7, 4), (:'runde', :'anders', 7, 4);
select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.lik((public.settle_bet(:'hull6', 'no')).status, 'resolved', 'feiingen avgjør hull 6: NEI');
select pg_temp.lik((select resolved_by from public.bets where id = :'hull6'), null::uuid, 'avgjort av scorene (resolved_by tom)');
select pg_temp.lik((select data ->> 'auto' from public.activity order by created_at desc, kind limit 1), 'true',
                   'aktivitetslinja merket automatisk');
select pg_temp.feil($$select public.resolve_bet('$$ || :'duell' || $$', 'void')$$, '55000');
select pg_temp.lik((select status from public.bets where id = :'duell'), 'open', 'arrangøren med innsats avgjorde ikke');
select pg_temp.lik((public.settle_bet(:'duell', 'void')).status, 'void', 'delt hull annulleres av feiingen, også med arrangørens innsats');
select pg_temp.feil($$select public.settle_bet('$$ || :'duell' || $$', 'yes')$$, '55000');
reset role;

-- === Hele poeng og den som avgjør ===========================================
-- Sesongveddemål (uten runde). Ingen bank ennå, så bare taket gjelder.
-- «Rest»: Thomas og Anders JA 50 hver mot Dags NEI 1. Gevinsten 0,5 rundes til 1
-- hver (floor(x + 0.5)) = 2, ett for mye; det tas fra største innsats, likt →
-- laveste medlems-id (Thomas). Thomas 0, Anders +1, Dag −1.
select pg_temp.som(:'u5');
set role authenticated;
select (public.create_bet(:'klubb', null, null, 'Det blir sol i morgen', null, null, 'no', 1)) ->> 'bet_id' as rest \gset
select (public.create_bet(:'klubb', null, null, 'Thomas vinner sesongen', null, :'thomas', 'no', 100)) ->> 'bet_id' as hele \gset
reset role;
select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.lik(public.place_bet_stake(:'rest', 'yes', 50) is not null, true, 'Thomas JA 50 på rest');
select pg_temp.lik(public.place_bet_stake(:'hele', 'yes', 100) is not null, true, 'Thomas JA 100 på hele');
reset role;
select pg_temp.som(:'u2');
set role authenticated;
select pg_temp.lik(public.place_bet_stake(:'rest', 'yes', 50) is not null, true, 'Anders JA 50 på rest');
select pg_temp.lik(public.place_bet_stake(:'hele', 'yes', 50) is not null, true, 'Anders JA 50 på hele');
reset role;
-- Thomas er eneste arrangør og har satset: han kan ikke avgjøre.
select pg_temp.som(:'u1');
set role authenticated;
select pg_temp.feil($$select public.resolve_bet('$$ || :'rest' || $$', 'yes')$$, '55000');
select pg_temp.feil($$select public.resolve_bet('$$ || :'hele' || $$', 'void')$$, '55000');
select pg_temp.lik((select count(*) from public.bets where id in (:'rest', :'hele') and status = 'open'), 2::bigint,
                   'begge står åpne');
reset role;
-- Bjørn blir arrangør (uten innsats i disse to) og avgjør.
update public.club_members set is_organizer = true where id = :'bjorn';
select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((public.resolve_bet(:'rest', 'yes')).status, 'resolved', 'en annen arrangør avgjør rest');
select pg_temp.lik((public.resolve_bet(:'hele', 'yes')).status, 'resolved', 'og hele');
-- hele: Dags 100 delt 100/50: 66,67 → 67 og 33,33 → 33.
select pg_temp.lik((select net from public.bet_points(:'sesong', :'thomas')), 67::numeric, 'Thomas: 0 + 67');
select pg_temp.lik((select net from public.bet_points(:'sesong', :'anders')), 134::numeric, 'Anders: 100 + 1 + 33');
select pg_temp.lik((select net from public.bet_points(:'sesong', :'dag')), -101::numeric, 'Dag: −1 − 100');
select pg_temp.lik((select sum(p.net) from public.club_members m, public.bet_points(:'sesong', m.id) p
                    where m.club_id = :'klubb'), 0::numeric, 'hele poeng: summen over klubben er null');
-- To desimaler (PWA-en): 0,5 hver i rest, 66,67 og 33,33 i hele.
reset role;
update public.seasons set rules = '{"version": 2, "bets": {"startingPoints": null, "payoutDecimals": 2}}' where id = :'sesong';
select pg_temp.som(:'u3');
set role authenticated;
select pg_temp.lik((select net from public.bet_points(:'sesong', :'thomas')), 67.17::numeric, 'to desimaler: Thomas 0,5 + 66,67');
select pg_temp.lik((select net from public.bet_points(:'sesong', :'anders')), 133.83::numeric, 'to desimaler: Anders 100 + 0,5 + 33,33');
select pg_temp.lik((select sum(p.net) from public.club_members m, public.bet_points(:'sesong', m.id) p
                    where m.club_id = :'klubb'), 0::numeric, 'to desimaler: summen er null');
reset role;
update public.seasons set rules = '{"version": 2, "bets": {"startingPoints": null}}' where id = :'sesong';
update public.club_members set is_organizer = false where id = :'bjorn';

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
