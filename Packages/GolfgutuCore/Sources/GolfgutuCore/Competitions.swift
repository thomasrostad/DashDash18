import Foundation

// Konkurranser over flere runder (fase 15): liga, cup (utslag i matchspill) og morroturnering.
// Sesongen (jakkeracet) regnes av `Season` som før, og endres ikke her.
//
// Ingen regelverdier i koden: hver type har en mal med standardverdier (`LeagueRules.league`,
// `LeagueRules.fun`, `CupRules.standard`), og konkurransens regelsett kan overstyre dem under
// `competition` (`Ruleset.competition`). Felt som mangler i JSON-en, får malens verdi.
// Golfgutu-oppsettet har ingen `competition`, så jakkeracet er urørt. Fasiten er
// `Tests/GolfgutuCoreTests/Fixtures/konkurranser.json`.
//
// Liga og morroturnering:
// - Inn: de påmeldte (i navnerekkefølge) og de tellende rundene i tidsrekkefølge, med
//   stablefordpoengene til dem som spilte. Spillere som ikke er påmeldt, strykes før runden
//   regnes, så de tar ikke plasser fra de påmeldte.
// - Poeng per runde: etter plassering (stableford avgjør plassen; delt plass deler summen av
//   plassenes poeng likt) eller selve stablefordpoengene, pluss deltakerpoeng for å ha spilt.
// - De beste N rundene teller (`bestRounds`), ellers alle. Likt poeng: den tidligste runden teller.
// - Tabellen: flest poeng, så skillene i rekkefølge (høyest først), så rekkefølgen inn (navn).
//   Like på alt gir delt plass.
//
// Cup:
// - Seeding: trekning (tilfeldig, men gjentakbar med et frø), lavest handicap eller en rangering
//   (f.eks. plassen i hovedturneringen). Trekningen er Fisher–Yates bakfra med SplitMix64 over
//   deltakerne sortert på id, så en annen plattform kan gjenskape den.
// - Treet: neste toerpotens; seedene plasseres som vanlig (1–8, 4–5, 2–7, 3–6 …), og de beste
//   seedene får walkover (bye) i første runde når deltakerne ikke fyller treet.
// - Vinneren av kamp `slot` i runde r møter vinneren av nabokampen i runde r + 1, kamp `slot / 2`.
// - En kamp avgjøres i en runde de begge spiller, som matchspill med regelsettets slag
//   (`MatchPlay`). Står det likt etter siste hull, gjelder cupens regel for uavgjort.

// MARK: - Malene

/// Liga og morroturnering: poeng per runde og hva som teller.
public struct LeagueRules: Hashable, Sendable {
    /// Hva en runde gir.
    public enum Scoring: String, Codable, Hashable, Sendable, CaseIterable {
        /// Poeng etter plassen i runden (stableford avgjør plassen).
        case placement
        /// Stablefordpoengene i runden.
        case stableford
    }

    /// Et skille ved poenglikhet i tabellen. Høyest først.
    public enum Tiebreak: String, Codable, Hashable, Sendable, CaseIterable {
        /// Flest rundeseire (førsteplass, også delt).
        case wins
        /// Beste enkeltrunde (poeng).
        case bestRound
        /// Stablefordsummen i de tellende rundene.
        case stableford
    }

    public var scoring: Scoring
    /// Poeng for 1., 2., 3. plass … Plasser utover lista gir 0.
    public var placementPoints: [Double]
    /// Poeng for å ha spilt en tellende runde (i tillegg).
    public var participationPoints: Double
    /// De beste N rundene teller. `nil`: alle.
    public var bestRounds: Int?
    /// Skillene ved likt totalpoeng, i rekkefølge. Rekkefølgen inn (navn) er alltid det siste.
    public var tiebreaks: [Tiebreak]

