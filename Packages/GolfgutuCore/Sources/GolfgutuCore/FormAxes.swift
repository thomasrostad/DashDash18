import Foundation

// Steg 7: en konkurranseform er to akser, lagform (hvem som spiller sammen) og poengtelling (hvordan
// runden regnes). Formene i katalogen (`CompetitionForm.catalog`) er faste par av akser, én til én
// begge veier, så id-ene i JSON (`Round.gameType`, `formats.allowedFormIDs`, fixturene) er som før.
// En konkurranse på runden (`RoundCompetition`) bruker aksene direkte.

/// Former for to spillere på en side (NGF «Spilleformer» 2023, side 2–4).
public enum PairForm: String, Codable, Hashable, Sendable, CaseIterable {
    /// Hver sin ball, beste ball på hullet teller.
    case fourball
    /// Én ball, annethvert slag.
    case foursome
    /// Begge slår ut, velger én ball, så annethvert slag.
    case greensome
    /// Chapman / Pinehurst: begge slår ut, bytter ball til andreslaget, velger én.
    case chapman
    /// Hver sin ball, begges score legges sammen («sammenlagt»).
    case aggregate
}

/// Lagformen: hvem som spiller sammen, og hvor mange.
public enum TeamForm: Hashable, Sendable {
    /// Hver for seg.
    case individual
    /// To og to.
    case pairs(PairForm)
    /// Flere på laget, hver sin ball, beste ball teller (f.eks. 4-mann beste ball).
    case team(size: Int)
    /// Scramble med lagstørrelse.
    case scramble(size: Int)

    /// Spillere per side.
    public var size: Int {
        switch self {
        case .individual: 1
        case .pairs: 2
        case .team(let n), .scramble(let n): n
        }
    }

    /// Laget fører ett kort (én ball).
    public var playsOneBall: Bool {
        switch self {
        case .individual, .team: false
        case .pairs(let p): p == .foursome || p == .greensome || p == .chapman
        case .scramble: true
        }
    }
}

/// Poengspill der spillerne i en gruppe deler et fast antall poeng per hull (se `PointsGame`).
public enum PointsGameKind: String, Codable, Hashable, Sendable, CaseIterable {
    /// Fire spillere, 12 poeng per hull (NGF side 3).
    case amerikaner
    /// Tre spillere, 6 poeng per hull (NGF side 4).
    case kobenhavner
}

/// Poengtellingen: hvordan runden regnes.
public enum ScoringMethod: Hashable, Sendable {
    /// Slagspill. Lavest sum vinner.
    case strokePlay(net: Bool)
    /// Stableford mot (netto) par. Høyest sum vinner.
    case stableford(net: Bool)
    /// Par/bogey: pluss, deling eller minus mot netto par.
    case parBogey
    /// Maksimumscore: slagspill med tak per hull.
    case maximumScore
    /// Matchspill, hull for hull.
    case matchPlay
    /// Poengspill i gruppe (Amerikaner, Københavner).
    case pointsGame(PointsGameKind)
    /// Skins: hvert hull er ett skin.
    case skins

    /// Høyest score er best (stableford, poeng, skins). Ellers lavest (slag).
    public var higherIsBetter: Bool {
        switch self {
        case .strokePlay, .maximumScore: false
        default: true
        }
    }
}

/// En form som to akser.
public struct FormAxes: Codable, Hashable, Sendable {
    public var teamForm: TeamForm
    public var scoring: ScoringMethod

    public init(teamForm: TeamForm, scoring: ScoringMethod) {
        self.teamForm = teamForm
        self.scoring = scoring
    }
}

// MARK: - Katalogen

extension CompetitionForm {
    /// Formene som er kommet til etter PWA-en (steg 7). Ikke med i `all` (PWA-katalogen) eller i
    /// Golfgutu-oppsettet, så JSON-en for det er som før.
    public static let added: [CompetitionForm] = [
        CompetitionForm(id: "amerikaner", name: "Amerikaner", teamSize: 1, card: .perPlayer,
                        scoring: "amerikaner", allowance: 1.0, support: .partial,
                        help: "Fire spiller slagspill og deler 12 poeng på hvert hull: 8, 4, 0, 0 (NGF)."),
        CompetitionForm(id: "kobenhavner", name: "Københavner", teamSize: 1, card: .perPlayer,
                        scoring: "kobenhavner", allowance: 1.0, support: .partial,
                        help: "Tre spiller slagspill og deler 6 poeng på hvert hull: 4, 2, 0 (NGF)."),
    ]

    /// Alle formene motoren kjenner: PWA-katalogen og de nye.
    public static let catalog: [CompetitionForm] = all + added

