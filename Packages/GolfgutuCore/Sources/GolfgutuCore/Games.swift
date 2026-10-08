import Foundation

// Spill på runden (fase 14): skins, Nassau, Wolf, bingo-bango-bongo og 2 mot 2 best ball.
// Et spill ligger oppå en runde (klubb eller løs). En runde kan ha flere spill, og hvert spill
// har sine egne deltakere. Inn: runden med scorer, spillets oppsett (deltakere, sider,
// innstillinger) og manuelle markeringer (Wolf-valg, bingo-bango-bongo). Ut: stillingen per
// hull, sluttresultatet og poengoverføringer i hele poeng som går i null (B10, aldri kroner).
//
// Ingen regelverdier i koden: hver spilltype har en mal med standardverdier (`…Rules.standard`),
// og hvert spill kan overstyre dem (`round_games.settings`). Felt som mangler i JSON-en, får
// malens verdi, som `Ruleset`. Skjemaet er `sql/020_spill.sql`, fasiten
// `Tests/GolfgutuCoreTests/Fixtures/spill.json`.
//
// Felles regler for alle spillene:
// - Hullene som teller, er rundens hull (9 eller 18, rundens 0-baserte indeks). En avkortet
//   runde teller bare hullene før avkortingen, uansett avkortingsregel: et hull ingen rakk, kan
//   ikke vinnes (`Games.countingHoles`).
// - Runden er ferdig når den er låst eller avkortet (`Games.isFinal`). Før det er et hull ferdig
//   når alle i spillet har ført det. Stillingen regnes hull for hull til første hull som ikke er
//   ferdig (spill som avhenger av scorene). Når runden er ferdig, regnes hull med manglende score
//   med de scorene som finnes: den som mangler score, kan ikke vinne hullet.
// - Handicap: spillerens handicap i runden (`Handicap.effective`, frosset ved start) ganget med
//   spillets andel og rundet som JS (`floor(x + 0.5)`). Med `fromLowest` spiller den laveste i
//   spillet fra scratch. Slagene fordeles som i resten av appen (`Scoring.handicapStrokes`).
// - Oppgjøret: et spill er en rekke «veddemål» der hver taper gir verdien, og vinnerne deler
//   potten likt, med samme avrunding og restfordeling som `Bets.payouts` (`PointSplit`). Spill
//   med poeng (Wolf, bingo-bango-bongo) gjøres opp parvis: hver betaler forskjellen i poeng
//   ganger poengverdien til hver av de andre. Summen er alltid null.

// MARK: - Spilltypene

/// Spilltypen (`round_games.kind`).
public enum GameKind: String, Codable, Hashable, Sendable, CaseIterable {
    case skins
    case nassau
    case wolf
    case bingoBangoBongo = "bbb"
    case bestBall = "best_ball"

    /// Antall spillere spillet tåler. Sidene (Nassau, best ball) sjekkes i `Games.problems`.
    public var playerRange: ClosedRange<Int> {
        switch self {
        case .skins: 2...8
        case .nassau: 2...4
        case .wolf: 3...5
        case .bingoBangoBongo: 2...8
        case .bestBall: 4...4
        }
    }

    /// Spillet har to sider (lag).
    public var hasSides: Bool { self == .nassau || self == .bestBall }
}

// MARK: - Malene (standardverdier per spilltype)

/// Handicap i et spill.
public struct GameHandicap: Codable, Hashable, Sendable {
    /// Netto (slag etter handicap). `false`: brutto.
    public var net: Bool
    /// Andelen av spillehandicapet i runden (1 = fullt).
    public var allowance: Double
    /// Den laveste i spillet spiller fra scratch, de andre får forskjellen (matchspill).
    public var fromLowest: Bool

    public init(net: Bool, allowance: Double, fromLowest: Bool) {
        self.net = net
        self.allowance = allowance
        self.fromLowest = fromLowest
    }

    public static let gross = GameHandicap(net: false, allowance: 1, fromLowest: false)

    /// Handicapet fra et spills innstillinger: feltene som mangler, får malens verdi (`fallback`).
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K,
                                     fallback: GameHandicap) throws -> GameHandicap {
        guard c.contains(key), try !c.decodeNil(forKey: key) else { return fallback }
        let n = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: key)
        return GameHandicap(net: try n.decodeIfPresent(Bool.self, forKey: .net) ?? fallback.net,
                            allowance: try n.decodeIfPresent(Double.self, forKey: .allowance) ?? fallback.allowance,
                            fromLowest: try n.decodeIfPresent(Bool.self, forKey: .fromLowest) ?? fallback.fromLowest)
    }

    private enum CodingKeys: String, CodingKey { case net, allowance, fromLowest }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        net = try c.decodeIfPresent(Bool.self, forKey: .net) ?? true
        allowance = try c.decodeIfPresent(Double.self, forKey: .allowance) ?? 1
        fromLowest = try c.decodeIfPresent(Bool.self, forKey: .fromLowest) ?? false
    }
}

