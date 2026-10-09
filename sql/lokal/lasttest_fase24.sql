\set ON_ERROR_STOP on
\pset footer off
-- ===========================================================================
-- KUN LOKALT. ALDRI MOT SUPABASE (verken test eller prod).
-- ===========================================================================
-- Fase 24: måler RPC-ene som ble kjørt på test 09.10.2026 (036 tavla_data,
-- 037 mengde-RPC-ene, 038 delete_tournament) mot spørringene de erstatter,
-- på samme data som lasttest.sql (kjør den først, i samme database, med
-- 001–032 og 036–038). Samme spiller og målemetode (lasttest.maal, median av 7,
-- planlegging + kjøring, som innlogget med RLS).
-- ===========================================================================

select m.user_id as bruker, m.club_id as klubb
from public.club_members m
where m.club_id = md5('k3')::uuid and not m.is_organizer
  and m.user_id in (select user_id from public.club_members group by user_id having count(*) >= 2)
order by m.display_name limit 1 \gset
select (select array_agg(club_id)::text from public.club_members where user_id = :'bruker') as klubber,
       (select id from public.seasons where club_id = :'klubb') as sesong \gset

create temp table f24 (nr int, sporring text, median_ms numeric, rader bigint, plan text);
grant all on f24 to authenticated;
select lasttest.som(:'bruker');
set role authenticated;
insert into f24 select 1, m.* from lasttest.maal('036 tavla_data(sesong): hele Tavla i ett kall',
  format($q$select public.tavla_data(%L)$q$, :'sesong')) m;
insert into f24 select 2, m.* from lasttest.maal('037 known_profiles(): folk du kjenner',
  $q$select id, display_name from public.known_profiles()$q$) m;
insert into f24 select 3, m.* from lasttest.maal('037 my_loose_rounds(): dine løse runder (limit 40)',
  $q$select * from public.my_loose_rounds() order by started_at desc limit 40$q$) m;
insert into f24 select 4, m.* from lasttest.maal('037 my_competitions(): turneringslista',
  $q$select * from public.my_competitions() where kind <> 'game' order by created_at desc$q$) m;
insert into f24 select 5, m.* from lasttest.maal('037 my_activity(): Hjem siste 30 dager (limit 150)',
  format($q$select * from public.my_activity(%L::uuid[], now() - interval '30 days') order by created_at desc limit 150$q$, :'klubber')) m;
insert into f24 select 6, m.* from lasttest.maal('Før: profiles uten filter (RLS filtrerer)',
  $q$select id, display_name from public.profiles$q$) m;
insert into f24 select 7, m.* from lasttest.maal('Før: løse runder (RLS filtrerer, limit 40)',
  $q$select * from public.rounds where club_id is null and status <> 'draft' order by started_at desc limit 40$q$) m;
insert into f24 select 8, m.* from lasttest.maal('Før: turneringer (RLS filtrerer)',
  $q$select * from public.competitions where kind <> 'game' order by created_at desc$q$) m;
insert into f24 select 9, m.* from lasttest.maal('Før: aktivitet i klubbene (RLS, limit 150)',
  format($q$select * from public.activity where club_id = any(%L::uuid[]) and created_at >= now() - interval '30 days' order by created_at desc limit 150$q$, :'klubber')) m;
reset role;

\echo
\echo Fase 24-RPC-ene mot spørringene de erstatter (som spilleren, RLS på):
select nr, sporring, rader, median_ms as ms, plan from f24 order by nr;

-- 038: slette sesongen i klubb k3 (alle kvelder, runder og hullscorer), som arrangør. Rulles tilbake.
select m.user_id as arrangor from public.club_members m
 where m.club_id = md5('k3')::uuid and m.is_organizer and m.user_id is not null limit 1 \gset
select c.id as jakke, c.name as jakkenavn from public.competitions c where c.season_id = :'sesong' \gset
select count(*) as runder_for from public.rounds r join public.events e on e.id = r.event_id
 where e.season_id = :'sesong' \gset
begin;
select lasttest.som(:'arrangor');
set local role authenticated;
\timing on
select public.delete_tournament(:'jakke', :'jakkenavn') as slettet;
\timing off
rollback;
\echo 038: runder i sesongen før sletting (rullet tilbake):
select :'runder_for' as runder;