    public init(scoring: Scoring, placementPoints: [Double], participationPoints: Double, bestRounds: Int?,
                tiebreaks: [Tiebreak]) {
        self.scoring = scoring
        self.placementPoints = placementPoints
        self.participationPoints = participationPoints
        self.bestRounds = bestRounds
        self.tiebreaks = tiebreaks
    }

    /// Ligamalen: plasseringspoeng 10, 8, 6, 5, 4, 3, 2, 1 og 1 poeng for å spille, alle runder
    /// teller, skille på seire, beste runde og stablefordsum.
    public static let league = LeagueRules(scoring: .placement, placementPoints: [10, 8, 6, 5, 4, 3, 2, 1],
                                           participationPoints: 1, bestRounds: nil,
                                           tiebreaks: [.wins, .bestRound, .stableford])

    /// Morromalen: stablefordpoengene teller rett fram, alle runder, skille på beste runde og seire.
    public static let fun = LeagueRules(scoring: .stableford, placementPoints: league.placementPoints,
                                        participationPoints: 0, bestRounds: nil, tiebreaks: [.bestRound, .wins])

    private enum CodingKeys: String, CodingKey {
        case scoring, placementPoints, participationPoints, bestRounds, tiebreaks
    }

    /// Reglene fra JSON-en: feltene som mangler, får malens verdi (`fallback`). `bestRounds: null`
    /// er et valg (alle teller).
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K, fallback: LeagueRules) throws -> LeagueRules {
        guard c.contains(key), try !c.decodeNil(forKey: key) else { return fallback }
        let n = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: key)
        return LeagueRules(
            scoring: try n.decodeIfPresent(Scoring.self, forKey: .scoring) ?? fallback.scoring,
            placementPoints: try n.decodeIfPresent([Double].self, forKey: .placementPoints) ?? fallback.placementPoints,
            participationPoints: try n.decodeIfPresent(Double.self, forKey: .participationPoints)
                ?? fallback.participationPoints,
            bestRounds: n.contains(.bestRounds) ? try n.decodeIfPresent(Int.self, forKey: .bestRounds) : fallback.bestRounds,
            tiebreaks: try n.decodeIfPresent([Tiebreak].self, forKey: .tiebreaks) ?? fallback.tiebreaks)
    }
}

extension LeagueRules: Codable {
    public init(from decoder: Decoder) throws {
        // Et frittstående objekt leses med ligamalen som grunnlag.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = LeagueRules.league
        self.init(scoring: try c.decodeIfPresent(Scoring.self, forKey: .scoring) ?? f.scoring,
                  placementPoints: try c.decodeIfPresent([Double].self, forKey: .placementPoints) ?? f.placementPoints,
                  participationPoints: try c.decodeIfPresent(Double.self, forKey: .participationPoints) ?? f.participationPoints,
                  bestRounds: c.contains(.bestRounds) ? try c.decodeIfPresent(Int.self, forKey: .bestRounds) : f.bestRounds,
                  tiebreaks: try c.decodeIfPresent([Tiebreak].self, forKey: .tiebreaks) ?? f.tiebreaks)
    }

    /// `bestRounds: null` skrives ut, så det står i JSON-en at alle runder teller.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scoring, forKey: .scoring)
        try c.encode(placementPoints, forKey: .placementPoints)
        try c.encode(participationPoints, forKey: .participationPoints)
        try c.encode(bestRounds, forKey: .bestRounds)
        try c.encode(tiebreaks, forKey: .tiebreaks)
    }
}

/// Cup: seeding og hva som skjer ved uavgjort.
public struct CupRules: Codable, Hashable, Sendable {
    public enum Seeding: String, Codable, Hashable, Sendable, CaseIterable {
        /// Trekning.
        case random
        /// Lavest handicapindeks er seed 1.
        case handicap
        /// En rangering arrangøren gir (f.eks. plassen i hovedturneringen). Uten rangering: handicap.
        case ranking
    }