/// Skins: hvert hull er et «skin». Lavest score alene vinner hullet og får verdien fra hver av
/// de andre. Delt hull: skinnet går videre til neste hull (carry-over), eller faller bort.
public struct SkinsRules: Codable, Hashable, Sendable {
    /// Hva står igjen når siste hull er delt.
    public enum Leftover: String, Codable, Hashable, Sendable, CaseIterable {
        /// Ingen vinner dem. Alle har satt like mye, så ingen poeng flytter seg.
        case lapse
        /// De som delte siste hull, deler skinnene.
        case split
    }

    public var handicap: GameHandicap
    /// Poeng hver av de andre gir vinneren per skin («skins-verdi»).
    public var valuePerSkin: Int
    /// Delt hull går videre til neste hull.
    public var carryOver: Bool
    /// Skins som står igjen etter siste hull.
    public var leftover: Leftover

    public init(handicap: GameHandicap, valuePerSkin: Int, carryOver: Bool, leftover: Leftover) {
        self.handicap = handicap
        self.valuePerSkin = valuePerSkin
        self.carryOver = carryOver
        self.leftover = leftover
    }

    /// Malen: netto med fullt handicap, 10 poeng per skin, carry-over, og det som står igjen
    /// etter siste hull faller bort.
    public static let standard = SkinsRules(handicap: GameHandicap(net: true, allowance: 1, fromLowest: false),
                                            valuePerSkin: 10, carryOver: true, leftover: .lapse)

    private enum CodingKeys: String, CodingKey { case handicap, valuePerSkin, carryOver, leftover }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = SkinsRules.standard
        handicap = try GameHandicap.decode(c, .handicap, fallback: s.handicap)
        valuePerSkin = try c.decodeIfPresent(Int.self, forKey: .valuePerSkin) ?? s.valuePerSkin
        carryOver = try c.decodeIfPresent(Bool.self, forKey: .carryOver) ?? s.carryOver
        leftover = try c.decodeIfPresent(Leftover.self, forKey: .leftover) ?? s.leftover
    }
}

/// Nassau: tre veddemål mellom to sider, første ni, siste ni og hele runden. En 9-hullsrunde har
/// bare «hele runden». Match (flest hull vunnet) eller slag (lavest sum). Med «press» starter et
/// nytt veddemål når en side ligger `pressTrigger` hull under i det siste veddemålet på en ni.
public struct NassauRules: Codable, Hashable, Sendable {
    public enum Scoring: String, Codable, Hashable, Sendable, CaseIterable {
        case match
        case stroke
    }

    public var handicap: GameHandicap
    public var scoring: Scoring
    /// Verdien av første ni, siste ni og hele runden, per spiller på taperlaget.
    public var front: Int
    public var back: Int
    public var total: Int
    /// Automatisk press (bare match).
    public var press: Bool
    /// Hvor mange hull under før et press starter.
    public var pressTrigger: Int
    /// Verdien av et press, per spiller på taperlaget.
    public var pressValue: Int

    public init(handicap: GameHandicap, scoring: Scoring, front: Int, back: Int, total: Int,
                press: Bool, pressTrigger: Int, pressValue: Int) {
        self.handicap = handicap
        self.scoring = scoring
        self.front = front
        self.back = back
        self.total = total
        self.press = press
        self.pressTrigger = pressTrigger
        self.pressValue = pressValue
    }

    /// Malen: netto match, laveste fra scratch, 10 poeng på hvert av de tre, ingen press
    /// (press ved 2 under, 10 poeng, når det slås på).
    public static let standard = NassauRules(handicap: GameHandicap(net: true, allowance: 1, fromLowest: true),
                                             scoring: .match, front: 10, back: 10, total: 10,
                                             press: false, pressTrigger: 2, pressValue: 10)

