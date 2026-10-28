import Foundation

// Føring og visning i runden (regelvern, inspirert av Golfify): maks slag per hull, låst kort etter
// levering, hvor mange av de siste hullene som skjules, og om lagkamerater fører for hverandre.
// Golfgutu-oppsettet har standarden (`PlayRules.standard`), som er slik PWA-en gjør det: ingen grense,
// ingen levering, og «skjul de siste hullene» skjuler tre. Da skrives gruppen ikke, og JSON-en er som
// før. Se REGELSETT.md.

extension Ruleset {
    /// Høyeste antall slag som kan føres på et hull.
    public enum MaxStrokes: Hashable, Sendable {
        /// Ingen grense utover inndatagrensen på skjermen (Golfgutu, som PWA-en).
        case off
        /// Netto dobbel bogey: par + 2 + slagene spilleren får på hullet.
        case netDoubleBogey
        /// Et fast tall slag.
        case fixed(Int)

        /// Det høyeste en spiller kan føre på et hull med `par` når hun får `strokesReceived` slag.
        /// `nil`: ingen grense.
        public func limit(par: Int, strokesReceived: Int) -> Int? {
            switch self {
            case .off: nil
            case .netDoubleBogey: par + 2 + max(0, strokesReceived)
            case .fixed(let strokes): strokes
            }
        }

        /// Grensen for et fast tall: et hull må kunne spilles på par 3 med litt å gå på, og databasen
        /// tar høyst 20.
        public static let fixedRange = 3...20
    }

    /// Føring og visning i runden.
    public struct PlayRules: Hashable, Sendable {
        /// Maks slag per hull. Føringen lar deg ikke gå over, og motoren kapper scorer som står over.
        public var maxStrokes: MaxStrokes
        /// Markøren leverer kortet når båsen er ferdig, og bare arrangøren kan åpne det igjen.
        public var lockSubmittedCards: Bool
        /// Hvor mange av de siste hullene «Skjul de siste hullene» skjuler i en ny runde (1–9).
        public var hiddenHoles: Int
        /// Shank (brutto firedobbel bogey eller verre) står i feeden, uten push (sql/073).
        public var shankPosts: Bool
        /// I lagformer der hver spiller sin egen ball (fourball, sammenlagt lag), fører lagkameratene for
        /// hverandre, også med markør i båsen (sql/074). Lag med én ball fører alltid lagets kort (sql/071).
        /// En-mot-en: du fører ditt eget, eller markøren.
        public var teammatesScore: Bool

        public init(maxStrokes: MaxStrokes = .off, lockSubmittedCards: Bool = false, hiddenHoles: Int = 3,
                    shankPosts: Bool = false, teammatesScore: Bool = true) {
            self.maxStrokes = maxStrokes
            self.lockSubmittedCards = lockSubmittedCards
            self.hiddenHoles = hiddenHoles
            self.shankPosts = shankPosts
            self.teammatesScore = teammatesScore
        }

        /// Golfgutu og alle regelsett fra før: ingen grense, ingen levering, tre skjulte hull, ingen shank,
        /// og lagkamerater fører for hverandre.
        public static let standard = PlayRules()

        /// Lovlige antall skjulte hull (`rounds.hide_last_holes` tar 0–9, og 0 er «av»).
        public static let hiddenHolesRange = 1...9

        /// Problemene i gruppen, med feltstier som i JSON-en.
        func issues() -> [RulesetIssue] {
            var out: [RulesetIssue] = []
            if case .fixed(let n) = maxStrokes, !MaxStrokes.fixedRange.contains(n) {
                out.append(RulesetIssue(field: "play.maxStrokes.strokes",
                                        message: "Maks slag per hull må være fra \(MaxStrokes.fixedRange.lowerBound) til \(MaxStrokes.fixedRange.upperBound)."))
            }
            if !Self.hiddenHolesRange.contains(hiddenHoles) {
                out.append(RulesetIssue(field: "play.hiddenHoles",
                                        message: "Antall skjulte hull må være fra \(Self.hiddenHolesRange.lowerBound) til \(Self.hiddenHolesRange.upperBound)."))
            }
            return out
        }
    }
}

// MARK: - Maks slag i utregningen

extension Round {
    /// Grensen for `playerID` på hull `hole` (0-basert i runden), eller `nil` uten grense.
    /// Slagene fått regnes som i stablefordregningen (`Handicap.effective`, stroke index).
    public func strokeLimit(hole: Int, playerID: String, roster: [Player], rules: Ruleset) -> Int? {
        guard rules.play.maxStrokes != .off else { return nil }
        let course = courseHoles()
        guard course.indices.contains(hole) else { return nil }
        let hcp = Handicap.effective(for: roster.first { $0.id == playerID }, in: self, roster: roster, rules: rules)
        return limit(hole: course[hole], handicap: hcp, rules: rules)
    }

    /// Runden med hver score kappet til grensen i regelsettet (`play.maxStrokes`). Uendret når
    /// grensen er av (Golfgutu). En score som ble ført før grensen kom (eller fra et sted uten
    /// grense), teller som grensen.
    public func cappingStrokes(roster: [Player], rules: Ruleset) -> Round {
        guard rules.play.maxStrokes != .off, !holeScores.isEmpty else { return self }
        let course = courseHoles()
        var r = self
        for (pid, scores) in holeScores {
            let hcp = Handicap.effective(for: roster.first { $0.id == pid }, in: self, roster: roster, rules: rules)
            var capped = scores
            for (h, gross) in scores where course.indices.contains(h) {
                if let max = limit(hole: course[h], handicap: hcp, rules: rules), gross > max { capped[h] = max }
            }
            r.holeScores[pid] = capped
        }
        return r
    }

    private func limit(hole: PlayedHole, handicap: Double, rules: Ruleset) -> Int? {
        let received = Scoring.handicapStrokes(handicap: handicap, strokeIndex: hole.strokeIndex, holes: numberOfHoles)
        return rules.play.maxStrokes.limit(par: hole.par, strokesReceived: received)
    }
}

// MARK: - JSON

extension Ruleset.MaxStrokes: Codable {
    private enum CodingKeys: String, CodingKey { case type, strokes }
    private enum Kind: String, Codable { case off, netDoubleBogey, fixed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .off: self = .off
        case .netDoubleBogey: self = .netDoubleBogey
        case .fixed: self = .fixed(try c.decode(Int.self, forKey: .strokes))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .off: try c.encode(Kind.off, forKey: .type)
        case .netDoubleBogey: try c.encode(Kind.netDoubleBogey, forKey: .type)
        case .fixed(let n):
            try c.encode(Kind.fixed, forKey: .type)
            try c.encode(n, forKey: .strokes)
        }
    }
}

extension Ruleset.PlayRules: Codable {
    private enum CodingKeys: String, CodingKey { case maxStrokes, lockSubmittedCards, hiddenHoles, shankPosts, teammatesScore }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = Ruleset.PlayRules.standard
        maxStrokes = try c.decodeIfPresent(Ruleset.MaxStrokes.self, forKey: .maxStrokes) ?? s.maxStrokes
        lockSubmittedCards = try c.decodeIfPresent(Bool.self, forKey: .lockSubmittedCards) ?? s.lockSubmittedCards
        hiddenHoles = try c.decodeIfPresent(Int.self, forKey: .hiddenHoles) ?? s.hiddenHoles
        shankPosts = try c.decodeIfPresent(Bool.self, forKey: .shankPosts) ?? s.shankPosts
        teammatesScore = try c.decodeIfPresent(Bool.self, forKey: .teammatesScore) ?? s.teammatesScore
    }
}
