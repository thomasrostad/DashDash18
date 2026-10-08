import Foundation
import GolfgutuCore

/// Alt oppsettet holder på for én runde, før det lagres. Rådata som i `rounds` og `round_players`.
nonisolated struct RoundDraft: Equatable, Sendable {
    /// Lages i appen for en ny runde, så et nytt forsøk etter en feil treffer samme rad (upsert på id).
    let roundID: UUID
    /// Finnes raden i databasen?
    var isSaved: Bool
    var eventID: UUID
    var roundNo: Int
    var courseID: UUID?
    var holeCount: Int
    /// 1, eller 10 for siste ni på en 18-hullsbane.
    var firstHole: Int
    /// `HH:MM:SS`, eller nil.
    var teeTime: String?
    /// De som er med, i troppens rekkefølge.
    var participants: [UUID]
    var participantSource: RoundParticipants.Source
    var bays: BayPlan
    var formID: String
    /// Lagnummer per spiller (bare i lagformer).
    var teams: [UUID: Int]
    var matches: [MatchDraft]
    var ldEnabled: Bool
    /// Rundens 0-baserte hull. `nil` = forslaget.
    var ldHoleIndex: Int?
    var kpEnabled: Bool
    var kpHoleIndex: Int?
    var weight: Double
    var externalHandicap: Bool
    var allowance: Double
    /// Simulator eller ekte bane. Lagres bare når `VenueFeature` er på.
    var venue: Venue = .simulator

    var form: CompetitionForm { CompetitionForm.form(id: formID) }

    /// Siste ni kan bare spilles som 9 hull på en 18-hullsbane.
    static func canStartAtTen(holeCount: Int, courseHoles: Int?) -> Bool {
        holeCount == 9 && courseHoles == 18
    }

    /// Ny runde med regelsettets standardverdier.
    static func new(eventID: UUID, roundNo: Int, teeTime: String?, participants: [UUID],
                    source: RoundParticipants.Source, rules: Ruleset) -> RoundDraft {
        let form = CompetitionForm.form(id: rules.formats.defaultFormID)
        let bays = BayPlan.suggested(participants: participants,
                                     bays: BayPlan.defaultBayCount(players: participants.count, maxPerBay: rules.formats.maxPerBay))
        return RoundDraft(
            roundID: UUID(), isSaved: false, eventID: eventID, roundNo: roundNo, courseID: nil, holeCount: 18, firstHole: 1,
            teeTime: teeTime, participants: participants, participantSource: source, bays: bays,
            formID: form.id, teams: [:], matches: [],
            ldEnabled: rules.sidePrizes.longestDrive.enabled, ldHoleIndex: nil,
            kpEnabled: rules.sidePrizes.closestToPin.enabled, kpHoleIndex: nil,
            weight: 1, externalHandicap: rules.handicap.externalHandicap, allowance: rules.allowance(for: form)
        )
    }

    /// Kladden slik den er lagret.
    static func saved(_ round: RoundRow, players: [RoundPlayerRow], matches: [RoundMatchRow],
                      participants: [UUID], source: RoundParticipants.Source) -> RoundDraft {
        let order = Dictionary(uniqueKeysWithValues: participants.enumerated().map { ($1, $0) })
        let seats = players
            .compactMap { p in p.bayNo.map { BaySeat(memberID: p.memberID, bay: $0, isMarker: p.isMarker) } }
            .sorted { (order[$0.memberID] ?? .max) < (order[$1.memberID] ?? .max) }
        var teams: [UUID: Int] = [:]
        for p in players { if let t = p.teamNo { teams[p.memberID] = t } }
        // Arrangørsiden henter bare klubbens runder, og de har alltid en kveld (`rounds_home_check`,
        // sql/017). Mangler den likevel, avviser databasen lagringen (fremmednøkkelen til kvelden).
        return RoundDraft(
            roundID: round.id, isSaved: true, eventID: round.eventID ?? UUID(), roundNo: round.roundNo,
            courseID: round.courseID,
            holeCount: round.holeCount, firstHole: round.firstHole, teeTime: round.teeTime,
            participants: participants, participantSource: source, bays: BayPlan(seats: seats),
            formID: round.format, teams: teams,
            matches: matches.sorted { $0.matchNo < $1.matchNo }.map(MatchDraft.init),
            ldEnabled: round.ldEnabled, ldHoleIndex: round.ldHoleIndex,
            kpEnabled: round.kpEnabled, kpHoleIndex: round.kpHoleIndex,
            weight: round.weight, externalHandicap: round.externalHandicap, allowance: round.handicapAllowance,
            venue: Venue(stored: round.venue)
        )
    }

    /// Ordet for gruppene: «bås» i simulatoren, «flight» på ekte bane.
    var groupTerm: GroupTerm { .for(venue) }

    /// Bytter mellom simulator og ekte bane. Trackman deler bare ut slag i simulatoren, så på ekte bane
    /// fører dere brutto; tilbake i simulatoren gjelder regelsettets valg igjen.
    mutating func setVenue(_ venue: Venue, rules: Ruleset) {
        guard venue != self.venue else { return }
        self.venue = venue
        externalHandicap = venue == .simulator ? rules.handicap.externalHandicap : false
    }

    /// Lag og matcher klare for oppsettet (`handleStartRunde`): forslag til lag i en lagform uten lag,
    /// og matchene trekkes på nytt når de lagrede ikke kan stå med de som er med.
    mutating func prepareSetup(rules: Ruleset, roster: [ClubMemberRow]) {
        if form.isTeamForm && teams.isEmpty {
            teams = TeamPlanner.suggested(participants: participants, form: form, maxPerBay: rules.formats.maxPerBay)
        }
        if !MatchPlanner.canKeep(matches, participants: participants, teams: teams, isTeamForm: form.isTeamForm) {
            redrawMatches(roster: roster)
        }
    }

    /// Runden slik regelmotoren ser den: for forslag til LD- og KP-hull og for spillehandicap.
    func coreRound(course: Course?) -> Round {
        Round(
            id: roundID.uuidString, gameType: formID, holeCount: holeCount,
            holeStart: firstHole == 10 ? 9 : 0, course: course, hcpAllowance: allowance,
            hcpExtern: externalHandicap,
            teams: form.isTeamForm ? Dictionary(uniqueKeysWithValues: teams.map { ($0.key.uuidString, $0.value) }) : [:],
            ldEnabled: ldEnabled, kpEnabled: kpEnabled, ldHoleIndex: ldHoleIndex, kpHoleIndex: kpHoleIndex,
            weight: weight
        )
    }

    /// Hullet som lagres for longest drive: det valgte, ellers forslaget. Lagres også når premien er av,
    /// så det står klart om den slås på igjen (som PWA-en).
    func ldHole(course: Course?) -> Int {
        ldHoleIndex.flatMap { $0 < holeCount ? $0 : nil } ?? SidePrizes.suggestedLongestDriveHole(coreRound(course: course))
    }

    func kpHole(course: Course?) -> Int {
        kpHoleIndex.flatMap { $0 < holeCount ? $0 : nil } ?? SidePrizes.suggestedClosestToPinHole(coreRound(course: course))
    }

    /// Skifter form: ny andel fra regelsettet, og lag og matcher legges på nytt.
    mutating func setForm(_ id: String, rules: Ruleset, roster: [ClubMemberRow]) {
        formID = id
        allowance = rules.allowance(for: form)
        if form.isTeamForm {
            teams = TeamPlanner.suggested(participants: participants, form: form, maxPerBay: rules.formats.maxPerBay)
        } else {
            teams = [:]
        }
        redrawMatches(roster: roster)
    }

    /// Trekker matchene på nytt: lag mot lag i lagformer, `trekkMatcher` ellers.
    mutating func redrawMatches(roster: [ClubMemberRow]) {
        if form.isTeamForm {
            matches = MatchPlanner.teamMatches(teams.filter { participants.contains($0.key) })
        } else {
            let included = Set(participants)
            matches = MatchPlanner.drawIndividual(roster.filter { included.contains($0.id) })
        }
    }

    /// Fordeler båsene på nytt, med duellpartnerne samlet.
    mutating func reshuffleBays(count: Int) {
        let groups = matches.map { $0.members(teams: teams) }
        bays = BayPlan.suggested(participants: participants, matchGroups: groups, bays: count)
    }

    /// Tar med en spiller: inn i båsen med færrest.
    mutating func include(_ memberID: UUID, roster: [ClubMemberRow]) {
        guard !participants.contains(memberID) else { return }
        let wanted = Set(participants + [memberID])
        participants = roster.map(\.id).filter { wanted.contains($0) }
        bays.add(memberID)
    }

    /// Tar ut en spiller fra runden, båsen, laget og matchene han sto i.
    mutating func exclude(_ memberID: UUID) {
        participants.removeAll { $0 == memberID }
        bays.move(memberID, to: nil)
        teams[memberID] = nil
        matches.removeAll { !$0.isTeamMatch && $0.members().contains(memberID) }
    }
}