    private enum CodingKeys: String, CodingKey {
        case handicap, scoring, front, back, total, press, pressTrigger, pressValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = NassauRules.standard
        handicap = try GameHandicap.decode(c, .handicap, fallback: s.handicap)
        scoring = try c.decodeIfPresent(Scoring.self, forKey: .scoring) ?? s.scoring
        front = try c.decodeIfPresent(Int.self, forKey: .front) ?? s.front
        back = try c.decodeIfPresent(Int.self, forKey: .back) ?? s.back
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? s.total
        press = try c.decodeIfPresent(Bool.self, forKey: .press) ?? s.press
        pressTrigger = try c.decodeIfPresent(Int.self, forKey: .pressTrigger) ?? s.pressTrigger
        pressValue = try c.decodeIfPresent(Int.self, forKey: .pressValue) ?? s.pressValue
    }
}

/// Wolf: spillerne er wolf etter tur (rekkefølgen i spillet). Wolfen velger en partner etter
/// utslagene, eller spiller alene («lone wolf»), eller melder alene før noen har slått («blind
/// wolf»). Beste ball på hver side avgjør hullet. Poengene er malens.
public struct WolfRules: Codable, Hashable, Sendable {
    public var handicap: GameHandicap
    /// Wolf og partner vinner: poeng til hver av dem.
    public var partnerWin: Int
    /// De andre slår wolf og partner: poeng til hver av dem.
    public var opponentsWin: Int
    /// Wolf alene vinner: poeng til wolfen.
    public var loneWin: Int
    /// Wolf alene taper: poeng til hver av de andre.
    public var loneLoss: Int
    /// Blind wolf er lov.
    public var blindAllowed: Bool
    /// Blind wolf vinner: poeng til wolfen.
    public var blindWin: Int
    /// Blind wolf taper: poeng til hver av de andre.
    public var blindLoss: Int
    /// Oppgjøret: hver gir forskjellen i wolf-poeng ganger dette til hver av de andre.
    public var pointValue: Int

    public init(handicap: GameHandicap, partnerWin: Int, opponentsWin: Int, loneWin: Int, loneLoss: Int,
                blindAllowed: Bool, blindWin: Int, blindLoss: Int, pointValue: Int) {
        self.handicap = handicap
        self.partnerWin = partnerWin
        self.opponentsWin = opponentsWin
        self.loneWin = loneWin
        self.loneLoss = loneLoss
        self.blindAllowed = blindAllowed
        self.blindWin = blindWin
        self.blindLoss = blindLoss
        self.pointValue = pointValue
    }

    /// Malen: netto med fullt handicap. Partner vinner 2 hver, de andre vinner 3 hver, alene
    /// vinner 4 og taper 1 til hver av de andre, blind vinner 6 og taper 2 til hver. 1 poeng i
    /// oppgjøret per wolf-poeng i forskjell.
    public static let standard = WolfRules(handicap: GameHandicap(net: true, allowance: 1, fromLowest: false),
                                           partnerWin: 2, opponentsWin: 3, loneWin: 4, loneLoss: 1,
                                           blindAllowed: true, blindWin: 6, blindLoss: 2, pointValue: 1)

    private enum CodingKeys: String, CodingKey {
        case handicap, partnerWin, opponentsWin, loneWin, loneLoss, blindAllowed, blindWin, blindLoss, pointValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = WolfRules.standard
        handicap = try GameHandicap.decode(c, .handicap, fallback: s.handicap)
        partnerWin = try c.decodeIfPresent(Int.self, forKey: .partnerWin) ?? s.partnerWin
        opponentsWin = try c.decodeIfPresent(Int.self, forKey: .opponentsWin) ?? s.opponentsWin
        loneWin = try c.decodeIfPresent(Int.self, forKey: .loneWin) ?? s.loneWin
        loneLoss = try c.decodeIfPresent(Int.self, forKey: .loneLoss) ?? s.loneLoss
        blindAllowed = try c.decodeIfPresent(Bool.self, forKey: .blindAllowed) ?? s.blindAllowed
        blindWin = try c.decodeIfPresent(Int.self, forKey: .blindWin) ?? s.blindWin
        blindLoss = try c.decodeIfPresent(Int.self, forKey: .blindLoss) ?? s.blindLoss
        pointValue = try c.decodeIfPresent(Int.self, forKey: .pointValue) ?? s.pointValue
    }
}

/// Bingo-bango-bongo: tre poeng på hvert hull, satt for hånd. Bingo: først på green. Bango:
/// nærmest hullet når alle er på green. Bongo: først i hullet.
public struct BingoBangoBongoRules: Codable, Hashable, Sendable {
    public var bingo: Int
    public var bango: Int
    public var bongo: Int
    /// Oppgjøret: hver gir forskjellen i poeng ganger dette til hver av de andre.
    public var pointValue: Int

    public init(bingo: Int, bango: Int, bongo: Int, pointValue: Int) {
        self.bingo = bingo
        self.bango = bango
        self.bongo = bongo
        self.pointValue = pointValue
    }

