-- 071_lag_forer.sql — alle på laget fører lagets kort i former med ett kort per lag.
-- Ikke kjørt (verken test eller prod).
--
-- Ønske fra klubbkvelden 22.10.2026: i scramble, foursome, greensome og chapman spiller laget én
-- ball og har ett kort (appens CompetitionForm.card == .perTeam). I dag kan bare markøren i båsen
-- (eller gruppeføreren og arrangøren) føre det. Nå kan alle på laget føre lagets kort.
--
-- Hva som endres:
-- * can_score (fra 057) får én gren til, etter levert kort-sjekken og før markørsjekken: runden går,
--   formen har ett kort per lag (rounds.format er foursome, greensome, chapman, scramble-2 eller
--   scramble-4), spilleren står på et lag (team_no 1–99), og den innloggede eier en rad i runden
--   (owns_round_player) på samme lag → true.
--   save_hole sjekker can_score for hver rad og skriver lagscoren på alle på laget, så en lagkamerat
--   får nå lagret hele hullet. Samme regel gjelder hole_scores-policyene, spillene (020),
--   markørkonflikten (055) og submit_card (057).
-- * Formene står her som en fast liste. SQL har ingen katalog over formene; listen er de med
--   card: .perTeam i CompetitionForm.all og .added (GolfgutuCore). Kommer det en ny form med ett
--   kort per lag, må listen utvides.
--
-- Ikke endret: levert kort (057) går foran som før, så bare arrangøren fører på et levert kort.
-- Arrangøren, klubbens rett 'rounds', eieren av en løs runde og gruppeføreren som før. Former med
-- ett kort per spiller (også fourball og sammenlagt lag) som før: markøren eller spilleren selv.
-- Gamle apper (1.0.1) får serverregelen, men viser ikke kortet som redigerbart for lagkameraten.
--
-- Bare legg til (docs/utgivelser.md punkt 4): samme signatur, samme rettigheter, ingen svar blir
-- false der det var true før.
--
-- Krever 057. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- can_score: lagkameraten fører lagets kort -------------------------------------
-- Fra 057. Ny: grenen «071» etter levert kort-sjekken.
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
  if v_format in ('foursome', 'greensome', 'chapman', 'scramble-2', 'scramble-4')
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
-- select prosrc like '%scramble-4%' from pg_proc where proname = 'can_score';             -- true
-- select has_function_privilege('anon', 'public.can_score(uuid, uuid)', 'execute');       -- false
-- select has_function_privilege('authenticated', 'public.can_score(uuid, uuid)', 'execute'); -- true
-- Lagkamerat uten markørrett (som den innloggede lagkameraten, i en aktiv scramble-runde med markør):
-- select public.can_score('<runde>', '<lagkamerat på samme lag>');                         -- true
-- select public.can_score('<runde>', '<spiller på et annet lag i samme bås>');             -- false

-- --- Rullebakk -------------------------------------------------------------------
-- can_score: kjør blokken «can_score: levert kort» fra 057_levert_kort.sql på nytt
-- (create or replace function public.can_score … til og med grant execute).
