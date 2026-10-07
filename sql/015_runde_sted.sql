-- ===========================================================================
-- 015 – SIMULATOR ELLER EKTE BANE PÅ RUNDEN (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning. Ikke kjørt noe sted.
-- Nummer: 015. Lages en annen 015 samtidig (fase 11, Banene / Sesong), gis
-- denne neste ledige nummer før den kjøres. Den avhenger ikke av andre filer
-- enn 001.
--
-- Hvorfor (fase 11, besluttet 07.10.2026): «Hvor spiller dere?» er et eget
-- valg på runden, Simulator eller Ekte bane. Reglene er de samme; på ekte bane
-- heter gruppene «flight» i stedet for «bås», og Trackman kan ikke dele ut
-- slagene. Skjemaet har ikke noe felt for dette i dag (events.venue er stedet
-- for kvelden, fritekst, og courses har ikke noe skille).
--
-- Hva: én kolonne, rounds.venue, 'simulator' eller 'course', standard
-- 'simulator'. Eksisterende runder blir 'simulator' (alt som er spilt til nå,
-- er spilt i simulatoren). Ingen nye funksjoner eller policyer: arrangøren
-- skriver raden med upsert som før, og tabellrettighetene fra 001 dekker den
-- nye kolonnen.
--
-- Appen etter kjøring: sett VenueFeature.isEnabled = true
-- (DashDash18/Features/Admin/Runde/RoundVenue.swift). Da hentes kolonnen med
-- rundene og sendes ved lagring. Før det sender appen den ikke, så fila kan
-- kjøres når som helst uten at noe brekker.
-- ===========================================================================

begin;

alter table public.rounds
  add column if not exists venue text not null default 'simulator';

do $$
begin
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.rounds'::regclass and conname = 'rounds_venue_check') then
    alter table public.rounds
      add constraint rounds_venue_check check (venue in ('simulator', 'course'));
  end if;
end $$;

comment on column public.rounds.venue is
  'Hvor runden spilles: simulator (grupper = båser) eller course (ekte bane, grupper = flighter).';

commit;


-- ===========================================================================
-- KONTROLL. Kjør i SQL Editor etter fila. Én rad per sjekk, alle skal ha ok = true.
-- ===========================================================================
-- select 1 as nr, 'rounds.venue finnes: text, not null, standard simulator' as sjekk,
--        exists (select 1 from information_schema.columns
--                where table_schema = 'public' and table_name = 'rounds' and column_name = 'venue'
--                  and data_type = 'text' and is_nullable = 'NO'
--                  and column_default like '''simulator''%') as ok
-- union all
-- select 2, 'Sjekken tillater bare simulator og course',
--        exists (select 1 from pg_constraint
--                where conrelid = 'public.rounds'::regclass and conname = 'rounds_venue_check'
--                  and pg_get_constraintdef(oid) like '%simulator%' and pg_get_constraintdef(oid) like '%course%')
-- union all
-- select 3, 'Alle runder har gyldig sted',
--        not exists (select 1 from public.rounds where venue not in ('simulator', 'course'))
-- union all
-- select 4, 'authenticated kan lese og skrive kolonnen',
--        has_column_privilege('authenticated', 'public.rounds', 'venue', 'SELECT')
--        and has_column_privilege('authenticated', 'public.rounds', 'venue', 'INSERT')
--        and has_column_privilege('authenticated', 'public.rounds', 'venue', 'UPDATE')
-- union all
-- select 5, 'anon kan ikke lese kolonnen',
--        not has_column_privilege('anon', 'public.rounds', 'venue', 'SELECT')
-- union all
-- select 6, 'RLS er fortsatt på for rounds',
--        (select relrowsecurity from pg_class where oid = 'public.rounds'::regclass)
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Slå av VenueFeature i appen FØRST, ellers spør appen
-- etter en kolonne som ikke finnes. Valget som er lagret på rundene forsvinner.
-- ===========================================================================
-- begin;
-- alter table public.rounds drop constraint if exists rounds_venue_check;
-- alter table public.rounds drop column if exists venue;
-- commit;
