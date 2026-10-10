-- 043: TV-visning med kode også for liga, morro og cup (fase 26). IKKE KJØRT. Krever godkjenning.
--
-- 041 ga TV-koden bare for turneringer med kvelder (sesongen). Nå svarer tv_board_data også for
-- liga, morro og cup, med det appen henter for turneringssiden (se tv_competition_data). TV-siden
-- (Workeren atten-lenker) regner tabellen med regelmotoren i TypeScript, som appen.
-- Samme person kan stå som profil i påmeldingen og som medlem i runden, og tabellen må slå dem
-- sammen. Derfor er profil-id-ene med, men maskert: md5(turnering, profil) i stedet for innloggings-
-- id-en, likt overalt i svaret og ulikt fra turnering til turnering. Ingen ekte user_id, owner_id eller
-- par_confirmed_by (heller ikke for sesongen, som 041 sendte med), ingen e-post, bilder, tråd eller påmeldinger utover turneringens egne.
--
-- Én transaksjon, idempotent. Rullebakke: kjør tv_board_data fra 041 igjen og
-- drop function public.tv_competition_data(uuid).

begin;

-- Liga, morro og cup: det appen henter for turneringssiden (CompetitionQueries.detail): påmeldte,
-- koblingene, de tellende rundene (aktiv og låst) med alt under, rundenes spillere med navn og profil,
-- deltakerne i løse runder, troppen (navn, handicap og seeding; user_id trengs for å finne samme
-- person som medlem og profil, maskert) og profilenes visningsnavn. Cup: kampene. Ingen e-post eller bilder.
create or replace function public.tv_competition_data(p_competition_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_rounds  uuid[];
  v_courses uuid[];
  v_profiles uuid[];
begin
  select * into v_comp from public.competitions c where c.id = p_competition_id;
  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.competition_rounds cr join public.rounds r on r.id = cr.round_id
   where cr.competition_id = p_competition_id and r.status in ('active', 'locked');
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;
  select coalesce(array_agg(distinct x.id), '{}') into v_profiles from (
    select p.profile_id as id from public.competition_participants p where p.competition_id = p_competition_id and p.profile_id is not null
    union select rp.profile_id from public.round_participants rp where rp.round_id = any (v_rounds) and rp.profile_id is not null
    union select rr.profile_id from public.round_roster rr where rr.round_id = any (v_rounds) and rr.profile_id is not null) x;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind, 'status', v_comp.status,
                                      'season_id', null, 'club_id', v_comp.club_id, 'owner_id', null,
                                      'entry', v_comp.entry, 'rules', v_comp.rules, 'starts_on', v_comp.starts_on,
                                      'ends_on', v_comp.ends_on, 'is_main', v_comp.is_main,
                                      'requires_purchase', v_comp.requires_purchase, 'entitlement_id', null,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'participants', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select p.id, p.competition_id, p.member_id, md5(p_competition_id::text || p.profile_id::text)::uuid as profile_id, p.status
          from public.competition_participants p where p.competition_id = p_competition_id) x),
    'links', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select cr.competition_id, cr.round_id, cr.source
          from public.competition_rounds cr where cr.competition_id = p_competition_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               null::uuid as par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue, null::uuid as owner_id,
               r.tee_id, r.tee_name, r.course_rating, r.slope_rating, r.tee_par,
               (select e.event_date from public.events e where e.id = r.event_id) as event_date
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
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s where s.round_id = any (v_rounds)) x),
    'roster', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select rr.round_id, rr.player_id, rr.club_id, rr.display_name, md5(p_competition_id::text || rr.profile_id::text)::uuid as profile_id, rr.is_guest
          from public.round_roster rr where rr.round_id = any (v_rounds)) x),
    'round_participants', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select rp.id, rp.round_id, md5(p_competition_id::text || rp.profile_id::text)::uuid as profile_id, rp.display_name, rp.handicap_index
          from public.round_participants rp where rp.round_id = any (v_rounds)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, md5(p_competition_id::text || m.user_id::text)::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'profiles', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select md5(p_competition_id::text || p.id::text)::uuid as id, p.display_name, p.handicap_index, null::text as avatar_path
          from public.profiles p where p.id = any (v_profiles)) x),
    'cup_matches', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.competition_id, m.round_no, m.slot, m.player_a, m.player_b, m.winner, m.walkover, m.result, m.round_id
          from public.competition_matches m where m.competition_id = p_competition_id and v_comp.kind = 'cup') x)
  );
end;
$$;
revoke all on function public.tv_competition_data(uuid) from public, anon, authenticated;

create or replace function public.tv_board_data(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_comp    public.competitions%rowtype;
  v_events  uuid[];
  v_rounds  uuid[];
  v_courses uuid[];
begin
  select c.* into v_comp
    from public.tv_codes t join public.competitions c on c.id = t.competition_id
   where t.code = upper(btrim(coalesce(p_code, ''))) and t.revoked_at is null and t.expires_at > now();
  if v_comp.id is null then
    raise exception 'Fant ingen TV-visning for koden' using errcode = 'P0002';
  end if;
  if v_comp.season_id is null then
    return public.tv_competition_data(v_comp.id);
  end if;

  select coalesce(array_agg(e.id), '{}') into v_events
    from public.events e where e.season_id = v_comp.season_id;
  select coalesce(array_agg(r.id), '{}') into v_rounds
    from public.rounds r where r.event_id = any (v_events) and r.status in ('active', 'locked');
  select coalesce(array_agg(distinct r.course_id), '{}') into v_courses
    from public.rounds r where r.id = any (v_rounds) and r.course_id is not null;

  return jsonb_build_object(
    'competition', jsonb_build_object('id', v_comp.id, 'name', v_comp.name, 'kind', v_comp.kind,
                                      'status', v_comp.status, 'season_id', v_comp.season_id,
                                      'club_id', v_comp.club_id, 'rules', v_comp.rules,
                                      'club_name', (select k.name from public.clubs k where k.id = v_comp.club_id)),
    'events', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select e.id, e.club_id, e.season_id, e.event_date, e.start_time, e.venue
          from public.events e where e.id = any (v_events)) x),
    'members', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select m.id, m.club_id, null::uuid as user_id, m.display_name, m.handicap_index, m.seed_group,
               m.is_organizer, m.is_treasurer, m.status, null::text as avatar_path
          from public.club_members m where m.club_id = v_comp.club_id) x),
    'rounds', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select r.id, r.club_id, r.event_id, r.course_id, r.round_no, r.name, r.status, r.hole_count,
               r.first_hole, r.tee_time, r.format, r.handicap_allowance, r.external_handicap, r.weight,
               r.ld_enabled, r.ld_hole_index, r.kp_enabled, r.kp_hole_index, r.cut_rule, r.cut_after,
               null::uuid as par_confirmed_by, r.par_confirmed_at, r.started_at, r.locked_at, r.venue,
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
               null::uuid as confirmed_by, null::timestamptz as confirmed_at
          from public.courses c where c.id = any (v_courses)) x),
    'course_holes', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select h.course_id, h.hole_number, h.par, h.stroke_index, h.length_m
          from public.course_holes h where h.course_id = any (v_courses)) x),
    'scores', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from (
        select s.round_id, s.member_id, s.hole_index, s.strokes
          from public.hole_scores s where s.round_id = any (v_rounds)) x)
  );
end;
$$;
revoke all on function public.tv_board_data(text) from public;
grant execute on function public.tv_board_data(text) to anon, authenticated;

commit;
