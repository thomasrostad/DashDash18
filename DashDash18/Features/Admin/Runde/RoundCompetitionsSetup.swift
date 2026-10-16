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

    /// Konkurransen spilles i par med hver sin ball (parene er en del av konkurransen). Former med én
    /// ball per lag (foursome, greensome, chapman) bruker rundens lag.
    var isPairs: Bool {
        if case .pairs = axes.teamForm, !axes.teamForm.playsOneBall { true } else { false }
    }
    var isPointsGame: Bool { if case .pointsGame = axes.scoring { true } else { false } }
    /// Match: to spillere (`entrants` [[a], [b]]), eller side 1 mot side 2 i lag mot lag (uten `entrants`).
    /// Med én ball per lag: to av rundens lag (`entrants` med lagenes spillere), eller rundens to lag (uten).
    var isMatch: Bool { axes.scoring == .matchPlay }
    /// Match med én ball per lag (foursome, greensome, chapman, scramble): lag mot lag med lagets ene score.
    var isOneBallMatch: Bool { isMatch && axes.teamForm.playsOneBall }

    /// Spillerne som er valgt, når konkurransen ikke er for alle.
    var selectedPlayers: Set<String>? { config.entrants.map { Set($0.flatMap { $0 }) } }

    // MARK: Match

    /// Matchen er side 1 mot side 2 (sidene i lag mot lag), ikke to valgte spillere.
    var matchIsSides: Bool { isMatch && config.entrants == nil }

    /// Spiller 1 og 2 i matchen (første på hver side).
    func matchPlayer(_ index: Int) -> UUID? {
        guard let entrants = config.entrants, entrants.indices.contains(index) else { return nil }
        return entrants[index].first.flatMap(UUID.init(uuidString:))
    }

    /// Setter spiller 1 eller 2. Den andre beholdes (eller blir tom).
    mutating func setMatchPlayer(_ index: Int, to id: UUID) {
        var players = [matchPlayer(0), matchPlayer(1)]
        players[index] = id
        config.entrants = players.map { $0.map { [$0.uuidString] } ?? [] }
    }

    /// Side 1 mot side 2 (nil), eller to spillere (de to første i lista når ingen er valgt). Med én ball
    /// per lag: rundens to lag (nil), eller to valgte lag (de to første når ingen er valgt).
    mutating func setMatchSides(_ sides: Bool, participants: [UUID], teams: [UUID: Int] = [:]) {
        if sides {
            config.entrants = nil
        } else if config.entrants == nil {
            config.entrants = isOneBallMatch
                ? CompetitionSetup.teamNumbers(participants: participants, teams: teams).prefix(2)
                    .map { CompetitionSetup.members(of: $0, participants: participants, teams: teams) }
                : participants.prefix(2).map { [$0.uuidString] }
        }
    }

    /// Lag 1 og 2 i en match med én ball: lagnummeret til den første på siden.
    func matchTeam(_ index: Int, teams: [UUID: Int]) -> Int? {
        matchPlayer(index).flatMap { teams[$0] }
    }

    /// Setter lag 1 eller 2 (alle på laget som er med). Det andre beholdes (eller blir tomt).
    mutating func setMatchTeam(_ index: Int, to number: Int, participants: [UUID], teams: [UUID: Int]) {
        var picked = [matchTeam(0, teams: teams), matchTeam(1, teams: teams)]
        picked[index] = number
        config.entrants = picked.map { n in
            n.map { CompetitionSetup.members(of: $0, participants: participants, teams: teams) } ?? []
        }
    }

    // MARK: Maksimumscore

    /// Maksimumscore: netto eller brutto og taket (nil: regelsettets `formPlay.maximumScore`).
    var maximumScore: (net: Bool, cap: Ruleset.MaxStrokes?)? {
        if case .maximumScore(let net, let cap) = axes.scoring { (net, cap) } else { nil }
    }

    /// Endrer netto/brutto og taket. Konkurransen får aksene (ikke formen) i config.
    mutating func setMaximumScore(net: Bool, cap: Ruleset.MaxStrokes?) {
        let teamForm = axes.teamForm
        config.form = nil
        config.teamForm = teamForm
        config.scoring = .maximumScore(net: net, maxStrokes: cap)
    }
}

