// Henting for «Tabeller». Bare lesing, med samme spørringer og kolonner som appen
// (TavlaQueries.rpc, CompetitionQueries.detail, RundeQueries.snapshot). RLS avgjør hva du ser.

import { supabase } from "../supabase.ts";
import type { Competition } from "../data.ts";
import type { CompetitionRaw, RoundRosterRow } from "./model.ts";

const competitionColumns = "id, kind, name, club_id, owner_id, season_id, status, entry, rules, starts_on, ends_on, is_main";
const seasonColumns = "id, club_id, name, status, rules";
const roundColumns =
  "id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, " +
  "handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, " +
  "cut_rule, cut_after, par_confirmed_by, par_confirmed_at, started_at, locked_at, venue, " +
  "tee_id, tee_name, course_rating, slope_rating, tee_par";
const memberColumns = "id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, is_treasurer, status, avatar_path";

type Query = PromiseLike<{ data: unknown; error: { message: string } | null }>;

async function rows(q: Query): Promise<unknown[]> {
  const { data, error } = await q;
  if (error) throw error;
  return (data as unknown[] | null) ?? [];
}

/** Serien: svaret fra `tavla_data` (sql/036) og sesongraden. Mangler sesongraden, brukes konkurransens felt (som appen). */
export async function loadSeason(c: Competition): Promise<{ tavlaData: unknown; season: unknown }> {
  if (!c.season_id) throw new Error("Serien mangler sesong.");
  const [rpc, seasons] = await Promise.all([
    supabase.rpc("tavla_data", { p_season_id: c.season_id }),
    rows(supabase.from("seasons").select(seasonColumns).eq("id", c.season_id)),
  ]);
  if (rpc.error) throw rpc.error;
  const season = seasons[0] ?? { id: c.season_id, club_id: c.club_id, name: c.name, status: c.status, rules: c.rules };
  return { tavlaData: rpc.data, season };
}

/** Liga, cup og morro: alt `CompetitionQueries.detail` henter, rått. */
export async function loadCompetition(competitionID: string): Promise<CompetitionRaw> {
  const [competitions, participants, links] = await Promise.all([
    rows(supabase.from("competitions").select(competitionColumns).eq("id", competitionID)),
    rows(supabase.from("competition_participants").select("id, competition_id, member_id, profile_id, status").eq("competition_id", competitionID)),
    rows(supabase.from("competition_rounds").select("competition_id, round_id, source").eq("competition_id", competitionID)),
  ]);
  const competition = competitions[0] as { id: string; kind: string; club_id: string | null } | undefined;
  if (!competition) throw new Error("Fant ikke turneringen.");
  const roundIDs = (links as { round_id: string }[]).map((l) => l.round_id);

  // Kladder teller ikke.
  const rounds = roundIDs.length === 0 ? [] : await rows(supabase.from("rounds").select(roundColumns)
    .in("id", roundIDs).in("status", ["active", "locked"]));
  const typed = rounds as { id: string; club_id: string | null; event_id: string | null; course_id: string | null }[];
  const ids = typed.map((r) => r.id);
  const courseIDs = [...new Set(typed.map((r) => r.course_id).filter((x): x is string => !!x))];
  const eventIDs = [...new Set(typed.map((r) => r.event_id).filter((x): x is string => !!x))];
  const roundClubs = [...new Set(typed.filter((r) => r.club_id && r.event_id).map((r) => r.club_id!))];
  const none = Promise.resolve([] as unknown[]);
  const inRounds = (table: string, columns: string) => (ids.length === 0 ? none : rows(supabase.from(table).select(columns).in("round_id", ids)));

  const [roundHoles, players, matches, claims, courses, courseHoles, events, roster, roundParticipants, clubMembers, roundMembers, cupMatches, scores] =
    await Promise.all([
      inRounds("round_holes", "round_id, hole_index, par, stroke_index, length_m"),
      inRounds("round_players", "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no"),
      inRounds("round_matches", "round_id, match_no, player_a, player_b, player_c, team_a, team_b, result"),
      inRounds("side_claims", "id, round_id, member_id, kind, meters, hole_index, created_at"),
      courseIDs.length === 0 ? none : rows(supabase.from("courses").select("id, club_id, name, external_name, course_rating, slope_rating, in_use").in("id", courseIDs)),
      courseIDs.length === 0 ? none : rows(supabase.from("course_holes").select("course_id, hole_number, par, stroke_index, length_m").in("course_id", courseIDs)),
      eventIDs.length === 0 ? none : rows(supabase.from("events").select("id, club_id, season_id, event_date, start_time, venue, note, competition_id").in("id", eventIDs)),
      inRounds("round_roster", "round_id, player_id, club_id, display_name, profile_id, is_guest"),
      inRounds("round_participants", "id, round_id, profile_id, display_name, handicap_index"),
      competition.club_id ? rows(supabase.from("club_members").select(memberColumns).eq("club_id", competition.club_id)) : none,
      roundClubs.length === 0 ? none : rows(supabase.from("club_members").select(memberColumns).in("club_id", roundClubs)),
      competition.kind === "cup"
        ? rows(supabase.from("competition_matches").select("id, competition_id, round_no, slot, player_a, player_b, winner, walkover, result, round_id").eq("competition_id", competitionID))
        : none,
      // Scorene per runde: mange runder kan gå over PostgREST-grensen på 1000 rader i ett svar.
      Promise.all(ids.map((id) => rows(supabase.from("hole_scores").select("round_id, member_id, hole_index, strokes").eq("round_id", id)))).then((x) => x.flat()),
    ]);

  // Regelsettet per runde: kveldens sesong, ellers klubbens aktive sesong.
  const seasonIDs = [...new Set((events as { season_id: string | null }[]).map((e) => e.season_id).filter((x): x is string => !!x))];
  const [byID, active] = await Promise.all([
    seasonIDs.length === 0 ? none : rows(supabase.from("seasons").select(seasonColumns).in("id", seasonIDs)),
    roundClubs.length === 0 ? none : rows(supabase.from("seasons").select(seasonColumns).in("club_id", roundClubs).eq("status", "active")),
  ]);

  const profileIDs = [...new Set([
    ...(participants as { profile_id: string | null }[]).map((p) => p.profile_id),
    ...(roster as RoundRosterRow[]).map((p) => p.profile_id),
    ...(roundParticipants as { profile_id: string | null }[]).map((p) => p.profile_id),
  ].filter((x): x is string => !!x))];
  const profiles = profileIDs.length === 0 ? [] : await rows(supabase.from("profiles").select("id, display_name, handicap_index, avatar_path").in("id", profileIDs));

  return {
    competition, participants, links, rounds, roundHoles, players, matches, scores, claims, courses, courseHoles, events,
    clubMembers, roundMembers, seasons: [...byID, ...active], roster: roster as RoundRosterRow[], roundParticipants, profiles, cupMatches,
  };
}