    /// Malen: 1 poeng for hver av de tre, 1 poeng i oppgjøret per poeng i forskjell.
    public static let standard = BingoBangoBongoRules(bingo: 1, bango: 1, bongo: 1, pointValue: 1)

    private enum CodingKeys: String, CodingKey { case bingo, bango, bongo, pointValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = BingoBangoBongoRules.standard
        bingo = try c.decodeIfPresent(Int.self, forKey: .bingo) ?? s.bingo
        bango = try c.decodeIfPresent(Int.self, forKey: .bango) ?? s.bango
        bongo = try c.decodeIfPresent(Int.self, forKey: .bongo) ?? s.bongo
        pointValue = try c.decodeIfPresent(Int.self, forKey: .pointValue) ?? s.pointValue
    }
}

/// 2 mot 2 best ball: beste netto på laget teller på hvert hull. Match (flest hull vunnet) eller
/// stableford (summen av lagets beste poeng per hull).
public struct BestBallRules: Codable, Hashable, Sendable {
    public enum Scoring: String, Codable, Hashable, Sendable, CaseIterable {
        case match
        case stableford
    }

    public var scoring: Scoring
    /// Handicap i match.
    public var matchHandicap: GameHandicap
    /// Handicap i stableford.
    public var stablefordHandicap: GameHandicap
    /// Verdien, per spiller på taperlaget.
    public var value: Int

    public init(scoring: Scoring, matchHandicap: GameHandicap, stablefordHandicap: GameHandicap, value: Int) {
        self.scoring = scoring
        self.matchHandicap = matchHandicap
        self.stablefordHandicap = stablefordHandicap
        self.value = value
    }

    /// Handicapet for valgt telling.
    public var handicap: GameHandicap { scoring == .match ? matchHandicap : stablefordHandicap }

    /// Malen: match. Handicapandelene er WHS-anbefalingene for fourball (Appendix C): 90 % i
    /// match med laveste fra scratch, 85 % i slagspill (stableford) med fullt spillehandicap.
    /// 10 poeng per spiller.
    public static let standard = BestBallRules(scoring: .match,
                                               matchHandicap: GameHandicap(net: true, allowance: 0.9, fromLowest: true),
                                               stablefordHandicap: GameHandicap(net: true, allowance: 0.85, fromLowest: false),
                                               value: 10)

    private enum CodingKeys: String, CodingKey { case scoring, matchHandicap, stablefordHandicap, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = BestBallRules.standard
        scoring = try c.decodeIfPresent(Scoring.self, forKey: .scoring) ?? s.scoring
        matchHandicap = try GameHandicap.decode(c, .matchHandicap, fallback: s.matchHandicap)
        stablefordHandicap = try GameHandicap.decode(c, .stablefordHandicap, fallback: s.stablefordHandicap)
        value = try c.decodeIfPresent(Int.self, forKey: .value) ?? s.value
    }
}

/// Innstillingene for ett spill: malen for typen, med det spillet har overstyrt.
public enum GameSettings: Hashable, Sendable {
    case skins(SkinsRules)
    case nassau(NassauRules)
    case wolf(WolfRules)
    case bingoBangoBongo(BingoBangoBongoRules)
    case bestBall(BestBallRules)

    public var kind: GameKind {
        switch self {
        case .skins: .skins
        case .nassau: .nassau
        case .wolf: .wolf
        case .bingoBangoBongo: .bingoBangoBongo
        case .bestBall: .bestBall
        }
    }

    /// Malen for typen.
    public static func standard(_ kind: GameKind) -> GameSettings {
        switch kind {
        case .skins: .skins(.standard)
        case .nassau: .nassau(.standard)
        case .wolf: .wolf(.standard)
        case .bingoBangoBongo: .bingoBangoBongo(.standard)
        case .bestBall: .bestBall(.standard)
        }
    }

    /// Innstillingene fra JSON (`round_games.settings`). Felt som mangler, får malens verdi.
    public static func decode(_ kind: GameKind, from data: Data) throws -> GameSettings {
        let d = JSONDecoder()
        switch kind {
        case .skins: return .skins(try d.decode(SkinsRules.self, from: data))
        case .nassau: return .nassau(try d.decode(NassauRules.self, from: data))
        case .wolf: return .wolf(try d.decode(WolfRules.self, from: data))
        case .bingoBangoBongo: return .bingoBangoBongo(try d.decode(BingoBangoBongoRules.self, from: data))
        case .bestBall: return .bestBall(try d.decode(BestBallRules.self, from: data))
        }
    }