    /// Likt etter siste hull.
    public enum Tie: String, Codable, Hashable, Sendable, CaseIterable {
        /// De spiller videre til noen vinner et hull. Arrangøren fører vinneren.
        case suddenDeath
        /// Den som vant det siste hullet som ikke var delt (bakfra). Alle delt: som sudden death.
        case countback
        /// Den beste seeden går videre.
        case higherSeed
        /// Den med lavest handicap i runden går videre. Likt: som sudden death.
        case lowerHandicap
    }

    public var seeding: Seeding
    public var tie: Tie

    public init(seeding: Seeding, tie: Tie) {
        self.seeding = seeding
        self.tie = tie
    }

    /// Malen: trekning, og sudden death ved likt.
    public static let standard = CupRules(seeding: .random, tie: .suddenDeath)

    private enum CodingKeys: String, CodingKey { case seeding, tie }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = CupRules.standard
        seeding = try c.decodeIfPresent(Seeding.self, forKey: .seeding) ?? s.seeding
        tie = try c.decodeIfPresent(Tie.self, forKey: .tie) ?? s.tie
    }
}

/// Reglene for konkurransetypene. Ligger i regelsettet under `competition`; feltene som mangler,
/// får malene.
public struct CompetitionRules: Hashable, Sendable {
    public var league: LeagueRules
    public var fun: LeagueRules
    public var cup: CupRules

    public init(league: LeagueRules = .league, fun: LeagueRules = .fun, cup: CupRules = .standard) {
        self.league = league
        self.fun = fun
        self.cup = cup
    }

    public static let standard = CompetitionRules()
}

extension CompetitionRules: Codable {
    private enum CodingKeys: String, CodingKey { case league, fun, cup }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        league = try LeagueRules.decode(c, .league, fallback: .league)
        fun = try LeagueRules.decode(c, .fun, fallback: .fun)
        cup = try c.decodeIfPresent(CupRules.self, forKey: .cup) ?? .standard
    }
}

extension Ruleset {
    /// Reglene for liga, cup og morroturnering, med malene for det som mangler.
    public var competitionRules: CompetitionRules { competition ?? .standard }
}

extension CompetitionRules {
    /// Gyldighetssjekk før konkurransen lagres. Tom liste: alt er i orden.
    public func validate() -> [RulesetIssue] {
        var issues: [RulesetIssue] = []
        func check(_ r: LeagueRules, _ field: String) {
            if r.placementPoints.contains(where: { $0 < 0 || !$0.isFinite }) {
                issues.append(.init(field: "\(field).placementPoints", message: "Plasseringspoeng kan ikke være negative."))
            }
            if zip(r.placementPoints, r.placementPoints.dropFirst()).contains(where: { $0 < $1 }) {
                issues.append(.init(field: "\(field).placementPoints",
                                    message: "En bedre plass må gi minst like mange poeng som en dårligere."))
            }
            if r.scoring == .placement, r.placementPoints.isEmpty {
                issues.append(.init(field: "\(field).placementPoints", message: "Plasseringspoeng trenger minst én plass."))
            }
            if r.participationPoints < 0 || !r.participationPoints.isFinite {
                issues.append(.init(field: "\(field).participationPoints", message: "Deltakerpoeng kan ikke være negative."))
            }
            if let best = r.bestRounds, best < 1 {
                issues.append(.init(field: "\(field).bestRounds",
                                    message: "«Beste N runder» må være minst 1. La feltet stå tomt for at alle skal telle."))
            }
            if Set(r.tiebreaks).count != r.tiebreaks.count {
                issues.append(.init(field: "\(field).tiebreaks", message: "Et skille står to ganger."))
            }
        }
        check(league, "competition.league")
        check(fun, "competition.fun")
        return issues
    }
}

// MARK: - Liga og morroturnering

public enum League {
    /// En tellende runde: stablefordpoengene til dem som spilte, spiller-id → poeng.
    public struct Round: Codable, Hashable, Sendable {
        public var id: String
        public var stableford: [String: Int]

