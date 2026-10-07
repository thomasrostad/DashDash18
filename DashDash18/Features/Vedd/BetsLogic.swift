import Foundation
import GolfgutuCore

// Veddemål med poeng (fase 10, B10): radene fra `sql/012_veddemaal.sql`, mapping til
// regelmotorens `Bet`, og tekstene i vedd-arket og på kortene. Ren logikk, uten nettverk og
// SwiftUI. Regnestykket (låsing, utfall, oppgjør, poengbank) ligger i GolfgutuCore (`Bets`).

/// Veddemålene er av til 012 er godkjent og kjørt. Da kaller ingenting RPC-er som ikke finnes.
nonisolated enum BetsFeature {
    static let isEnabled = true
}

// MARK: - Radene

/// Vilkåret slik databasen lagrer det (`bets.condition`). Runden er kolonnen `round_id`.
nonisolated struct BetConditionRecord: Codable, Equatable, Sendable {
    var kind: BetCondition.Kind
    var hole: Int?
    var player: UUID?
    var a: UUID?
    var b: UUID?

    private enum CodingKeys: String, CodingKey { case kind, hole, player, a, b }

    init(kind: BetCondition.Kind, hole: Int? = nil, player: UUID? = nil, a: UUID? = nil, b: UUID? = nil) {
        self.kind = kind
        self.hole = hole
        self.player = player
        self.a = a
        self.b = b
    }

    /// Nøkler uten verdi skrives ikke: databasens formsjekk (`bet_condition_valid`) skiller på
    /// om nøkkelen finnes.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(hole, forKey: .hole)
        try c.encodeIfPresent(player.map { $0.uuidString.lowercased() }, forKey: .player)
        try c.encodeIfPresent(a.map { $0.uuidString.lowercased() }, forKey: .a)
        try c.encodeIfPresent(b.map { $0.uuidString.lowercased() }, forKey: .b)
    }
}

/// `bets`.
nonisolated struct BetRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var seasonID: UUID
    var eventID: UUID?
    var roundID: UUID?
    var creatorID: UUID?
    var againstID: UUID?
    var question: String
    var condition: BetConditionRecord?
    var status: Bet.Status
    var resolution: BetSide?
    var closedAt: String?
    var resolvedBy: UUID?
    var resolvedAt: String?
    var createdAt: String

    static let columns = "id, club_id, season_id, event_id, round_id, creator_id, against_id, question, condition, "
        + "status, resolution, closed_at, resolved_by, resolved_at, created_at"

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case seasonID = "season_id"
        case eventID = "event_id"
        case roundID = "round_id"
        case creatorID = "creator_id"
        case againstID = "against_id"
        case question, condition, status, resolution
        case closedAt = "closed_at"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
    }
}

/// `bet_stakes`.
nonisolated struct BetStakeRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let betID: UUID
    let clubID: UUID
    var memberID: UUID
    var side: BetSide
    var points: Int
    var createdAt: String

    static let columns = "id, bet_id, club_id, member_id, side, points, created_at"

    enum CodingKeys: String, CodingKey {
        case id
        case betID = "bet_id"
        case clubID = "club_id"
        case memberID = "member_id"
        case side, points
        case createdAt = "created_at"
    }
}

// MARK: - RPC-parametrene

/// `create_bet`. Alle argumentene sendes, også de tomme (PostgREST velger funksjon på navnene).
nonisolated struct CreateBetParams: Encodable, Equatable, Sendable {
    var clubID: UUID
    var roundID: UUID?
    var eventID: UUID?
    var question: String
    var condition: BetConditionRecord?
    var against: UUID?
    var side: BetSide
    var points: Int

    private enum CodingKeys: String, CodingKey {
        case clubID = "p_club_id", roundID = "p_round_id", eventID = "p_event_id", question = "p_question"
        case condition = "p_condition", against = "p_against", side = "p_side", points = "p_points"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clubID, forKey: .clubID)
        try c.encode(roundID, forKey: .roundID)
        try c.encode(eventID, forKey: .eventID)
        try c.encode(question, forKey: .question)
        try c.encode(condition, forKey: .condition)
        try c.encode(against, forKey: .against)
        try c.encode(side, forKey: .side)
        try c.encode(points, forKey: .points)
    }
}

/// `place_bet_stake`.
nonisolated struct PlaceStakeParams: Encodable, Equatable, Sendable {
    let p_bet_id: UUID
    let p_side: BetSide
    let p_points: Int
}

/// `resolve_bet` (arrangøren for hånd) og `settle_bet` (feiingen): `yes`, `no` eller `void`.
nonisolated struct ResolveBetParams: Encodable, Equatable, Sendable {
    let p_bet_id: UUID
    let p_resolution: String
}

/// `mark_bets_closed`.
nonisolated struct CloseBetsParams: Encodable, Equatable, Sendable {
    let p_bet_ids: [UUID]
}

// MARK: - Mapping til regelmotoren

