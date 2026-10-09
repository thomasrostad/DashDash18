-- 036: Tavla-data i én RPC (fase 24, punkt 1).
--
-- Tavla henter i dag sesongen, kveldene, troppen, rundene, banene og alle hullscorene med
-- om lag 106 kall, og RLS sjekker hver rad for seg (can_read_round per hullscore). Lasttesten
-- (docs/fase-22-turnering-som-kjerne.md kap. 9) målte ~700 ms databasetid. Denne funksjonen
-- sjekker tilgangen én gang per sesong og én gang per runde, og gir rådata i ett svar (~26 ms).
-- Tabellen regnes fortsatt på telefonen, så pariteten med db-nytt.js står.
--
-- Tilgang (samme svar som RLS gir et aktivt medlem):
--   * Sesongen: is_club_member(klubben), som seasons_select. Ellers P0002, og appen
--     faller tilbake til spørringene som før (for eksempel påmeldte som ikke er medlemmer).
--   * Rundene: kveldene i sesongen, status active eller locked, og can_read_round per runde.
--     Alt under rundene (hull, spillere, matcher, sidepremier, scorer) følger runden, som
--     policyene på de tabellene (can_read_round(round_id)).
--   * Banene: is_club_member(banens klubb) eller felles bane, som courses_select.
--   * Kveldene og troppen: is_club_member(klubben), som events_select og club_members_select.
--
-- Kolonnene er de samme som appens radtyper henter (`…Row.columns` i Rows.swift).
-- Bare lesing. Idempotent (create or replace).

create or replace function public.tavla_data(p_season_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club uuid;
  v_events uuid[];
  v_rounds uuid[];
  v_courses uuid[];
begin
  select s.club_id into v_club from public.seasons s where s.id = p_season_id;
  if v_club is null or not public.is_club_member(v_club) then
    raise exception 'Fant ikke sesongen' using errcode = 'P0002';
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = p_season_id;

  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r
   where r.event_id = any (v_events)
     and r.status in ('active', 'locked')
     and public.can_read_round(r.id);

  select coalesce(array_agg(c.id), '{}') into v_courses
    from public.courses c
   where c.id in (select r.course_id from public.rounds r where r.id = any (v_rounds))
     and (c.club_id is null or public.is_club_member(c.club_id));

  return jsonb_build_object(
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue, e.note
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, m.user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, m.avatar_path
          from public.club_members m where m.club_id = v_club) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               r.par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par
          from public.rounds r where r.id = any (v_rounds)) x),
    'round_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.round_id, h.hole_index, h.par, h.stroke_index, h.length_m
          from public.round_holes h where h.round_id = any (v_rounds)) x),
    'players', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.round_id, p.member_id, p.club_id, p.handicap_index, p.seed_group, p.playing_handicap,
               p.bay_no, p.is_marker, p.team_no
          from public.round_players p where p.round_id = any (v_rounds)) x),
    'matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.round_id, m.match_no, m.player_a, m.player_b, m.player_c, m.team_a, m.team_b, m.result
          from public.round_matches m where m.round_id = any (v_rounds)) x),
    'claims', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.round_id, c.member_id, c.kind, c.meters, c.hole_index, c.created_at
          from public.side_claims c where c.round_id = any (v_rounds)) x),
    'courses', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select c.id, c.club_id, c.name, c.external_name, c.course_rating, c.slope_rating, c.in_use,
               c.confirmed_by, c.confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes, s.recorded_at, s.updated_by, s.updated_at
          from public.hole_scores s where s.round_id = any (v_rounds)) x)
  );
end;
$$;

revoke all on function public.tavla_data(uuid) from public, anon;
grant execute on function public.tavla_data(uuid) to authenticated;

-- Rull tilbake:
-- drop function if exists public.tavla_data(uuid);