    /// JSON for `round_games.settings` (alle felt skrives ut).
    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        switch self {
        case .skins(let r): return try e.encode(r)
        case .nassau(let r): return try e.encode(r)
        case .wolf(let r): return try e.encode(r)
        case .bingoBangoBongo(let r): return try e.encode(r)
        case .bestBall(let r): return try e.encode(r)
        }
    }
}

// MARK: - Oppsett og markeringer

/// Ett spill på runden: type, innstillinger, deltakere i rekkefølge og sider.
public struct GameSetup: Hashable, Sendable {
    public var settings: GameSettings
    /// Deltakerne (spiller-id i runden). For Wolf er rekkefølgen tee-rekkefølgen: første spiller
    /// er wolf på første hull.
    public var players: [String]
    /// Side (1 eller 2) per spiller, for Nassau og best ball.
    public var sides: [String: Int]

    public init(settings: GameSettings, players: [String], sides: [String: Int] = [:]) {
        self.settings = settings
        self.players = players
        self.sides = sides
    }

    public var kind: GameKind { settings.kind }

    /// Spillerne på en side, i spillets rekkefølge.
    public func side(_ number: Int) -> [String] {
        players.filter { sides[$0] == number }
    }
}

extension GameSetup: Codable {
    private enum CodingKeys: String, CodingKey { case kind, settings, players, sides }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(GameKind.self, forKey: .kind)
        players = try c.decode([String].self, forKey: .players)
        sides = try c.decodeIfPresent([String: Int].self, forKey: .sides) ?? [:]
        switch kind {
        case .skins: settings = .skins(try c.decodeIfPresent(SkinsRules.self, forKey: .settings) ?? .standard)
        case .nassau: settings = .nassau(try c.decodeIfPresent(NassauRules.self, forKey: .settings) ?? .standard)
        case .wolf: settings = .wolf(try c.decodeIfPresent(WolfRules.self, forKey: .settings) ?? .standard)
        case .bingoBangoBongo:
            settings = .bingoBangoBongo(try c.decodeIfPresent(BingoBangoBongoRules.self, forKey: .settings) ?? .standard)
        case .bestBall: settings = .bestBall(try c.decodeIfPresent(BestBallRules.self, forKey: .settings) ?? .standard)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(players, forKey: .players)
        try c.encode(sides, forKey: .sides)
        switch settings {
        case .skins(let r): try c.encode(r, forKey: .settings)
        case .nassau(let r): try c.encode(r, forKey: .settings)
        case .wolf(let r): try c.encode(r, forKey: .settings)
        case .bingoBangoBongo(let r): try c.encode(r, forKey: .settings)
        case .bestBall(let r): try c.encode(r, forKey: .settings)
        }
    }
}

/// Wolfens valg på ett hull.
public struct WolfChoice: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable, CaseIterable {
        /// Partner valgt etter utslaget.
        case partner
        /// Alene etter utslagene («lone wolf»).
        case alone
        /// Alene før noen har slått («blind wolf»).
        case blind
    }

    public var mode: Mode
    /// Partneren (bare `partner`).
    public var partner: String?

    public init(mode: Mode, partner: String? = nil) {
        self.mode = mode
        self.partner = partner
    }

    public static func partner(_ id: String) -> WolfChoice { WolfChoice(mode: .partner, partner: id) }
    public static let alone = WolfChoice(mode: .alone)
    public static let blind = WolfChoice(mode: .blind)
}

/// Bingo, bango og bongo på ett hull: hvem som fikk hvert av dem (eller ingen).
public struct BingoBangoBongoMarks: Codable, Hashable, Sendable {
    public var bingo: String?
    public var bango: String?
    public var bongo: String?

    public init(bingo: String? = nil, bango: String? = nil, bongo: String? = nil) {
        self.bingo = bingo
        self.bango = bango
        self.bongo = bongo
    }

    public var isEmpty: Bool { bingo == nil && bango == nil && bongo == nil }
}

/// De manuelle markeringene i et spill, per rundens 0-baserte hull (`round_game_marks`).
public struct GameMarks: Codable, Hashable, Sendable {
    public var wolf: [Int: WolfChoice]
    public var bingoBangoBongo: [Int: BingoBangoBongoMarks]

    public init(wolf: [Int: WolfChoice] = [:], bingoBangoBongo: [Int: BingoBangoBongoMarks] = [:]) {
        self.wolf = wolf
        self.bingoBangoBongo = bingoBangoBongo
    }