nonisolated enum BetMapping {
    /// Regelmotoren bruker `UUID.uuidString` (store bokstaver) som spiller- og runde-id.
    static func key(_ id: UUID) -> String { id.uuidString }

    static func condition(_ record: BetConditionRecord?, roundID: UUID?) -> BetCondition? {
        guard let record, let roundID else { return nil }
        return BetCondition(kind: record.kind, round: key(roundID), hole: record.hole,
                            player: record.player.map(key), a: record.a.map(key), b: record.b.map(key))
    }

    static func record(_ condition: BetCondition) -> BetConditionRecord {
        BetConditionRecord(kind: condition.kind, hole: condition.hole,
                           player: condition.player.flatMap(UUID.init(uuidString:)),
                           a: condition.a.flatMap(UUID.init(uuidString:)),
                           b: condition.b.flatMap(UUID.init(uuidString:)))
    }

    static func bet(_ row: BetRow, stakes: [BetStakeRow]) -> Bet {
        Bet(id: key(row.id), status: row.status, resolution: row.resolution, closedAt: row.closedAt,
            condition: condition(row.condition, roundID: row.roundID), against: row.againstID.map(key),
            creatorID: row.creatorID.map(key),
            stakes: stakes.filter { $0.betID == row.id }
                .sorted { $0.createdAt < $1.createdAt }
                .map { BetStake(id: key($0.id), playerID: key($0.memberID), side: $0.side, points: Double($0.points)) })
    }
}

// MARK: - Tekstene

/// Tekstene i vedd-arket og på kortene, med PWA-ens ordlyd. Kroner er poeng.
nonisolated enum BetTexts {
    /// Påstanden for en mal (`utfordringMaler`). `me` og `him` er navnene; `roundName` gir
    /// «i Runde 2», ellers «i neste runde».
    static func template(_ t: BetTemplate, me: String, him: String?, roundName: String?) -> String {
        let ham = him ?? ""
        let naar = roundName.map { "i \($0)" } ?? "i neste runde"
        let hole = (t.condition?.hole).map { $0 + 1 } ?? 0
        switch t.kind {
        case .holeDuel: return "\(ham) slår \(me) netto på hull \(hole)"
        case .par: return "\(ham) holder par eller bedre på hull \(hole)"
        case .beats: return "\(ham) slår \(me) netto \(naar)"
        case .podium: return "\(ham) kommer på pallen \(naar)"
        case .myBirdie: return "\(me) får birdie på hull \(hole)"
        case .anyBirdie: return "Noen får birdie på hull \(hole)"
        case .myPar: return "\(me) holder par eller bedre på hull \(hole)"
        case .winRound: return "\(me) vinner runden"
        case .seasonPodium: return "\(me) kommer på pallen i sesongen"
        }
    }

    /// `utfordringSideTekst`.
    static func side(_ side: BetSide, against: String?) -> String {
        switch side {
        case .yes:
            guard let against, let first = against.split(separator: " ").first else { return "Ja, det skjer" }
            return "Ja, \(first) gjør det"
        case .no:
            return "Nei, jeg vinner"
        }
    }

    static func sideShort(_ side: BetSide) -> String { side == .yes ? "JA" : "NEI" }

    /// Statuspillen: én betydning per pille (C7).
    static func phase(_ phase: BetPhase) -> String {
        switch phase {
        case .open: "Åpent"
        case .closed: "Stengt"
        case .resolvedYes: "Avgjort · JA"
        case .resolvedNo: "Avgjort · NEI"
        case .void: "Annullert"
        }
    }

    /// `veddemaalStengtFordi`: hva som stengte veddemålet, i én setning.
    static func closedReason(_ bet: Bet, round: Round?, rules: Ruleset) -> String {
        switch bet.status {
        case .resolved: return "Veddemålet er avgjort."
        case .void: return "Veddemålet er annullert."
        case .open: break
        }
        guard let c = bet.condition else { return "Veddemålet er lukket – spillet er i gang." }
        guard let round, round.id == c.round else { return "Veddemålet er lukket." }
        if round.locked { return "Runden er ferdig – veddemålet gjøres opp." }
        if c.kind.isHoleBet {
            guard let open = Bets.firstOpenHole(round, players: c.players, rules: rules) else {
                return "Runden er for langt kommet – det er ingen hull igjen å vedde på."
            }
            return "Hull \((c.hole ?? 0) + 1) spilles nå. Neste hull du kan satse på er hull \(open + 1)."
        }
        return "Runden er i gang – det er ikke lenger en spådom."
    }

    /// Hvorfor innsatsen ikke tas imot.
    static func problem(_ problem: StakeProblem, closedReason: String) -> String {
        switch problem {
        case .closed: closedReason
        case .invalidAmount: "Velg et beløp."
        case .overCap(let max, let already):
            "Maks \(max) poeng per veddemål." + (already > 0 ? " Du har \(points(already)) på det fra før." : "")
        case .otherSide(let side): "Du har alt satset \(sideShort(side)) på dette."
        case .insufficient(let available): "Du har \(points(available)) ledige poeng."
        }
    }

    /// Den som avgjør, vedder ikke (besluttet 07.10.2026). Samme ordlyd som `resolve_bet`.
    static let resolverHasStake = "Du har satset på dette veddemålet og kan ikke avgjøre det. En annen arrangør må gjøre det."

    /// Hvem som avgjorde: arrangøren for hånd, eller scorene (feiingen, `resolved_by` tom).
    static func resolvedBy(_ name: String?) -> String {
        name.map { "avgjort av \($0)" } ?? "avgjort av scorene"
    }

    /// Poeng med norsk desimalkomma og to desimaler på det meste («33,33»).
    static func points(_ x: Double) -> String {
        JS.norwegianString(JS.round2(x))
    }

    /// «+50», «−33,33», «0».
    static func signed(_ x: Double) -> String {
        let r = JS.round2(x)
        if r > 0 { return "+" + points(r) }
        if r < 0 { return "−" + points(-r) }
        return "0"
    }
}
