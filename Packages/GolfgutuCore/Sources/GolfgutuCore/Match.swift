import Foundation

/// En match i runden (`round_matches`): to spillere, to lag, eller en trekant av tre spillere.
public struct Match: Codable, Hashable, Sendable {
    /// Manuelt satt resultat. Overstyrer hullene (noen ga seg, eller møtte ikke opp).
    public enum Result: String, Codable, Hashable, Sendable {
        case a, b, halved

        /// Fra lagret verdi. PWA-en lagrer `A`/`B` og regner all annen tekst som delt;
        /// skjemaet bruker `a`/`b`/`halved`. Tom tekst er ikke noe resultat (JS-sannhet).
        public init?(stored raw: String?) {
            guard let raw, !raw.isEmpty else { return nil }
            switch raw.lowercased() {
            case "a": self = .a
            case "b": self = .b
            default: self = .halved
            }
        }
    }

    public var matchNo: Int?
    public var playerA: String?
    public var playerB: String?
    /// Satt = trekant (avgjøres på poengsum, ikke hull).
    public var playerC: String?
    /// Satt = lagmatch. Lagnumrene slås opp i rundens lag.
    public var teamA: Int?
    public var teamB: Int?
    public var result: Result?

    public init(matchNo: Int? = nil, playerA: String? = nil, playerB: String? = nil, playerC: String? = nil,
                teamA: Int? = nil, teamB: Int? = nil, result: Result? = nil) {
        self.matchNo = matchNo
        self.playerA = playerA
        self.playerB = playerB
        self.playerC = playerC
        self.teamA = teamA
        self.teamB = teamB
        self.result = result
    }

    /// `erTrekant`.
    public var isTriangle: Bool { !(playerC ?? "").isEmpty }
    /// `erLagmatch`.
    public var isTeamMatch: Bool { teamA != nil }

    private enum CodingKeys: String, CodingKey {
        case matchNo, playerA, playerB, playerC, teamA, teamB, result
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchNo = try c.decodeIfPresent(Int.self, forKey: .matchNo)
        playerA = try c.decodeIfPresent(String.self, forKey: .playerA)
        playerB = try c.decodeIfPresent(String.self, forKey: .playerB)
        playerC = try c.decodeIfPresent(String.self, forKey: .playerC)
        teamA = try c.decodeIfPresent(Int.self, forKey: .teamA)
        teamB = try c.decodeIfPresent(Int.self, forKey: .teamB)
        result = Result(stored: try c.decodeIfPresent(String.self, forKey: .result))
    }
}

/// Sidene i en match (`matchSider`). `c` finnes bare for singelmatcher (trekant eller ikke).
public struct MatchSides: Hashable, Sendable {
    public var a: [String]
    public var b: [String]
    public var c: [String]?

    /// Alle spillerne i matchen.
    public var all: [String] { a + b + (c ?? []) }
}

/// Hulldifferansen sett fra A (`matchHullDiff`).
public struct MatchHoleDiff: Hashable, Sendable {
    /// Hull opp (negativt = ned).
    public var up: Int
    /// Hull der begge sider har ført.
    public var played: Int
}

/// Stillingen sett fra én spiller (`matchStilling`).
public struct MatchStanding: Hashable, Sendable {
    /// Hull opp (negativt = ned).
    public var up: Int
    public var played: Int
    /// Tellende hull som gjenstår.
    public var remaining: Int
    /// Avgjort: flere hull opp enn det er igjen.
    public var decided: Bool
    /// Motstanderne. `opponent` er den første (`motstander`).
    public var opponents: [String]
    public var opponent: String? { opponents.first }

    public init(up: Int, played: Int, remaining: Int, decided: Bool, opponents: [String] = []) {
        self.up = up
        self.played = played
        self.remaining = remaining
        self.decided = decided
        self.opponents = opponents
    }
}

/// Matchspill hull for hull (db-nytt.js linje 398–634).
///
/// Alle funksjonene som trenger handicap tar inn troppen og seedinggruppene fra regelsettet,
/// med Golfgutu-gruppene som standard.
public enum MatchPlay {
    // MARK: Sidene

    /// `matcherForRunde`.
    public static func matches(in round: Round) -> [Match] {
        round.matches
    }

    /// `lagForRunde` for ett lagnummer. Spillerne sorteres på id, siden rekkefølgen fra
    /// databasen ikke er noe å stole på (JS bruker radrekkefølgen).
    static func teamMembers(_ number: Int, in round: Round) -> [String] {
        round.teams.filter { $0.value == number }.map(\.key).sorted()
    }

