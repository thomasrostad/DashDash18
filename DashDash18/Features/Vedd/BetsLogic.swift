import Foundation
import GolfgutuCore

// Veddemål med poeng (fase 10, B10): radene fra `sql/012_veddemaal.sql`, mapping til
// regelmotorens `Bet`, og tekstene i vedd-arket og på kortene. Ren logikk, uten nettverk og
// SwiftUI. Regnestykket (låsing, utfall, oppgjør, poengbank) ligger i GolfgutuCore (`Bets`).

/// Bryter for veddemålene. Av: ingenting kaller RPC-ene fra `sql/012_veddemaal.sql`.
/// Av i App Store-bygget (prod): poeng satt på spill er «simulert gambling» for Apple, og det
/// krever at appen sendes inn av en organisasjon (avvist 21.10.2026, 2.3.6). Styrer også innsatsen
/// i tippekupongen (`TipsBoard`), som da alltid er for æra.
nonisolated enum BetsFeature {
    static let isEnabled = AppEnvironment.current != .prod
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

/// `bets`. Siden 052 hører veddemålet til en turnering (`competition_id`) eller en enkeltrunde
/// (`round_scope`), og personene kan være profiler (private turneringer, løse runder).
nonisolated struct BetRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// Tom i turneringer uten klubb og i løse runder (052).
    var clubID: UUID?
    /// Tom utenfor sesongturneringer (052).
    var seasonID: UUID?
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
    /// 052: turneringens bank, eller enkeltrundens (`round_scope`). Nøyaktig én av dem.
    var competitionID: UUID? = nil
    var roundScope: UUID? = nil
    /// 052: profilene ved siden av medlemmene.
    var creatorProfileID: UUID? = nil
    var againstProfileID: UUID? = nil
    var resolvedByProfile: UUID? = nil

    /// Kolonnene før 052.
    static let columns = "id, club_id, season_id, event_id, round_id, creator_id, against_id, question, condition, "
        + "status, resolution, closed_at, resolved_by, resolved_at, created_at"
    /// Med 052.
    static let columnsV2 = columns + ", competition_id, round_scope, creator_profile_id, against_profile_id, resolved_by_profile"

    /// Personen som la ut veddemålet: medlemmet, ellers profilen.
    var creator: UUID? { creatorID ?? creatorProfileID }
    /// Personen veddemålet er rettet mot.
    var against: UUID? { againstID ?? againstProfileID }
    /// Arrangøren som avgjorde for hånd. Tom: scorene (telefonens feiing eller serveren).
    var resolver: UUID? { resolvedBy ?? resolvedByProfile }

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
        case competitionID = "competition_id"
        case roundScope = "round_scope"
        case creatorProfileID = "creator_profile_id"
        case againstProfileID = "against_profile_id"
        case resolvedByProfile = "resolved_by_profile"
    }
}

