import Foundation
import GolfgutuCore

// Spill på runden (fase 14): radene fra `sql/020_spill.sql`, mapping til regelmotoren
// (`Games.evaluate`) og tekstene på kortene og i arket. Ren logikk, uten nettverk og SwiftUI.
// Regnestykket (stilling, sluttresultat og oppgjør i hele poeng) ligger i GolfgutuCore.

/// Spill på runden (krever 020, kjørt på test). Med flagget av kaller ingenting RPC-ene i 020.
nonisolated enum GamesFeature {
    static let isEnabled = true
}

// MARK: - Radene

/// `round_games`. Innstillingene leses med malen for typen som grunnlag.
nonisolated struct RoundGameRow: Codable, Equatable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case open
        case settled
    }

    let id: UUID
    let roundID: UUID
    var settings: GameSettings
    var status: Status
    var createdBy: UUID?
    var settledAt: String?

    var kind: GameKind { settings.kind }

    static let columns = "id, round_id, kind, settings, status, created_by, settled_at"

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case kind, settings, status
        case createdBy = "created_by"
        case settledAt = "settled_at"
    }

    init(id: UUID, roundID: UUID, settings: GameSettings, status: Status = .open, createdBy: UUID? = nil,
         settledAt: String? = nil) {
        self.id = id
        self.roundID = roundID
        self.settings = settings
        self.status = status
        self.createdBy = createdBy
        self.settledAt = settledAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roundID = try c.decode(UUID.self, forKey: .roundID)
        let kind = try c.decode(GameKind.self, forKey: .kind)
        settings = try GameSettingsCoding.decode(kind, from: c, forKey: .settings)
        status = try c.decode(Status.self, forKey: .status)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        settledAt = try c.decodeIfPresent(String.self, forKey: .settledAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roundID, forKey: .roundID)
        try c.encode(kind, forKey: .kind)
        try GameSettingsCoding.encode(settings, to: &c, forKey: .settings)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(settledAt, forKey: .settledAt)
    }
}

/// Innstillingene som jsonb: hver type har sin mal (`…Rules`), og felt som mangler får malens verdi.
nonisolated enum GameSettingsCoding {
    static func decode<K: CodingKey>(_ kind: GameKind, from c: KeyedDecodingContainer<K>,
                                     forKey key: K) throws -> GameSettings {
        switch kind {
        case .skins: .skins(try c.decodeIfPresent(SkinsRules.self, forKey: key) ?? .standard)
        case .nassau: .nassau(try c.decodeIfPresent(NassauRules.self, forKey: key) ?? .standard)
        case .wolf: .wolf(try c.decodeIfPresent(WolfRules.self, forKey: key) ?? .standard)
        case .bingoBangoBongo:
            .bingoBangoBongo(try c.decodeIfPresent(BingoBangoBongoRules.self, forKey: key) ?? .standard)
        case .bestBall: .bestBall(try c.decodeIfPresent(BestBallRules.self, forKey: key) ?? .standard)
        }
    }

    static func encode<K: CodingKey>(_ s: GameSettings, to c: inout KeyedEncodingContainer<K>, forKey key: K) throws {
        switch s {
        case .skins(let r): try c.encode(r, forKey: key)
        case .nassau(let r): try c.encode(r, forKey: key)
        case .wolf(let r): try c.encode(r, forKey: key)
        case .bingoBangoBongo(let r): try c.encode(r, forKey: key)
        case .bestBall(let r): try c.encode(r, forKey: key)
        }
    }
}

/// `round_game_players`.
nonisolated struct RoundGamePlayerRow: Codable, Equatable, Sendable {
    let gameID: UUID
    let roundID: UUID
    let playerID: UUID
    var seat: Int
    var side: Int?

    static let columns = "game_id, round_id, player_id, seat, side"

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case roundID = "round_id"
        case playerID = "player_id"
        case seat, side
    }
}

/// `round_game_marks`.
nonisolated struct RoundGameMarkRow: Codable, Equatable, Sendable {
    enum Award: String, Codable, Sendable, CaseIterable {
        case wolf, bingo, bango, bongo
    }

    let gameID: UUID
    let roundID: UUID
    var holeIndex: Int
    var award: Award
    var playerID: UUID?
    var wolfMode: WolfChoice.Mode?

    static let columns = "game_id, round_id, hole_index, award, player_id, wolf_mode"

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case roundID = "round_id"
        case holeIndex = "hole_index"
        case award
        case playerID = "player_id"
        case wolfMode = "wolf_mode"
    }
}