    /// `matchSider`: lagmatch slår opp lagene, ellers spillerne A, B og C.
    public static func sides(of match: Match, in round: Round) -> MatchSides {
        if let teamA = match.teamA {
            let b = match.teamB.map { teamMembers($0, in: round) } ?? []
            return MatchSides(a: teamMembers(teamA, in: round), b: b, c: nil)
        }
        return MatchSides(a: nonEmpty(match.playerA), b: nonEmpty(match.playerB), c: nonEmpty(match.playerC))
    }

    /// `matchGjelder`: er spilleren med i matchen?
    public static func involves(_ match: Match, playerID: String, in round: Round) -> Bool {
        sides(of: match, in: round).all.contains(playerID)
    }

    private static func nonEmpty(_ id: String?) -> [String] {
        guard let id, !id.isEmpty else { return [] }
        return [id]
    }

    // MARK: Slag

    /// `sideHandicap`: laveste `effectiveHandicap` på siden. Tom side → 0.
    public static func sideHandicap(_ playerIDs: [String], in round: Round, roster: [Player],
                                    groups: [SeedingGroup] = SeedingGroup.golfgutu) -> Double {
        playerIDs.map { effective($0, round, roster, groups) }.min() ?? 0
    }

    /// `matchSlag`: full forskjell. Den laveste i matchen spiller fra scratch, og dette tallet
    /// trekkes fra alle.
    public static func strokeOffset(for match: Match, in round: Round, roster: [Player],
                                    groups: [SeedingGroup] = SeedingGroup.golfgutu) -> Double {
        let s = sides(of: match, in: round)
        return min(sideHandicap(s.a, in: round, roster: roster, groups: groups),
                   sideHandicap(s.b, in: round, roster: roster, groups: groups))
    }

    /// `sideNettoPaaHull`: beste netto på siden på hullet. Slagene er `effectiveHandicap − ekstraSlag`
    /// (ikke under 0), fordelt over hele runden. `nil` når ingen på siden har ført, eller hullet
    /// ikke finnes.
    public static func sideNet(_ playerIDs: [String], hole: Int, extraStrokes: Double, in round: Round,
                               roster: [Player], groups: [SeedingGroup] = SeedingGroup.golfgutu) -> Int? {
        let course = round.courseHoles()
        guard hole >= 0, hole < course.count else { return nil }
        let played = course[hole]
        var best: Int?
        for pid in playerIDs {
            guard let gross = round.holeScores[pid]?[hole] else { continue }
            let own = effective(pid, round, roster, groups)
            let net = Scoring.netStrokes(gross: gross, handicap: max(0, own - extraStrokes),
                                         strokeIndex: played.strokeIndex, holes: round.numberOfHoles)
            if best == nil || net < best! { best = net }
        }
        return best
    }

    // MARK: Hull for hull

    /// `matchHullVinner`: 1 når A vant hullet, −1 når B vant, 0 delt. `nil` når en side ikke har ført.
    /// Laveste netto vinner, ikke stableford.
    public static func holeWinner(_ match: Match, hole: Int, in round: Round, roster: [Player],
                                  groups: [SeedingGroup] = SeedingGroup.golfgutu, strokeOffset lowest: Double? = nil) -> Int? {
        let s = sides(of: match, in: round)
        guard !s.a.isEmpty, !s.b.isEmpty else { return nil }
        let lav = lowest ?? strokeOffset(for: match, in: round, roster: roster, groups: groups)
        guard let a = sideNet(s.a, hole: hole, extraStrokes: lav, in: round, roster: roster, groups: groups),
              let b = sideNet(s.b, hole: hole, extraStrokes: lav, in: round, roster: roster, groups: groups) else { return nil }
        return a < b ? 1 : (b < a ? -1 : 0)
    }

    /// `matchHullDiff`: summen over de tellende hullene, sett fra A. Slagfordelingen går fortsatt
    /// over hele runden. `nil` når en side er tom.
    public static func holeDiff(_ match: Match, in round: Round, roster: [Player],
                                groups: [SeedingGroup] = SeedingGroup.golfgutu) -> MatchHoleDiff? {
        let s = sides(of: match, in: round)
        guard !s.a.isEmpty, !s.b.isEmpty else { return nil }
        let lav = strokeOffset(for: match, in: round, roster: roster, groups: groups)
        var diff = MatchHoleDiff(up: 0, played: 0)
        for h in 0..<Truncation.countingHoles(round) {
            guard let v = holeWinner(match, hole: h, in: round, roster: roster, groups: groups, strokeOffset: lav) else { continue }
            diff.played += 1
            diff.up += v
        }
        return diff
    }