// MARK: - Sjekk før lagring og start

nonisolated enum RoundSetupIssue: Equatable, Sendable {
    case noCourse
    case courseNotReady(String)
    case tooFewPlayers
    case bayWithoutMarker([Int])
    case formNotAllowed(String)
    case formNotSupported(String)
    case teams(String)
    case matches([String])
    case sidePrizeOutsideRound(Int)

    /// Meldingen med rundens ord for gruppene (bås / flight).
    func message(_ term: GroupTerm) -> String {
        switch self {
        case .noCourse:
            "Velg en bane. Uten kjenner ikke appen parene."
        case .courseNotReady(let name):
            "\(name) har ikke par på alle hull. Legg inn tallene under Banene først."
        case .tooFewPlayers:
            "Det må være minst to spillere med."
        case .bayWithoutMarker(let bays):
            "\(term.numberedList(bays)) har ingen markør."
        case .formNotAllowed(let name):
            "\(name) er ikke tillatt i sesongens regelsett."
        case .formNotSupported(let name):
            "\(name) kan ikke føres i appen ennå. Velg en annen form."
        case .teams(let text):
            text
        case .matches(let problems):
            problems.joined(separator: " ")
        case .sidePrizeOutsideRound(let holes):
            "Longest drive og nærmest pinnen må ligge innenfor de \(holes) hullene."
        }
    }
}

