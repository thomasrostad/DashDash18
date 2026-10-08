import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Kveldens runder for arrangøren: lista, oppsettet og handlingene (lagre, starte, låse, slette).
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
    /// Alle kveldene i klubben, også fra tidligere sesonger. For grupperingen i «Runder».
    private(set) var allEvents: [EventRow] = []
    private(set) var selectedEventID: UUID?
    private(set) var seasons: [SeasonRow] = []
    /// Banene som er klare, i bibliotekets rekkefølge.
    private(set) var courses: [CourseListItem] = []
    private(set) var allCourses: [CourseListItem] = []
    /// Aktive medlemmer, sortert på navn.
    private(set) var members: [ClubMemberRow] = []
    private(set) var signups: [SignupRow] = []
    /// Alle rundene i klubben, alle statuser. Kladder ser bare arrangørene (RLS).
    private(set) var allRounds: [RoundRow] = []
    /// Rundene på den valgte kvelden, i rundenummerets rekkefølge.
    private(set) var rounds: [RoundRow] = []
    /// Deltakerne i alle rundene.
    private(set) var playersByRound: [UUID: [RoundPlayerRow]] = [:]
    /// Runden som går i klubben nå, på hvilken som helst kveld.
    private(set) var activeRound: RoundRow?
    /// Er alle hull ført i runden som går?
    private(set) var activeComplete = false
    /// Rundene på sesongens kvelder, for forslaget fra forrige runde.
    private(set) var seasonRounds: [RoundRow] = []

    private let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }
    var clubContext: ClubContext { context }

    static let roundColumns = RundeQueries.roundColumns
    static let playerColumns =
        "round_id, member_id, club_id, handicap_index, seed_group, playing_handicap, bay_no, is_marker, team_no"
    static let matchColumns = "round_id, match_no, player_a, player_b, player_c, team_a, team_b, result"

    var selectedEvent: EventRow? { events.first { $0.id == selectedEventID } }

    /// Rundene gruppert per kveld, nyeste først, med kvelden som står for tur selv uten runder.
    var groups: [RoundGroup] {
        RoundGroups.make(rounds: allRounds, events: allEvents, including: selectedEventID)
    }

    /// Kan en ny runde settes opp på kvelden fra lista?
    func allowsNewRound(_ event: EventRow) -> Bool {
        RoundGroups.allowsNewRound(event, today: EveningDates.today(), defaultID: selectedEventID)
    }

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
            self.allEvents = allEvents
            let activeSeason = seasons.first { $0.status == .active }
            events = Terminliste.eveningsForSeason(allEvents, activeSeasonID: activeSeason?.id)
            members = KveldQueries.sortedByName(roster)
            let kinds = try await CourseLibraryModel.loadKinds(client: client, clubID: clubID)
            allCourses = CourseListItem.make(courses: courseList, holes: holes, kinds: kinds)
            courses = allCourses.filter(\.isReady)

            if selectedEventID == nil || !events.contains(where: { $0.id == selectedEventID }) {
                selectedEventID = try await defaultEventID()
            }
            try await loadRounds()
            try await loadEvent()
            await loadActiveProgress()
            state = .loaded
        } catch {
            if case .loaded = state { return }  // behold det som vises ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
    }

    /// Bytter kveld. Feiler hentingen, står den forrige kvelden valgt, med rundene sine.
    func select(eventID: UUID) async throws(DataError) {
        let previous = selectedEventID
        selectedEventID = eventID
        do {
            try await loadEvent()
        } catch {
            if selectedEventID == eventID { selectedEventID = previous }
            throw DataError.from(error)
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

    /// Alle rundene i klubben med deltakerne. Rundene på sesongens kvelder gir forslaget fra
    /// forrige runde.
    private func loadRounds() async throws {
        let loaded: [RoundRow] = try await client.from("rounds")
            .select(Self.roundColumns)
            .eq("club_id", value: clubID)
            .order("round_no")
            .execute().value
        var players: [RoundPlayerRow] = []
        if !loaded.isEmpty {
            players = try await client.from("round_players")
                .select(Self.playerColumns)
                .in("round_id", values: loaded.map(\.id.uuidString))
                .execute().value
        }
        allRounds = loaded
        playersByRound = Dictionary(grouping: players, by: \.roundID)
        let seasonEventIDs = Set(events.map(\.id))
        seasonRounds = loaded.filter { $0.eventID.map(seasonEventIDs.contains) ?? false }
        rounds = roundsForSelectedEvent()
    }

    private func roundsForSelectedEvent() -> [RoundRow] {
        guard let eventID = selectedEventID else { return [] }
        return allRounds.filter { $0.eventID == eventID }.sorted { $0.roundNo < $1.roundNo }
    }

    /// Påmeldingene på den valgte kvelden, og kveldens runder fra `allRounds`.
    private func loadEvent() async throws {
        guard let eventID = selectedEventID else {
            rounds = []
            signups = []
            return
        }
        let loadedSignups: [SignupRow] = try await client.from("signups")
            .select("event_id, member_id, club_id, status, comment")
            .eq("event_id", value: eventID)
            .execute().value
        // Er en annen kveld valgt mens vi hentet, hører svaret ikke til den.
        guard selectedEventID == eventID else { return }
        signups = loadedSignups
        rounds = roundsForSelectedEvent()
    }

    /// Hvor langt runden som går har kommet: førte hull og antall spillere. For «Avslutt kvelden»
    /// på arrangørsiden. Feiler hentingen, regnes runden som ikke ferdig.
    private func loadActiveProgress() async {
        guard let round = activeRound else { activeComplete = false; return }
        struct Row: Decodable { let member_id: UUID }
        do {
            async let scoreRows: [Row] = client.from("hole_scores")
                .select("member_id")
                .eq("round_id", value: round.id)
                .execute().value
            async let playerRows: [Row] = client.from("round_players")
                .select("member_id")
                .eq("round_id", value: round.id)
                .execute().value
            let scores = try await scoreRows
            let players = try await playerRows
            activeComplete = Tonight.isComplete(scoredHoles: scores.count, players: players.count, round: round)
        } catch {
            activeComplete = false
        }
    }

    // MARK: Utkast

    /// Ny runde på den valgte kvelden: de påmeldte, forslaget fra forrige runde i sesongen (ellers
    /// regelsettets standard og første klare bane), og gruppene fordelt automatisk.
    func newDraft() -> RoundDraft? {
        guard let event = selectedEvent else { return nil }
        let (ids, source) = RoundParticipants.initial(roster: members, signups: signups)
        var draft = RoundDraft.new(eventID: event.id, roundNo: RoundListing.nextRoundNo(existing: rounds),
                                   teeTime: event.startTime, participants: ids, source: source, rules: rules)
        draft.courseID = courses.first?.id
        QuickStart.applySuggestion(from: previousRound(for: event), to: &draft, courses: courses, rules: rules)
        QuickStart.autoArrange(&draft, rules: rules, roster: members)
        return draft
    }

    /// Forrige startede runde i sesongen, til og med den valgte kvelden.
    func previousRound(for event: EventRow) -> RoundRow? {
        QuickStart.previousRound(rounds: seasonRounds, events: events, upTo: event)
    }

    /// Kladden med id, slik den er lagret.
    func draft(id: UUID) async throws(DataError) -> RoundDraft? {
        guard let round = rounds.first(where: { $0.id == id }) else { return nil }
        return try await draft(for: round)
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
        if let issue = issues(draft, forStart: false).first { throw .invalid(issue.message(draft.groupTerm)) }
        let id = try await writeRound(draft)
        try await writeSetup(draft, roundID: id, withPlayingHandicap: false)
        await reload()
        return id
    }

    /// «Start runden»: lagrer oppsettet med spillehandicap og setter status til pågår.
    /// Databasen tillater én pågående runde per klubb (23505).
    func start(_ draft: RoundDraft) async throws(DataError) {
        if let issue = issues(draft, forStart: true).first { throw .invalid(issue.message(draft.groupTerm)) }
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
        await logStarted(roundID: id)
    }

    /// «Ny runde» i aktiviteten, fra runden slik serveren har den etter start_round. Feiler
    /// hentingen eller loggingen, står runden startet likevel.
    private func logStarted(roundID: UUID) async {
        let active = activeRound?.id == roundID ? activeRound : nil
        guard let row = rounds.first(where: { $0.id == roundID }) ?? active,
              let snapshot = try? await RundeQueries.snapshot(client: client, round: row),
              let event = RoundGame(snapshot).startedEventIfActive else { return }
        await activityLog.logQuietly(event, eventID: row.eventID, roundID: row.id)
    }

    private var activityLog: ActivityLog { ActivityLog(client: client, clubID: clubID) }

    /// Start en kladd fra lista: henter oppsettet, sjekker det og starter.
    func start(_ round: RoundRow) async throws(DataError) {
        let draft = try await draft(for: round)
        try await start(draft)
    }

    /// «Lås runden»: runden er ferdig.
    func lock(_ round: RoundRow) async throws(DataError) {
        let locked: RoundRow
        do {
            let updated: [RoundRow] = try await client.from("rounds")
                .update(RoundStatusPatch(status: .locked))
                .eq("id", value: round.id)
                .select(Self.roundColumns)
                .execute().value
            guard let row = updated.first, row.status == .locked else { throw DataError.notAllowed }
            locked = row
        } catch {
            throw DataError.from(error)
        }
        // En kladd som låses, har aldri vært ute hos de andre.
        if RoundActivity.isLoggable(round.status),
           let event = RoundActivity.locked(locked, courseName: course(locked.courseID)?.course.name) {
            await activityLog.logQuietly(event, eventID: locked.eventID, roundID: locked.id)
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
        try? await loadRounds()
        try? await loadEvent()
        await loadActiveProgress()
    }
}

#if DEBUG
extension RundeAdminModel {
    /// Hvilken tilstand skjermprøven viser.
    enum SampleVariant {
        /// Alt er på plass, og kvelden i dag er ikke satt opp (`hurtigstart`, `arrangor`, `runder`).
        case tonight
        /// Kvelden i dag med én runde som går og én kladd (`kvelden`, `kveldene`).
        case liveEvening
        /// Ny klubb der banene og neste kveld mangler (`arrangorstart`).
        case gettingStarted
    }

    /// Oppdiktet kveld for skjermprøvene. Uten nett: en feilet henting beholder det som står.
    static func sample(_ variant: SampleVariant = .tonight) -> RundeAdminModel {
        let club = UUID()
        let client = SupabaseClient(supabaseURL: URL(string: "https://forhandsvisning.supabase.co")!,
                                    supabaseKey: "sb_publishable_forhandsvisning")
        let model = RundeAdminModel(context: ClubContext(client: client, user: .preview, membership: .preview))
        let names = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Gunnar", "Halvor", "Ivar", "Jon",
                     "Kåre", "Lars", "Magne", "Nils"]
        model.members = names.map {
            ClubMemberRow(id: UUID(), clubID: club, userID: UUID(), displayName: $0, handicapIndex: 12, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
        let season = SeasonRow(id: UUID(), clubID: club, name: "Høst 2026", status: .active, rules: .golfgutu)
        model.seasons = [season]
        let today = EveningDates.today()
        func later(_ days: Int) -> String {
            let date = EveningDates.date(from: today).flatMap { Calendar.current.date(byAdding: .day, value: days, to: $0) }
            return date.map(EveningDates.dateString) ?? today
        }
        func event(_ date: String) -> EventRow {
            EventRow(id: UUID(), clubID: club, seasonID: season.id, eventDate: date, startTime: "18:00:00",
                     venue: "Golfstudio Bryn", note: nil)
        }
        let earlier = event(later(-14))
        let tonight = event(today)
        let upcoming = [event(later(7)), event(later(14))]
        model.events = variant == .gettingStarted ? [earlier] : [earlier, tonight] + upcoming
        model.allEvents = model.events
        model.selectedEventID = variant == .gettingStarted ? nil : tonight.id
        if variant != .gettingStarted {
            model.signups = model.members.prefix(12).map {
                SignupRow(eventID: tonight.id, memberID: $0.id, clubID: club, status: .yes, comment: nil)
            } + [SignupRow(eventID: tonight.id, memberID: model.members[12].id, clubID: club, status: .maybe, comment: nil)]
        }
        let courses = ["Pebble Beach", "St Andrews Old Course", "Valderrama"].map { name in
            let row = CourseRow(id: UUID(), clubID: club, name: name, externalName: nil, courseRating: 72,
                                slopeRating: 128, inUse: true, confirmedBy: nil, confirmedAt: nil)
            let pars = [4, 5, 4, 4, 3, 5, 3, 4, 4, 4, 4, 3, 4, 5, 4, 4, 3, 5]
            let holes = pars.enumerated().map {
                CourseHoleRecord(courseID: row.id, holeNumber: $0.offset + 1, par: $0.element,
                                 strokeIndex: ($0.offset * 7) % 18 + 1, lengthM: nil)
            }
            return CourseListItem(course: row, holes: variant == .gettingStarted ? [] : holes)
        }
        model.allCourses = courses
        model.courses = courses.filter(\.isReady)
        func round(_ no: Int, on event: EventRow, course: Int, status: RoundStatus) -> RoundRow {
            RoundRow(id: UUID(), clubID: club, eventID: event.id, courseID: courses[course].id, roundNo: no, name: nil,
                     status: status, holeCount: 18, firstHole: 1, teeTime: "18:00:00", format: "stableford",
                     handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: true, ldHoleIndex: 17,
                     kpEnabled: true, kpHoleIndex: 6, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                     parConfirmedAt: nil, startedAt: nil, lockedAt: nil)
        }
        model.allRounds = [round(1, on: earlier, course: 0, status: .locked)]
        if variant == .liveEvening {
            let live = round(1, on: tonight, course: 1, status: .active)
            model.allRounds += [live, round(2, on: tonight, course: 2, status: .draft)]
            model.activeRound = live
            model.playersByRound[live.id] = model.members.prefix(12).enumerated().map { index, member in
                RoundPlayerRow(roundID: live.id, memberID: member.id, clubID: club, handicapIndex: 12, seedGroup: nil,
                               playingHandicap: 12, bayNo: index / 4 + 1, isMarker: index % 4 == 0, teamNo: nil)
            }
        }
        model.rounds = model.allRounds.filter { $0.eventID == model.selectedEventID }
        model.seasonRounds = model.allRounds
        model.state = .loaded
        return model
    }
}
#endif