    private enum CodingKeys: String, CodingKey { case wolf, bingoBangoBongo }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wolf = try c.decodeIfPresent([Int: WolfChoice].self, forKey: .wolf) ?? [:]
        bingoBangoBongo = try c.decodeIfPresent([Int: BingoBangoBongoMarks].self, forKey: .bingoBangoBongo) ?? [:]
    }
}

// MARK: - Resultatet

/// Ett hull i et spill.
public struct GameHole: Hashable, Sendable {
    public enum State: String, Codable, Hashable, Sendable {
        /// Ikke ferdig ennå (noen mangler score eller markering).
        case pending
        /// Vunnet (`winners`).
        case won
        /// Delt.
        case halved
        /// Teller ikke: runden er ferdig, og hullet mangler det som trengs (Wolf-valg, markering).
        case void
    }

    /// Rundens 0-baserte hull.
    public var hole: Int
    public var state: State
    /// Spillerne som vant hullet (en side kan være flere). Delt skins-hull: de som delte laveste score.
    public var winners: [String]
    /// Skins: antall skins avgjort på hullet (med carry-over). Wolf og bingo-bango-bongo:
    /// poengene som ble delt ut. Ellers 0.
    public var value: Int
    /// Spillpoeng på hullet per spiller (Wolf og bingo-bango-bongo).
    public var points: [String: Int]
    /// Wolf: hvem som var wolf.
    public var wolf: String?
    /// Matchspill (Nassau og best ball i match): stillingen etter hullet, sett fra side 1.
    public var up: Int?

    public init(hole: Int, state: State, winners: [String] = [], value: Int = 0, points: [String: Int] = [:],
                wolf: String? = nil, up: Int? = nil) {
        self.hole = hole
        self.state = state
        self.winners = winners
        self.value = value
        self.points = points
        self.wolf = wolf
        self.up = up
    }
}

/// Ett veddemål i et spill (Nassau-ni, press, best ball-matchen).
public struct GameBet: Hashable, Sendable {
    public enum Segment: String, Codable, Hashable, Sendable {
        case front, back, total, press, match
    }

    public enum State: String, Codable, Hashable, Sendable {
        case pending, won, halved, void
    }

    public var segment: Segment
    /// For et press: veddemålet det hører til (front, back eller total).
    public var pressOf: Segment?
    /// Første og siste hull (0-basert, inkludert).
    public var firstHole: Int
    public var lastHole: Int
    public var state: State
    /// Siden som vant (1 eller 2).
    public var winner: Int?
    /// Match: hull opp for side 1 (negativt: under). Slag og stableford: side 2s sum minus side
    /// 1s (slag, positivt er bra for side 1) eller side 1s minus side 2s (stableford).
    public var margin: Int
    /// Hull spilt i veddemålet.
    public var played: Int
    /// Hull igjen i veddemålet.
    public var remaining: Int
    /// Verdien per spiller på taperlaget.
    public var value: Int

    public init(segment: GameBet.Segment, pressOf: GameBet.Segment? = nil, firstHole: Int, lastHole: Int,
                state: GameBet.State, winner: Int? = nil, margin: Int = 0, played: Int = 0, remaining: Int = 0,
                value: Int) {
        self.segment = segment
        self.pressOf = pressOf
        self.firstHole = firstHole
        self.lastHole = lastHole
        self.state = state
        self.winner = winner
        self.margin = margin
        self.played = played
        self.remaining = remaining
        self.value = value
    }
}

/// Stillingen i et spill.
public struct GameResult: Hashable, Sendable {
    public var kind: GameKind
    /// Ett per tellende hull.
    public var holes: [GameHole]
    /// Nassau og best ball: veddemålene.
    public var bets: [GameBet]
    /// Spillpoeng per spiller: skins vunnet (skins), wolf-poeng (Wolf), poeng (bingo-bango-
    /// bongo), lagets stableford (best ball i stableford). Tomt for matchspillene.
    public var scores: [String: Double]
    /// Oppgjøret så langt i hele poeng, per spiller i spillet (også 0). Summen er null.
    public var settlement: [String: Int]
    /// Alt er avgjort, og oppgjøret er endelig.
    public var isFinished: Bool
    /// Skins: skins som står (carry-over) nå.
    public var carry: Int

    public init(kind: GameKind, holes: [GameHole], bets: [GameBet] = [], scores: [String: Double] = [:],
                settlement: [String: Int], isFinished: Bool, carry: Int = 0) {
        self.kind = kind
        self.holes = holes
        self.bets = bets
        self.scores = scores
        self.settlement = settlement
        self.isFinished = isFinished
        self.carry = carry
    }
}