/// `round_game_results`: oppgjøret, poengbanken per runde.
nonisolated struct RoundGameResultRow: Codable, Equatable, Sendable {
    let gameID: UUID
    let roundID: UUID
    let playerID: UUID
    var points: Int

    static let columns = "game_id, round_id, player_id, points"

    enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case roundID = "round_id"
        case playerID = "player_id"
        case points
    }
}

/// Alt som er hentet om spillene i én runde.
nonisolated struct GamesInput: Equatable, Sendable {
    var games: [RoundGameRow] = []
    var players: [RoundGamePlayerRow] = []
    var marks: [RoundGameMarkRow] = []
    var results: [RoundGameResultRow] = []

    func players(of gameID: UUID) -> [RoundGamePlayerRow] {
        players.filter { $0.gameID == gameID }.sorted { $0.seat < $1.seat }
    }

    /// Regelmotorens oppsett: spiller-id-ene er `uuidString`, som i `RoundGame`.
    func setup(for game: RoundGameRow) -> GameSetup {
        let rows = players(of: game.id)
        var sides: [String: Int] = [:]
        for r in rows { if let s = r.side { sides[r.playerID.uuidString] = s } }
        return GameSetup(settings: game.settings, players: rows.map(\.playerID.uuidString), sides: sides)
    }

    func marks(for gameID: UUID) -> GameMarks {
        var out = GameMarks()
        for m in marks where m.gameID == gameID {
            switch m.award {
            case .wolf:
                if let mode = m.wolfMode {
                    out.wolf[m.holeIndex] = WolfChoice(mode: mode, partner: m.playerID?.uuidString)
                }
            case .bingo: out.bingoBangoBongo[m.holeIndex, default: .init()].bingo = m.playerID?.uuidString
            case .bango: out.bingoBangoBongo[m.holeIndex, default: .init()].bango = m.playerID?.uuidString
            case .bongo: out.bingoBangoBongo[m.holeIndex, default: .init()].bongo = m.playerID?.uuidString
            }
        }
        return out
    }

    func results(for gameID: UUID) -> [UUID: Int] {
        Dictionary(results.filter { $0.gameID == gameID }.map { ($0.playerID, $0.points) },
                   uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - RPC-parametrene

nonisolated struct CreateRoundGameParams: Encodable, Sendable {
    struct Entry: Encodable, Sendable {
        let player_id: UUID
        let side: Int?
    }

    let p_round_id: UUID
    let settings: GameSettings
    let p_players: [Entry]

    private enum CodingKeys: String, CodingKey { case p_round_id, p_kind, p_settings, p_players }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_round_id, forKey: .p_round_id)
        try c.encode(settings.kind, forKey: .p_kind)
        try GameSettingsCoding.encode(settings, to: &c, forKey: .p_settings)
        try c.encode(p_players, forKey: .p_players)
    }
}

nonisolated struct GameIDParams: Encodable, Sendable {
    let p_game_id: UUID
}

nonisolated struct GameMarkParams: Encodable, Sendable {
    let p_game_id: UUID
    let p_hole: Int
    let p_award: RoundGameMarkRow.Award
    let p_player_id: UUID?
    let p_wolf_mode: WolfChoice.Mode?
}

nonisolated struct SettleGameParams: Encodable, Sendable {
    let p_game_id: UUID
    /// Spiller-id (små bokstaver) → hele poeng. Summen er null.
    let p_points: [String: Int]

    init(gameID: UUID, points: [UUID: Int]) {
        p_game_id = gameID
        p_points = Dictionary(uniqueKeysWithValues: points.map { ($0.key.uuidString.lowercased(), $0.value) })
    }
}

// MARK: - Tekstene

nonisolated enum GameTexts {
    static func name(_ kind: GameKind) -> String {
        switch kind {
        case .skins: "Skins"
        case .nassau: "Nassau"
        case .wolf: "Wolf"
        case .bingoBangoBongo: "Bingo-bango-bongo"
        case .bestBall: "2 mot 2 best ball"
        }
    }

    /// Kort forklaring på norsk.
    static func explanation(_ kind: GameKind) -> String {
        switch kind {
        case .skins:
            "Hvert hull er et skin. Lavest score alene vinner hullet og får poeng fra hver av de andre. "
                + "Blir hullet delt, går skinnet videre til neste hull."
        case .nassau:
            "Tre veddemål mellom to sider: første ni, siste ni og hele runden. Den som vinner flest hull, "
                + "vinner hvert av dem. Med press starter et nytt veddemål når noen ligger to hull under."
        case .wolf:
            "Dere er wolf etter tur. Wolfen velger partner etter utslagene, eller spiller alene for flere poeng. "
                + "Beste ball på hver side avgjør hullet."
        case .bingoBangoBongo:
            "Tre poeng på hvert hull: først på green (bingo), nærmest hullet når alle er på green (bango) "
                + "og først i hullet (bongo). Settes for hånd."
        case .bestBall:
            "To lag på to. Beste netto på laget teller på hvert hull, som match eller stableford."
        }
    }

    static func icon(_ kind: GameKind) -> String {
        switch kind {
        case .skins: "square.stack.3d.up"
        case .nassau: "rectangle.split.3x1"
        case .wolf: "pawprint"
        case .bingoBangoBongo: "3.circle"
        case .bestBall: "person.2"
        }
    }

    static func handicap(_ h: GameHandicap) -> String {
        guard h.net else { return "Brutto" }
        let share = h.allowance == 1 ? "fullt handicap" : "\(percent(h.allowance)) av handicapet"
        return h.fromLowest ? "Netto, \(share), laveste fra scratch" : "Netto, \(share)"
    }

    static func percent(_ x: Double) -> String {
        "\(Int((x * 100).rounded())) %"
    }

    /// Innstillingene i én linje.
    static func summary(_ s: GameSettings) -> String {
        switch s {
        case .skins(let r):
            let carry = r.carryOver ? "delte hull går videre" : "delte hull faller bort"
            return "\(handicap(r.handicap)) · \(points(r.valuePerSkin)) per skin · \(carry)"
        case .nassau(let r):
            let form = r.scoring == .match ? "Match" : "Slag"
            let press = r.press && r.scoring == .match ? " · press ved \(r.pressTrigger) under" : ""
            return "\(form) · \(r.front)/\(r.back)/\(r.total) poeng\(press) · \(handicap(r.handicap))"
        case .wolf(let r):
            let blind = r.blindAllowed ? ", blind \(r.blindWin)" : ""
            return "Partner \(r.partnerWin), de andre \(r.opponentsWin), alene \(r.loneWin)\(blind) · "
                + "\(handicap(r.handicap))"
        case .bingoBangoBongo(let r):
            return "Bingo \(r.bingo), bango \(r.bango), bongo \(r.bongo)"
        case .bestBall(let r):
            let form = r.scoring == .match ? "Match" : "Stableford"
            return "\(form) · \(points(r.value)) · \(handicap(r.handicap))"
        }
    }

    static func points(_ n: Int) -> String {
        n == 1 ? "1 poeng" : "\(n) poeng"
    }

    /// «+30», «−10», «0».
    static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "0")
    }

    static func skins(_ x: Double) -> String {
        let text = x == x.rounded() ? String(Int(x)) : String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",")
        return x == 1 ? "1 skin" : "\(text) skins"
    }

    static func problem(_ p: GameSetupProblem, names: (String) -> String) -> String {
        switch p {
        case .playerCount(let kind, let range):
            range.lowerBound == range.upperBound
                ? "\(name(kind)) er for \(range.lowerBound) spillere."
                : "\(name(kind)) er for \(range.lowerBound)–\(range.upperBound) spillere."
        case .duplicatePlayer: "Samme spiller er med to ganger."
        case .notInRound(let id): "\(names(id)) er ikke med i runden."
        case .sides: "Velg to sider med like mange på hver (1 eller 2, i best ball 2)."
        case .invalidValue: "Poengene kan ikke være negative, og handicapandelen må være mellom 0 og 100 %."
        }
    }

    static func wolfChoice(_ c: WolfChoice?, partnerName: (String) -> String) -> String {
        guard let c else { return "Ikke valgt ennå" }
        switch c.mode {
        case .partner: return "Partner: \(c.partner.map(partnerName) ?? "?")"
        case .alone: return "Alene"
        case .blind: return "Blind wolf"
        }
    }
}

