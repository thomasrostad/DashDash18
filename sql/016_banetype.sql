-- ===========================================================================
-- 016 – BANETYPE: SIMULATORBANE ELLER EKTE BANE (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning. Ikke kjørt noe sted.
-- Nummer: 016 fordi 015 kan bli brukt av runde-oppsettet i samme runde (fase 11).
--
-- Hvorfor (fase 11, «Banene – enklere»): banelista skal skille simulatorbaner
-- og ekte baner, og «Ny bane» skal spørre om typen. Skjemaet har ingen
-- banetype (sql/001: courses har bare external_name, navnet i simulatoren).
-- Typen kan ikke avledes sikkert: mange simulatorbaner har samme navn som hos
-- oss og står uten external_name.
--
-- Endring: én kolonne, courses.kind, 'simulator' eller 'course'.
-- Standard 'simulator', så alle baner som finnes (og alle som lagres av en
-- app uten typevalg, også save_course i 002) blir simulatorbaner, som i dag.
-- Ingen ny policy: courses_update (001) lar arrangøren skrive kolonnen, og
-- tabellrettighetene fra 001 gjelder hele tabellen.
--
-- Appen etter at fila er kjørt: sett CourseKindFeature.isEnabled = true
-- (DashDash18/Features/Admin/Baner/CourseKind.swift). Da leses kind i
-- banelista, typevalget vises i «Ny bane», og typen skrives med en update
-- rett etter save_course (raden leses tilbake). Med flagget av rører appen
-- ikke kolonnen, så appen tåler at fila ikke er kjørt.
-- ===========================================================================

begin;

alter table public.courses
  add column if not exists kind text not null default 'simulator'
  constraint courses_kind_check check (kind in ('simulator', 'course'));

comment on column public.courses.kind is
  'simulator = bane i simulatoren (Trackman), course = ekte bane ute. Styrer bare visning og ordbruk (bås/flight), ikke reglene.';

commit;


-- ===========================================================================
-- KONTROLL (kjør etterpå i SQL Editor). Én rad per sjekk, alle skal ha ok = true.
-- ===========================================================================
-- select 1 as nr, 'Kolonnen kind finnes, not null, standard simulator' as sjekk,
--        exists (select 1 from information_schema.columns
--                where table_schema = 'public' and table_name = 'courses'
--                  and column_name = 'kind' and is_nullable = 'NO'
--                  and column_default like '''simulator''%') as ok
-- union all
-- select 2, 'Sjekken tillater bare simulator og course',
--        exists (select 1 from pg_constraint
--                where conname = 'courses_kind_check'
--                  and conrelid = 'public.courses'::regclass)
-- union all
-- select 3, 'Alle baner som fantes, er simulatorbaner',
--        not exists (select 1 from public.courses where kind <> 'simulator')
-- union all
-- select 4, 'RLS står fortsatt på courses',
--        (select relrowsecurity from pg_class where oid = 'public.courses'::regclass)
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner kolonnen og typene som er lagret i den.
-- Slå av CourseKindFeature i appen først.
-- ===========================================================================
-- begin;
-- alter table public.courses drop constraint if exists courses_kind_check;
-- alter table public.courses drop column if exists kind;
-- commit;