nonisolated enum RoundSetupCheck {
    /// Færrest spillere en runde kan startes med. Ingen regelverdi: det er det minste en
    /// konkurranse trenger, og det samme som «Kom i gang» på arrangørsiden krever av troppen.
    static let minimumPlayers = 2

    /// Det som stopper en lagring. En kladd trenger en bane som er klar og en form som går an;
    /// start krever i tillegg minst to spillere, markør i hver bås, lag som går opp og gyldige matcher.
    static func issues(_ draft: RoundDraft, course: CourseListItem?, rules: Ruleset, roster: [ClubMemberRow],
                       forStart: Bool) -> [RoundSetupIssue] {
        var issues: [RoundSetupIssue] = []
        if let course {
            if !course.isReady { issues.append(.courseNotReady(course.course.name)) }
        } else {
            issues.append(.noCourse)
        }

        let form = draft.form
        if !rules.formats.allowedFormIDs.contains(form.id) { issues.append(.formNotAllowed(form.name)) }
        if form.support == .missing { issues.append(.formNotSupported(form.name)) }

        if let ld = draft.ldHoleIndex, ld >= draft.holeCount { issues.append(.sidePrizeOutsideRound(draft.holeCount)) }
        else if let kp = draft.kpHoleIndex, kp >= draft.holeCount { issues.append(.sidePrizeOutsideRound(draft.holeCount)) }

        guard forStart else { return issues }

        if draft.participants.count < minimumPlayers { issues.append(.tooFewPlayers) }
        let included = Set(draft.participants)
        var bays = draft.bays
        bays.keepOnly(included)
        let missing = bays.baysWithoutMarker
        if !missing.isEmpty { issues.append(.bayWithoutMarker(missing)) }

        if form.isTeamForm,
           let problem = TeamPlanner.problem(teams: draft.teams, participants: draft.participants, form: form,
                                             maxPerBay: rules.formats.maxPerBay) {
            issues.append(.teams(problem))
        }
        let names = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.displayName) })
        let problems = MatchPlanner.problems(draft.matches, participants: draft.participants, teams: draft.teams, names: names)
        if !problems.isEmpty { issues.append(.matches(problems)) }
        return issues
    }
}

// MARK: - Det som sendes

