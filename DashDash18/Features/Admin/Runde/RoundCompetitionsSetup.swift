import Foundation
import GolfgutuCore

/// En ekstra konkurranse i oppsettet («Konkurranser i runden», sql/048). Hovedkonkurransen er formen
/// (`RoundDraft.formID`) og står ikke her.
nonisolated struct RoundCompetitionDraft: Equatable, Identifiable, Sendable {
    /// Lokal id for lista i oppsettet.
    let id: UUID
    /// Raden i `round_competitions`, når den er lagret. nil: ny rad.
    var rowID: UUID?
    var name: String
    var config: CompetitionConfig

    init(id: UUID = UUID(), rowID: UUID? = nil, name: String, config: CompetitionConfig) {
        self.id = id
        self.rowID = rowID
        self.name = name
        self.config = config
    }

    var axes: FormAxes { config.axes }

    /// Konkurransen spilles i par (lagene er en del av oppsettet).
    var isPairs: Bool { if case .pairs = axes.teamForm { true } else { false } }
    var isPointsGame: Bool { if case .pointsGame = axes.scoring { true } else { false } }

    /// Spillerne som er valgt, når konkurransen ikke er for alle.
    var selectedPlayers: Set<String>? { config.entrants.map { Set($0.flatMap { $0 }) } }
}

/// Oppskriftene i «Legg til konkurranse». Detaljene (hvem, hull, andel) kan endres etterpå.
nonisolated enum CompetitionRecipe: String, CaseIterable, Identifiable, Sendable {
    case bestBallPairs
    case skins
    case frontNine
    case backNine
    case amerikaner
    case kobenhavner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestBallPairs: "Bestball i par"
        case .skins: "Skins"
        case .frontNine: "Første ni"
        case .backNine: "Siste ni"
        case .amerikaner: "Amerikaner"
        case .kobenhavner: "Københavner"
        }
    }

    var symbol: String {
        switch self {
        case .bestBallPairs: "person.2"
        case .skins: "dollarsign.circle"
        case .frontNine: "1.circle"
        case .backNine: "10.circle"
        case .amerikaner: "square.grid.2x2"
        case .kobenhavner: "triangle"
        }
    }

    /// Første og siste ni bare på 18 hull.
    func isAvailable(holeCount: Int) -> Bool {
        switch self {
        case .frontNine, .backNine: holeCount == 18
        default: true
        }
    }

    /// Konkurransen oppskriften gir for kladden.
    func make(for draft: RoundDraft) -> RoundCompetitionDraft {
        let config: CompetitionConfig = switch self {
        case .bestBallPairs:
            CompetitionConfig(teamForm: .pairs(.fourball), scoring: .stableford(net: true),
                              entrants: CompetitionSetup.suggestedPairs(draft))
        case .skins: CompetitionConfig(form: "skins")
        case .frontNine: CompetitionConfig(form: draft.formID, holes: HoleRange(first: 0, last: 8))
        case .backNine: CompetitionConfig(form: draft.formID, holes: HoleRange(first: 9, last: 17))
        case .amerikaner: CompetitionConfig(form: "amerikaner")
        case .kobenhavner: CompetitionConfig(form: "kobenhavner")
        }
        return RoundCompetitionDraft(name: title, config: config)
    }
}

/// Hullvalget i oppsettet: alle, første ni eller siste ni.
nonisolated enum CompetitionHoles: String, CaseIterable, Identifiable, Sendable {
    case all, front, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .front: "1–9"
        case .back: "10–18"
        }
    }

    var range: HoleRange? {
        switch self {
        case .all: nil
        case .front: HoleRange(first: 0, last: 8)
        case .back: HoleRange(first: 9, last: 17)
        }
    }

    init(_ range: HoleRange?) {
        switch (range?.first, range?.last) {
        case (0, 8): self = .front
        case (9, 17): self = .back
        default: self = .all
        }
    }

    static func choices(holeCount: Int) -> [CompetitionHoles] {
        holeCount == 18 ? allCases : [.all]
    }
}

