import Foundation
import GolfgutuCore
import Supabase

// Gjenbruk av oppsett (gjennomføringsplanen steg 8, sql/049): spilledager i serie, egne maler og
// «Samme som sist». Ren logikk uten SwiftUI og nettverk. Nøklene i malene er de samme som i web-admin
// (`web/admin/src/reuse.ts`) og i svaret fra `previous_round_setup`.

// MARK: - Serie av spilledager

/// Planen for en serie: ukedag (ISO, 1 = mandag), hver n-te uke, antall, starttid og sted.
/// Samme form som `schedule` i en turneringsmal.
nonisolated struct SeriesPlan: Codable, Equatable, Hashable, Sendable {
    var weekday: Int
    var everyWeeks: Int = 1
    var count: Int
    /// `HH:MM` (eller `HH:MM:SS`), eller nil.
    var startTime: String?
    var venue: String?

    static let weekdayRange = 1...7
    static let everyWeeksRange = 1...8
    static let countRange = 1...52

    enum CodingKeys: String, CodingKey {
        case weekday
        case everyWeeks = "every_weeks"
        case count
        case startTime = "start_time"
        case venue
    }

    init(weekday: Int, everyWeeks: Int = 1, count: Int, startTime: String? = nil, venue: String? = nil) {
        self.weekday = weekday
        self.everyWeeks = everyWeeks
        self.count = count
        self.startTime = startTime
        self.venue = venue
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weekday = min(7, max(1, (try? c.decodeIfPresent(Int.self, forKey: .weekday)) ?? 4))
        everyWeeks = min(8, max(1, (try? c.decodeIfPresent(Int.self, forKey: .everyWeeks)) ?? 1))
        count = min(52, max(1, (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 10))
        startTime = (try? c.decodeIfPresent(String.self, forKey: .startTime)) ?? nil
        venue = (try? c.decodeIfPresent(String.self, forKey: .venue)) ?? nil
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(everyWeeks, forKey: .everyWeeks)
        try c.encode(count, forKey: .count)
        try c.encode(startTime.flatMap(EventSeriesDates.shortTime), forKey: .startTime)
        try c.encode(venue.flatMap(EventSeriesDates.cleanVenue), forKey: .venue)
    }
}

/// Datoene i en serie, som `create_event_series` regner dem: første dato fra og med startdatoen med
/// riktig ukedag, så hver n-te uke. Datoer turneringen alt har, hoppes over.
nonisolated enum EventSeriesDates {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = utc.date(from: components), text(date) == String(string.prefix(10)) else { return nil }
        return date
    }

    private static func text(_ date: Date) -> String {
        let p = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }

    /// ISO-ukedagen (1 = mandag, 7 = søndag) for `YYYY-MM-DD`.
    static func isoWeekday(_ date: String) -> Int? {
        guard let d = day(date) else { return nil }
        let weekday = utc.component(.weekday, from: d)  // 1 = søndag
        return (weekday + 5) % 7 + 1
    }

    /// Første dato fra og med `start` med ukedagen (`p_first_date + ((p_weekday - isodow + 7) % 7)`).
    static func firstDate(onOrAfter start: String, weekday: Int) -> String? {
        guard let d = day(start), let iso = isoWeekday(start) else { return nil }
        let shift = ((weekday - iso) % 7 + 7) % 7
        return utc.date(byAdding: .day, value: shift, to: d).map(text)
    }

    /// Alle datoene i serien, `count` stykker, med `everyWeeks` ukers mellomrom.
    static func dates(start: String, weekday: Int, count: Int, everyWeeks: Int) -> [String] {
        guard SeriesPlan.weekdayRange.contains(weekday), count > 0, everyWeeks > 0,
              let first = firstDate(onOrAfter: start, weekday: weekday), let firstDay = day(first) else { return [] }
        return (0..<count).compactMap { i in
            utc.date(byAdding: .day, value: i * 7 * everyWeeks, to: firstDay).map(text)
        }
    }

    static func dates(start: String, plan: SeriesPlan) -> [String] {
        dates(start: start, weekday: plan.weekday, count: plan.count, everyWeeks: plan.everyWeeks)
    }

    /// Forhåndsvisningen: datoene som blir lagt inn, og de som hoppes over fordi turneringen alt har
    /// en dag den datoen.
    static func preview(start: String, plan: SeriesPlan, existing: Set<String>) -> (created: [String], skipped: [String]) {
        let all = dates(start: start, plan: plan)
        return (all.filter { !existing.contains($0) }, all.filter { existing.contains($0) })
    }

    /// `18:00:00` → `18:00`. Ugyldig gir nil.
    static func shortTime(_ string: String) -> String? {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// Trimmet sted, tomt blir nil.
    static func cleanVenue(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Tekstene for seriene.
nonisolated enum SeriesText {
    /// Ukedagene i ISO-rekkefølge (1 = mandag).
    static let weekdays = ["mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag", "søndag"]

    static func weekday(_ iso: Int) -> String {
        SeriesPlan.weekdayRange.contains(iso) ? weekdays[iso - 1] : ""
    }

    /// «Hver uke», «Annenhver uke», «Hver 3. uke».
    static func every(_ weeks: Int) -> String {
        switch weeks {
        case ...1: "Hver uke"
        case 2: "Annenhver uke"
        default: "Hver \(weeks). uke"
        }
    }

    /// «Hver torsdag kl. 18:00», «Annenhver tirsdag».
    static func summary(weekday iso: Int, everyWeeks: Int, startTime: String?) -> String {
        let day = weekday(iso)
        let head = switch everyWeeks {
        case ...1: "Hver \(day)"
        case 2: "Annenhver \(day)"
        default: "Hver \(everyWeeks). uke på \(day)"
        }
        return EveningDates.timeText(startTime).map { "\(head) kl. \($0)" } ?? head
    }

    /// «Hoppet over 3. og 10. september: turneringen har alt en dag da.»
    static func skippedDates(_ dates: [String]) -> String? {
        guard !dates.isEmpty else { return nil }
        return "Hoppet over \(NorwegianList.join(dates.map(EveningDates.dayMonthText))), som alt var i bruk."
    }

    /// Svaret etter «Lag serie».
    static func created(_ result: CreateSeriesResult) -> String {
        let made = result.dates.count
        var text = made == 0 ? "Ingen nye datoer ble lagt inn."
            : (made == 1 ? "1 dato er lagt inn." : "\(made) datoer er lagt inn.")
        if let skipped = skippedDates(result.skipped) { text += " " + skipped }
        return text
    }

    /// Svaret etter «Denne og fremtidige». nil når ingen ble hoppet over.
    static func updated(_ result: UpdateSeriesResult, dates: [UUID: String]) -> String? {
        guard !result.skipped.isEmpty else { return nil }
        let names = result.skipped.compactMap { dates[$0] }.sorted().map(EveningDates.dayMonthText)
        let list = names.isEmpty ? "\(result.skipped.count)" : NorwegianList.join(names)
        return "\(result.updated.count) endret. Ikke endret: \(list) (passert eller startet)."
    }
}

/// En serie (`event_series`).
nonisolated struct EventSeriesRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let competitionID: UUID
    var weekday: Int
    var everyWeeks: Int
    var firstDate: String
    var count: Int
    var startTime: String?
    var venue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case competitionID = "competition_id"
        case weekday
        case everyWeeks = "every_weeks"
        case firstDate = "first_date"
        case count
        case startTime = "start_time"
        case venue
    }

    static let columns = "id, competition_id, weekday, every_weeks, first_date, count, start_time, venue"

    var summary: String { SeriesText.summary(weekday: weekday, everyWeeks: everyWeeks, startTime: startTime) }
}

/// Svaret fra `create_event_series`.
nonisolated struct CreateSeriesResult: Decodable, Equatable, Sendable {
    let seriesID: UUID?
    let eventIDs: [UUID]
    let dates: [String]
    let skipped: [String]

    enum CodingKeys: String, CodingKey {
        case seriesID = "series_id"
        case eventIDs = "event_ids"
        case dates
        case skipped
    }
}

/// Svaret fra `update_event_series`.
nonisolated struct UpdateSeriesResult: Decodable, Equatable, Sendable {
    let updated: [UUID]
    let skipped: [UUID]
    let shiftedDays: Int

    enum CodingKeys: String, CodingKey {
        case updated
        case skipped
        case shiftedDays = "shifted_days"
    }
}

/// «Bare denne» eller «Denne og fremtidige».
nonisolated enum SeriesScope: String, CaseIterable, Sendable {
    case one
    case future

    var title: String {
        switch self {
        case .one: "Bare denne"
        case .future: "Denne og fremtidige"
        }
    }
}

// MARK: - Maler

nonisolated enum TemplateKind: String, Codable, Sendable {
    case round
    case tournament
}

/// En lagret mal (`setup_templates`). Innholdet tolkes av `RoundTemplatePayload` eller
/// `TournamentTemplatePayload`.
nonisolated struct SetupTemplateRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID?
    let ownerID: UUID?
    let kind: TemplateKind
    var name: String
    var payload: AnyJSON
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case ownerID = "owner_id"
        case kind
        case name
        case payload
        case updatedAt = "updated_at"
    }

    static let columns = "id, club_id, owner_id, kind, name, payload, updated_at"

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Malnavn: 1–60 tegn, trimmet (`setup_template_save`).
nonisolated enum TemplateName {
    static let max = 60

    static func clean(_ raw: String) -> Result<String, DataError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.invalid("Gi malen et navn.")) }
        if name.count > max { return .failure(.invalid("Navnet kan ha høyst \(max) tegn.")) }
        return .success(name)
    }
}

