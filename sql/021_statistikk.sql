-- ===========================================================================
-- 021 – STATISTIKK: VALGFRI FØRING PER HULL (FASE 16) – FORSLAG, IKKE KJØRT
-- ===========================================================================
-- Status: FORSLAG til godkjenning (ROADMAP B5). Ikke kjørt mot Supabase, verken
-- test eller prod. Prøvd lokalt (lokal/021_prove.sql). Krever 001–017.
--
-- Hvorfor (docs/visjon-apen-app.md, fase 16): spilleren kan, hvis hen vil,
-- føre fairway, green i regulering, putter, bunker og straffeslag per hull.
-- Appen regner fairway-%, GIR-%, putter per runde og sand save av dette. Alt
-- annet i statistikken (snitt, rekorder, fordeling og WHS-indeks) regnes av
-- hole_scores og banen, som før. Ingenting avledet lagres (CLAUDE.md).
--
-- Hva fila gjør:
--   * Ny tabell hole_stats med samme nøkkel som hole_scores (runde, spiller,
--     hull). Hvert felt kan være tomt; en rad uten noe ført finnes ikke (appen
--     sletter raden når alt nullstilles).
--   * Fairway bare på par 4 og 5 (par fra round_holes, ellers banens hull).
--   * Lese: som hole_scores (can_read_round). Skrive: den som kan føre hullet
--     (can_score fra 017, kanFore), PLUSS spilleren selv mens runden pågår.
--     Det siste er et bevisst tillegg: i en bås med markør er det markøren
--     som fører slagene, men putter og fairway vet spilleren best selv. Det
--     gir ingen ny tilgang til hole_scores.
--   * Hvem som skrev (updated_by = auth.uid()) og når settes av serveren.
--
-- Ingen endring i hole_scores, save_hole, can_score eller andre tabeller.
-- Raden henger på round_players (on delete cascade), ikke på hole_scores, så
-- den kan lagres før slagene er sendt (utboksen) uten å feile. Statistikken
-- bruker bare hull som også har slag.
--
-- Om spilleren vil føre dette, er en innstilling på telefonen (av som
-- standard), ikke en kolonne. Se åpent spørsmål i rapporten.
--
-- Mønsteret fra 001–017 følges: én transaksjon, idempotent, `set search_path
-- = ''`, `revoke … from public, anon` ETTER hver create or replace, og
-- triggerfunksjoner tas fra authenticated også.
-- ===========================================================================

begin;


-- ===========================================================================
-- 1. TABELLEN
-- ===========================================================================
create table if not exists public.hole_stats (
  round_id             uuid not null,
  member_id            uuid not null,
  hole_index           smallint not null check (hole_index between 0 and 17),
  -- Utslaget på par 4 og 5: venstre, treff eller høyre for fairway.
  fairway              text check (fairway in ('left', 'hit', 'right')),
  green_in_regulation  boolean,
  putts                smallint check (putts between 0 and 9),
  -- Var i bunker på hullet (minst én gang).
  bunker               boolean,
  penalties            smallint check (penalties between 0 and 9),
  -- Settes av trigger: hvem (innloggingen) og når på serveren.
  updated_by           uuid references auth.users(id) on delete set null,
  updated_at           timestamptz not null default now(),
  primary key (round_id, member_id, hole_index),
  -- Bare deltakere kan ha statistikk. Går med runden og deltakeren.
  constraint hole_stats_player_fk foreign key (round_id, member_id)
    references public.round_players (round_id, member_id) on delete cascade,
  constraint hole_stats_not_empty check (
    fairway is not null or green_in_regulation is not null or putts is not null
    or bunker is not null or penalties is not null)
);
comment on table public.hole_stats is
  'Valgfri føring per hull (fase 16): fairway (par 4/5), green i regulering, putter, bunker og '
  'straffeslag. Samme nøkkel som hole_scores. Prosenter og snitt regnes i appen.';


