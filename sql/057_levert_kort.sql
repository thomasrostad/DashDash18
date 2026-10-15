-- 057_levert_kort.sql — låst kort etter levering (regelvern, inspirert av Golfify).
-- IKKE KJØRT. Venter på godkjenning fra Thomas. Kjøres på test først.
--
-- Når markøren (eller spilleren selv, uten markør) leverer kortet for båsen, kan bare arrangøren
-- føre på det, og bare arrangøren kan åpne det igjen. Appen viser «Lever kortet» når regelsettet har
-- `play.lockSubmittedCards` (standard av, så Golfgutu er som før) og denne fila er kjørt.
--
-- Hva som endres:
-- * round_players får card_submitted_at og card_submitted_by (auth.uid() til den som leverte).
-- * can_score (fra 044) får én sjekk til: når spillerens kort er levert, kan bare arrangøren føre.
--   can_score styrer hole_scores-policyene, save_hole, spillene (020) og markørkonflikten (055),
--   så serveren avviser en føring på et levert kort uansett hvilken app eller kø den kommer fra.
--   Statistikken (can_write_hole_stats, 021) lar spilleren selv føre sin egen statistikk som før.
-- * submit_card(runde, spillere): leverer kortene. Den som leverer må kunne føre for hver spiller
--   (can_score), runden må gå, og hvert kort må ha score på alle hullene i runden.
-- * reopen_card(runde, spillere): åpner kortene igjen. Bare arrangøren (is_round_organizer).
-- * Sanntid: en endring av levert-feltet sendes på rundens kanal (broadcast_round_change fra 040),
--   så den andre telefonen i båsen og arrangøren ser det med en gang.
--
-- Ikke endret: rundens status, «Avslutt kvelden», låsing og avkorting. En låst runde er låst for
-- alle utenom arrangøren som før.
--
-- Krever 040 og 044. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- Kolonnene ------------------------------------------------------------------
alter table public.round_players add column if not exists card_submitted_at timestamptz;
alter table public.round_players add column if not exists card_submitted_by uuid;
comment on column public.round_players.card_submitted_at is
  'Kortet er levert (057). Da kan bare arrangøren føre for spilleren (can_score), til reopen_card.';
comment on column public.round_players.card_submitted_by is
  'auth.uid() til den som leverte kortet (057).';