/// `bet_stakes`. Siden 052: medlem eller profil, og `person_key` som husker personen når en konto
/// slettes.
nonisolated struct BetStakeRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let betID: UUID
    var clubID: UUID?
    var memberID: UUID?
    var side: BetSide
    var points: Int
    var createdAt: String
    var profileID: UUID? = nil
    var personKey: UUID? = nil

    /// Kolonnene før 052.
    static let columns = "id, bet_id, club_id, member_id, side, points, created_at"
    /// Med 052.
    static let columnsV2 = columns + ", profile_id, person_key"

    /// Personen som satset: `person_key`, ellers medlemmet eller profilen.
    var person: UUID? { personKey ?? memberID ?? profileID }

    enum CodingKeys: String, CodingKey {
        case id
        case betID = "bet_id"
        case clubID = "club_id"
        case memberID = "member_id"
        case side, points
        case createdAt = "created_at"
        case profileID = "profile_id"
        case personKey = "person_key"
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

/// `create_bet_v2` (052): turneringens bank (runden må høre til den) eller enkeltrundens. Alle
/// argumentene sendes, også de tomme.
nonisolated struct CreateBetV2Params: Encodable, Equatable, Sendable {
    var competitionID: UUID?
    var roundID: UUID?
    var question: String
    var condition: BetConditionRecord?
    var againstMember: UUID?
    var againstProfile: UUID?
    var side: BetSide
    var points: Int

    private enum CodingKeys: String, CodingKey {
        case competitionID = "p_competition_id", roundID = "p_round_id", question = "p_question"
        case condition = "p_condition", againstMember = "p_against_member", againstProfile = "p_against_profile"
        case side = "p_side", points = "p_points"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(competitionID, forKey: .competitionID)
        try c.encode(roundID, forKey: .roundID)
        try c.encode(question, forKey: .question)
        try c.encode(condition, forKey: .condition)
        try c.encode(againstMember, forKey: .againstMember)
        try c.encode(againstProfile, forKey: .againstProfile)
        try c.encode(side, forKey: .side)
        try c.encode(points, forKey: .points)
    }
}

/// `bet_bank` (052): turnering eller runde, nøyaktig én. Uten person gjelder den som spør.
nonisolated struct BetScopeParams: Encodable, Equatable, Sendable {
    let competitionID: UUID?
    let roundID: UUID?

    init(_ scope: BetScope) {
        switch scope {
        case .competition(let id): competitionID = id; roundID = nil
        case .round(let id): competitionID = nil; roundID = id
        }
    }

    private enum CodingKeys: String, CodingKey { case competitionID = "p_competition_id", roundID = "p_round_id" }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(competitionID, forKey: .competitionID)
        try c.encode(roundID, forKey: .roundID)
    }
}

/// `bets_set_enabled(turnering, runde, på)` (052).
nonisolated struct BetsSetEnabledParams: Encodable, Equatable, Sendable {
    let scope: BetScope
    let enabled: Bool

    private enum CodingKeys: String, CodingKey {
        case competitionID = "p_competition_id", roundID = "p_round_id", enabled = "p_enabled"
    }

    func encode(to encoder: Encoder) throws {
        let ids = BetScopeParams(scope)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ids.competitionID, forKey: .competitionID)
        try c.encode(ids.roundID, forKey: .roundID)
        try c.encode(enabled, forKey: .enabled)
    }
}