-- ===========================================================================
-- 2. HJELPER OG VAKT
-- ===========================================================================
-- Kan jeg skrive statistikk for spilleren i runden? Den som kan føre hullet
-- (kanFore, can_score fra 017), eller spilleren selv mens runden pågår.
create or replace function public.can_write_hole_stats(p_round_id uuid, p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.can_score(p_round_id, p_member_id)
      or (exists (select 1 from public.rounds r where r.id = p_round_id and r.status = 'active')
          and public.owns_round_player(p_round_id, p_member_id));
$$;
revoke all on function public.can_write_hole_stats(uuid, uuid) from public, anon;
grant execute on function public.can_write_hole_stats(uuid, uuid) to authenticated;

-- Hullet finnes i runden, fairway bare på par 4 og 5, hvem og når settes av
-- serveren.
create or replace function public.hole_stats_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hole_count  smallint;
  v_first_hole  smallint;
  v_course      uuid;
  v_par         smallint;
begin
  select r.hole_count, r.first_hole, r.course_id into v_hole_count, v_first_hole, v_course
  from public.rounds r where r.id = new.round_id;

  if new.hole_index >= v_hole_count then
    raise exception 'Hull % finnes ikke i en runde på % hull', new.hole_index + 1, v_hole_count
      using errcode = '22023';
  end if;

  if new.fairway is not null then
    select coalesce(
             (select rh.par from public.round_holes rh
               where rh.round_id = new.round_id and rh.hole_index = new.hole_index),
             (select ch.par from public.course_holes ch
               where ch.course_id = v_course and ch.hole_number = new.hole_index + v_first_hole))
      into v_par;
    if v_par = 3 then
      raise exception 'Fairway føres bare på par 4 og 5' using errcode = '22023';
    end if;
  end if;

  new.updated_at := now();
  new.updated_by := auth.uid();   -- null fra SQL Editor
  return new;
end;
$$;
revoke all on function public.hole_stats_before_write() from public, anon, authenticated;

drop trigger if exists hole_stats_before_write on public.hole_stats;
create trigger hole_stats_before_write
  before insert or update on public.hole_stats
  for each row execute function public.hole_stats_before_write();


-- ===========================================================================
-- 3. RLS
-- ===========================================================================
alter table public.hole_stats enable row level security;

do $$
declare
  p record;
begin
  for p in select policyname from pg_policies where schemaname = 'public' and tablename = 'hole_stats' loop
    execute format('drop policy if exists %I on public.hole_stats', p.policyname);
  end loop;
end $$;

create policy hole_stats_select on public.hole_stats
  for select to authenticated using (public.can_read_round(round_id));
create policy hole_stats_insert on public.hole_stats
  for insert to authenticated with check (public.can_write_hole_stats(round_id, member_id));
create policy hole_stats_update on public.hole_stats
  for update to authenticated
  using (public.can_write_hole_stats(round_id, member_id))
  with check (public.can_write_hole_stats(round_id, member_id));
create policy hole_stats_delete on public.hole_stats
  for delete to authenticated using (public.can_write_hole_stats(round_id, member_id));


-- ===========================================================================
-- 4. RETTIGHETER
-- ===========================================================================
revoke all on table public.hole_stats from public, anon, authenticated;
grant select, insert, update, delete on table public.hole_stats to authenticated;

commit;


-- ===========================================================================
-- KONTROLL (kjør i SQL Editor etter fila, som én kjøring). Én rad per sjekk,
-- alle skal ha ok = true.
-- ===========================================================================
-- with f as (select p.proname,
--                   has_function_privilege('anon', p.oid, 'execute') as anon_kan,
--                   has_function_privilege('authenticated', p.oid, 'execute') as auth_kan
--            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--            where n.nspname = 'public' and p.proname in ('can_write_hole_stats', 'hole_stats_before_write'))
-- select 1 as nr, 'hole_stats finnes med RLS og fire policyer' as sjekk,
--        (select c.relrowsecurity from pg_class c where c.oid = 'public.hole_stats'::regclass)
--        and (select count(*) = 4 from pg_policies where schemaname = 'public' and tablename = 'hole_stats') as ok
-- union all
-- select 2, 'anon har ingen rettigheter på hole_stats',
--        not exists (select 1 from information_schema.role_table_grants
--                    where table_schema = 'public' and table_name = 'hole_stats' and grantee in ('anon', 'PUBLIC'))
-- union all
-- select 3, 'anon kan ikke kjøre de nye funksjonene', not exists (select 1 from f where anon_kan)
-- union all
-- select 4, 'authenticated kan kjøre hjelperen, ikke triggerfunksjonen',
--        (select bool_and(auth_kan = (proname = 'can_write_hole_stats')) and count(*) = 2 from f)
-- union all
-- select 5, 'Vakta på hole_stats finnes',
--        exists (select 1 from pg_trigger where not tgisinternal and tgname = 'hole_stats_before_write'
--                  and tgrelid = 'public.hole_stats'::regclass)
-- union all
-- select 6, 'Ingen fairway på par 3',
--        not exists (select 1 from public.hole_stats s join public.rounds r on r.id = s.round_id
--                    left join public.round_holes rh on rh.round_id = s.round_id and rh.hole_index = s.hole_index
--                    left join public.course_holes ch on ch.course_id = r.course_id
--                                                    and ch.hole_number = s.hole_index + r.first_hole
--                    where s.fairway is not null and coalesce(rh.par, ch.par) = 3)
-- union all
-- select 7, 'hole_scores har fortsatt sine fire policyer (urørt)',
--        (select count(*) = 4 from pg_policies where schemaname = 'public' and tablename = 'hole_scores')
-- order by nr;


-- ===========================================================================
-- RULLEBAKKE (bare test). Fjerner all føring av fairway, green og putter.
-- Slå av StatsFeature i appen først (den er av fra start).
-- ===========================================================================
-- begin;
-- drop table if exists public.hole_stats;
-- drop function if exists public.hole_stats_before_write();
-- drop function if exists public.can_write_hole_stats(uuid, uuid);
-- commit;