    // MARK: Utfall og poeng

    /// `matchUtfallForA`: 1 seier, 0,5 delt, 0 tap. Manuelt resultat vinner over hullene.
    /// `nil` for trekant, og når ingen hull er spilt.
    public static func outcomeForA(_ match: Match, in round: Round, roster: [Player],
                                   groups: [SeedingGroup] = SeedingGroup.golfgutu) -> Double? {
        if match.isTriangle { return nil }
        if let result = match.result {
            switch result {
            case .a: return 1
            case .b: return 0
            case .halved: return 0.5
            }
        }
        guard let d = holeDiff(match, in: round, roster: roster, groups: groups), d.played > 0 else { return nil }
        return d.up > 0 ? 1 : (d.up < 0 ? 0 : 0.5)
    }

    /// `poengForUtfall`: hva utfallet er verdt i tabellen, etter regelsettet.
    public static func points(forOutcome outcome: Double?, _ points: Ruleset.MatchPoints = Ruleset.golfgutu.matchPoints) -> Double {
        outcome == 1 ? points.win : (outcome == 0.5 ? points.draw : points.loss)
    }

    // MARK: Stilling og tekst

    /// `matchStilling`: stillingen sett fra spilleren. `nil` for trekant og tom side.
    /// Hull igjen måles mot de tellende hullene.
    public static func standing(_ match: Match, from playerID: String, in round: Round, roster: [Player],
                                groups: [SeedingGroup] = SeedingGroup.golfgutu) -> MatchStanding? {
        if match.isTriangle { return nil }
        guard let d = holeDiff(match, in: round, roster: roster, groups: groups) else { return nil }
        let s = sides(of: match, in: round)
        let onB = s.b.contains(playerID)
        let mine = onB ? -d.up : d.up
        let remaining = Truncation.countingHoles(round) - d.played
        return MatchStanding(up: mine, played: d.played, remaining: remaining,
                             decided: abs(mine) > remaining && d.played > 0,
                             opponents: onB ? s.a : s.b)
    }

    /// `matchTekst`: «Vunnet 3&2», «Tapt 4 ned», «Delt etter 5», «2 opp etter 6», «Ikke startet».
    public static func text(_ standing: MatchStanding?) -> String {
        guard let st = standing else { return "" }
        if st.played == 0 { return "Ikke startet" }
        let n = abs(st.up)
        let dir = st.up > 0 ? " opp" : " ned"
        if st.decided || st.remaining == 0 {
            if st.up == 0 { return "Delt" }
            let outcome = st.up > 0 ? "Vunnet " : "Tapt "
            return st.remaining > 0 ? "\(outcome)\(n)&\(st.remaining)" : "\(outcome)\(n)\(dir)"
        }
        if st.up == 0 { return "Delt etter \(st.played)" }
        return "\(n)\(dir) etter \(st.played)"
    }

    /// `matchStillingKort`: «2 opp», «1 ned», «Delt» eller «—» (em dash).
    public static func shortText(_ standing: MatchStanding?) -> String {
        guard let st = standing, st.played > 0 else { return "—" }
        if st.up == 0 { return "Delt" }
        return "\(abs(st.up))" + (st.up > 0 ? " opp" : " ned")
    }

    // MARK: Runder som avgjøres hull for hull

    /// `hullMatchFor`: spillerens første match som ikke er en trekant.
    public static func holeMatch(for playerID: String, in round: Round) -> Match? {
        round.matches.first { !$0.isTriangle && involves($0, playerID: playerID, in: round) }
    }

    /// `avgjoresHullForHull`: har runden minst én match som ikke er en trekant?
    public static func isDecidedHoleByHole(_ round: Round) -> Bool {
        round.matches.contains { !$0.isTriangle }
    }

    // MARK: Hjelpere

    static func effective(_ pid: String, _ round: Round, _ roster: [Player], _ groups: [SeedingGroup]) -> Double {
        Handicap.effective(for: roster.first { $0.id == pid }, in: round, roster: roster, groups: groups)
    }
}
