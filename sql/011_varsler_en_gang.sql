-- ===========================================================================
-- 011 – VARSLER UNDER RUNDEN BARE ÉN GANG (FORSLAG)
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5, fase 8). IKKE KJØRT mot
-- Supabase. Kjøres først på TEST etter ja fra brukeren, så kontrollen
-- nederst. Prod først etter ny godkjenning.
--
-- Krever 008 (activity) og 010 (push_queue med triggeren push_enqueue_activity).
-- Tar med indeksen fra 009 (samme navn, «if not exists»), så 009 trenger ikke
-- kjøres for seg. Er 009 kjørt fra før, er den delen et nei-op.
--
-- Hvorfor: appen logger store scorer, ledelsen og «ny runde» fra telefonen der
-- det skjer. Hver linje blir én push (010). Samme hendelse kan komme fra to
-- telefoner samtidig:
--   * to båser fullfører samme sjekkpunkt (f.eks. hull 9) samtidig, og begge
--     ser at alle er i mål → to «ledelsen etter hull 9» (009),
--   * markøren og arrangøren fører samme spillers hull samtidig, eller et hull
--     i kø (utboksen) sendes mens den andre telefonen lagrer → to eagler,
--   * «Start runden» trykkes på to telefoner → to «Ny runde».
-- Appen stopper gjentak fra SAMME telefon selv (ActivityOnceLog i
-- DashDash18/Features/Runde/RundeActivity.swift, samme nøkler som her). Mellom
-- telefoner kan bare databasen avgjøre. En unik indeks lar den første gå inn;
-- den andre får 23505, og appen (ActivityLog.logQuietly) svelger feilen. Den
-- avviste raden kommer aldri i push_queue (after insert-triggeren kjører ikke).
--
-- Gjelder bare disse tre typene i en runde (round_id satt). Alt annet i
-- aktiviteten påvirkes ikke. Ingen endring i RLS: 008 lar alle medlemmer
-- skrive score, lead og round, og triggeren activity_before_insert gjelder bare
-- announcement, nudge, reminder og mottakerlister.
--
-- FØR KJØRING: finnes det duplikater fra før, feiler create unique index, og
-- hele fila rulles tilbake. Sjekk med spørringen under («Duplikater fra før»).
-- Gir den rader, si fra: å slette dem er en dataendring som må godkjennes for
-- seg.
--
-- Én transaksjon. Idempotent.
-- ===========================================================================
begin;

-- Ledelsen: én linje per runde og sjekkpunkt (samme som 009).
create unique index if not exists activity_lead_once_per_checkpoint
  on public.activity (round_id, ((data ->> 'after_hole')))
  where kind = 'lead_changed' and round_id is not null and data ? 'after_hole';

-- Store scorer: én linje per runde, spiller og hull (rundens 0-baserte hull).
create unique index if not exists activity_big_score_once_per_hole
  on public.activity (round_id, ((data ->> 'member')), ((data ->> 'hole_index')))
  where kind = 'big_score' and round_id is not null and data ? 'member' and data ? 'hole_index';

-- Ny runde: én linje per runde.
create unique index if not exists activity_round_started_once
  on public.activity (round_id)
  where kind = 'round_started' and round_id is not null;

commit;


-- ===========================================================================
-- DUPLIKATER FRA FØR (kjør FØR fila). Forventet: 0 rader.
-- ===========================================================================
-- select kind, round_id, data ->> 'after_hole' as after_hole,
--        data ->> 'member' as member, data ->> 'hole_index' as hole_index, count(*)
-- from public.activity
-- where round_id is not null and kind in ('lead_changed', 'big_score', 'round_started')
-- group by 1, 2, 3, 4, 5
-- having count(*) > 1;


-- ===========================================================================
-- KONTROLL (kjør etterpå i SQL Editor). Én rad per sjekk, alle skal ha ok = true.
-- ===========================================================================
-- with i as (
--   select indexname, indexdef from pg_indexes
--   where schemaname = 'public' and tablename = 'activity'
-- )
-- select 1 as nr, 'Ledelsen én gang per sjekkpunkt' as sjekk,
--        exists (select 1 from i where indexname = 'activity_lead_once_per_checkpoint'
--                                  and indexdef ilike 'create unique index%') as ok
-- union all
-- select 2, 'Stor score én gang per spiller og hull',
--        exists (select 1 from i where indexname = 'activity_big_score_once_per_hole'
--                                  and indexdef ilike 'create unique index%')
-- union all
-- select 3, 'Ny runde én gang per runde',
--        exists (select 1 from i where indexname = 'activity_round_started_once'
--                                  and indexdef ilike 'create unique index%')
-- union all
-- select 4, 'Påminnelsen fra 010 står fortsatt',
--        exists (select 1 from i where indexname = 'activity_reminder_once_per_event')
-- union all
-- select 5, 'Køtriggeren fra 010 står fortsatt',
--        exists (select 1 from pg_trigger where tgname = 'push_enqueue_activity'
--                                           and tgrelid = 'public.activity'::regclass)
-- order by nr;
--
-- Prøve på test (valgfritt, i appen): før samme spillers hull på to telefoner
-- samtidig med en eagle. Forventet: én big_score-linje og én jobb i push_queue.


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner bare indeksene, ingen data.
-- ===========================================================================
-- begin;
-- drop index if exists public.activity_round_started_once;
-- drop index if exists public.activity_big_score_once_per_hole;
-- drop index if exists public.activity_lead_once_per_checkpoint;
-- commit;