/// Raden i `rounds`. Feltene oppsettet eier; status settes for seg (se `RoundStatusPatch`).
/// Tomme felt sendes som null, så de også tømmes ved endring. Skrives med upsert på id.
nonisolated struct RoundWrite: Encodable, Equatable, Sendable {
    let id: UUID
    let clubID: UUID
    let eventID: UUID
    let roundNo: Int
    let courseID: UUID?
    let holeCount: Int
    let firstHole: Int
    let teeTime: String?
    let format: String
    let handicapAllowance: Double
    let externalHandicap: Bool
    let weight: Double
    let ldEnabled: Bool
    let ldHoleIndex: Int
    let kpEnabled: Bool
    let kpHoleIndex: Int
    /// `simulator` / `course`, eller nil når `VenueFeature` er av.
    let venue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case eventID = "event_id"
        case roundNo = "round_no"
        case courseID = "course_id"
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case teeTime = "tee_time"
        case format
        case handicapAllowance = "handicap_allowance"
        case externalHandicap = "external_handicap"
        case weight
        case ldEnabled = "ld_enabled"
        case ldHoleIndex = "ld_hole_index"
        case kpEnabled = "kp_enabled"
        case kpHoleIndex = "kp_hole_index"
        case venue
    }

    init(draft: RoundDraft, clubID: UUID, course: Course?, includeVenue: Bool = VenueFeature.isEnabled) {
        id = draft.roundID
        self.clubID = clubID
        eventID = draft.eventID
        roundNo = draft.roundNo
        courseID = draft.courseID
        holeCount = draft.holeCount
        // Databasen tillater bare hull 10 for 9 hull (`rounds_first_hole_check`).
        firstHole = draft.holeCount == 9 && draft.firstHole == 10 ? 10 : 1
        teeTime = draft.teeTime
        format = draft.formID
        // numeric(4,3): tre desimaler, så et steg på 0,05 ikke blir 0,9500000001.
        handicapAllowance = (draft.allowance * 1000).rounded() / 1000
        externalHandicap = draft.externalHandicap
        weight = draft.weight
        ldEnabled = draft.ldEnabled
        ldHoleIndex = draft.ldHole(course: course)
        kpEnabled = draft.kpEnabled
        kpHoleIndex = draft.kpHole(course: course)
        venue = includeVenue ? draft.venue.rawValue : nil
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(clubID, forKey: .clubID)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(roundNo, forKey: .roundNo)
        try c.encode(courseID, forKey: .courseID)
        try c.encode(holeCount, forKey: .holeCount)
        try c.encode(firstHole, forKey: .firstHole)
        try c.encode(teeTime, forKey: .teeTime)
        try c.encode(format, forKey: .format)
        try c.encode(handicapAllowance, forKey: .handicapAllowance)
        try c.encode(externalHandicap, forKey: .externalHandicap)
        try c.encode(weight, forKey: .weight)
        try c.encode(ldEnabled, forKey: .ldEnabled)
        try c.encode(ldHoleIndex, forKey: .ldHoleIndex)
        try c.encode(kpEnabled, forKey: .kpEnabled)
        try c.encode(kpHoleIndex, forKey: .kpHoleIndex)
        // Kolonnen finnes først etter sql/015. Uten flagget sendes den ikke.
        try c.encodeIfPresent(venue, forKey: .venue)
    }
}

nonisolated struct RoundStatusPatch: Encodable, Sendable {
    let status: RoundStatus
}