-- --- can_score: levert kort --------------------------------------------------------
-- Fra 044. Ny: sjekken på card_submitted_at etter arrangørsjekken og statussjekken.
create or replace function public.can_score(p_round_id uuid, p_member_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_found   boolean;
  v_club    uuid;
  v_status  text;
  v_owner   uuid;
  v_bay     smallint;
  v_marker  uuid;
  v_done    timestamptz;
begin
  if auth.uid() is null then
    return false;
  end if;

  select true, r.club_id, r.status, r.owner_id into v_found, v_club, v_status, v_owner
  from public.rounds r where r.id = p_round_id;
  if v_found is null then
    return false;
  end if;

  if v_club is not null then
    if private.has_club_right(v_club, 'rounds') then
      return true;
    end if;
  elsif v_owner = auth.uid() then
    return true;
  end if;

  -- 032: arrangøren i staben har arrangørens rett.
  if public.is_round_staff(p_round_id, 'organizer') then
    return true;
  end if;

  if v_status <> 'active' then
    return false;
  end if;

  select rp.bay_no, rp.card_submitted_at into v_bay, v_done
  from public.round_players rp
  where rp.round_id = p_round_id and rp.member_id = p_member_id;

  -- 057: levert kort. Bare arrangøren (over) fører på det.
  if v_done is not null then
    return false;
  end if;

  if v_bay is not null then
    select rp.member_id into v_marker
    from public.round_players rp
    where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker;
  end if;

  if v_marker is not null then
    return public.owns_round_player(p_round_id, v_marker)
        or public.is_group_scorer(p_round_id, v_bay);
  end if;

  return public.owns_round_player(p_round_id, p_member_id)
      or public.is_group_scorer(p_round_id, v_bay);
end;
$$;
revoke all on function public.can_score(uuid, uuid) from public, anon;
grant execute on function public.can_score(uuid, uuid) to authenticated, service_role;

-- --- RPC: lever kortet ------------------------------------------------------------
create or replace function public.submit_card(p_round_id uuid, p_member_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round  public.rounds;
  v_member uuid;
  v_holes  integer;
  v_count  integer;
begin
  if auth.uid() is null then
    raise exception 'Ikke innlogget' using errcode = '42501';
  end if;
  select * into v_round from public.rounds where id = p_round_id;
  if not found then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;
  if v_round.status <> 'active' then
    raise exception 'Runden er ikke i gang' using errcode = '55000';
  end if;
  if p_member_ids is null or cardinality(p_member_ids) = 0 then
    raise exception 'Ingen spillere å levere for' using errcode = '22023';
  end if;
  v_holes := case when v_round.hole_count = 9 then 9 else 18 end;

  foreach v_member in array p_member_ids loop
    if not exists (select 1 from public.round_players rp
                   where rp.round_id = p_round_id and rp.member_id = v_member) then
      raise exception 'Spilleren er ikke med i runden' using errcode = 'P0002';
    end if;
    -- Levert fra før: står (ingen ny tid).
    if exists (select 1 from public.round_players rp
               where rp.round_id = p_round_id and rp.member_id = v_member and rp.card_submitted_at is not null) then
      continue;
    end if;
    if not public.can_score(p_round_id, v_member) then
      raise exception 'Du kan ikke levere kortet for denne spilleren' using errcode = '42501';
    end if;
    select count(distinct s.hole_index) into v_count
    from public.hole_scores s
    where s.round_id = p_round_id and s.member_id = v_member and s.hole_index between 0 and v_holes - 1;
    if v_count < v_holes then
      raise exception 'Kortet er ikke ferdig: % av % hull er ført', v_count, v_holes using errcode = '22023';
    end if;
  end loop;

  update public.round_players rp
     set card_submitted_at = now(), card_submitted_by = auth.uid()
   where rp.round_id = p_round_id and rp.member_id = any (p_member_ids) and rp.card_submitted_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.submit_card(uuid, uuid[]) from public, anon;
grant execute on function public.submit_card(uuid, uuid[]) to authenticated;

-- --- RPC: åpne kortet igjen (arrangøren) -----------------------------------------------
create or replace function public.reopen_card(p_round_id uuid, p_member_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if auth.uid() is null or not public.is_round_organizer(p_round_id) then
    raise exception 'Bare arrangøren kan åpne kortet igjen' using errcode = '42501';
  end if;
  update public.round_players rp
     set card_submitted_at = null, card_submitted_by = null
   where rp.round_id = p_round_id and rp.member_id = any (coalesce(p_member_ids, '{}'))
     and rp.card_submitted_at is not null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.reopen_card(uuid, uuid[]) from public, anon;
grant execute on function public.reopen_card(uuid, uuid[]) to authenticated;

-- --- Sanntid: levert og åpnet går ut på rundens kanal (040) ------------------------------
drop trigger if exists round_players_card_broadcast on public.round_players;
create trigger round_players_card_broadcast
  after update of card_submitted_at on public.round_players
  for each row
  when (old.card_submitted_at is distinct from new.card_submitted_at)
  execute function public.broadcast_round_change();

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select column_name from information_schema.columns
--  where table_schema = 'public' and table_name = 'round_players'
--    and column_name in ('card_submitted_at', 'card_submitted_by');                     -- 2 rader
-- select count(*) from public.round_players where card_submitted_at is not null;        -- 0
-- select proname from pg_proc where proname in ('submit_card', 'reopen_card');          -- 2 rader
-- select has_function_privilege('anon', 'public.submit_card(uuid, uuid[])', 'execute'); -- false
-- select has_function_privilege('anon', 'public.reopen_card(uuid, uuid[])', 'execute'); -- false
-- select tgname from pg_trigger where tgname = 'round_players_card_broadcast';           -- 1 rad
-- select prosrc like '%card_submitted_at%' from pg_proc where proname = 'can_score';      -- true

-- --- Rullebakk -------------------------------------------------------------------
-- begin;
-- drop trigger if exists round_players_card_broadcast on public.round_players;
-- drop function if exists public.submit_card(uuid, uuid[]);
-- drop function if exists public.reopen_card(uuid, uuid[]);
-- -- can_score: kjør blokken «Fra 032. Bare arrangørsjekken er endret» fra 044_roller.sql på nytt.
-- alter table public.round_players drop column if exists card_submitted_by;
-- alter table public.round_players drop column if exists card_submitted_at;
-- commit;