/// Feilene fra spill-RPC-ene er skrevet på norsk og kan vises som de er.
nonisolated enum GameErrors {
    static func text(sqlState: String?, message: String) -> String? {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["42501", "22023", "55000", "P0002"].contains(sqlState ?? ""),
              !m.hasPrefix("permission denied"), !m.hasPrefix("new row violates") else { return nil }
        return m
    }
}

// MARK: - Kortene under runden

/// Markeringen som trengs på hullet som vises.
nonisolated enum GameHoleAction: Equatable, Sendable {
    /// Wolfen velger partner, alene eller blind.
    case wolf(hole: Int, wolf: UUID, partners: [UUID], blindAllowed: Bool, current: WolfChoice?)
    /// Bingo, bango og bongo.
    case bingoBangoBongo(hole: Int, players: [UUID], current: BingoBangoBongoMarks)

    var hole: Int {
        switch self {
        case .wolf(let h, _, _, _, _), .bingoBangoBongo(let h, _, _): h
        }
    }
}

/// Et spill slik kortet viser det.
nonisolated struct GameCard: Identifiable, Equatable, Sendable {
    struct Row: Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        /// Spillpoeng eller side («2 skins», «11 p», «Lag 1»).
        let detail: String?
        /// Oppgjøret så langt (eller det endelige).
        let points: Int
    }

    let id: UUID
    let kind: GameKind
    let title: String
    let summary: String
    let status: String
    /// Veddemålene (Nassau, best ball) eller hullet (Wolf, bingo-bango-bongo).
    let lines: [String]
    let rows: [Row]
    let isSettled: Bool
    /// Oppgjøret kan skrives (runden er ferdig, alt er avgjort, og du laget spillet eller er arrangør).
    let canSettle: Bool
    let canDelete: Bool
    /// Det som skrives ved oppgjøret.
    let settlement: [UUID: Int]
    let action: GameHoleAction?
}

