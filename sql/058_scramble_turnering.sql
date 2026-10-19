-- 058_scramble_turnering.sql — klubbturnering med scramble: flere lag og funksjonærer som fører.
-- Godkjent 19.10.2026. Ikke kjørt på test eller prod.
--
-- Hva som endres:
-- * Lagnummer kan være 1–99 (før 1–20): round_players.team_no og round_matches.team_a/team_b.
--   En scramble-4 med 120 spillere har 30 lag. Samme grense som bås/flight (034).
-- * confirm_round_par (fra 044): funksjonæren for en gruppe (round_start_groups.scorer_id, sql/032)
--   kan bekrefte parene mens runden går, som en markør. Før kunne bare arrangøren og spillerne det,
--   så en funksjonær som ikke spiller kom ikke i gang med føringen. can_score lar allerede
--   funksjonæren føre for gruppa si (is_group_scorer).
--
-- Ikke endret: hvem som kan føre (can_score), RLS og resten av rundene.
--
-- Krever 032 og 044. Idempotent. Kontroll og rullebakk nederst.

begin;

-- --- Flere lag ------------------------------------------------------------------
alter table public.round_players drop constraint if exists round_players_team_no_check;
alter table public.round_players add constraint round_players_team_no_check check (team_no between 1 and 99);
alter table public.round_matches drop constraint if exists round_matches_team_a_check;
alter table public.round_matches add constraint round_matches_team_a_check check (team_a between 1 and 99);
alter table public.round_matches drop constraint if exists round_matches_team_b_check;
alter table public.round_matches add constraint round_matches_team_b_check check (team_b between 1 and 99);

-- --- Par-bekreftelsen: også funksjonæren ----------------------------------------
-- Som i 044. Bare blokken merket «058» er ny.
create or replace function public.confirm_round_par(p_round_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_round   public.rounds%rowtype;
  v_member  uuid;
  v_boss    boolean;
  v_bay     integer;
  v_marker  uuid;
begin
  if auth.uid() is null then
    raise exception 'Du må være logget inn' using errcode = '42501';
  end if;

  select * into v_round from public.rounds r where r.id = p_round_id for update;
  if not found or not public.can_read_round(p_round_id) then
    raise exception 'Fant ikke runden' using errcode = 'P0002';
  end if;

  if v_round.club_id is null then
    select pa.id into v_member from public.round_participants pa
    where pa.round_id = p_round_id and pa.profile_id = auth.uid();
    v_boss := v_round.owner_id is not distinct from auth.uid();
  else
    v_member := public.my_member_id(v_round.club_id);
    v_boss := private.has_club_right(v_round.club_id, 'rounds');
  end if;

  -- 058: funksjonæren for en gruppe i runden (fortsatt i staben) bekrefter som en markør.
  if not v_boss and v_round.status = 'active'
     and exists (select 1 from public.round_start_groups g
                  where g.round_id = p_round_id and g.scorer_id = auth.uid())
     and public.is_round_staff(p_round_id) then
    v_boss := true;
  end if;

  if not v_boss then
    if v_round.status <> 'active' then
      raise exception 'Runden er ikke i gang' using errcode = '55000';
    end if;
    if not exists (select 1 from public.round_players rp
                   where rp.round_id = p_round_id and rp.member_id = v_member) then
      raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
    end if;

    select rp.bay_no into v_bay
      from public.round_players rp
     where rp.round_id = p_round_id and rp.member_id = v_member;

    if v_bay is not null and v_bay >= 1 then
      select rp.member_id into v_marker
        from public.round_players rp
       where rp.round_id = p_round_id and rp.bay_no = v_bay and rp.is_marker
       limit 1;
      if v_marker is not null and v_marker <> v_member then
        raise exception 'Bare arrangøren eller en markør kan bekrefte parene' using errcode = '42501';
      end if;
    end if;
  end if;

  if v_round.par_confirmed_at is null then
    update public.rounds
       set par_confirmed_by = case when v_round.club_id is null then null else v_member end,
           par_confirmed_at = now()
     where id = p_round_id;
    return now();
  end if;
  return v_round.par_confirmed_at;
end;
$$;

commit;

-- --- Kontroll (les) ------------------------------------------------------------
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conname in ('round_players_team_no_check', 'round_matches_team_a_check',
--                    'round_matches_team_b_check');                                   -- 3 rader, 1–99
-- select prosrc like '%round_start_groups%' from pg_proc where proname = 'confirm_round_par'; -- true
-- select has_function_privilege('anon', 'public.confirm_round_par(uuid)', 'execute');      -- false

-- --- Rullebakk -------------------------------------------------------------------
-- Lagnummer over 20 må fjernes først: select count(*) from public.round_players where team_no > 20;
-- begin;
-- alter table public.round_players drop constraint if exists round_players_team_no_check;
-- alter table public.round_players add constraint round_players_team_no_check check (team_no between 1 and 20);
-- alter table public.round_matches drop constraint if exists round_matches_team_a_check;
-- alter table public.round_matches add constraint round_matches_team_a_check check (team_a between 1 and 20);
-- alter table public.round_matches drop constraint if exists round_matches_team_b_check;
-- alter table public.round_matches add constraint round_matches_team_b_check check (team_b between 1 and 20);
-- -- confirm_round_par: kjør definisjonen fra 044_roller.sql på nytt.
-- commit;