        public init(id: String, stableford: [String: Int]) {
            self.id = id
            self.stableford = stableford
        }
    }

    /// Plassen og poengene i én runde.
    public struct Placing: Hashable, Sendable {
        /// 1, 2, 2, 4 …: delt plass har samme nummer.
        public var place: Int
        public var points: Double
    }

    /// Spillerens resultat i én runde.
    public struct RoundResult: Hashable, Sendable {
        public var roundID: String
        public var place: Int
        public var stableford: Int
        public var points: Double
        /// Blant de beste N.
        public var counted: Bool
    }

    /// En rad i tabellen.
    public struct Row: Hashable, Sendable {
        public var playerID: String
        /// 1, 1, 3 …: like på total og alle skillene gir delt plass.
        public var place: Int
        /// Summen av de tellende rundene.
        public var total: Double
        public var played: Int
        /// Førsteplasser (også delte).
        public var wins: Int
        /// Beste enkeltrunde (poeng). `nil` før første runde.
        public var bestRound: Double?
        /// Stablefordsummen i de tellende rundene.
        public var stableford: Int
        /// Rundene spilleren spilte, i tidsrekkefølge.
        public var results: [RoundResult]
    }

    /// Plass og poeng i runden for de påmeldte som spilte. Andre spillere strykes først.
    public static func placings(_ round: Round, entrants: Set<String>, rules: LeagueRules) -> [String: Placing] {
        let scores = round.stableford.filter { entrants.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var out: [String: Placing] = [:]
        var i = 0
        while i < scores.count {
            let value = scores[i].value
            var j = i
            while j < scores.count, scores[j].value == value { j += 1 }
            // Plassene i..<j deler summen av plassenes poeng.
            let shared = (i..<j).reduce(0.0) { $0 + (rules.placementPoints.indices.contains($1) ? rules.placementPoints[$1] : 0) }
                / Double(j - i)
            for k in i..<j {
                let base = rules.scoring == .placement ? shared : Double(value)
                out[scores[k].key] = Placing(place: i + 1, points: base + rules.participationPoints)
            }
            i = j
        }
        return out
    }

    /// Tabellen. `entrants` i rekkefølgen som skiller til slutt (navn), `rounds` i tidsrekkefølge.
    public static func table(entrants: [String], rounds: [Round], rules: LeagueRules) -> [Row] {
        let set = Set(entrants)
        let perRound = rounds.map { placings($0, entrants: set, rules: rules) }
        var rows: [Row] = entrants.map { id in
            var results: [RoundResult] = []
            for (r, round) in rounds.enumerated() {
                guard let p = perRound[r][id], let s = round.stableford[id] else { continue }
                results.append(RoundResult(roundID: round.id, place: p.place, stableford: s, points: p.points, counted: true))
            }
            // De beste N: flest poeng, og den tidligste ved likt.
            if let best = rules.bestRounds {
                let keep = Set(results.indices.sorted { a, b in
                    results[a].points != results[b].points ? results[a].points > results[b].points : a < b
                }.prefix(best))
                for i in results.indices { results[i].counted = keep.contains(i) }
            }
            let counted = results.filter(\.counted)
            return Row(playerID: id, place: 0, total: counted.reduce(0) { $0 + $1.points }, played: results.count,
                       wins: results.filter { $0.place == 1 }.count, bestRound: results.map(\.points).max(),
                       stableford: counted.reduce(0) { $0 + $1.stableford }, results: results)
        }

        func key(_ row: Row) -> [Double] {
            [row.total] + rules.tiebreaks.map { t in
                switch t {
                case .wins: Double(row.wins)
                case .bestRound: row.bestRound ?? 0
                case .stableford: Double(row.stableford)
                }
            }
        }
        // Summer av brøker sammenlignes på tusendeler, så 1/3 + 2/3 er lik 1.
        func rounded(_ k: [Double]) -> [Double] { k.map { ($0 * 1000).rounded() } }
        let order = Dictionary(uniqueKeysWithValues: entrants.enumerated().map { ($1, $0) })
        rows.sort { a, b in
            let ka = rounded(key(a)), kb = rounded(key(b))
            if ka != kb { return ka.lexicographicallyPrecedes(kb, by: >) }
            return order[a.playerID, default: 0] < order[b.playerID, default: 0]
        }
        for i in rows.indices {
            rows[i].place = i > 0 && rounded(key(rows[i])) == rounded(key(rows[i - 1])) ? rows[i - 1].place : i + 1
        }
        return rows
    }
}

// MARK: - Cup

public enum Cup {
    /// En deltaker i cupen med det seedingen trenger.
    public struct Entrant: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var handicap: Double?
        /// Plassen i rangeringen (1 = best). `nil`: ikke rangert.
        public var rank: Int?