/// Parameterne til `set_round_setup(p_round_id, p_players, p_matches)` og
/// `start_round(p_round_id, p_players, p_matches)`.
nonisolated struct RoundSetupParams: Encodable, Equatable, Sendable {
    struct PlayerEntry: Encodable, Equatable, Sendable {
        let memberID: UUID
        let bayNo: Int?
        let isMarker: Bool
        let teamNo: Int?
        let playingHandicap: Int?

        enum CodingKeys: String, CodingKey {
            case memberID = "member_id"
            case bayNo = "bay_no"
            case isMarker = "is_marker"
            case teamNo = "team_no"
            case playingHandicap = "playing_handicap"
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(memberID, forKey: .memberID)
            try c.encode(bayNo, forKey: .bayNo)
            try c.encode(isMarker, forKey: .isMarker)
            try c.encode(teamNo, forKey: .teamNo)
            try c.encode(playingHandicap, forKey: .playingHandicap)
        }
    }

    struct MatchEntry: Encodable, Equatable, Sendable {
        let matchNo: Int
        let playerA: UUID?
        let playerB: UUID?
        let playerC: UUID?
        let teamA: Int?
        let teamB: Int?
        let result: String?

        enum CodingKeys: String, CodingKey {
            case matchNo = "match_no"
            case playerA = "player_a"
            case playerB = "player_b"
            case playerC = "player_c"
            case teamA = "team_a"
            case teamB = "team_b"
            case result
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(matchNo, forKey: .matchNo)
            try c.encode(playerA, forKey: .playerA)
            try c.encode(playerB, forKey: .playerB)
            try c.encode(playerC, forKey: .playerC)
            try c.encode(teamA, forKey: .teamA)
            try c.encode(teamB, forKey: .teamB)
            try c.encode(result, forKey: .result)
        }
    }

    let roundID: UUID
    let players: [PlayerEntry]
    let matches: [MatchEntry]

    enum CodingKeys: String, CodingKey {
        case roundID = "p_round_id"
        case players = "p_players"
        case matches = "p_matches"
    }

    /// Bygger hele oppsettet for runden. Spillere utenfor troppen tas ikke med.
    /// - Parameter withPlayingHandicap: ved start regnes spillehandicapet med `effectiveHandicap`
    ///   og lagres som rundens fasit (beslutning). I en kladd sendes null.
    static func make(roundID: UUID, draft: RoundDraft, roster: [ClubMemberRow], course: Course?,
                     rules: Ruleset, withPlayingHandicap: Bool) -> RoundSetupParams {
        let byID = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        let ids = draft.participants.filter { byID[$0] != nil }
        let included = Set(ids)
        var bays = draft.bays
        bays.keepOnly(included)
        let isTeamForm = draft.form.isTeamForm

        let corePlayers = ids.map { id in
            let m = byID[id]!
            return Player(id: id.uuidString, name: m.displayName, handicap: m.handicapIndex, seedGroup: m.seedGroup)
        }
        let round = draft.coreRound(course: course)

        let players = zip(ids, corePlayers).map { id, player in
            let seat = bays.seat(for: id)
            let handicap = withPlayingHandicap
                ? Int(rules.effectiveHandicap(for: player, in: round, roster: corePlayers))
                : nil
            return PlayerEntry(memberID: id, bayNo: seat?.bay, isMarker: seat?.isMarker ?? false,
                               teamNo: isTeamForm ? draft.teams[id] : nil, playingHandicap: handicap)
        }
        let matches = draft.matches.enumerated().map { i, m in
            MatchEntry(matchNo: i + 1, playerA: m.isTeamMatch ? nil : m.playerA, playerB: m.isTeamMatch ? nil : m.playerB,
                       playerC: m.isTeamMatch ? nil : m.playerC, teamA: m.isTeamMatch ? m.teamA : nil,
                       teamB: m.isTeamMatch ? m.teamB : nil, result: m.isTriangle ? nil : m.result)
        }
        return RoundSetupParams(roundID: roundID, players: players, matches: matches)
    }
}

// MARK: - Visning og sletting

nonisolated enum RoundListing {
    /// Linja under runden i lista: «18 hull · Stableford · 12 med · 3 båser · 18:00».
    static func subtitle(_ round: RoundRow, players: Int, bays: Int) -> String {
        var parts = ["\(round.holeCount) hull" + (round.firstHole == 10 ? " fra hull 10" : "")]
        parts.append(CompetitionForm.form(id: round.format).name)
        if players > 0 { parts.append("\(players) med") }
        if bays > 0 { parts.append(GroupTerm.for(stored: round.venue).count(bays)) }
        if let tee = EveningDates.timeText(round.teeTime) { parts.append(tee) }
        return parts.joined(separator: " · ")
    }

    /// «Runde 2 – Pebble Beach». Nummeret er rundens nummer på kvelden.
    static func title(roundNo: Int, courseName: String?) -> String {
        "Runde \(roundNo)" + (courseName.map { " – \($0)" } ?? "")
    }

    static func statusText(_ status: RoundStatus) -> String {
        switch status {
        case .draft: "Kladd"
        case .active: "Pågår"
        case .locked: "Låst"
        }
    }

    /// Neste ledige rundenummer på kvelden.
    static func nextRoundNo(existing: [RoundRow]) -> Int {
        (existing.map(\.roundNo).max() ?? 0) + 1
    }

    /// Kvelden som står for tur i lista (`nextScheduleEntry`), ellers den siste.
    static func defaultEvent(_ events: [EventRow], today: String, finished: Set<UUID>) -> EventRow? {
        NextEvening.next(in: events, today: today, finished: finished) ?? events.max { $0.eventDate < $1.eventDate }
    }

    /// Regelsettet for kvelden: kveldens sesong, så den aktive, ellers Golfgutu-oppsettet.
    static func rules(for event: EventRow?, seasons: [SeasonRow]) -> Ruleset {
        if let id = event?.seasonID, let season = seasons.first(where: { $0.id == id }) { return season.rules }
        return seasons.first { $0.status == .active }?.rules ?? .golfgutu
    }
}

