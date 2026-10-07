-- ===========================================================================
-- export_pwa.sql: øyeblikksbilde av PWA-basen for importen (fase 9)
-- ===========================================================================
-- BARE LESING. Én SELECT som gir én rad med én kolonne, `snapshot` (json).
-- Ingen INSERT/UPDATE/DELETE/DDL, ingen funksjonskall med sideeffekter.
--
-- Slik brukes den:
--   1. Åpne PWA-prosjektet i Supabase (prod: «Golfgutu», iynczkyyimrijliqeant,
--      eller PWA-ens test: «Golfgutu Test», tihudaeamrnrukjyplvf) → SQL Editor.
--   2. Lim inn hele fila og trykk Run. Ett resultat, én celle.
--   3. Kopier cellen (eller «Export → JSON») og lagre den som
--        import-snapshot/<dato>/snapshot.json
--      i rota av repoet. Mappa står i .gitignore: den inneholder navn.
--   4. swift run dashimport parity  import-snapshot/<dato>
--      swift run dashimport          import-snapshot/<dato> import-out/<dato>.sql
--
-- Med vilje IKKE med (B10, persondata, ting appen ikke bruker):
--   telefon, user_id, e-post (allowed_emails), push_subscriptions, prat_push,
--   bilder, kalender_token, penger (bank_bevegelser, fines, poster, utlegg,
--   tips_betalinger, markets, market_stakes, schedule.utlegg*), activity_log
--   og activity_reaksjoner.
-- round_points er med bare for paritetssjekken (lagret, avledet tall i PWA-en).
-- Teksten i meldinger er med (kveldens tråd); bildene er ikke.
-- ===========================================================================

select json_build_object(
  'format', 1,
  'exported_at', now(),
  'source', current_database(),

  'settings', coalesce((
    select json_agg(t order by t.id) from (
      select id, name, year, location, finished, treasurer_id
      from public.settings
    ) t), '[]'::json),

  'players', coalesce((
    select json_agg(t order by t.joined_at, t.id) from (
      select id, name, commissioner, joined_at, handicap, seed_group
      from public.players
    ) t), '[]'::json),

  'courses', coalesce((
    select json_agg(t order by t.id) from (
      select id, name, par, course_rating, slope_rating, holes, trackman_name,
             i_bruk, bekreftet_av, bekreftet_at, created_at
      from public.courses
    ) t), '[]'::json),

  'course_holes', coalesce((
    select json_agg(t order by t.course_id, t.hole_number) from (
      select course_id, hole_number, par, hcp_index, distance_meters
      from public.course_holes
    ) t), '[]'::json),

  'schedule', coalesce((
    select json_agg(t order by t.date, t.id) from (
      select id, date, time, social_1, social_2, tips_innsats, tips_linje
      from public.schedule
    ) t), '[]'::json),

  'signups', coalesce((
    select json_agg(t order by t.schedule_id, t.player_id) from (
      select schedule_id, player_id, status, kommentar, created_at
      from public.signups
    ) t), '[]'::json),

  'rounds', coalesce((
    select json_agg(t order by t.created_at, t.id) from (
      select id, name, game_type, date, tee_time, course_id, locked, kladd,
             created_at, longest_drive_hole_index, kp_hole_index, ld_aktiv, kp_aktiv,
             multiplier, hcp_allowance, hole_count, hcp_extern, hole_start,
             par_bekreftet_av, par_bekreftet_at,
             avkortet_etter, avkort_regel, avkortet_av, avkortet_at
      from public.rounds
    ) t), '[]'::json),

  'round_holes', coalesce((
    select json_agg(t order by t.round_id, t.hole_index) from (
      select round_id, hole_index, par, stroke_index, meters
      from public.round_holes
    ) t), '[]'::json),

  'round_bays', coalesce((
    select json_agg(t order by t.round_id, t.bay_no, t.player_id) from (
      select round_id, player_id, bay_no, er_markor
      from public.round_bays
    ) t), '[]'::json),

  'round_teams', coalesce((
    select json_agg(t order by t.round_id, t.team_no, t.player_id) from (
      select round_id, player_id, team_no
      from public.round_teams
    ) t), '[]'::json),

  'round_matches', coalesce((
    select json_agg(t order by t.round_id, t.match_no) from (
      select round_id, match_no, player_a, player_b, player_c, team_a, team_b, result
      from public.round_matches
    ) t), '[]'::json),

  'hole_scores', coalesce((
    select json_agg(t order by t.round_id, t.player_id, t.hole_index) from (
      select round_id, player_id, hole_index, strokes, updated_at
      from public.hole_scores
    ) t), '[]'::json),

  'side_claims', coalesce((
    select json_agg(t order by t.created_at, t.id) from (
      select id, type, player_id, meters, round_id, hole_index, created_at
      from public.side_claims
    ) t), '[]'::json),

  'round_points', coalesce((
    select json_agg(t order by t.round_id, t.player_id) from (
      select round_id, player_id, points
      from public.round_points
    ) t), '[]'::json),

  'tips', coalesce((
    select json_agg(t order by t.schedule_id, t.player_id) from (
      select schedule_id, player_id, vinner, forste_ni, flest_par, birdie, over_linja,
             created_at, updated_at
      from public.tips
    ) t), '[]'::json),

  'meldinger', coalesce((
    select json_agg(t order by t.created_at, t.id) from (
      select id, schedule_id, player_id, tekst, nevnt, created_at,
             (bilde is not null) as har_bilde
      from public.meldinger
    ) t), '[]'::json),

  -- Radtall per tabell, også de som ikke eksporteres. Bare tall.
  'counts', json_build_object(
    'players', (select count(*) from public.players),
    'courses', (select count(*) from public.courses),
    'course_holes', (select count(*) from public.course_holes),
    'schedule', (select count(*) from public.schedule),
    'signups', (select count(*) from public.signups),
    'rounds', (select count(*) from public.rounds),
    'round_holes', (select count(*) from public.round_holes),
    'round_bays', (select count(*) from public.round_bays),
    'round_teams', (select count(*) from public.round_teams),
    'round_matches', (select count(*) from public.round_matches),
    'hole_scores', (select count(*) from public.hole_scores),
    'side_claims', (select count(*) from public.side_claims),
    'round_points', (select count(*) from public.round_points),
    'tips', (select count(*) from public.tips),
    'meldinger', (select count(*) from public.meldinger),
    'activity_log', (select count(*) from public.activity_log),
    'activity_reaksjoner', (select count(*) from public.activity_reaksjoner),
    'markets', (select count(*) from public.markets),
    'market_stakes', (select count(*) from public.market_stakes),
    'fines', (select count(*) from public.fines),
    'poster', (select count(*) from public.poster),
    'bank_bevegelser', (select count(*) from public.bank_bevegelser),
    'utlegg', (select count(*) from public.utlegg),
    'tips_betalinger', (select count(*) from public.tips_betalinger),
    'push_subscriptions', (select count(*) from public.push_subscriptions),
    'allowed_emails', (select count(*) from public.allowed_emails)
  )
) as snapshot;