        public init(id: String, name: String = "", handicap: Double? = nil, rank: Int? = nil) {
            self.id = id
            self.name = name
            self.handicap = handicap
            self.rank = rank
        }

        private enum CodingKeys: String, CodingKey { case id, name, handicap, rank }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            handicap = try c.decodeIfPresent(Double.self, forKey: .handicap)
            rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        }
    }

    /// En kamp i første runde. `b` tom: walkover (bye) for `a`.
    public struct Pairing: Codable, Hashable, Sendable {
        public var slot: Int
        public var a: String
        public var b: String?

        public init(slot: Int, a: String, b: String?) {
            self.slot = slot
            self.a = a
            self.b = b
        }
    }

    /// Et ført resultat: vinneren av kamp `slot` i runde `round` (1 = første).
    public struct Result: Codable, Hashable, Sendable {
        public var round: Int
        public var slot: Int
        public var winner: String
        /// Motstanderen stilte ikke (eller trakk seg).
        public var walkover: Bool

        public init(round: Int, slot: Int, winner: String, walkover: Bool = false) {
            self.round = round
            self.slot = slot
            self.winner = winner
            self.walkover = walkover
        }
    }

    /// En kamp i treet.
    public struct Match: Hashable, Sendable {
        public enum State: String, Hashable, Sendable {
            /// Minst én spiller er ikke klar (venter på en kamp før).
            case waiting
            /// Begge er klare, ingen vinner ennå.
            case ready
            /// Avgjort, også walkover og bye.
            case decided
        }

        public var round: Int
        public var slot: Int
        public var a: String?
        public var b: String?
        public var winner: String?
        /// Bye i første runde: `a` går rett videre.
        public var isBye: Bool
        public var walkover: Bool

        public var state: State {
            if winner != nil { return .decided }
            return a != nil && b != nil ? .ready : .waiting
        }

        public func involves(_ id: String) -> Bool { a == id || b == id }

        public func opponent(of id: String) -> String? {
            a == id ? b : (b == id ? a : nil)
        }
    }

    /// Hele treet med det som er avgjort.
    public struct Bracket: Hashable, Sendable {
        /// Rundene, første først. Siste runde er finalen (én kamp).
        public var rounds: [[Match]]
        public var champion: String?

        public var size: Int { (rounds.first?.count ?? 0) * 2 }

        /// Kampen spilleren skal spille nå (klar eller venter på motstander), eller nil når hen er ute
        /// eller har vunnet.
        public func nextMatch(for id: String) -> Match? {
            for round in rounds {
                if let m = round.first(where: { $0.involves(id) }), m.winner == nil { return m }
            }
            return nil
        }

        /// Motstanderen i neste kamp, når den er kjent.
        public func opponent(of id: String) -> String? {
            nextMatch(for: id)?.opponent(of: id)
        }

        /// Hen tapte en kamp.
        public func isEliminated(_ id: String) -> Bool {
            rounds.joined().contains { $0.involves(id) && $0.winner != nil && $0.winner != id }
        }

        /// Kampene som kan spilles nå.
        public var readyMatches: [Match] { rounds.joined().filter { $0.state == .ready } }

        public func match(round: Int, slot: Int) -> Match? {
            guard round >= 1, round <= rounds.count, slot >= 0, slot < rounds[round - 1].count else { return nil }
            return rounds[round - 1][slot]
        }
    }

    /// Antall plasser i treet: minste toerpotens som rommer alle (minst 2).
    public static func bracketSize(entrants n: Int) -> Int {
        var size = 2
        while size < n { size *= 2 }
        return size
    }

    /// Seedenes plass i treet, ovenfra: 1, 8, 4, 5, 2, 7, 3, 6 for 8. Kamp i er plass 2i mot 2i + 1.
    public static func seedPositions(size: Int) -> [Int] {
        var order = [1, 2]
        while order.count < size {
            let n = order.count * 2
            order = order.flatMap { [$0, n + 1 - $0] }
        }
        return order
    }

    /// Deltakerne i seed-rekkefølge (seed 1 først).
    public static func seeded(_ entrants: [Entrant], rules: CupRules, randomSeed: UInt64) -> [String] {
        func byHandicap(_ a: Entrant, _ b: Entrant) -> Bool {
            switch (a.handicap, b.handicap) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let c = NorwegianSort.compare(a.name, b.name)
                return c != .orderedSame ? c == .orderedAscending : a.id < b.id
            }
        }
        switch rules.seeding {
        case .handicap:
            return entrants.sorted(by: byHandicap).map(\.id)
        case .ranking:
            return entrants.sorted { a, b in
                switch (a.rank, b.rank) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return byHandicap(a, b)
                }
            }.map(\.id)
        case .random:
            var ids = entrants.map(\.id).sorted()
            var rng = SplitMix64(seed: randomSeed)
            if ids.count > 1 {
                for i in stride(from: ids.count - 1, through: 1, by: -1) {
                    let j = Int(rng.next() % UInt64(i + 1))
                    ids.swapAt(i, j)
                }
            }
            return ids
        }
    }

    /// Første runde fra seed-rekkefølgen. De beste seedene får bye når deltakerne ikke fyller treet.
    public static func draw(seeded: [String]) -> [Pairing] {
        guard seeded.count >= 2 else { return [] }
        let positions = seedPositions(size: bracketSize(entrants: seeded.count))
        return stride(from: 0, to: positions.count, by: 2).map { i in
            let x = min(positions[i], positions[i + 1]), y = max(positions[i], positions[i + 1])
            return Pairing(slot: i / 2, a: seeded[x - 1], b: y <= seeded.count ? seeded[y - 1] : nil)
        }
    }

    /// Treet fra første runde og resultatene. Et resultat som ikke passer (feil runde, spilleren er
    /// ikke i kampen, kampen er ikke klar), hoppes over.
    public static func bracket(draw: [Pairing], results: [Result]) -> Bracket {
        guard !draw.isEmpty else { return Bracket(rounds: [], champion: nil) }
        // Én kamp per plass (den siste vinner), og plassene fylt opp til en toerpotens, så treet tåler
        // rader som ikke passer (de blir tomme kamper).
        let byslot = Dictionary(draw.map { ($0.slot, $0) }, uniquingKeysWith: { _, last in last })
        let slots = bracketSize(entrants: ((byslot.keys.max() ?? 0) + 1) * 2) / 2
        var roundCount = 1
        while (1 << roundCount) < slots * 2 { roundCount += 1 }
        let byKey = Dictionary(results.map { ("\($0.round):\($0.slot)", $0) }, uniquingKeysWith: { _, last in last })

        func apply(_ m: inout Match) {
            guard m.winner == nil, let a = m.a, let b = m.b, let r = byKey["\(m.round):\(m.slot)"],
                  r.winner == a || r.winner == b else { return }
            m.winner = r.winner
            m.walkover = r.walkover
        }

        var rounds: [[Match]] = []
        var first = (0..<slots).map { i in
            guard let p = byslot[i] else {
                return Match(round: 1, slot: i, a: nil, b: nil, winner: nil, isBye: false, walkover: false)
            }
            return Match(round: 1, slot: i, a: p.a, b: p.b, winner: p.b == nil ? p.a : nil, isBye: p.b == nil,
                         walkover: false)
        }
        for i in first.indices { apply(&first[i]) }
        rounds.append(first)
        for r in stride(from: 2, through: roundCount, by: 1) {
            let previous = rounds[r - 2]
            var current = stride(from: 0, to: previous.count, by: 2).map { i in
                Match(round: r, slot: i / 2, a: previous[i].winner, b: previous[i + 1].winner, winner: nil,
                      isBye: false, walkover: false)
            }
            for i in current.indices { apply(&current[i]) }
            rounds.append(current)
        }
        return Bracket(rounds: rounds, champion: rounds.last?.first?.winner)
    }

    // MARK: Kampen i en runde

    /// Utfallet av en cupkamp spilt i en runde.
    public enum Decision: Hashable, Sendable {
        /// Ingen hull er spilt av begge.
        case notStarted
        /// Kampen pågår. `up` er sett fra a.
        case inProgress(up: Int, played: Int, remaining: Int)
        /// Avgjort. `tie` er regelen som avgjorde når det sto likt etter siste hull.
        case won(winner: String, up: Int, remaining: Int, tie: CupRules.Tie?)
        /// Likt etter siste hull, og regelen avgjør ikke: arrangøren fører vinneren.
        case tied
    }

    /// Kampen mellom `a` og `b` i runden, som matchspill med regelsettets slag (`MatchPlay`).
    /// `seeds`: spiller-id → seed (1 = best), for regelen `higherSeed`.
    public static func decide(a: String, b: String, in round: Round, roster: [Player], rules: Ruleset,
                              seeds: [String: Int] = [:]) -> Decision {
        let match = GolfgutuCore.Match(playerA: a, playerB: b)
        guard let st = MatchPlay.standing(match, from: a, in: round, roster: roster, rules: rules), st.played > 0 else {
            return .notStarted
        }
        if st.up != 0 && (st.decided || st.remaining == 0) {
            return .won(winner: st.up > 0 ? a : b, up: abs(st.up), remaining: st.remaining, tie: nil)
        }
        guard st.remaining == 0 else { return .inProgress(up: st.up, played: st.played, remaining: st.remaining) }

        let tie = rules.competitionRules.cup.tie
        switch tie {
        case .suddenDeath:
            return .tied
        case .countback:
            let lowest = MatchPlay.strokeOffset(for: match, in: round, roster: roster, rules: rules)
            for hole in stride(from: Truncation.countingHoles(round) - 1, through: 0, by: -1) {
                if let w = MatchPlay.holeWinner(match, hole: hole, in: round, roster: roster, rules: rules,
                                                strokeOffset: lowest), w != 0 {
                    return .won(winner: w > 0 ? a : b, up: 0, remaining: 0, tie: .countback)
                }
            }
            return .tied
        case .higherSeed:
            guard let sa = seeds[a], let sb = seeds[b], sa != sb else { return .tied }
            return .won(winner: sa < sb ? a : b, up: 0, remaining: 0, tie: .higherSeed)
        case .lowerHandicap:
            let ha = MatchPlay.sideHandicap([a], in: round, roster: roster, rules: rules)
            let hb = MatchPlay.sideHandicap([b], in: round, roster: roster, rules: rules)
            guard ha != hb else { return .tied }
            return .won(winner: ha < hb ? a : b, up: 0, remaining: 0, tie: .lowerHandicap)
        }
    }
}

/// SplitMix64 (Steele, Lea og Flood 2014): en liten, gjentakbar tallgenerator for trekningen.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
