import Foundation
import GolfgutuCore

/// Konkurransene på runden (sql/048) regnet med motoren: øyeblikksbildet fra start (`FrozenRound`)
/// og `RoundCompetitions.evaluate`, og lag mot lag med `RyderCup`. Ren logikk, uten nettverk og SwiftUI.
nonisolated enum RoundCompetitionBoard {
    // MARK: Øyeblikksbildet

    /// `FrozenRound` for runden: regelsettet fra `rules_snapshot`, hullene fra `holes_snapshot.holes`,
    /// spillehandicapet som ble frosset ved start, formen og lagene. Mangler øyeblikksbildet (kladd, runde
    /// uten turnering, eller 048 ikke kjørt), brukes dagens regelsett og hull, som før.
    static func frozenRound(_ game: RoundGame) -> FrozenRound {
        let s = game.snapshot
        let rules = s.freeze?.rules ?? s.rules
        let holes = snapshotHoles(s.freeze?.holes, count: game.holeCount) ?? game.holes
        var handicaps: [String: Double] = [:]
        for p in s.players { handicaps[p.memberID.uuidString] = game.handicap(p.memberID) }
        return FrozenRound(ruleset: rules, holes: holes, playingHandicaps: handicaps,
                           gameType: s.round.format, teams: game.round.teams)
    }

    /// Hullene fra `holes_snapshot.holes`. par som mangler eller ikke er gyldig, blir standardbanens
    /// (`Course.defaultPar`, som `courseHoles()`). nil når antallet ikke stemmer med runden.
    static func snapshotHoles(_ holes: [RoundFreeze.Hole]?, count: Int) -> [PlayedHole]? {
        guard let holes, holes.count == count, count > 0 else { return nil }
        let played = holes.enumerated().map { i, h in
            let par = h.par.flatMap { Course.isValidPar($0) ? $0 : nil } ?? Course.defaultPar[i % Course.defaultPar.count]
            return PlayedHole(par: par, cardIndex: h.cardIndex ?? (i + 1), meters: h.meters, strokeIndex: h.strokeIndex ?? (i + 1))
        }
        return played
    }

    // MARK: Konkurransene

    /// Én konkurranse slik skjermen viser den.
    struct Board: Equatable, Identifiable, Sendable {
        struct Line: Equatable, Identifiable, Sendable {
            var id: String { players.joined(separator: ",") }
            var rank: Int
            var players: [String]
            var names: String
            var score: String
            var holes: Int
        }

        var id: String
        var name: String
        var isMain: Bool
        /// «Stableford · hull 1–9 · 90 %».
        var detail: String
        /// `false`: «Ikke støttet ennå».
        var supported: Bool
        var lines: [Line]
        /// Teksten når det ikke er noen rader.
        var emptyText = "Ingen scorer ennå"
    }

    static let unsupportedText = "Ikke støttet ennå"

    /// Konkurransene på runden, i rekkefølge, med hovedkonkurransen først. Tom når runden bare har
    /// formen (ingen rader i `round_competitions`), siden den står i resten av skjermen.
    static func boards(_ game: RoundGame) -> [Board] {
        let s = game.snapshot
        guard !s.competitions.isEmpty, !s.round.isPlayoff else { return [] }
        let rows = s.competitions.sorted { ($0.isMain ? 0 : 1, $0.sortOrder) < ($1.isMain ? 0 : 1, $1.sortOrder) }
        let frozen = frozenRound(game)
        let competitions = rows.compactMap { competition(for: $0, game: game) }
        let results = RoundCompetitions.evaluate(frozen, scores: game.round.holeScores,
                                                 locked: s.round.status == .locked, competitions: competitions)
        let byID = Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return rows.map { row in
            let comp = competitions.first { $0.id == row.id.uuidString }
            let result = byID[row.id.uuidString]
            let supported = comp != nil && (result?.supported ?? false)
            return Board(
                id: row.id.uuidString, name: row.name, isMain: row.isMain,
                detail: comp.map { detail($0, holeCount: game.holeCount, firstHole: s.round.firstHole, rules: frozen.ruleset) } ?? "",
                supported: supported,
                lines: supported ? (result?.rows ?? []).map { line($0, scoring: comp!.scoring, game: game) } : [],
                emptyText: comp.map { emptyText($0, isMain: row.isMain) } ?? "Ingen scorer ennå"
            )
        }
    }

    /// Motorens konkurranse for raden. Hovedkonkurransen er rundens form (`rounds.format`) med fullt
    /// spillehandicap (rundens andel er alt med i det frosne handicapet). nil når oppsettet ikke kan leses.
    static func competition(for row: RoundCompetitionRow, game: RoundGame) -> RoundCompetition? {
        let s = game.snapshot
        if row.isMain {
            let axes = CompetitionForm.form(id: s.round.format).axes
            return RoundCompetition(id: row.id.uuidString, teamForm: axes.teamForm, scoring: axes.scoring,
                                    entrants: defaultEntrants(axes, game: game))
        }
        guard let config = row.config else { return nil }
        let axes = config.axes
        let entrants = config.entrants.flatMap { filtered($0, players: s.players) } ?? defaultEntrants(axes, game: game)
        var holes = config.holes
        if let h = holes {
            guard h.first >= 0, h.first < game.holeCount else { return nil }
            holes = HoleRange(first: h.first, last: min(h.last, game.holeCount - 1))
        }
        return RoundCompetition(id: row.id.uuidString, teamForm: axes.teamForm, scoring: axes.scoring,
                                entrants: entrants, holes: holes, allowance: config.allowance)
    }

    /// Bare spillere som er med i runden; tomme lag tas bort. nil når ingen er igjen.
    static func filtered(_ entrants: [[String]], players: [RoundPlayerRow]) -> [[String]]? {
        let ids = Set(players.map(\.memberID.uuidString))
        let kept = entrants.map { $0.filter(ids.contains) }.filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept
    }

    /// Lagene eller gruppene når konkurransen ikke har egne: rundens lag i lagformer; i Amerikaner og
    /// Københavner rundens lag (lagnummeret er flighten, som `FormPlay.groups`), ellers båsene. Match:
    /// side 1 mot side 2 i lag mot lag (`round_players.side`).
    static func defaultEntrants(_ axes: FormAxes, game: RoundGame) -> [[String]]? {
        let teams = groups(game.round.teams)
        switch axes.scoring {
        case .matchPlay:
            let sides = TeamVsTeam.sides(game.snapshot.players)
            let one = sides.filter { $0.value == 1 }.map(\.key).sorted()
            let two = sides.filter { $0.value == 2 }.map(\.key).sorted()
            return one.isEmpty || two.isEmpty ? nil : [one, two]
        case .pointsGame:
            if !teams.isEmpty { return teams }
            let bays = game.bays.keys.sorted().compactMap { game.bays[$0]?.players.map(\.uuidString) }
            return bays.isEmpty ? nil : bays
        default:
            guard axes.teamForm != .individual, !teams.isEmpty else { return nil }
            return teams
        }
    }

    /// Lagene som lister, i lagnummerets rekkefølge, spillerne sortert på id.
    static func groups(_ teams: [String: Int]) -> [[String]] {
        Dictionary(grouping: teams.keys, by: { teams[$0]! }).sorted { $0.key < $1.key }.map { $0.value.sorted() }
    }

    static func line(_ row: RoundCompetitionResult.Row, scoring: ScoringMethod, game: RoundGame) -> Board.Line {
        let names = row.players.map { UUID(uuidString: $0).map(game.name) ?? "Ukjent" }.joined(separator: " og ")
        // Match: stillingen sett fra raden («2 opp etter 6», «Delt etter 5», «Vunnet 3&2»).
        let score = row.match.map { MatchPlay.text($0) } ?? scoreText(row.score, scoring: scoring)
        return Board.Line(rank: row.rank, players: row.players, names: names, score: score, holes: row.holes)
    }

    /// Uten rader: en match mangler sidene, ellers er det ingen scorer ennå.
    static func emptyText(_ comp: RoundCompetition, isMain: Bool) -> String {
        guard comp.scoring == .matchPlay, (comp.entrants?.count ?? 0) != 2 else { return "Ingen scorer ennå" }
        return isMain ? "Matchene i runden står i «Bayen nå»." : "Mangler to spillere eller lag mot lag."
    }

    /// Taket i maksimumscore: «tak netto dobbel bogey» eller «tak 8 slag».
    static func capText(_ cap: Ruleset.MaxStrokes) -> String {
        switch cap {
        case .off: "uten tak"
        case .netDoubleBogey: "tak netto dobbel bogey"
        case .fixed(let n): "tak \(n) slag"
        }
    }

    /// «34 p», «72 slag», «3 skins», og par/bogey med fortegn: «+3», «0», «−2».
    static func scoreText(_ score: Double, scoring: ScoringMethod) -> String {
        let number = RuleFormat.number(score)
        switch scoring {
        case .strokePlay, .maximumScore: return "\(number) slag"
        case .skins: return score == 1 ? "1 skin" : "\(number) skins"
        case .parBogey: return signedText(score)
        default: return "\(number) p"
        }
    }

    /// Par/bogey-summen med fortegn (regel 21.3: hull vunnet minus hull tapt): «+3», «0», «−2».
    static func signedText(_ score: Double) -> String {
        let number = RuleFormat.number(abs(score))
        if score > 0 { return "+" + number }
        if score < 0 { return "−" + number }
        return number
    }

    /// Formen, taket (maksimumscore), hullene og andelen i én linje.
    static func detail(_ comp: RoundCompetition, holeCount: Int, firstHole: Int, rules: Ruleset? = nil) -> String {
        var parts = [formName(FormAxes(teamForm: comp.teamForm, scoring: comp.scoring))]
        if case .maximumScore(_, let own) = comp.scoring, let cap = own ?? rules?.formPlay.maximumScore {
            parts.append(capText(cap))
        }
        if let h = comp.holes, h.first > 0 || h.last < holeCount - 1 {
            let offset = firstHole == 10 ? 10 : 1
            parts.append("hull \(h.first + offset)–\(h.last + offset)")
        }
        if let a = comp.allowance, a != 1 { parts.append("\(Int((a * 100).rounded())) %") }
        return parts.joined(separator: " · ")
    }

    /// Katalogens navn for aksene, ellers lagformen og poengtellingen.
    static func formName(_ axes: FormAxes) -> String {
        if let form = CompetitionForm.form(axes: axes) { return form.name }
        let scoring = switch axes.scoring {
        case .stableford(let net): net ? "Stableford" : "Stableford brutto"
        case .strokePlay(let net): net ? "Slag netto" : "Slag brutto"
        case .parBogey: "Par/bogey"
        case .maximumScore(let net, _): net ? "Maksimumscore" : "Maksimumscore brutto"
        case .matchPlay: "Match"
        case .pointsGame(let g): g == .amerikaner ? "Amerikaner" : "Københavner"
        case .skins: "Skins"
        }
        let team: String? = switch axes.teamForm {
        case .individual: nil
        case .pairs(.fourball): "Bestball i par"
        case .pairs(.aggregate): "Sammenlagt i par"
        case .pairs(let p): p.rawValue.capitalized
        case .team(let n): "Bestball \(n) per lag"
        case .scramble(let n): "Scramble \(n)"
        }
        return [team, scoring].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Lag mot lag

/// Lag mot lag (Ryder Cup, sql/048): to sider per runde (`round_players.side`), rundens matcher regnet
/// med `RyderCup`. Ren logikk.
nonisolated enum TeamVsTeam {
    /// Sidene i runden, spiller-id → 1 eller 2. Tom: runden er ikke lag mot lag.
    static func sides(_ players: [RoundPlayerRow]) -> [String: Int] {
        Dictionary(players.compactMap { p in p.side.map { (p.memberID.uuidString, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Lagkonkurransen for én runde. nil når runden ikke har sider.
    static func result(_ game: RoundGame) -> RyderCup.Result? {
        let sides = sides(game.snapshot.players)
        guard !sides.isEmpty else { return nil }
        var round = game.round
        round.counts = true
        round.weight = 1
        return RyderCup.evaluate(rounds: [round], sides: sides, roster: game.roster, rules: game.rules)
    }

    /// Én side i lagtabellen over flere runder.
    struct Row: Equatable, Sendable {
        var side: Int
        var points: Double
        var won: Int
        var halved: Int
        var lost: Int
    }

    /// Lagtabellen over flere runder: hver runde med sine sider (en spiller kan bytte side), og
    /// tabellene lagt sammen. nil når ingen runde har sider.
    static func table(_ games: [RoundGame]) -> [Row]? {
        var rows: [Int: Row] = [:]
        var any = false
        for game in games where !game.snapshot.round.isPlayoff {
            let sides = sides(game.snapshot.players)
            guard !sides.isEmpty else { continue }
            any = true
            let result = RyderCup.evaluate(rounds: [game.round], sides: sides, roster: game.roster, rules: game.rules)
            for r in result.table {
                var row = rows[r.side] ?? Row(side: r.side, points: 0, won: 0, halved: 0, lost: 0)
                row.points += r.points
                row.won += r.won
                row.halved += r.halved
                row.lost += r.lost
                rows[r.side] = row
            }
        }
        guard any else { return nil }
        return rows.values.sorted { $0.points != $1.points ? $0.points > $1.points : $0.side < $1.side }
    }

    /// «Side 1 2½ – 1½ Side 2»: poengene for side 1 og 2.
    static func score(_ table: [RyderCup.Row]) -> (one: Double, two: Double) {
        score(table.map { Row(side: $0.side, points: $0.points, won: $0.won, halved: $0.halved, lost: $0.lost) })
    }

    static func score(_ table: [Row]) -> (one: Double, two: Double) {
        (table.first { $0.side == 1 }?.points ?? 0, table.first { $0.side == 2 }?.points ?? 0)
    }

    /// Halve poeng som «½»: 2,5 → «2½».
    static func pointsText(_ p: Double) -> String {
        let whole = p.rounded(.down)
        let half = p - whole == 0.5
        if half { return whole == 0 ? "½" : "\(Int(whole))½" }
        return RuleFormat.number(p)
    }

    static func sideName(_ side: Int) -> String { "Side \(side)" }

    // MARK: Oppsettet

    /// Hva som er galt med sidene: alle må ha en side, begge sidene må ha spillere, og spillerne på
    /// samme lag må være på samme side (som `set_round_setup`). nil når de går opp.
    static func problem(sides: [UUID: Int], teams: [UUID: Int], participants: [UUID]) -> String? {
        let mine = participants.compactMap { sides[$0] }
        if mine.count < participants.count { return "Alle må ha en side." }
        if !mine.contains(1) || !mine.contains(2) { return "Begge sidene må ha spillere." }
        var teamSide: [Int: Int] = [:]
        for id in participants {
            guard let team = teams[id], let side = sides[id] else { continue }
            if let other = teamSide[team], other != side { return "Spillerne på samme lag må være på samme side." }
            teamSide[team] = side
        }
        return nil
    }

    /// Forslag: lagene annenhver side (lag 1 side 1, lag 2 side 2 …), uten lag spillerne annenhver.
    static func suggested(participants: [UUID], teams: [UUID: Int]) -> [UUID: Int] {
        var out: [UUID: Int] = [:]
        let numbers = Array(Set(participants.compactMap { teams[$0] })).sorted()
        let sideOfTeam = Dictionary(uniqueKeysWithValues: numbers.enumerated().map { ($1, $0 % 2 + 1) })
        var next = 0
        for id in participants {
            if let team = teams[id], let side = sideOfTeam[team] {
                out[id] = side
            } else {
                out[id] = next % 2 + 1
                next += 1
            }
        }
        return out
    }

    /// Matchene side mot side: lag mot lag i lagformer (`RyderCup.pairings`), ellers singler (første
    /// mot første i troppens rekkefølge).
    static func matches(participants: [UUID], teams: [UUID: Int], sides: [UUID: Int], isTeamForm: Bool) -> [MatchDraft] {
        if isTeamForm {
            let t = Dictionary(uniqueKeysWithValues: teams.filter { participants.contains($0.key) }.map { ($0.key.uuidString, $0.value) })
            let s = Dictionary(uniqueKeysWithValues: sides.filter { participants.contains($0.key) }.map { ($0.key.uuidString, $0.value) })
            return RyderCup.pairings(teams: t, sides: s).compactMap { m in
                guard let a = m.teamA, let b = m.teamB else { return nil }
                return MatchDraft.teams(a, b)
            }
        }
        let one = participants.filter { sides[$0] == 1 }
        let two = participants.filter { sides[$0] == 2 }
        return zip(one, two).map { MatchDraft.players($0, $1) }
    }
}
