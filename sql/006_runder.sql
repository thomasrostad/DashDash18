-- ===========================================================================
-- 006 – RUNDER: START I ÉN TRANSAKSJON (FORSLAG, IKKE KJØRT)
-- ===========================================================================
-- Status: FORSLAG til godkjenning (fase 4). Ikke kjørt noe sted.
--
-- Hvorfor: Policyene og RPC-ene i 001 gir arrangøren det oppsettet trenger
-- (rounds: skriv arrangør; set_round_setup og delete_round). Ingen tillatelse
-- mangler. Men «Start runden» er i dag tre kall fra appen
-- (RundeAdminModel.start):
--   1. upsert av raden i rounds (status draft),
--   2. set_round_setup med spillehandicap (beslutning: lagres ved start),
--   3. update rounds set status = 'active'.
-- Feiler 3 (typisk 23505: en annen runde går), står runden igjen som kladd
-- med playing_handicap fylt ut. Det er ufarlig – kladden regnes på nytt ved
-- neste start – men to kall er ikke én transaksjon, og troppens handicap kan
-- i teorien endres mellom 2 og 3 (triggeren rounds_after_update fryser
-- indeks og gruppe ved 3, mens spillehandicapet ble regnet ved 2).
--
-- start_round gjør 2 og 3 i én transaksjon: oppsettet skrives, så settes
-- status. Går en annen runde, ruller alt tilbake med 23505 (appen viser
-- «En runde går allerede»).
--
-- Når denne er kjørt, bytter appen kall 2 og 3 med ett kall til start_round.

begin;

create or replace function public.start_round(
  p_round_id  uuid,
  p_players   jsonb,
  p_matches   jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds%rowtype;
  v_setup  jsonb;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if not public.is_club_organizer(v_round.club_id) then
    raise exception 'Bare en arrangør kan starte runden' using errcode = '42501';
  end if;
  if v_round.status <> 'draft' then
    raise exception 'Bare en kladd kan startes' using errcode = '55000';
  end if;

  -- Samme sjekker og skriving som før (deltakere, båser, lag, matcher).
  v_setup := public.set_round_setup(p_round_id, p_players, p_matches);

  -- Den unike indeksen rounds_one_active_per_club gir 23505 hvis en annen
  -- runde går. Da ruller også oppsettet over tilbake.
  update public.rounds set status = 'active' where id = p_round_id;

  return v_setup || jsonb_build_object('status', 'active');
end;
$$;
revoke all on function public.start_round(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.start_round(uuid, jsonb, jsonb) to authenticated;

commit;

-- --- Kontroll (kjør etter, én om gangen) -----------------------------------
-- 1. anon kan ikke kjøre funksjonen (forventet: false).
-- select has_function_privilege('anon', 'public.start_round(uuid, jsonb, jsonb)', 'execute') as anon_kan;
-- 2. authenticated kan (forventet: true).
-- select has_function_privilege('authenticated', 'public.start_round(uuid, jsonb, jsonb)', 'execute') as innlogget_kan;

-- --- Observasjon, ingen endring foreslått ------------------------------------
-- rounds_before_write stopper låst → kladd, men ikke låst → pågår. Appen
-- tilbyr ikke det, men en arrangør kan gjøre det via API-et. Ønskes det
-- stoppet, kan sjekken utvides til `old.status = 'locked' and new.status <> 'locked'`.

-- --- Rullebakke ---------------------------------------------------------------
-- drop function if exists public.start_round(uuid, jsonb, jsonb);