nonisolated enum CompetitionSetup {
    /// Høyst ti konkurranser per runde (048), hovedkonkurransen med.
    static let maxExtra = 9

    /// Par til bestball: rundens lag når de er par, ellers to og to i hver bås (troppens rekkefølge).
    static func suggestedPairs(_ draft: RoundDraft) -> [[String]] {
        let included = Set(draft.participants)
        let teams = Dictionary(grouping: draft.teams.filter { included.contains($0.key) }.keys,
                               by: { draft.teams[$0]! })
        if !teams.isEmpty, teams.values.allSatisfy({ $0.count <= 2 }) {
            return teams.sorted { $0.key < $1.key }.map { $0.value.map(\.uuidString).sorted() }
        }
        var bays = draft.bays
        bays.keepOnly(included)
        var groups: [[UUID]] = []
        let order = Dictionary(uniqueKeysWithValues: draft.participants.enumerated().map { ($1, $0) })
        let seated = Dictionary(grouping: draft.participants.compactMap { id in bays.seat(for: id).map { (id, $0.bay) } },
                                by: \.1)
        for bay in seated.keys.sorted() {
            groups.append(seated[bay]!.map(\.0).sorted { (order[$0] ?? 0) < (order[$1] ?? 0) })
        }
        let unseated = draft.participants.filter { bays.seat(for: $0) == nil }
        if !unseated.isEmpty { groups.append(unseated) }
        return groups.flatMap { group in
            stride(from: 0, to: group.count, by: 2).map { Array(group[$0..<min($0 + 2, group.count)]).map(\.uuidString) }
        }
    }

    /// Hvem som er med: alle (nil), eller de valgte. I par og poengspill er de valgte én gruppe per
    /// lag/gruppe slik konkurransen har dem; ellers hver for seg (skins: én gruppe).
    static func entrants(selected: Set<UUID>?, draft: RoundCompetitionDraft, participants: [UUID]) -> [[String]]? {
        guard let selected else { return draft.isPairs ? draft.config.entrants : nil }
        let ids = participants.filter(selected.contains).map(\.uuidString)
        if draft.isPairs {
            return (draft.config.entrants ?? []).map { $0.filter { ids.contains($0) } }.filter { !$0.isEmpty }
        }
        if draft.axes.scoring == .skins || draft.isPointsGame { return [ids] }
        return ids.map { [$0] }
    }

    /// Det som er galt med konkurransene i kladden, eller nil.
    static func problem(_ draft: RoundDraft) -> String? {
        if draft.competitions.count > maxExtra { return "Høyst \(maxExtra + 1) konkurranser i runden." }
        for c in draft.competitions {
            let name = c.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty || name.count > 60 { return "Gi hver konkurranse et navn (høyst 60 tegn)." }
            if let h = c.config.holes, h.last >= draft.holeCount { return "\(name): hullene er utenfor runden." }
            if c.isPairs, (c.config.entrants ?? []).isEmpty { return "\(name): sett opp parene." }
            if let a = c.config.allowance, !(0...1).contains(a) { return "\(name): andelen må være 0–100 %." }
        }
        return nil
    }

    /// Lista til `round_competitions_set`: hovedkonkurransen (formen) først, så de ekstra. nil: ingenting
    /// å lagre (ingen ekstra nå og ingen rader fra før). Spillere som ikke er med, tas ut av lag og grupper.
    static func writes(_ draft: RoundDraft) -> [CompetitionWrite]? {
        guard !draft.competitions.isEmpty || draft.hasSavedCompetitions else { return nil }
        guard !draft.competitions.isEmpty else { return [] }
        let ids = Set(draft.participants.map(\.uuidString))
        var out = [CompetitionWrite(id: draft.mainCompetitionID, name: CompetitionForm.form(id: draft.formID).name,
                                    isMain: true, config: CompetitionConfig(form: draft.formID), sortOrder: 0)]
        for (i, c) in draft.competitions.enumerated() {
            var config = c.config
            if let entrants = config.entrants {
                let kept = entrants.map { $0.filter(ids.contains) }.filter { !$0.isEmpty }
                config.entrants = kept.isEmpty ? nil : kept
            }
            if let h = config.holes, h.last >= draft.holeCount { config.holes = nil }
            out.append(CompetitionWrite(id: c.rowID, name: String(c.name.trimmingCharacters(in: .whitespaces).prefix(60)),
                                        isMain: false, config: config, sortOrder: min(i + 1, 99)))
        }
        return out
    }

    /// Kladdens konkurranser fra radene: de ekstra, og id-en til hovedkonkurransen.
    static func drafts(from rows: [RoundCompetitionRow]) -> (main: UUID?, extra: [RoundCompetitionDraft]) {
        let sorted = rows.sorted { $0.sortOrder < $1.sortOrder }
        let extra = sorted.filter { !$0.isMain }.compactMap { row in
            row.config.map { RoundCompetitionDraft(rowID: row.id, name: row.name, config: $0) }
        }
        return (sorted.first(where: \.isMain)?.id, extra)
    }

    /// Kopier fra «Samme som sist» eller en mal: nye rader (uten id).
    static func drafts(from copies: [CompetitionCopy]) -> [RoundCompetitionDraft] {
        copies.filter { !$0.isMain }.sorted { $0.sortOrder < $1.sortOrder }.compactMap { copy in
            copy.config.map { RoundCompetitionDraft(name: copy.name, config: $0) }
        }
    }

    /// «Bestball i par · hull 1–9 · alle».
    static func summary(_ c: RoundCompetitionDraft, holeCount: Int, firstHole: Int) -> String {
        var parts = [RoundCompetitionBoard.formName(c.axes)]
        if let h = c.config.holes, h.first > 0 || h.last < holeCount - 1 {
            let offset = firstHole == 10 ? 10 : 1
            parts.append("hull \(h.first + offset)–\(h.last + offset)")
        }
        if c.isPairs {
            let n = c.config.entrants?.count ?? 0
            parts.append(n == 1 ? "1 par" : "\(n) par")
        } else if let picked = c.selectedPlayers {
            parts.append("\(picked.count) valgt")
        }
        if let a = c.config.allowance, a != 1 { parts.append("\(Int((a * 100).rounded())) %") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Lag mot lag i kladden

nonisolated extension RoundDraft {
    /// Slår lag mot lag av eller på. På: sidene foreslås fra lagene (eller annenhver spiller), og
    /// matchene trekkes side mot side. Av: sidene tas bort, og matchene trekkes som vanlig.
    mutating func setTeamVsTeam(_ on: Bool, roster: [ClubMemberRow], plan: MatchDrawPlan = .standings) {
        guard on != isTeamVsTeam else { return }
        sides = on ? TeamVsTeam.suggested(participants: participants, teams: form.isTeamForm ? teams : [:]) : [:]
        redrawMatches(roster: roster, plan: plan)
    }

    /// Flytter spilleren (og laget hans i en lagform) til siden.
    mutating func setSide(_ side: Int, for member: UUID, roster: [ClubMemberRow], plan: MatchDrawPlan = .standings) {
        if form.isTeamForm, let team = teams[member] {
            for (id, t) in teams where t == team { sides[id] = side }
        } else {
            sides[member] = side
        }
        redrawMatches(roster: roster, plan: plan)
    }
}
