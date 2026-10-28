-- 074_lagkamerat_forer.sql — lagkamerater fører for hverandre også når hver spiller sin egen ball.
-- Thomas 29.10.2026: «alle på laget sitt kan føre for hverandre. Er det 1v1, fører man det man selv slår.»
--
-- 071 ga alle på laget rett til lagets kort når laget spiller én ball (foursome, greensome, chapman,
-- scramble-2, scramble-4). Nå gjelder det også lagformene der hver spiller sin egen ball og har eget
-- kort: fourball, fourball-4 og sammenlagt-lag (CompetitionForm med teamSize > 1 og card: .perPlayer).
-- Former med én spiller per lag (stableford, slagspill, match, skins, Ryder Cup-singler …) er som før:
-- markøren, eller spilleren selv.
--
-- Regelsettet har valget play.teammatesScore («Lagkamerater fører for hverandre», standard på). Som
-- for levert kort (057) leser ikke databasen regelsettet: serveren gir lagkameraten retten, og appen
-- viser lagkameratens rad bare når valget er på. Med valget av kan en lagkamerat i teorien føre
-- gjennom API-et; det er samme lag, og markørkonflikten (055) viser det om to fører ulikt.
--
-- Hva som endres: can_score (fra 071), formlisten i lag-grenen. Ellers som 071.
-- Bare legg til (docs/utgivelser.md punkt 4): samme signatur, samme rettigheter, ingen svar blir
-- false der det var true før. Eldre apper får serverregelen, men viser ikke raden som redigerbar.
--
-- Krever 071. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- can_score: lagkameraten fører for laget ---------------------------------------
-- Fra 071. Ny: formlisten i 071-grenen har fourball, fourball-4 og sammenlagt-lag.
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
  v_format  text;
  v_bay     smallint;
  v_team    smallint;
  v_marker  uuid;
  v_done    timestamptz;
begin
  if auth.uid() is null then
    return false;
  end if;

  select true, r.club_id, r.status, r.owner_id, r.format into v_found, v_club, v_status, v_owner, v_format
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

  select rp.bay_no, rp.team_no, rp.card_submitted_at into v_bay, v_team, v_done
  from public.round_players rp
  where rp.round_id = p_round_id and rp.member_id = p_member_id;

  -- 057: levert kort. Bare arrangøren (over) fører på det.
  if v_done is not null then
    return false;
  end if;

  -- 071: ett kort per lag. Alle på laget fører lagets kort, også når båsen har markør.
  -- 074: også lagformene der hver spiller sin egen ball (fourball, fourball-4, sammenlagt-lag):
  -- lagkameratene fører for hverandre. Appen viser raden bare når play.teammatesScore er på.
  if v_format in ('foursome', 'greensome', 'chapman', 'scramble-2', 'scramble-4',
                  'fourball', 'fourball-4', 'sammenlagt-lag')
     and coalesce(v_team, 0) <> 0
     and exists (select 1 from public.round_players rp
                 where rp.round_id = p_round_id and rp.team_no = v_team
                   and public.owns_round_player(p_round_id, rp.member_id)) then
    return true;
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

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select prosrc like '%card_submitted_at%' from pg_proc where proname = 'can_score';      -- true (057 står)
-- select prosrc like '%scramble-4%' from pg_proc where proname = 'can_score';             -- true (071 står)
-- select prosrc like '%sammenlagt-lag%' from pg_proc where proname = 'can_score';         -- true (074)
-- select has_function_privilege('anon', 'public.can_score(uuid, uuid)', 'execute');       -- false
-- select has_function_privilege('authenticated', 'public.can_score(uuid, uuid)', 'execute'); -- true
-- Lagkamerat (som den innloggede lagkameraten, i en aktiv fourball-runde med markør i båsen):
-- select public.can_score('<runde>', '<lagkamerat på samme lag>');                         -- true
-- select public.can_score('<runde>', '<spiller på det andre laget i samme bås>');          -- false
-- --- Rullebakk -------------------------------------------------------------------
-- can_score: kjør blokken «can_score: lagkameraten fører lagets kort» fra 071_lag_forer.sql på nytt
-- (create or replace function public.can_score … til og med grant execute).