/// Et spill på runden (`round_games`): typen og innstillingene.
nonisolated struct TemplateGame: Codable, Equatable, Sendable {
    var kind: String
    var settings: AnyJSON

    init(kind: String, settings: AnyJSON = .object([:])) {
        self.kind = kind
        self.settings = settings
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        settings = (try? c.decodeIfPresent(AnyJSON.self, forKey: .settings)) ?? .object([:])
    }
}

/// Oppsettet for en runde: innholdet i en rundemal, og rundedelen av `previous_round_setup`.
/// Nøklene som i `rounds`. Mangler en nøkkel, gjelder standarden. Spillerne er aldri med i en mal.
nonisolated struct RoundTemplatePayload: Codable, Equatable, Sendable {
    var version = 1
    var courseID: UUID?
    var teeID: UUID?
    var holeCount = 18
    var firstHole = 1
    var format: String?
    var handicapAllowance: Double?
    var externalHandicap: Bool?
    var venue: String?
    var ldEnabled: Bool?
    var ldHoleIndex: Int?
    var kpEnabled: Bool?
    var kpHoleIndex: Int?
    var weight: Double = 1
    var counts = true
    var pointsTable: String?
    var hideLastHoles = 0
    var games: [TemplateGame] = []

    enum CodingKeys: String, CodingKey {
        case version
        case courseID = "course_id"
        case teeID = "tee_id"
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case format
        case handicapAllowance = "handicap_allowance"
        case externalHandicap = "external_handicap"
        case venue
        case ldEnabled = "ld_enabled"
        case ldHoleIndex = "ld_hole_index"
        case kpEnabled = "kp_enabled"
        case kpHoleIndex = "kp_hole_index"
        case weight
        case counts
        case pointsTable = "points_table"
        case hideLastHoles = "hide_last_holes"
        case games
    }

    init() {}

    /// Oppsettet slik kladden står (uten spillere).
    init(draft: RoundDraft) {
        courseID = draft.courseID
        teeID = draft.teeID
        holeCount = draft.holeCount
        firstHole = draft.firstHole
        format = draft.formID
        handicapAllowance = (draft.allowance * 1000).rounded() / 1000
        externalHandicap = draft.externalHandicap
        venue = draft.venue.rawValue
        ldEnabled = draft.ldEnabled
        ldHoleIndex = draft.ldHoleIndex
        kpEnabled = draft.kpEnabled
        kpHoleIndex = draft.kpHoleIndex
        weight = draft.weight
        counts = draft.counts
        pointsTable = draft.pointsTable
        hideLastHoles = draft.hidesLastHoles ? RoundDraft.hiddenHoleCount : 0
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        version = value(.version) ?? 1
        courseID = value(.courseID)
        teeID = value(.teeID)
        holeCount = value(.holeCount) ?? 18
        firstHole = value(.firstHole) ?? 1
        format = value(.format)
        handicapAllowance = value(.handicapAllowance)
        externalHandicap = value(.externalHandicap)
        venue = value(.venue)
        ldEnabled = value(.ldEnabled)
        ldHoleIndex = value(.ldHoleIndex)
        kpEnabled = value(.kpEnabled)
        kpHoleIndex = value(.kpHoleIndex)
        weight = value(.weight) ?? 1
        counts = value(.counts) ?? true
        pointsTable = value(.pointsTable)
        hideLastHoles = value(.hideLastHoles) ?? 0
        games = value(.games) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(courseID, forKey: .courseID)
        try c.encode(teeID, forKey: .teeID)
        try c.encode(holeCount, forKey: .holeCount)
        try c.encode(firstHole, forKey: .firstHole)
        try c.encode(format, forKey: .format)
        try c.encode(handicapAllowance, forKey: .handicapAllowance)
        try c.encode(externalHandicap, forKey: .externalHandicap)
        try c.encode(venue, forKey: .venue)
        try c.encode(ldEnabled, forKey: .ldEnabled)
        try c.encode(ldHoleIndex, forKey: .ldHoleIndex)
        try c.encode(kpEnabled, forKey: .kpEnabled)
        try c.encode(kpHoleIndex, forKey: .kpHoleIndex)
        try c.encode(weight, forKey: .weight)
        try c.encode(counts, forKey: .counts)
        try c.encode(pointsTable, forKey: .pointsTable)
        try c.encode(hideLastHoles, forKey: .hideLastHoles)
        try c.encode(games, forKey: .games)
    }

    /// Fyller inn oppsettet i kladden: sted, form og andel, vekt, tabellreglene, sidepremiene og banen.
    /// Banen tas bare når den fortsatt er klar (som `QuickStart.applySuggestion`), og en form som ikke
    /// er tillatt i regelsettet, hoppes over. Spillerne røres ikke, men lag og matcher legges på nytt
    /// når formen skifter.
    func apply(to draft: inout RoundDraft, courses: [CourseListItem], rules: Ruleset, roster: [ClubMemberRow],
               plan: MatchDrawPlan = .standings) {
        draft.setVenue(Venue(stored: venue), rules: rules)
        if let externalHandicap { draft.externalHandicap = externalHandicap }
        if let format, format != draft.formID, rules.formats.allowedFormIDs.contains(format) {
            draft.setForm(format, rules: rules, roster: roster, plan: plan)
        }
        if let handicapAllowance, format == nil || format == draft.formID { draft.allowance = handicapAllowance }
        draft.weight = weight
        draft.counts = counts
        draft.pointsTable = pointsTable.flatMap { rules.table.pointsTables[$0] == nil ? nil : $0 }
        draft.hidesLastHoles = hideLastHoles > 0
        if let ldEnabled { draft.ldEnabled = ldEnabled }
        if let kpEnabled { draft.kpEnabled = kpEnabled }
        guard let course = courses.first(where: { $0.id == courseID && $0.isReady }) else { return }
        draft.courseID = course.id
        draft.teeID = course.tee(teeID)?.id
        draft.holeCount = holeCount == 9 ? 9 : 18
        draft.firstHole = RoundDraft.canStartAtTen(holeCount: draft.holeCount, courseHoles: course.holeCount)
            ? firstHole : 1
        draft.ldHoleIndex = ldHoleIndex.flatMap { $0 < draft.holeCount ? $0 : nil }
        draft.kpHoleIndex = kpHoleIndex.flatMap { $0 < draft.holeCount ? $0 : nil }
    }
}