    /// Aksene per form-id. Én til én: ingen to former har samme akser.
    static let axesByID: [String: FormAxes] = [
        "stableford": FormAxes(teamForm: .individual, scoring: .stableford(net: true)),
        "stableford-brutto": FormAxes(teamForm: .individual, scoring: .stableford(net: false)),
        "slag-netto": FormAxes(teamForm: .individual, scoring: .strokePlay(net: true)),
        "slag-brutto": FormAxes(teamForm: .individual, scoring: .strokePlay(net: false)),
        "par-bogey": FormAxes(teamForm: .individual, scoring: .parBogey),
        "maks-score": FormAxes(teamForm: .individual, scoring: .maximumScore),
        "match": FormAxes(teamForm: .individual, scoring: .matchPlay),
        "fourball": FormAxes(teamForm: .pairs(.fourball), scoring: .strokePlay(net: true)),
        "fourball-4": FormAxes(teamForm: .team(size: 4), scoring: .strokePlay(net: true)),
        "sammenlagt-lag": FormAxes(teamForm: .pairs(.aggregate), scoring: .strokePlay(net: true)),
        "foursome": FormAxes(teamForm: .pairs(.foursome), scoring: .stableford(net: true)),
        "greensome": FormAxes(teamForm: .pairs(.greensome), scoring: .stableford(net: true)),
        "chapman": FormAxes(teamForm: .pairs(.chapman), scoring: .stableford(net: true)),
        "scramble-2": FormAxes(teamForm: .scramble(size: 2), scoring: .stableford(net: true)),
        "scramble-4": FormAxes(teamForm: .scramble(size: 4), scoring: .stableford(net: true)),
        "skins": FormAxes(teamForm: .individual, scoring: .skins),
        "amerikaner": FormAxes(teamForm: .individual, scoring: .pointsGame(.amerikaner)),
        "kobenhavner": FormAxes(teamForm: .individual, scoring: .pointsGame(.kobenhavner)),
    ]

    /// Formen som to akser.
    public var axes: FormAxes {
        CompetitionForm.axesByID[id] ?? FormAxes(teamForm: .individual, scoring: .stableford(net: true))
    }

    /// Formen med disse aksene, eller `nil` når katalogen ikke har den.
    public static func form(axes: FormAxes) -> CompetitionForm? {
        catalog.first { $0.axes == axes }
    }
}

// MARK: - JSON

extension TeamForm: Codable {
    private enum CodingKeys: String, CodingKey { case type, pairs, size }
    private enum Kind: String, Codable { case individual, pairs, team, scramble }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .individual: self = .individual
        case .pairs: self = .pairs(try c.decode(PairForm.self, forKey: .pairs))
        case .team: self = .team(size: try c.decode(Int.self, forKey: .size))
        case .scramble: self = .scramble(size: try c.decode(Int.self, forKey: .size))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .individual:
            try c.encode(Kind.individual, forKey: .type)
        case .pairs(let p):
            try c.encode(Kind.pairs, forKey: .type)
            try c.encode(p, forKey: .pairs)
        case .team(let n):
            try c.encode(Kind.team, forKey: .type)
            try c.encode(n, forKey: .size)
        case .scramble(let n):
            try c.encode(Kind.scramble, forKey: .type)
            try c.encode(n, forKey: .size)
        }
    }
}

extension ScoringMethod: Codable {
    private enum CodingKeys: String, CodingKey { case type, net, game }
    private enum Kind: String, Codable { case strokePlay, stableford, parBogey, maximumScore, matchPlay, pointsGame, skins }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .strokePlay: self = .strokePlay(net: try c.decodeIfPresent(Bool.self, forKey: .net) ?? true)
        case .stableford: self = .stableford(net: try c.decodeIfPresent(Bool.self, forKey: .net) ?? true)
        case .parBogey: self = .parBogey
        case .maximumScore: self = .maximumScore
        case .matchPlay: self = .matchPlay
        case .pointsGame: self = .pointsGame(try c.decode(PointsGameKind.self, forKey: .game))
        case .skins: self = .skins
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .strokePlay(let net):
            try c.encode(Kind.strokePlay, forKey: .type)
            try c.encode(net, forKey: .net)
        case .stableford(let net):
            try c.encode(Kind.stableford, forKey: .type)
            try c.encode(net, forKey: .net)
        case .parBogey: try c.encode(Kind.parBogey, forKey: .type)
        case .maximumScore: try c.encode(Kind.maximumScore, forKey: .type)
        case .matchPlay: try c.encode(Kind.matchPlay, forKey: .type)
        case .pointsGame(let g):
            try c.encode(Kind.pointsGame, forKey: .type)
            try c.encode(g, forKey: .game)
        case .skins: try c.encode(Kind.skins, forKey: .type)
        }
    }
}
