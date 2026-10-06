import Foundation
import GolfgutuCore

// Matchene under spill: matchkortet, linja på hullkortet og «Bayen nå» med stilling.
// Som PWA-ens renderMatchKort, renderHullMatch og Bayen-delen av renderKveld
// (app-nytt.js 8536, 6186 og 4340). Reglene ligger i GolfgutuCore (MatchPlay, Triangle).

/// Hvilken farge en stilling skal ha: opp (grønn), ned (rust) eller nøytral.
nonisolated enum MatchTone: Equatable, Sendable {
    case neutral, up, down

    /// Opp eller ned bare når hull er spilt og noen leder.
    init(_ standing: MatchStanding?) {
        guard let st = standing, st.played > 0, st.up != 0 else { self = .neutral; return }
        self = st.up > 0 ? .up : .down
    }
}

/// Ett hull i min match: vunnet, tapt, delt eller ikke spilt (sett fra meg).
nonisolated struct MatchHoleMark: Equatable, Identifiable, Sendable {
    enum Result: Equatable, Sendable { case won, lost, halved, open }

    let index: Int
    let number: Int
    let result: Result
    var id: Int { index }

    var accessibilityLabel: String {
        let what = switch result {
        case .won: "vunnet"
        case .lost: "tapt"
        case .halved: "delt"
        case .open: "ikke spilt"
        }
        return "Hull \(number) \(what)"
    }
}

/// Én rad i matchkortet.
nonisolated struct MatchLine: Equatable, Identifiable, Sendable {
    enum Leader: Equatable, Sendable { case a, b }

    let matchNo: Int
    let isMine: Bool
    let isTriangle: Bool
    /// Min match: «Mot Bjørn» / «Mot Cato + Dag». Andres: side A.
    let title: String
    /// Andres match: side B (ellers nil). Vises «A – B».
    let opponent: String?
    /// Andres match: siden som leder, i halvfeit.
    let leader: Leader?
    /// «2 opp etter 5», «Vunnet 3&2», «Delt», «Ikke startet». Trekant: «1 · 0,5 · 0».
    let text: String
    let tone: MatchTone
    /// Trekant: «Trekant · 1 / 0,5 / 0 etter poengsum».
    let subtitle: String?
    /// Min match: hull for hull over de tellende hullene. Tom for trekant og andres matcher.
    let holes: [MatchHoleMark]
    var id: Int { matchNo }
}

/// Matchkortet: mine matcher først, så de andre.
nonisolated struct MatchCard: Equatable, Sendable {
    let mine: [MatchLine]
    let others: [MatchLine]
    /// «Matchen er avgjort. Resten av hullene endrer den ikke.»
    let decidedHint: String?
}

/// Linja under hullkortet for én match (`renderHullMatch`).
nonisolated struct HoleMatchLine: Equatable, Identifiable, Sendable {
    let matchNo: Int
    /// «Hull 5 til Erik + Frode», «Hull 5 delt», «Matchen» eller «Match 2».
    let what: String
    let standing: String
    let tone: MatchTone
    var id: Int { matchNo }
}

