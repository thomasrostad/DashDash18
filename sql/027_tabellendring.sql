-- ===========================================================================
-- 027 – PLASSBYTTE I TABELLEN BARE ÉN GANG PER RUNDE OG TURNERING – KJØRT PÅ TEST 08.10.2026
-- ===========================================================================
-- Status: godkjent og kjørt på test 08.10.2026 (kontrollen 6 av 6). Ikke prod.
-- Krever 008 (activity) og 011 (samme mønster for de andre hendelsene).
--
-- Hvorfor: Hjem-feeden (fase 19) viser plassbytte i tabellen («Du klatret til
-- 3. plass i Jakkeracet», «Anders gikk forbi deg»). Appen regner tabellen før
-- og etter når arrangøren låser en runde eller avslutter kvelden, og logger
-- én linje per turnering med kind = 'table_changed' (TableChangeLogger i
-- appen). To telefoner kan logge det samme: to arrangører som låser samtidig,
-- «Lås runden» og «Avslutt kvelden» rett etter hverandre, eller et nytt
-- forsøk etter dårlig nett. Da får alle to like push og to like kort. Samme
-- problem som 011 løste for store scorer, ledelsen og «ny runde».
--
-- Hva fila gjør:
--   * Én unik delindeks: høyst én 'table_changed' per runde og turnering
--     (round_id, data->>'competition'). Appen tåler at innsettingen avvises
--     (23505 svelges av ActivityLog.logQuietly), som for 011.
--
-- Hva fila IKKE gjør, og hvorfor:
--   * Ingen ny kategori. Plassbyttet kommer av at en runde ble låst, og bruker
--     kategorien 'round' («Rundene» i «Hva blir push»). Den som har slått av
--     rundene, slipper også tabellen. check på activity.category,
--     push_club_categories()/push_player_categories() (010) og
--     ActivityCategory i appen står som før.
--   * activity.club_id blir ikke valgfri. Private turneringer og løse runder
--     har ingen klubb; der regner appen kortene selv fra rundene den allerede
--     henter (MyRounds, CompetitionBoard). push_queue.club_id er not null og
--     push_job_payload() bygger på klubben, så en linje uten klubb ville ha
--     stoppet innsettingen i activity (triggeren push_enqueue_activity).
--   * Ingen ny lesetilgang. Hjem leser activity med club_id in (klubbene dine),
--     og det dekker activity_select fra 008 (is_club_member) allerede.
--   * Ingen funksjoner, så ingen revoke/grant.
--
-- Før den kjøres: appflagget HomeFeedFeature.logsTableChanges står av, og
-- skal slås på først når denne fila er kjørt OG push-send med teksten for
-- 'table_changed' er deployet (ellers går pushen ut som «Ny hendelse i
-- klubben»). Mens flagget er av, finnes det ingen 'table_changed'-linjer, så
-- indeksen kan ikke feile på duplikater.
--
-- Hva som skjer om fila ikke kjøres: ingenting knekker. Plassbyttet kan da i
-- sjeldne tilfeller stå to ganger (og gi to push) når to telefoner låser
-- samme runde samtidig.
--
-- Mønsteret fra 001–026 følges: én transaksjon, idempotent, kontroll og
-- rullebakke nederst.
-- ===========================================================================

begin;

set local search_path = '';

create unique index if not exists activity_table_changed_once
  on public.activity (round_id, ((data ->> 'competition')))
  where kind = 'table_changed';

comment on index public.activity_table_changed_once is
  'Fase 19: høyst ett plassbytte (table_changed) per runde og turnering, så to telefoner ikke gir dobbel push.';

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Alle rader skal ha ok = true.
-- ===========================================================================
-- with i as (
--   select indexname, indexdef from pg_indexes
--   where schemaname = 'public' and tablename = 'activity'
-- )
-- select 1 as nr, 'Indeksen finnes og er unik' as sjekk,
--        exists (select 1 from i where indexname = 'activity_table_changed_once'
--                and indexdef like 'CREATE UNIQUE INDEX%') as ok
-- union all
-- select 2, 'Den gjelder bare table_changed, på runde og turnering',
--        exists (select 1 from i where indexname = 'activity_table_changed_once'
--                and indexdef like '%round_id%' and indexdef like '%competition%'
--                and indexdef like '%table_changed%')
-- union all
-- select 3, 'Indeksene fra 011 står',
--        (select count(*) = 4 from i where indexname in ('activity_lead_once_per_checkpoint',
--          'activity_big_score_once_per_hole', 'activity_round_started_once', 'activity_reminder_once_per_event'))
-- union all
-- select 4, 'Kategoriene er uendret (round finnes, ingen ny)',
--        (select pg_get_constraintdef(c.oid) like '%''round''%'
--                and pg_get_constraintdef(c.oid) not like '%''table%'
--         from pg_constraint c
--         where c.conrelid = 'public.activity'::regclass and c.contype = 'c'
--           and pg_get_constraintdef(c.oid) like '%category%')
-- union all
-- select 5, 'Push-køen fylles fortsatt fra activity',
--        exists (select 1 from pg_trigger where tgname = 'push_enqueue_activity'
--                and tgrelid = 'public.activity'::regclass)
-- union all
-- select 6, 'Ingen doble plassbytter',
--        not exists (select 1 from public.activity where kind = 'table_changed'
--                    group by round_id, data ->> 'competition' having count(*) > 1)
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test)
-- ===========================================================================
-- drop index if exists public.activity_table_changed_once;
