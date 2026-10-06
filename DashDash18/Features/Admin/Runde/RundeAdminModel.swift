import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Kveldens runder for arrangøren: lista, veiviseren og handlingene (lagre, starte, låse, slette).
///
/// Lagring er to kall: raden i `rounds`, så `set_round_setup` (deltakere, båser, lag og matcher
/// i én transaksjon). Start er raden, så `start_round` (sql/006_runder.sql), som skriver oppsettet
/// og setter status i én transaksjon. Feiler start_round, står runden som kladd slik den var.
@Observable
final class RundeAdminModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    /// Kveldene i sesongen, eldste først.
    private(set) var events: [EventRow] = []
    private(set) var selectedEventID: UUID?
    private(set) var seasons: [SeasonRow] = []
    /// Banene som er klare, i bibliotekets rekkefølge.
    private(set) var courses: [CourseListItem] = []
    private(set) var allCourses: [CourseListItem] = []
    /// Aktive medlemmer, sortert på navn.
    private(set) var members: [ClubMemberRow] = []
    private(set) var signups: [SignupRow] = []
    /// Rundene på den valgte kvelden, i rundenummerets rekkefølge.
    private(set) var rounds: [RoundRow] = []
    private(set) var playersByRound: [UUID: [RoundPlayerRow]] = [:]
    /// Runden som går i klubben nå, på hvilken som helst kveld.
    private(set) var activeRound: RoundRow?

    private let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }

    static let roundColumns = """
        id, club_id, event_id, course_id, round_no, name, status, hole_count, first_hole, tee_time, format, \
        handicap_allowance, external_handicap, weight, ld_enabled, ld_hole_index, kp_enabled, kp_hole_index, \
        cut_rule, cut_after, par_confirmed_by, par_confirmed_at, started_at, locked_at
        """
    static let playerColumns =
        "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no"
    static let matchColumns = "round_id, match_no, player_a, player_b, player_c, team_a, team_b, result"

    var selectedEvent: EventRow? { events.first { $0.id == selectedEventID } }

    /// Regelsettet for den valgte kvelden.
    var rules: Ruleset { RoundListing.rules(for: selectedEvent, seasons: seasons) }

    func course(_ id: UUID?) -> CourseListItem? {
        guard let id else { return nil }
        return allCourses.first { $0.id == id }
    }

    func memberName(_ id: UUID) -> String {
        members.first { $0.id == id }?.displayName ?? "Ukjent"
    }

    func title(_ round: RoundRow) -> String {
        RoundListing.title(roundNo: round.roundNo, courseName: course(round.courseID)?.course.name)
    }

    // MARK: Lasting

    func load() async {
        do {
            async let seasonRows: [SeasonRow] = client.from("seasons")
                .select("id, club_id, name, status, rules")
                .eq("club_id", value: clubID)
                .execute().value
            async let eventRows: [EventRow] = client.from("events")
                .select("id, club_id, season_id, event_date, start_time, venue, note")
                .eq("club_id", value: clubID)
                .order("event_date")
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(KveldQueries.memberColumns)
                .eq("club_id", value: clubID)
                .eq("status", value: MemberStatus.active.rawValue)
                .execute().value
            async let courseRows: [CourseRow] = client.from("courses")
                .select(CourseLibraryModel.courseColumns)
                .eq("club_id", value: clubID)
                .execute().value
            async let activeRows: [RoundRow] = client.from("rounds")
                .select(Self.roundColumns)
                .eq("club_id", value: clubID)
                .eq("status", value: RoundStatus.active.rawValue)
                .limit(1)
                .execute().value

            let seasons = try await seasonRows
            let allEvents = try await eventRows
            let roster = try await memberRows
            let courseList = try await courseRows
            activeRound = try await activeRows.first

            var holes: [CourseHoleRecord] = []
            if !courseList.isEmpty {
                holes = try await client.from("course_holes")
                    .select("course_id, hole_number, par, stroke_index, length_m")
                    .in("course_id", values: courseList.map(\.id.uuidString))
                    .execute().value
            }

            self.seasons = seasons
            let activeSeason = seasons.first { $0.status == .active }
            events = Terminliste.eveningsForSeason(allEvents, activeSeasonID: activeSeason?.id)
            members = KveldQueries.sortedByName(roster)
            allCourses = CourseListItem.make(courses: courseList, holes: holes)
            courses = allCourses.filter(\.isReady)

            if selectedEventID == nil || !events.contains(where: { $0.id == selectedEventID }) {
                selectedEventID = try await defaultEventID()
            }
            try await loadEvent()
            state = .loaded
        } catch {
            if case .loaded = state { return }  // behold det som vises ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
    }

    func select(eventID: UUID) async {
        selectedEventID = eventID
        do {
            try await loadEvent()
        } catch {
            state = .failed(DataError.from(error).message)
        }
    }

    /// Neste kveld i terminlista som ikke er ferdig (alle runder låst), ellers den siste.
    private func defaultEventID() async throws -> UUID? {
        let today = EveningDates.today()
        let todays = events.filter { $0.eventDate == today }.map(\.id)
        var finished: Set<UUID> = []
        if !todays.isEmpty {
            let rows: [RoundStatusRow] = try await client.from("rounds")
                .select("event_id, status")
                .in("event_id", values: todays.map(\.uuidString))
                .execute().value
            finished = NextEvening.finishedEventIDs(rounds: rows.map { ($0.eventID, $0.status) })
        }
        return RoundListing.defaultEvent(events, today: today, finished: finished)?.id
    }

    private func loadEvent() async throws {
        guard let eventID = selectedEventID else {
            rounds = []
            signups = []
            playersByRound = [:]
            return
        }
        async let roundRows: [RoundRow] = client.from("rounds")
            .select(Self.roundColumns)
            .eq("event_id", value: eventID)
            .order("round_no")
            .execute().value
        async let signupRows: [SignupRow] = client.from("signups")
            .select("event_id, member_id, club_id, status, comment")
            .eq("event_id", value: eventID)
            .execute().value
        let loaded = try await roundRows
        signups = try await signupRows

        var players: [RoundPlayerRow] = []
        if !loaded.isEmpty {
            players = try await client.from("round_players")
                .select(Self.playerColumns)
                .in("round_id", values: loaded.map(\.id.uuidString))
                .execute().value
        }
        rounds = loaded
        playersByRound = Dictionary(grouping: players, by: \.roundID)
    }

    // MARK: Utkast

    /// Ny runde på den valgte kvelden: de påmeldte, regelsettets standarder og første klare bane.
    func newDraft() -> RoundDraft? {
        guard let event = selectedEvent else { return nil }
        let (ids, source) = RoundParticipants.initial(roster: members, signups: signups)
        var draft = RoundDraft.new(eventID: event.id, roundNo: RoundListing.nextRoundNo(existing: rounds),
                                   teeTime: event.startTime, participants: ids, source: source, rules: rules)
        draft.courseID = courses.first?.id
        draft.redrawMatches(roster: members)
        draft.reshuffleBays(count: BayPlan.defaultBayCount(players: ids.count, maxPerBay: rules.formats.maxPerBay))
        return draft
    }

    /// Kladden (eller runden) slik den er lagret, med deltakere og matcher.
    func draft(for round: RoundRow) async throws(DataError) -> RoundDraft {
        do {
            async let playerRows: [RoundPlayerRow] = client.from("round_players")
                .select(Self.playerColumns)
                .eq("round_id", value: round.id)
                .execute().value
            async let matchRows: [RoundMatchRow] = client.from("round_matches")
                .select(Self.matchColumns)
                .eq("round_id", value: round.id)
                .order("match_no")
                .execute().value
            let players = try await playerRows
            let matches = try await matchRows
            let (ids, source) = RoundParticipants.forDraft(roster: members, saved: players, signups: signups)
            var draft = RoundDraft.saved(round, players: players, matches: matches, participants: ids, source: source)
            if players.isEmpty {
                // Ingen oppsett lagret ennå: forslag som for en ny runde.
                draft.redrawMatches(roster: members)
                draft.reshuffleBays(count: BayPlan.defaultBayCount(players: ids.count, maxPerBay: rules.formats.maxPerBay))
            }
            return draft
        } catch {
            throw DataError.from(error)
        }
    }

    func issues(_ draft: RoundDraft, forStart: Bool) -> [RoundSetupIssue] {
        RoundSetupCheck.issues(draft, course: course(draft.courseID), rules: rules, roster: members, forStart: forStart)
    }

    /// Runden som er i veien for å starte denne, hvis noen.
    func blockingRound(for draft: RoundDraft) -> RoundRow? {
        guard let activeRound, activeRound.id != draft.roundID else { return nil }
        return activeRound
    }

    // MARK: Skriving

    /// «Lagre som kladd». Gir rundens id.
    @discardableResult
    func saveDraft(_ draft: RoundDraft) async throws(DataError) -> UUID {
        if let issue = issues(draft, forStart: false).first { throw .invalid(issue.message) }
        let id = try await writeRound(draft)
        try await writeSetup(draft, roundID: id, withPlayingHandicap: false)
        await reload()
        return id
    }

    /// «Start runden»: lagrer oppsettet med spillehandicap og setter status til pågår.
    /// Databasen tillater én pågående runde per klubb (23505).
    func start(_ draft: RoundDraft) async throws(DataError) {
        if let issue = issues(draft, forStart: true).first { throw .invalid(issue.message) }
        try await refreshActiveRound()
        if let blocking = blockingRound(for: draft) {
            throw .invalid("\(title(blocking)) går allerede. Lås den før du starter en ny, eller lagre denne som kladd.")
        }
        let id = try await writeRound(draft)
        let params = RoundSetupParams.make(roundID: id, draft: draft, roster: members,
                                           course: course(draft.courseID)?.coreCourse, rules: rules,
                                           withPlayingHandicap: true)
        struct Started: Decodable { let players: Int; let matches: Int; let status: RoundStatus }
        do {
            // Oppsett og status i én transaksjon. Går en annen runde (23505), ruller alt tilbake.
            let started: Started = try await client.rpc("start_round", params: params).execute().value
            guard started.status == .active, started.players == params.players.count,
                  started.matches == params.matches.count else {
                throw DataError.invalid("Runden ble ikke startet slik oppsettet sto. Last inn på nytt og sjekk.")
            }
        } catch {
            await reload()
            throw .invalid("Runden startet ikke. "
                           + RoundErrors.startMessage(sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error)))
        }
        await reload()
    }

    /// Start en kladd fra lista: henter oppsettet, sjekker det og starter.
    func start(_ round: RoundRow) async throws(DataError) {
        let draft = try await draft(for: round)
        try await start(draft)
    }

    /// «Lås runden»: runden er ferdig.
    func lock(_ round: RoundRow) async throws(DataError) {
        do {
            let updated: [RoundRow] = try await client.from("rounds")
                .update(RoundStatusPatch(status: .locked))
                .eq("id", value: round.id)
                .select(Self.roundColumns)
                .execute().value
            guard updated.first?.status == .locked else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        await reload()
    }

    /// Hva som forsvinner med runden. Telles før slettingen.
    func deleteSummary(_ round: RoundRow) async throws(DataError) -> RoundDeleteSummary {
        struct ScoreMember: Decodable { let member_id: UUID }
        do {
            async let scoreRows: [ScoreMember] = client.from("hole_scores")
                .select("member_id")
                .eq("round_id", value: round.id)
                .execute().value
            async let claimRows: [ScoreMember] = client.from("side_claims")
                .select("member_id")
                .eq("round_id", value: round.id)
                .execute().value
            let scores = try await scoreRows
            let claims = try await claimRows
            return RoundDeleteSummary(holeScores: scores.count, playersWithScores: Set(scores.map(\.member_id)).count,
                                      sideClaims: claims.count, isDraft: round.status == .draft)
        } catch {
            throw DataError.from(error)
        }
    }

    /// «Slett runden» med `delete_round`. Gir meldingen om hva som ble slettet.
    func delete(_ round: RoundRow) async throws(DataError) -> String {
        struct Params: Encodable { let p_round_id: UUID }
        do {
            let result: DeleteRoundResult = try await client
                .rpc("delete_round", params: Params(p_round_id: round.id))
                .execute().value
            await reload()
            return result.message
        } catch {
            throw DataError.from(error)
        }
    }

    private func writeRound(_ draft: RoundDraft) async throws(DataError) -> UUID {
        let write = RoundWrite(draft: draft, clubID: clubID, course: course(draft.courseID)?.coreCourse)
        do {
            // Upsert på id: en ny runde har fått id i appen, så et nytt forsøk etter en feil
            // oppdaterer samme rad i stedet for å lage en til. Status røres ikke her.
            let saved: [RoundRow] = try await client.from("rounds")
                .upsert(write, onConflict: "id")
                .select(Self.roundColumns)
                .execute().value
            guard let row = saved.first else { throw DataError.notAllowed }  // RLS sa nei uten feilkode
            return row.id
        } catch {
            throw .invalid(RoundErrors.saveMessage(sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error)))
        }
    }

    private func writeSetup(_ draft: RoundDraft, roundID: UUID, withPlayingHandicap: Bool) async throws(DataError) {
        let params = RoundSetupParams.make(roundID: roundID, draft: draft, roster: members,
                                           course: course(draft.courseID)?.coreCourse, rules: rules,
                                           withPlayingHandicap: withPlayingHandicap)
        struct Counts: Decodable { let players: Int; let matches: Int }
        do {
            let counts: Counts = try await client.rpc("set_round_setup", params: params).execute().value
            guard counts.players == params.players.count, counts.matches == params.matches.count else {
                throw DataError.invalid("Oppsettet ble ikke lagret slik det sto. Last inn på nytt og sjekk.")
            }
        } catch {
            await reload()
            throw .invalid("Runden er lagret, men ikke oppsettet. \(DataError.from(error).message)")
        }
    }

    private func refreshActiveRound() async throws(DataError) {
        do {
            let rows: [RoundRow] = try await client.from("rounds")
                .select(Self.roundColumns)
                .eq("club_id", value: clubID)
                .eq("status", value: RoundStatus.active.rawValue)
                .limit(1)
                .execute().value
            activeRound = rows.first
        } catch {
            throw DataError.from(error)
        }
    }

    private func reload() async {
        try? await refreshActiveRound()
        try? await loadEvent()
    }
}