/// Svaret fra `previous_round_setup(kveld)`: oppsettet fra forrige startede runde i turneringen, med
/// spillerne, matchene og spillene som forslag.
nonisolated struct PreviousRoundSetup: Decodable, Equatable, Sendable {
    struct Player: Decodable, Equatable, Sendable {
        let memberID: UUID
        let bayNo: Int?
        let isMarker: Bool
        let teamNo: Int?

        enum CodingKeys: String, CodingKey {
            case memberID = "member_id"
            case bayNo = "bay_no"
            case isMarker = "is_marker"
            case teamNo = "team_no"
        }
    }

    struct Match: Decodable, Equatable, Sendable {
        let matchNo: Int
        let playerA: UUID?
        let playerB: UUID?
        let playerC: UUID?
        let teamA: Int?
        let teamB: Int?

        enum CodingKeys: String, CodingKey {
            case matchNo = "match_no"
            case playerA = "player_a"
            case playerB = "player_b"
            case playerC = "player_c"
            case teamA = "team_a"
            case teamB = "team_b"
        }
    }

    let roundID: UUID
    let eventDate: String
    let roundNo: Int
    let setup: RoundTemplatePayload
    let players: [Player]
    let matches: [Match]

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case eventDate = "event_date"
        case roundNo = "round_no"
        case players
        case matches
    }

    init(roundID: UUID, eventDate: String, roundNo: Int, setup: RoundTemplatePayload, players: [Player],
         matches: [Match]) {
        self.roundID = roundID
        self.eventDate = eventDate
        self.roundNo = roundNo
        self.setup = setup
        self.players = players
        self.matches = matches
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roundID = try c.decode(UUID.self, forKey: .roundID)
        eventDate = try c.decode(String.self, forKey: .eventDate)
        roundNo = try c.decode(Int.self, forKey: .roundNo)
        setup = try RoundTemplatePayload(from: decoder)
        players = (try? c.decodeIfPresent([Player].self, forKey: .players)) ?? []
        matches = (try? c.decodeIfPresent([Match].self, forKey: .matches)) ?? []
    }

    /// «Fra torsdag 8. oktober, runde 2 · 12 spillere».
    var sourceText: String {
        "Fra \(EveningDates.longText(eventDate)), runde \(roundNo) · \(players.count) spillere"
    }

    /// Samme spillere, grupper, lag og matcher som sist. Bare de som fortsatt er i troppen, i troppens
    /// rekkefølge. Lag bare i en lagform, og matchene bare når alle i dem er med.
    func applyPlayers(to draft: inout RoundDraft, roster: [ClubMemberRow]) {
        let active = Set(roster.map(\.id))
        let own = players.filter { active.contains($0.memberID) }
        let wanted = Set(own.map(\.memberID))
        draft.participants = roster.map(\.id).filter { wanted.contains($0) }
        draft.participantSource = .saved
        let order = Dictionary(uniqueKeysWithValues: draft.participants.enumerated().map { ($1, $0) })
        draft.bays = BayPlan(seats: own
            .compactMap { p in p.bayNo.map { BaySeat(memberID: p.memberID, bay: $0, isMarker: p.isMarker) } }
            .sorted { (order[$0.memberID] ?? .max) < (order[$1.memberID] ?? .max) })
        var teams: [UUID: Int] = [:]
        if draft.form.isTeamForm {
            for p in own { if let team = p.teamNo { teams[p.memberID] = team } }
        }
        draft.teams = teams
        draft.matches = matches.sorted { $0.matchNo < $1.matchNo }.compactMap { m in
            let isTeam = m.teamA != nil && m.teamB != nil
            if isTeam { return draft.form.isTeamForm ? MatchDraft(teamA: m.teamA, teamB: m.teamB) : nil }
            let people = [m.playerA, m.playerB, m.playerC].compactMap { $0 }
            guard people.count >= 2, people.allSatisfy(wanted.contains) else { return nil }
            return MatchDraft(playerA: m.playerA, playerB: m.playerB, playerC: m.playerC)
        }
    }
}