/// Hva som følger med når en runde slettes (`rundenTarMedSeg`, `slettArkOpts`).
nonisolated struct RoundDeleteSummary: Equatable, Sendable {
    var holeScores: Int
    var playersWithScores: Int
    var sideClaims: Int
    var isDraft: Bool

    var noun: String { isDraft ? "kladden" : "runden" }

    var lines: [String] {
        var items: [String] = []
        if holeScores > 0 {
            items.append("\(holeScores) " + (holeScores == 1 ? "ført hull" : "førte hull")
                         + ", fra \(playersWithScores) " + (playersWithScores == 1 ? "spiller" : "spillere"))
        }
        if sideClaims > 0 {
            items.append("\(sideClaims) " + (sideClaims == 1 ? "innmeldt sidepremie" : "innmeldte sidepremier"))
        }
        return items
    }

    var message: String {
        var text: [String] = []
        let items = lines
        if items.isEmpty {
            text.append(isDraft ? "Ingen har sett den. Båsene og oppsettet forsvinner med den."
                                : "Ingen har ført et hull. Runden er tom.")
        } else {
            text.append("Dette følger med ut, og kan ikke angres:")
            text.append(contentsOf: items.map { "• \($0)" })
        }
        text.append("Spillerne, banene og terminlista står igjen.")
        return text.joined(separator: "\n")
    }

    var buttonTitle: String {
        holeScores > 0 ? "Slett runden og \(holeScores) " + (holeScores == 1 ? "ført hull" : "førte hull") : "Slett \(noun)"
    }
}

/// Svaret fra `delete_round`.
nonisolated struct DeleteRoundResult: Decodable, Equatable, Sendable {
    let roundNo: Int
    let holeScores: Int
    let sideClaims: Int
    let matches: Int
    let players: Int

    enum CodingKeys: String, CodingKey {
        case roundNo = "round_no"
        case holeScores = "hole_scores"
        case sideClaims = "side_claims"
        case matches
        case players
    }

    var message: String {
        var parts = ["Runde \(roundNo) er slettet"]
        if holeScores > 0 { parts.append("\(holeScores) " + (holeScores == 1 ? "ført hull" : "førte hull")) }
        if sideClaims > 0 { parts.append("\(sideClaims) " + (sideClaims == 1 ? "sidepremie" : "sidepremier")) }
        return parts.count == 1 ? parts[0] + "." : parts[0] + ", med " + parts.dropFirst().joined(separator: " og ") + "."
    }
}

/// Norske meldinger for feil ved lagring og start.
nonisolated enum RoundErrors {
    /// `start_round`: 23505 er den unike indeksen `rounds_one_active_per_club`,
    /// 55000 er at runden ikke er en kladd lenger.
    static func startMessage(sqlState: String?, fallback: DataError) -> String {
        switch sqlState {
        case "23505": "En runde går allerede. Lås den før du starter en ny."
        case "55000": "Bare en kladd kan startes. Last inn på nytt og sjekk."
        default: fallback.message
        }
    }

    /// 23505 ved lagring er `rounds_unique_no_per_event`: to arrangører lagret samtidig.
    static func saveMessage(sqlState: String?, fallback: DataError) -> String {
        sqlState == "23505" ? "Kvelden har alt en runde med samme nummer. Last inn på nytt og prøv igjen." : fallback.message
    }
}