/// Spillene i runden, regnet av regelmotoren.
nonisolated struct GamesBoard: Equatable, Sendable {
    let cards: [GameCard]

    /// - Parameters:
    ///   - me: profil-id-en (innloggingen), for «du laget spillet».
    ///   - hole: hullet som vises (rundens 0-baserte).
    init(_ input: GamesInput, game: RoundGame, viewer: Viewer, me: UUID?, hole: Int) {
        cards = input.games.map { row in
            GamesBoard.card(row, input: input, game: game, viewer: viewer, me: me, hole: hole)
        }
    }

    static func card(_ row: RoundGameRow, input: GamesInput, game: RoundGame, viewer: Viewer, me: UUID?,
                     hole: Int) -> GameCard {
        let setup = input.setup(for: row)
        let marks = input.marks(for: row.id)
        let result = Games.evaluate(setup, round: game.round, roster: game.roster, marks: marks, rules: game.rules)
        let ids = input.players(of: row.id).map(\.playerID)
        let byString = Dictionary(uniqueKeysWithValues: ids.map { ($0.uuidString, $0) })
        func name(_ s: String) -> String { byString[s].map(game.name) ?? "Ukjent" }

        let settled = row.status == .settled
        let stored = input.results(for: row.id)
        let computed = Dictionary(uniqueKeysWithValues: ids.map { ($0, result.settlement[$0.uuidString] ?? 0) })
        let shown = settled && !stored.isEmpty ? stored : computed
        let canMark = !settled && ids.contains { game.canScore(viewer, for: $0) }
        let isOwner = viewer.isOrganizer || (me != nil && row.createdBy == me)

        let rows = ids.map { id in
            GameCard.Row(id: id, name: game.name(id), detail: detail(id, setup: setup, result: result),
                         points: shown[id] ?? 0)
        }
        .sorted { $0.points != $1.points ? $0.points > $1.points
                                         : NorwegianSort.areInIncreasingOrder($0.name, $1.name) }

        return GameCard(
            id: row.id, kind: row.kind, title: GameTexts.name(row.kind), summary: GameTexts.summary(row.settings),
            status: status(result, settled: settled, game: game),
            lines: lines(result, setup: setup, marks: marks, game: game, hole: hole, name: name),
            rows: rows, isSettled: settled,
            canSettle: !settled && isOwner && Games.isFinal(game.round) && result.isFinished,
            canDelete: !settled && isOwner,
            settlement: computed,
            action: canMark ? action(setup, marks: marks, hole: hole, count: result.holes.count, byString: byString) : nil)
    }

    private static func detail(_ id: UUID, setup: GameSetup, result: GameResult) -> String? {
        let key = id.uuidString
        switch setup.kind {
        case .skins: return GameTexts.skins(result.scores[key] ?? 0)
        case .wolf, .bingoBangoBongo: return "\(Int(result.scores[key] ?? 0)) p"
        case .nassau, .bestBall:
            guard let side = setup.sides[key] else { return nil }
            if let team = result.scores[key] { return "Lag \(side) · \(Int(team)) p" }
            return setup.side(side).count > 1 ? "Lag \(side)" : nil
        }
    }

    private static func status(_ r: GameResult, settled: Bool, game: RoundGame) -> String {
        if settled { return "Gjort opp" }
        if r.isFinished { return Games.isFinal(game.round) ? "Klar til oppgjør" : "Avgjort" }
        let done = r.holes.filter { $0.state != .pending }.count
        var text: String
        switch r.kind {
        case .wolf, .bingoBangoBongo:
            text = done == 0 ? "Ikke startet" : "\(done) av \(r.holes.count) hull"
        default:
            let first = r.holes.firstIndex { $0.state == .pending } ?? r.holes.count
            text = first == 0 ? "Ikke startet" : "Etter hull \(game.holeNumber(first - 1))"
        }
        if r.kind == .skins, r.carry > 0 {
            text += " · " + (r.carry == 1 ? "1 skin står" : "\(r.carry) skins står")
        }
        return text
    }

    private static func lines(_ r: GameResult, setup: GameSetup, marks: GameMarks, game: RoundGame, hole: Int,
                              name: (String) -> String) -> [String] {
        func side(_ n: Int) -> String {
            setup.side(n).map(name).joined(separator: " og ")
        }
        switch setup.kind {
        case .nassau, .bestBall:
            return r.bets.map { betLine($0, kind: setup.kind, settings: setup.settings, game: game, side: side) }
        case .wolf:
            guard hole < r.holes.count, let wolf = Games.wolf(on: hole, players: setup.players) else { return [] }
            let choice = GameTexts.wolfChoice(marks.wolf[hole], partnerName: name)
            return ["Hull \(game.holeNumber(hole)): \(name(wolf)) er wolf · \(choice)"]
        case .bingoBangoBongo:
            guard hole < r.holes.count else { return [] }
            let m = marks.bingoBangoBongo[hole] ?? .init()
            func who(_ id: String?) -> String { id.map(name) ?? "–" }
            return ["Hull \(game.holeNumber(hole)): bingo \(who(m.bingo)), bango \(who(m.bango)), bongo \(who(m.bongo))"]
        case .skins:
            return []
        }
    }

    private static func betLine(_ b: GameBet, kind: GameKind, settings: GameSettings, game: RoundGame,
                                side: (Int) -> String) -> String {
        let label: String
        switch b.segment {
        case .front: label = "Første ni"
        case .back: label = "Siste ni"
        case .total: label = game.holeCount == 9 ? "Runden" : "Totalt"
        case .match: label = "Matchen"
        case .press: label = "Press fra hull \(game.holeNumber(b.firstHole))"
        }
        let isMatch: Bool
        switch settings {
        case .nassau(let r): isMatch = r.scoring == .match
        case .bestBall(let r): isMatch = r.scoring == .match
        default: isMatch = true
        }
        let isStableford: Bool
        if case .bestBall(let r) = settings { isStableford = r.scoring == .stableford } else { isStableford = false }
        let lead = abs(b.margin)
        let leader = b.margin > 0 ? 1 : 2
        switch b.state {
        case .void:
            return "\(label): teller ikke"
        case .halved:
            return "\(label): delt"
        case .won:
            let how = isMatch ? "\(lead) opp" : (isStableford ? "\(lead) poeng" : "\(lead) slag")
            return "\(label): \(side(b.winner ?? leader)) vant (\(how)) · \(b.value) poeng"
        case .pending:
            if isStableford { return "\(label): \(b.margin == 0 ? "likt" : "\(side(b.margin > 0 ? 1 : 2)) leder med \(lead)")" }
            if !isMatch { return "\(label): \(b.played) av \(b.played + b.remaining) hull spilt" }
            if b.margin == 0 { return "\(label): likt, \(b.remaining) igjen" }
            return "\(label): \(side(leader)) \(lead) opp, \(b.remaining) igjen"
        }
    }

    private static func action(_ setup: GameSetup, marks: GameMarks, hole: Int, count: Int,
                               byString: [String: UUID]) -> GameHoleAction? {
        guard hole >= 0, hole < count else { return nil }
        switch setup.settings {
        case .wolf(let r):
            guard let w = Games.wolf(on: hole, players: setup.players), let wolf = byString[w] else { return nil }
            let partners = setup.players.filter { $0 != w }.compactMap { byString[$0] }
            return .wolf(hole: hole, wolf: wolf, partners: partners, blindAllowed: r.blindAllowed,
                         current: marks.wolf[hole])
        case .bingoBangoBongo:
            return .bingoBangoBongo(hole: hole, players: setup.players.compactMap { byString[$0] },
                                    current: marks.bingoBangoBongo[hole] ?? .init())
        default:
            return nil
        }
    }
}