/// Svaret fra `bet_bank`: netto, det som står ute, saldo og ledig.
nonisolated struct BetBankRow: Decodable, Equatable, Sendable {
    var net: Double
    var atStake: Double
    var balance: Double
    var available: Double

    enum CodingKeys: String, CodingKey {
        case net
        case atStake = "at_stake"
        case balance, available
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

    /// Innsatsene er nøklet på personen (`person_key`: medlem eller profil), så profiler i private
    /// turneringer og løse runder teller som alle andre. Vilkåret bruker spiller-id-ene i runden.
    static func bet(_ row: BetRow, stakes: [BetStakeRow]) -> Bet {
        Bet(id: key(row.id), status: row.status, resolution: row.resolution, closedAt: row.closedAt,
            condition: condition(row.condition, roundID: row.roundID), against: row.against.map(key),
            creatorID: row.creator.map(key),
            stakes: stakes.filter { $0.betID == row.id }
                .sorted { $0.createdAt < $1.createdAt }
                .compactMap { s in
                    s.person.map { BetStake(id: key(s.id), playerID: key($0), side: s.side, points: Double(s.points)) }
                })
    }
}

// MARK: - Tekstene

/// Tekstene i vedd-arket og på kortene, med PWA-ens ordlyd. Kroner er poeng.
nonisolated enum BetTexts {
    /// Runden hører ikke til turneringen veddemålene gjelder (hovedturneringen).
    static func otherTournament(seasonName: String) -> String {
        "Veddemål gjelder foreløpig bare \(seasonName). Denne runden er i en annen turnering, så det kan ikke veddes på den ennå."
    }

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
        case .seasonPodium: return "\(me) kommer på pallen i turneringen"
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

    /// Det du har å gå på, vist før du satser: «Du har 900 ledige poeng · maks 200 per veddemål».
    /// Har du alt satset på veddemålet, står det hvor mye som er igjen under taket. Uten
    /// poengbank (`available` nil) bare taket.
    static func stakeHint(available: Double?, maxStake: Int, already: Double) -> String {
        var parts: [String] = []
        if let available { parts.append("Du har \(points(max(0, available))) ledige poeng") }
        if already > 0 {
            let room = max(0, Double(maxStake) - already)
            parts.append("\(points(room)) til kan settes her (maks \(maxStake))")
        } else {
            parts.append("maks \(maxStake) per veddemål")
        }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Veddemål er av der du står (052, `bets_enabled`).
    static let notEnabled = "Veddemål er ikke slått på."
    /// Under bryteren «Veddemål».
    static let toggleFooter = "Av som standard. Slått av kan ingen lage nye veddemål, men de som finnes, gjøres opp som før."

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

// MARK: - Feilene fra RPC-ene

/// Feilmeldingene fra `create_bet`, `place_bet_stake` og `resolve_bet` (`sql/012_veddemaal.sql`)
/// slik spilleren skal lese dem. De fleste er alt norske og står som de er; her rettes de som er
/// tekniske, og de som ellers ville blitt «Du har ikke tilgang til dette.» (42501).
nonisolated enum BetErrors {
    /// Teksten som skal vises, eller nil når den vanlige oversettingen (`DataError`) holder.
    static func text(sqlState: String?, message: String) -> String? {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fixed = replacements[m] { return fixed }
        // «Maks 200 poeng per veddemål. Du har 0 på det fra før.»: nullen sier ingenting.
        let none = " Du har 0 på det fra før."
        if m.hasSuffix(none) { return String(m.dropLast(none.count)) }
        // Tilgangsfeilene fra RPC-ene sier hva som mangler. RLS-feil (engelsk) får den vanlige teksten.
        if sqlState == "42501", ownAccessMessages.contains(where: m.hasPrefix) { return m }
        return nil
    }

    private static let replacements: [String: String] = [
        "Runden er låst": "Runden er ferdig, så den kan ikke veddes på lenger.",
        "Veddemålet tar ikke imot innsatser nå: utfallet har begynt å bli kjent":
            "Veddemålet er stengt: utfallet har begynt å bli kjent.",
        "Utfallet må være yes, no eller void": "Velg JA, NEI eller annuller.",
        "Veddemålet er alt avgjort": "Veddemålet er alt avgjort. Lista er hentet på nytt.",
    ]

    private static let ownAccessMessages = ["Du må være logget inn", "Du er ikke aktivt medlem", "Bare arrangøren"]
}

/// Når arrangørens telefon skal gjøre opp veddemålene (`BetsModel.load` feier).
///
/// Med 052 gjør serveren opp når runden låses (`bet-settle`). Da feier ikke Hjem lenger, og telefonen
/// er bare reserve: den rører bare runder som har vært låst så lenge at serveren skulle vært ferdig
/// (`reserveDelay`). Uten 052 er det som før: Hjem feier høyst hvert femte minutt.
nonisolated enum BetSweep {
    /// Høyst så ofte, så Hjem ikke henter veddemålene ved hver retur.
    static let interval: TimeInterval = 5 * 60
    /// Serveren prøver straks runden låses og så hvert femte minutt, høyst fem ganger. Etter så lang
    /// tid regnes oppgjøret som strandet, og arrangørens telefon tar det.
    static let reserveDelay: TimeInterval = 30 * 60

    /// Skal Hjem feie nå? Aldri når serveren gjør opp (`serverSettles`).
    static func isDue(last: Date?, now: Date, serverSettles: Bool = false) -> Bool {
        guard BetsFeature.isEnabled, !serverSettles else { return false }
        return last.map { now.timeIntervalSince($0) >= interval } ?? true
    }

    /// Kan telefonen gjøre opp veddemål i denne runden? Uten serveroppgjør: alltid. Med: bare en
    /// runde som har vært låst i minst `reserveDelay` (serveren har ikke fått det til).
    static func phoneMaySettle(roundLocked: Bool, lockedAt: Date?, now: Date, serverSettles: Bool) -> Bool {
        guard serverSettles else { return true }
        guard roundLocked, let lockedAt else { return false }
        return now.timeIntervalSince(lockedAt) >= reserveDelay
    }
}