/// Innholdet i en turneringsmal: oppsettet (kortet i «Ny turnering»), typen, regelsettet og planen
/// for spilledagene.
nonisolated struct TournamentTemplatePayload: Codable, Equatable, Sendable {
    var version = 1
    /// Kortet i steg 1 (`RulesetTemplate`).
    var template: RulesetTemplate
    /// `competitions.kind`: season, league, cup eller fun.
    var kind: CompetitionKind
    var rules: Ruleset
    var schedule: SeriesPlan?
    var venue: String?
    var entry: CompetitionEntry?
    var signupOpen: Bool?
    var maxEntrants: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case template
        case kind
        case rules
        case schedule
        case venue
        case entry
        case signupOpen = "signup_open"
        case maxEntrants = "max_entrants"
    }

    init(template: RulesetTemplate, kind: CompetitionKind, rules: Ruleset, schedule: SeriesPlan? = nil,
         venue: String? = nil, entry: CompetitionEntry? = nil, signupOpen: Bool? = nil, maxEntrants: Int? = nil) {
        self.template = template
        self.kind = kind
        self.rules = rules
        self.schedule = schedule
        self.venue = venue
        self.entry = entry
        self.signupOpen = signupOpen
        self.maxEntrants = maxEntrants
    }

    /// Malen fra utkastet i «Ny turnering».
    init(draft: TournamentDraft) {
        let kind = draft.target.kind
        let rules = switch draft.target {
        case .season: draft.seasonRules
        case .competition: draft.competitionDraft.rules(main: nil)
        }
        self.init(template: draft.template, kind: kind, rules: rules, schedule: draft.schedule,
                  venue: draft.schedule?.venue,
                  entry: kind == .season ? nil : draft.competition.entry,
                  signupOpen: kind == .season ? nil : draft.competition.signupOpen)
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        version = value(.version) ?? 1
        let kind: CompetitionKind? = value(.kind)
        let template = value(.template) ?? Self.template(for: kind ?? .season)
        self.template = template
        self.kind = kind ?? TournamentSetup.target(template, clubID: UUID()).kind
        rules = value(.rules) ?? template.rules
        schedule = value(.schedule)
        venue = value(.venue)
        entry = value(.entry)
        signupOpen = value(.signupOpen)
        maxEntrants = value(.maxEntrants)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(template, forKey: .template)
        try c.encode(kind, forKey: .kind)
        try c.encode(rules, forKey: .rules)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(venue, forKey: .venue)
        try c.encode(entry, forKey: .entry)
        try c.encode(signupOpen, forKey: .signupOpen)
        try c.encode(maxEntrants, forKey: .maxEntrants)
    }

    /// Kortet for en type når malen bare har typen (fra web-admin eller en eldre mal).
    static func template(for kind: CompetitionKind) -> RulesetTemplate {
        switch kind {
        case .cup: .cup
        case .fun: .fun
        case .league: .stablefordSeries
        case .season, .game: .matchSeries
        }
    }

    /// Utkastet i «Ny turnering» fra malen, med navnet som er foreslått.
    func draft(name: String, clubID: UUID?, today: String) -> TournamentDraft {
        var draft = TournamentDraft(template: template, clubID: clubID, name: name, today: today)
        draft.rules = rules
        if let term = rules.dayTerm { draft.dayTerm = term }
        if let competition = rules.competition {
            draft.competition.league = competition.league
            draft.competition.fun = competition.fun
            draft.competition.cup = competition.cup
        }
        if let entry, draft.competition.entryOptions.contains(entry) { draft.competition.entry = entry }
        if let signupOpen { draft.competition.signupOpen = signupOpen }
        draft.competition.normalize()
        draft.schedule = clubID == nil ? nil : schedule
        return draft
    }
}