/// Noe som er galt med oppsettet av et spill.
public enum GameSetupProblem: Hashable, Sendable {
    /// For få eller for mange spillere.
    case playerCount(GameKind, ClosedRange<Int>)
    /// Samme spiller to ganger.
    case duplicatePlayer
    /// En spiller er ikke med i runden.
    case notInRound(String)
    /// Sidene er feil (to sider, 1–2 spillere hver; best ball: 2 hver).
    case sides
    /// En verdi er negativ eller handicapandelen er utenfor 0–1.
    case invalidValue
}

// MARK: - Motoren

public enum Games {
    /// Stillingen i spillet.
    public static func evaluate(_ setup: GameSetup, round: Round, roster: [Player], marks: GameMarks = GameMarks(),
                                rules: Ruleset = .golfgutu) -> GameResult {
        let ctx = GameContext(setup: setup, round: round, roster: roster, rules: rules)
        switch setup.settings {
        case .skins(let r): return SkinsGame.evaluate(ctx, rules: r)
        case .nassau(let r): return NassauGame.evaluate(ctx, rules: r)
        case .wolf(let r): return WolfGame.evaluate(ctx, rules: r, marks: marks.wolf)
        case .bingoBangoBongo(let r): return BingoBangoBongoGame.evaluate(ctx, rules: r, marks: marks.bingoBangoBongo)
        case .bestBall(let r): return BestBallGame.evaluate(ctx, rules: r)
        }
    }

    /// Hva som er galt med oppsettet, eller tomt.
    public static func problems(_ setup: GameSetup, roundPlayers: [String]? = nil) -> [GameSetupProblem] {
        var out: [GameSetupProblem] = []
        let kind = setup.kind
        if !kind.playerRange.contains(setup.players.count) {
            out.append(.playerCount(kind, kind.playerRange))
        }
        if Set(setup.players).count != setup.players.count { out.append(.duplicatePlayer) }
        if let roundPlayers {
            for p in setup.players where !roundPlayers.contains(p) { out.append(.notInRound(p)) }
        }
        if kind.hasSides {
            let a = setup.side(1), b = setup.side(2)
            let everyoneHasSide = setup.players.allSatisfy { setup.sides[$0] == 1 || setup.sides[$0] == 2 }
            let sizes = kind == .bestBall ? 2...2 : 1...2
            if !everyoneHasSide || !sizes.contains(a.count) || !sizes.contains(b.count) { out.append(.sides) }
        }
        if !valuesAreValid(setup.settings) { out.append(.invalidValue) }
        return out
    }

    private static func valuesAreValid(_ s: GameSettings) -> Bool {
        func ok(_ h: GameHandicap) -> Bool { h.allowance >= 0 && h.allowance <= 1 }
        switch s {
        case .skins(let r): return ok(r.handicap) && r.valuePerSkin >= 0
        case .nassau(let r):
            return ok(r.handicap) && [r.front, r.back, r.total, r.pressValue].allSatisfy { $0 >= 0 } && r.pressTrigger >= 1
        case .wolf(let r):
            return ok(r.handicap)
                && [r.partnerWin, r.opponentsWin, r.loneWin, r.loneLoss, r.blindWin, r.blindLoss, r.pointValue]
                    .allSatisfy { $0 >= 0 }
        case .bingoBangoBongo(let r): return [r.bingo, r.bango, r.bongo, r.pointValue].allSatisfy { $0 >= 0 }
        case .bestBall(let r): return ok(r.matchHandicap) && ok(r.stablefordHandicap) && r.value >= 0
        }
    }

    /// Hullene som teller i spill på runden: rundens hull, kuttet ved avkortingen uansett regel.
    public static func countingHoles(_ round: Round) -> Int {
        let n = round.numberOfHoles
        if Truncation.isTruncated(round), let after = round.avkortetEtter, after.isFinite, after >= 1 {
            return min(n, JS.roundInt(after))
        }
        return n
    }

    /// Runden er ferdig (låst eller avkortet): hull med manglende score regnes med det som finnes.
    public static func isFinal(_ round: Round) -> Bool {
        round.locked || Truncation.isTruncated(round)
    }

    /// Wolfen på hullet: spillerne etter tur, første spiller på rundens første hull.
    public static func wolf(on hole: Int, players: [String]) -> String? {
        guard !players.isEmpty, hole >= 0 else { return nil }
        return players[hole % players.count]
    }
}

// MARK: - Felles regnestykker

/// Runden sett fra ett spill: hull, handicap og netto per spiller.
struct GameContext {
    let setup: GameSetup
    let round: Round
    let rules: Ruleset
    let holes: [PlayedHole]
    let count: Int
    let isFinal: Bool
    private let roster: [Player]