// MARK: - Nytt spill

/// Arket for et nytt spill: type, deltakere (i rekkefølge), sider og de viktigste verdiene.
/// Starter med malen for typen.
nonisolated struct GameDraft: Equatable, Sendable {
    var settings: GameSettings
    /// Deltakerne i rekkefølge (Wolf: tee-rekkefølgen).
    var players: [UUID]
    var sides: [UUID: Int]
    /// Alle i runden, i visningsrekkefølge.
    let roundPlayers: [UUID]

    init(kind: GameKind, roundPlayers: [UUID], preferred: [UUID] = []) {
        settings = .standard(kind)
        self.roundPlayers = roundPlayers
        players = []
        sides = [:]
        setKind(kind, preferred: preferred)
    }

    var kind: GameKind { settings.kind }

    /// Bytter type: malen for den nye typen, og et forslag til deltakere (de foretrukne først).
    mutating func setKind(_ kind: GameKind, preferred: [UUID] = []) {
        if kind != settings.kind { settings = .standard(kind) }
        let pool = preferred + roundPlayers.filter { !preferred.contains($0) }
        let keep = players.isEmpty ? pool : players + pool.filter { !players.contains($0) }
        players = Array(keep.prefix(kind.playerRange.upperBound))
        resetSides()
    }

    // Verdiene for typen (malen når typen er en annen).
    var skins: SkinsRules {
        get { if case .skins(let r) = settings { r } else { .standard } }
        set { settings = .skins(newValue) }
    }
    var nassau: NassauRules {
        get { if case .nassau(let r) = settings { r } else { .standard } }
        set { settings = .nassau(newValue) }
    }
    var wolf: WolfRules {
        get { if case .wolf(let r) = settings { r } else { .standard } }
        set { settings = .wolf(newValue) }
    }
    var bingoBangoBongo: BingoBangoBongoRules {
        get { if case .bingoBangoBongo(let r) = settings { r } else { .standard } }
        set { settings = .bingoBangoBongo(newValue) }
    }
    var bestBall: BestBallRules {
        get { if case .bestBall(let r) = settings { r } else { .standard } }
        set { settings = .bestBall(newValue) }
    }

    /// Med eller ikke. Nye legges sist.
    mutating func toggle(_ id: UUID) {
        if let i = players.firstIndex(of: id) {
            players.remove(at: i)
            sides[id] = nil
        } else {
            players.append(id)
            if kind.hasSides { sides[id] = side(1).count <= side(2).count ? 1 : 2 }
        }
    }

    mutating func setSide(_ id: UUID, _ side: Int) {
        guard players.contains(id) else { return }
        sides[id] = side
    }

    func side(_ n: Int) -> [UUID] { players.filter { sides[$0] == n } }

    private mutating func resetSides() {
        sides = [:]
        guard kind.hasSides else { return }
        for (i, id) in players.enumerated() { sides[id] = i % 2 == 0 ? 1 : 2 }
    }

    var setup: GameSetup {
        GameSetup(settings: settings, players: players.map(\.uuidString),
                  sides: kind.hasSides ? Dictionary(uniqueKeysWithValues: players.compactMap { id in
                      sides[id].map { (id.uuidString, $0) }
                  }) : [:])
    }

    func problems() -> [GameSetupProblem] {
        Games.problems(setup, roundPlayers: roundPlayers.map(\.uuidString))
    }

    func params(roundID: UUID) -> CreateRoundGameParams {
        CreateRoundGameParams(p_round_id: roundID, settings: settings,
                              p_players: players.map { .init(player_id: $0, side: kind.hasSides ? sides[$0] : nil) })
    }
}
