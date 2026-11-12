-- 078_tippekonge_en_gang.sql — tippekongen kåres én gang per kveld.
-- Thomas 12.11.2026: «hvordan velges og vises vinneren av tippekupongen?», og «Ja» til å få den
-- ut på Hjem, i varsler og som push.
--
-- Hvorfor: Hjem, varslene og push-send kjenner allerede 'tips_king' (008, 046, push-send), men
-- ingen skrev linja, så tippekongen ble bare vist inne i kupongen. Nå skriver appen den når
-- arrangøren låser den siste runden på kvelden (TipsKingLogger, samme sted som TableChangeLogger).
-- To telefoner kan skrive det samme: to arrangører som låser samtidig, «Lås runden» og «Avslutt
-- kvelden» rett etter hverandre, eller et nytt forsøk etter dårlig nett. Samme problem som 011
-- og 027 løste.
--
-- Hva fila gjør:
--   * Én unik delindeks: høyst én 'tips_king' per kveld (event_id). Appen tåler at innsettingen
--     avvises (23505 svelges av ActivityLog.logQuietly), som for 011 og 027.
--
-- Hva fila IKKE gjør:
--   * Ingen ny kategori: 'tips' finnes (008), og push-gruppene har ('tips', 'tips_king') (046).
--   * Ingen ny tilgang: activity_insert (008) lar medlemmer skrive i klubben sin.
--   * Ingen funksjoner, så ingen revoke/grant.
--
-- Før den kjøres: det finnes ingen 'tips_king'-linjer (sjekket på test 12.11.2026), så indeksen
-- kan ikke feile på duplikater.
--
-- Om fila ikke kjøres: ingenting knekker. Tippekongen kan da i sjeldne tilfeller stå to ganger
-- (og gi to push) når to telefoner låser samtidig.
--
-- Bare legg til (docs/utgivelser.md punkt 4). Krever 008. Idempotent. Kontroll og rullebakk nederst.
begin;
set local search_path = '';
create unique index if not exists activity_tips_king_once
  on public.activity (event_id)
  where kind = 'tips_king';
comment on index public.activity_tips_king_once is
  'Tippekongen (tips_king) høyst én gang per kveld, så to telefoner ikke gir dobbel push.';
commit;


-- ===========================================================================
-- KONTROLL (kjør etter fila, som én kjøring). Alle rader skal ha ok = true.
-- ===========================================================================
-- with i as (
--   select indexname, indexdef from pg_indexes
--   where schemaname = 'public' and tablename = 'activity'
-- )
-- select 1 as nr, 'Indeksen finnes og er unik' as sjekk,
--        exists (select 1 from i where indexname = 'activity_tips_king_once'
--                and indexdef like 'CREATE UNIQUE INDEX%') as ok
-- union all
-- select 2, 'Den gjelder bare tips_king, på kvelden',
--        exists (select 1 from i where indexname = 'activity_tips_king_once'
--                and indexdef like '%event_id%' and indexdef like '%tips_king%')
-- union all
-- select 3, 'Push-køen fylles fortsatt fra activity',
--        exists (select 1 from pg_trigger where tgname = 'push_enqueue_activity'
--                and tgrelid = 'public.activity'::regclass)
-- union all
-- select 4, 'Ingen doble tippekonger',
--        not exists (select 1 from public.activity where kind = 'tips_king'
--                    group by event_id having count(*) > 1)
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE
-- ===========================================================================
-- drop index if exists public.activity_tips_king_once;