/// Oppskriftene i «Legg til konkurranse». Detaljene (hvem, hull, andel) kan endres etterpå.
nonisolated enum CompetitionRecipe: String, CaseIterable, Identifiable, Sendable {
    case bestBallPairs
    case parBogey
    case maximumScore
    case matchPlay
    case skins
    case frontNine
    case backNine
    case amerikaner
    case kobenhavner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestBallPairs: "Bestball i par"
        case .parBogey: "Par/bogey"
        case .maximumScore: "Maksimumscore"
        case .matchPlay: "Match"
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
        case .parBogey: "plusminus"
        case .maximumScore: "arrow.down.to.line"
        case .matchPlay: "person.line.dotted.person"
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

    /// Konkurransen oppskriften gir for kladden. Maksimumscore tar taket fra regelsettet
    /// (`formPlay.maximumScore`), og match er side 1 mot side 2 i lag mot lag, ellers de to første. Spilles
    /// runden med én ball per lag, er matchen lag mot lag i den lagformen (se `CompetitionSetup.matchConfig`).
    func make(for draft: RoundDraft, rules: Ruleset = .golfgutu) -> RoundCompetitionDraft {
        let config: CompetitionConfig = switch self {
        case .bestBallPairs:
            CompetitionConfig(teamForm: .pairs(.fourball), scoring: .stableford(net: true),
                              entrants: CompetitionSetup.suggestedPairs(draft))
        case .parBogey:
            // Spilles runden med én ball per lag, er det lagene som spiller mot banen.
            draft.form.axes.teamForm.playsOneBall
                ? CompetitionConfig(teamForm: draft.form.axes.teamForm, scoring: .parBogey)
                : CompetitionConfig(form: "par-bogey")
        case .maximumScore:
            CompetitionConfig(teamForm: draft.form.axes.teamForm.playsOneBall ? draft.form.axes.teamForm : .individual,
                              scoring: .maximumScore(net: true, maxStrokes: rules.formPlay.maximumScore))
        case .matchPlay: CompetitionSetup.matchConfig(draft)
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
            if c.isMatch, let problem = matchProblem(c, draft: draft) { return "\(name): \(problem)" }
            if case .fixed(let n)? = c.maximumScore?.cap, !Ruleset.MaxStrokes.fixedRange.contains(n) {
                return "\(name): taket må være \(Ruleset.MaxStrokes.fixedRange.lowerBound)–\(Ruleset.MaxStrokes.fixedRange.upperBound) slag."
            }
        }
        return nil
    }

    /// Matchen oppskriften gir: med én ball per lag rundens to lag (nil) eller de to første lagene, ellers side
    /// 1 mot side 2 i lag mot lag eller de to første spillerne.
    static func matchConfig(_ draft: RoundDraft) -> CompetitionConfig {
        let teamForm = draft.form.axes.teamForm
        guard teamForm.playsOneBall else {
            return CompetitionConfig(teamForm: .individual, scoring: .matchPlay,
                                     entrants: draft.isTeamVsTeam ? nil : draft.participants.prefix(2).map { [$0.uuidString] })
        }
        let numbers = teamNumbers(participants: draft.participants, teams: draft.teams)
        return CompetitionConfig(
            teamForm: teamForm, scoring: .matchPlay,
            entrants: numbers.count == 2 ? nil
                : numbers.prefix(2).map { members(of: $0, participants: draft.participants, teams: draft.teams) })
    }

    /// Lagnumrene (over 0) til spillerne som er med, sortert.
    static func teamNumbers(participants: [UUID], teams: [UUID: Int]) -> [Int] {
        Set(participants.compactMap { teams[$0] }.filter { $0 != 0 }).sorted()
    }

    /// Spillerne på laget som er med, som id-tekster sortert (som rundens lag i motoren).
    static func members(of team: Int, participants: [UUID], teams: [UUID: Int]) -> [String] {
        participants.filter { teams[$0] == team }.map(\.uuidString).sorted()
    }

    /// Matchen trenger to forskjellige spillere som er med, eller lag mot lag med to sider. Med én ball per
    /// lag: runden spilles i lagformen, og to av rundens lag (uten valg: runden har nøyaktig to lag).
    static func matchProblem(_ c: RoundCompetitionDraft, draft: RoundDraft) -> String? {
        if c.isOneBallMatch {
            guard draft.form.axes.teamForm == c.axes.teamForm else {
                return "runden må spilles i \(RoundCompetitionBoard.teamFormName(c.axes.teamForm) ?? "lagformen") (én ball per lag)."
            }
            let numbers = teamNumbers(participants: draft.participants, teams: draft.teams)
            if c.matchIsSides { return numbers.count == 2 ? nil : "velg to lag." }
            let picked = [c.matchTeam(0, teams: draft.teams), c.matchTeam(1, teams: draft.teams)]
            guard let a = picked[0], let b = picked[1], a != b, numbers.contains(a), numbers.contains(b) else {
                return "velg to forskjellige lag."
            }
            for (i, n) in [a, b].enumerated()
            where Set(c.config.entrants?[i] ?? []) != Set(members(of: n, participants: draft.participants, teams: draft.teams)) {
                return "lagene er endret, velg lagene på nytt."
            }
            return nil
        }
        if c.matchIsSides {
            let sides = Set(draft.participants.compactMap { draft.sides[$0] })
            return sides.isSuperset(of: [1, 2]) ? nil : "slå på lag mot lag, eller velg to spillere."
        }
        let players = [c.matchPlayer(0), c.matchPlayer(1)].compactMap { $0 }.filter(draft.participants.contains)
        return players.count == 2 && players[0] != players[1] ? nil : "velg to forskjellige spillere."
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
        if let cap = c.maximumScore?.cap { parts.append(RoundCompetitionBoard.capText(cap)) }
        if let h = c.config.holes, h.first > 0 || h.last < holeCount - 1 {
            let offset = firstHole == 10 ? 10 : 1
            parts.append("hull \(h.first + offset)–\(h.last + offset)")
        }
        if c.isOneBallMatch {
            parts.append(c.matchIsSides ? "rundens to lag" : "to lag")
        } else if c.isMatch {
            // Katalogens navn er «Matchspill (individuelt)»; side mot side er ikke individuelt.
            if c.matchIsSides {
                parts[0] = "Matchspill"
                parts.append("side 1 mot side 2")
            }
        } else if c.isPairs {
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