    init(setup: GameSetup, round: Round, roster: [Player], rules: Ruleset) {
        self.setup = setup
        self.round = round
        self.rules = rules
        self.roster = roster
        holes = round.courseHoles()
        count = min(Games.countingHoles(round), holes.count)
        isFinal = Games.isFinal(round)
    }

    var players: [String] { setup.players }

    /// Spillehandicapet i spillet per spiller (hele slag).
    func handicaps(_ h: GameHandicap) -> [String: Int] {
        guard h.net else { return Dictionary(uniqueKeysWithValues: players.map { ($0, 0) }) }
        var out: [String: Int] = [:]
        for p in players {
            let base = Handicap.effective(for: roster.first { $0.id == p } ?? Player(id: p), in: round,
                                          roster: roster, rules: rules)
            out[p] = JS.roundInt(base * h.allowance)
        }
        if h.fromLowest, let low = out.values.min() {
            for p in players { out[p] = out[p]! - low }
        }
        return out
    }

    func gross(_ p: String, _ hole: Int) -> Int? {
        round.holeScores[p]?[hole]
    }

    /// Netto på hullet, eller `nil` uten score.
    func net(_ p: String, _ hole: Int, handicaps: [String: Int]) -> Int? {
        guard let g = gross(p, hole) else { return nil }
        return g - Scoring.handicapStrokes(handicap: Double(handicaps[p] ?? 0), strokeIndex: holes[hole].strokeIndex,
                                            holes: round.numberOfHoles)
    }

    /// Stablefordpoeng på hullet med rundens regelsett, eller `nil` uten score.
    func stableford(_ p: String, _ hole: Int, handicaps: [String: Int]) -> Int? {
        guard let n = net(p, hole, handicaps: handicaps) else { return nil }
        return max(rules.scoring.minimumPoints, holes[hole].par - n + rules.scoring.netParPoints)
    }

    /// Hullet kan regnes: alle har ført det, eller runden er ferdig.
    func isReady(_ hole: Int, for who: [String]? = nil) -> Bool {
        isFinal || (who ?? players).allSatisfy { gross($0, hole) != nil }
    }

    /// Laveste verdi på en side (beste ball), eller `nil` når ingen på siden har score.
    static func best(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.min()
    }
}

/// Fordeling av hele poeng med samme avrunding og restfordeling som `Bets.payouts`.
public enum PointSplit {
    /// Deler `total` enheter etter vekt. Hver andel rundes med `floor(x + 0.5)`, og resten (det
    /// avrundingen skapte eller fjernet) gis eller tas én enhet om gangen etter største vekt, så
    /// laveste id. Summen er nøyaktig `total`.
    public static func apportion(_ total: Double, weights: [(id: String, weight: Double)]) -> [String: Double] {
        let order = weights.filter { $0.weight > 0 }
            .sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.id < $1.id }
        let sum = order.reduce(0) { $0 + $1.weight }
        guard sum > 0 else { return [:] }
        var units = order.map { JS.round($0.weight * total / sum) }
        let rest = Int((total - units.reduce(0, +)).rounded())
        for k in 0..<abs(rest) {
            units[k % units.count] += rest > 0 ? 1 : -1
        }
        var out: [String: Double] = [:]
        for (i, w) in order.enumerated() { out[w.id] = units[i] }
        return out
    }

    /// Oppgjøret av veddemål der hver taper gir `value`, og vinnerne deler potten likt
    /// (`apportion`). Alle i `players` står i svaret, også med 0.
    static func settle(_ items: [(winners: [String], losers: [String], value: Int)], players: [String]) -> [String: Int] {
        var out = Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
        for item in items where !item.winners.isEmpty && !item.losers.isEmpty && item.value > 0 {
            for l in item.losers { out[l, default: 0] -= item.value }
            let pot = Double(item.value * item.losers.count)
            let shares = apportion(pot, weights: item.winners.map { ($0, 1) })
            for (id, s) in shares { out[id, default: 0] += Int(s) }
        }
        return out
    }

    /// Parvis oppgjør av spillpoeng: hver gir forskjellen ganger `value` til hver av de andre.
    /// Netto: `value · (n · poeng − sum)`.
    static func pairwise(_ points: [String: Int], players: [String], value: Int) -> [String: Int] {
        let total = players.reduce(0) { $0 + (points[$1] ?? 0) }
        let n = players.count
        return Dictionary(uniqueKeysWithValues: players.map { p in
            (p, value * (n * (points[p] ?? 0) - total))
        })
    }
}
