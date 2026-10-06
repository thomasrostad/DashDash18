-- ===========================================================================
-- 004 – SESONG (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Forslag fra fase 3 «Sesong og regler». Ingenting her er nødvendig for at
-- admin-skjermen skal virke: policyene i 001 lar arrangøren lese, lage, endre
-- og slette sesonger. Fila tetter to hull:
--
--   1. activate_season(): «aktiver denne, avslutt den aktive» i ÉN transaksjon.
--      I dag gjør appen to UPDATE etter hverandre. Feiler den andre (nett,
--      RLS), står klubben uten aktiv sesong. CLAUDE.md: handlinger som
--      skriver flere rader, skal være én RPC.
--   2. seasons_delete: bare planlagte sesonger kan slettes, også via API.
--      I dag sjekker bare appen dette.
--
-- Status: til godkjenning. Kjør først på TEST, med kontrollspørringene nederst.
-- Når den er kjørt, bytter SesongAdminModel.activate til RPC-en (én linje).
-- ===========================================================================

begin;

-- --- activate_season ------------------------------------------------------
-- SECURITY INVOKER: kjører som den innloggede, så RLS (seasons_update, bare
-- arrangør) gjelder som før. Avslutter klubbens aktive sesong (om det er en
-- annen) og aktiverer denne. Returnerer den aktiverte raden.
create or replace function public.activate_season(p_season_id uuid)
returns public.seasons
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_club   uuid;
  v_row    public.seasons;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if not found then
    raise exception 'Fant ikke sesongen' using errcode = 'P0002';
  end if;

  update public.seasons s
     set status = 'finished'
   where s.club_id = v_club and s.status = 'active' and s.id <> p_season_id;

  update public.seasons s
     set status = 'active'
   where s.id = p_season_id
  returning s.* into v_row;

  -- Ingen rad: RLS stoppet skrivingen (ikke arrangør).
  if v_row.id is null then
    raise exception 'Bare arrangøren kan aktivere en sesong' using errcode = '42501';
  end if;
  return v_row;
end;
$$;
revoke all on function public.activate_season(uuid) from public, anon;
grant execute on function public.activate_season(uuid) to authenticated;


-- --- seasons_delete: bare planlagte ---------------------------------------
drop policy if exists seasons_delete on public.seasons;
create policy seasons_delete on public.seasons
  for delete to authenticated
  using (public.is_club_organizer(club_id) and status = 'planned');

commit;


-- ===========================================================================
-- KONTROLL (kjør én blokk om gangen etter at fila er kjørt)
-- ===========================================================================
-- 1. anon kan ikke kjøre funksjonen. Forventet: false.
-- select has_function_privilege('anon', 'public.activate_season(uuid)', 'execute') as anon_kan;
--
-- 2. Policyen for sletting. Forventet: én rad, med «status = 'planned'» i qual.
-- select policyname, qual from pg_policies
--  where schemaname = 'public' and tablename = 'seasons' and cmd = 'DELETE';
--
-- 3. I appen (test), som arrangør: aktiver en planlagt sesong mens en annen er
--    aktiv. Forventet: den gamle blir finished, den nye active, ingen 23505.
--    Som spiller: forventet 42501.


-- ===========================================================================
-- RULLEBAKKE (bare på test)
-- ===========================================================================
-- begin;
-- drop function if exists public.activate_season(uuid);
-- drop policy if exists seasons_delete on public.seasons;
-- create policy seasons_delete on public.seasons
--   for delete to authenticated using (public.is_club_organizer(club_id));
-- commit;
