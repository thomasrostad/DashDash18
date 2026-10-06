-- ===========================================================================
-- 009 – Ledelsesvarsel bare én gang per sjekkpunkt (FORSLAG)
-- ===========================================================================
-- IKKE KJØRT. Til godkjenning. Kjøres først mot test.
--
-- Hvorfor: når to båser fullfører samme sjekkpunkt (f.eks. hull 9) samtidig,
-- kan begge telefonene logge «ledelsen etter hull 9». Det gir to like linjer og
-- to push. En unik indeks lar bare den første gå inn; den andre får 23505, og
-- appen (ActivityLog.logQuietly) svelger feilen.
--
-- Gjelder bare kind = 'lead_changed' med runde og after_hole. Andre hendelser
-- påvirkes ikke.
-- ===========================================================================
begin;

create unique index if not exists activity_lead_once_per_checkpoint
  on public.activity (round_id, ((data ->> 'after_hole')))
  where kind = 'lead_changed' and round_id is not null and data ? 'after_hole';

commit;

-- KONTROLL (kjør etterpå). Forventet: 1 rad.
-- select indexname from pg_indexes
--  where schemaname = 'public' and indexname = 'activity_lead_once_per_checkpoint';
--
-- RULLEBAKKE (bare test):
-- drop index if exists public.activity_lead_once_per_checkpoint;