nonisolated extension RoundGame {
    // MARK: Oppslag

    /// Navnet til en regelmotor-id (uuid som tekst).
    func matchName(_ id: String) -> String {
        UUID(uuidString: id).map(name) ?? "Ukjent"
    }

    /// «Erik + Frode».
    func matchNames(_ ids: [String]) -> String {
        ids.map { matchName($0) }.joined(separator: " + ")
    }

    /// Rundens matcher med nummer (radene har alltid et; ellers rekkefølgen).
    var numberedMatches: [(no: Int, match: Match)] {
        round.matches.enumerated().map { ($0.element.matchNo ?? $0.offset + 1, $0.element) }
    }

    /// `avgjoresHullForHull`.
    var isDecidedHoleByHole: Bool { MatchPlay.isDecidedHoleByHole(round) }

    func matchStanding(_ match: Match, from playerID: String?) -> MatchStanding? {
        let sides = MatchPlay.sides(of: match, in: round)
        return MatchPlay.standing(match, from: playerID ?? sides.a.first ?? "", in: round, roster: roster, rules: rules)
    }

    /// Stillingen i spillerens hullmatch, eller nil uten (trekant teller ikke).
    func holeMatchStanding(_ member: UUID) -> MatchStanding? {
        guard let m = MatchPlay.holeMatch(for: member.uuidString, in: round) else { return nil }
        return matchStanding(m, from: member.uuidString)
    }

    // MARK: Matchkortet

    /// `renderMatchKort`. Nil når runden ikke har matcher.
    func matchCard(viewer: Viewer) -> MatchCard? {
        let all = numberedMatches
        guard !all.isEmpty else { return nil }
        let me = viewer.memberID.uuidString
        let mine = all.filter { MatchPlay.involves($0.match, playerID: me, in: round) }
        let others = all.filter { !MatchPlay.involves($0.match, playerID: me, in: round) }
        var hint: String?
        if let first = mine.first?.match, matchStanding(first, from: me)?.decided == true {
            hint = "Matchen er avgjort. Resten av hullene endrer den ikke."
        }
        return MatchCard(mine: mine.map { line($0.match, no: $0.no, mine: me) },
                         others: others.map { line($0.match, no: $0.no, mine: nil) },
                         decidedHint: hint)
    }

    private func line(_ m: Match, no: Int, mine me: String?) -> MatchLine {
        if m.isTriangle { return triangleLine(m, no: no, isMine: me != nil) }
        let sides = MatchPlay.sides(of: m, in: round)
        if let me {
            let st = matchStanding(m, from: me)
            let opponents = st.map(\.opponents).flatMap { $0.isEmpty ? nil : $0 } ?? (m.playerB.map { [$0] } ?? [])
            return MatchLine(matchNo: no, isMine: true, isTriangle: false, title: "Mot " + matchNames(opponents),
                             opponent: nil, leader: nil, text: MatchPlay.text(st), tone: MatchTone(st),
                             subtitle: nil, holes: holeMarks(m, from: me))
        }
        // Andres matcher: «Vunnet 3 opp» sier ikke hvem. Marginen uten utfallsord, lederen i halvfeit.
        let st = matchStanding(m, from: sides.a.first)
        let text: String
        var leader: MatchLine.Leader?
        if let st, st.played > 0 {
            if st.up == 0 {
                text = st.remaining > 0 ? "Delt etter \(st.played)" : "Delt"
            } else {
                leader = st.up > 0 ? .a : .b
                text = "\(abs(st.up))" + (st.remaining > 0 && st.decided ? "&\(st.remaining)" : " opp")
            }
        } else {
            text = "Ikke startet"
        }
        return MatchLine(matchNo: no, isMine: false, isTriangle: false, title: matchNames(sides.a),
                         opponent: matchNames(sides.b), leader: leader, text: text, tone: .neutral,
                         subtitle: nil, holes: [])
    }

    /// Trekanten rangeres på rundens poengsum, ikke hull: tabell i miniatyr.
    private func triangleLine(_ m: Match, no: Int, isMine: Bool) -> MatchLine {
        let points = Triangle.points(m, in: round, roster: roster, rules: rules)
        let ids = [m.playerA, m.playerB, m.playerC].compactMap { $0 }
        let ranked = ids.enumerated().map { offset, pid in
            (pid: pid, offset: offset,
             score: Scoring.roundNetTotal(round, player: roster.first { $0.id == pid }, roster: roster, rules: rules))
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        let text = points.map { p in
            ranked.map { Season.formatPoints(p[$0.pid] ?? 0, rules: rules) }.joined(separator: " · ")
        } ?? "Ikke avgjort"
        let place = rules.table.trianglePoints.map { Season.formatPoints($0, rules: rules) }.joined(separator: " / ")
        return MatchLine(matchNo: no, isMine: isMine, isTriangle: true,
                         title: ranked.map { matchName($0.pid) }.joined(separator: " · "),
                         opponent: nil, leader: nil, text: text, tone: .neutral,
                         subtitle: "Trekant · \(place) etter poengsum", holes: [])
    }

    /// Hull for hull i matchen sett fra spilleren, over de tellende hullene.
    func holeMarks(_ m: Match, from playerID: String) -> [MatchHoleMark] {
        let onB = MatchPlay.sides(of: m, in: round).b.contains(playerID)
        let offset = MatchPlay.strokeOffset(for: m, in: round, roster: roster, rules: rules)
        return (0..<Truncation.countingHoles(round)).map { h in
            let v = MatchPlay.holeWinner(m, hole: h, in: round, roster: roster, rules: rules, strokeOffset: offset)
            let result: MatchHoleMark.Result = switch v.map({ onB ? -$0 : $0 }) {
            case nil: .open
            case 0: .halved
            case let x? where x > 0: .won
            default: .lost
            }
            return MatchHoleMark(index: h, number: holeNumber(h), result: result)
        }
    }

    // MARK: Linja på hullkortet

    /// `renderHullMatch`: matchene (ikke trekant) som noen på kortet spiller, med hvem som
    /// vant hullet og stillingen. Min match fra meg; andres med navnet på den som leder.
    func holeMatchLines(hole: Int, viewer: Viewer) -> [HoleMatchLine] {
        let players = cardPlayers(for: viewer).map(\.uuidString)
        let me = viewer.memberID.uuidString
        return numberedMatches.compactMap { no, m -> HoleMatchLine? in
            guard !m.isTriangle, players.contains(where: { MatchPlay.involves(m, playerID: $0, in: round) }) else { return nil }
            let sides = MatchPlay.sides(of: m, in: round)
            let isMine = MatchPlay.involves(m, playerID: me, in: round)
            let st = matchStanding(m, from: isMine ? me : sides.a.first)
            let v = MatchPlay.holeWinner(m, hole: hole, in: round, roster: roster, rules: rules)
            let what: String = switch v {
            case nil: isMine ? "Matchen" : "Match \(no)"
            case 0: "Hull \(holeNumber(hole)) delt"
            case let x?: "Hull \(holeNumber(hole)) til " + matchNames(x > 0 ? sides.a : sides.b)
            }
            if isMine {
                return HoleMatchLine(matchNo: no, what: what, standing: MatchPlay.text(st), tone: MatchTone(st))
            }
            let text: String
            if let st, st.played > 0 {
                text = st.up == 0 ? "Delt" : matchNames(st.up > 0 ? sides.a : sides.b) + " \(abs(st.up)) opp"
            } else {
                text = "Ikke startet"
            }
            return HoleMatchLine(matchNo: no, what: what, standing: text, tone: .neutral)
        }
    }
}

// MARK: - Bayen nå

/// Én rad i «Bayen nå»: en spiller, eller et lag der formen har ett kort per lag.
nonisolated struct BayenRow: Equatable, Identifiable, Sendable {
    /// Spilleren, eller lagets spillere (sortert på navn).
    let members: [UUID]
    let name: String
    let isMe: Bool
    let thru: Int
    let bay: Int?
    /// Plassen. Nil når runden avgjøres hull for hull: «1 opp» i match 1 og 3 er ikke 1. og 2. plass.
    let place: Int?
    /// Stablefordsummen (laget: lagets sum).
    let total: Int
    /// Stillingen i hullmatchen, eller nil når raden ikke står i en.
    let match: MatchStanding?
    /// Det som står til høyre: «24», «24 p», «1 opp», «Delt» eller «—».
    let value: String
    let tone: MatchTone
    var id: UUID { members[0] }
    /// Den som åpnes i scorekortet.
    var memberID: UUID { members[0] }
}

nonisolated extension RoundGame {
    /// «Bayen nå» som i PWA-en: avgjøres runden hull for hull, viser matchspillerne stillingen
    /// (flest hull opp først, så flest hull ført) og kommer før dem på poeng. Ellers flest
    /// poeng først. Likt: norsk navnesortering. Formene med ett kort per lag: én rad per lag
    /// med lagets sum.
    func bayenNaa(viewer: Viewer) -> [BayenRow] {
        let holeByHole = isDecidedHoleByHole
        let perTeam = round.form.card == .perTeam
        let teamPoints = perTeam ? Scoring.roundPoints(round, roster: roster, rules: rules) : [:]

        var seen: Set<UUID> = []
        var groups: [[UUID]] = []
        for p in snapshot.players where !seen.contains(p.memberID) {
            var members = [p.memberID]
            if perTeam, let mates = Handicap.teammates(of: p.memberID.uuidString, in: round), mates.count > 1 {
                members = mates.compactMap(UUID.init(uuidString:)).filter(isPlaying)
                    .sorted { NorwegianSort.areInIncreasingOrder(name($0), name($1)) }
                if members.isEmpty { members = [p.memberID] }
            }
            seen.formUnion(members)
            groups.append(members)
        }

        struct Entry {
            let members: [UUID]
            let name: String
            let total: Int
            let thru: Int
            let match: MatchStanding?
            let inMatch: Bool
        }
        let entries = groups.map { members -> Entry in
            let first = members[0]
            let total = members.count > 1
                ? (members.lazy.compactMap { teamPoints[$0.uuidString] }.first ?? 0)
                : self.total(first)
            let inMatch = holeByHole && MatchPlay.holeMatch(for: first.uuidString, in: round) != nil
            return Entry(members: members, name: members.map(name).joined(separator: " + "), total: total,
                         thru: members.map { scores($0).count }.max() ?? 0,
                         match: inMatch ? holeMatchStanding(first) : nil, inMatch: inMatch)
        }
        .sorted { a, b in
            if a.inMatch != b.inMatch { return a.inMatch }
            if a.inMatch {
                let ua = a.match?.up ?? 0, ub = b.match?.up ?? 0
                if ua != ub { return ua > ub }
                if a.thru != b.thru { return a.thru > b.thru }
            } else if a.total != b.total {
                return a.total > b.total
            }
            return NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }

        let me = viewer.memberID
        return entries.enumerated().map { i, e in
            BayenRow(members: e.members, name: e.name, isMe: e.members.contains(me), thru: e.thru,
                     bay: snapshot.players.first { $0.memberID == e.members[0] }?.bayNo,
                     place: holeByHole ? nil : i + 1, total: e.total, match: e.match,
                     value: e.inMatch ? MatchPlay.shortText(e.match) : "\(e.total)" + (holeByHole ? " p" : ""),
                     tone: e.inMatch ? MatchTone(e.match) : .neutral)
        }
    }
}
