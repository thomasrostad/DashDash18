import Foundation

// Veddemål med poeng (fase 10, B10). Gjenskaper db-nytt.js linje 2395–2640 (frontForSpiller,
// rundenHarStartet, vilkaarSpillere, frontForVeddemaal, forsteApneHull, markedTarInnsatser,
// vilkaarUtfall, skalLukkes, oppdaterMarkeder), malene i app-nytt.js (utfordringMaler) og
// oppgjøret (marketNetFor, veddemaalPoster og nettoingen i skyldOversikt). Kroner er poeng.
//
// Utvidelser utenfor PWA-en, besluttet 07.10.2026 (docs/veddemaal-poeng.md): `void` (annullert,
// alle får innsatsen tilbake), automatisk annullering av delt hull og likt resultat
// (`voidTies`), oppgjør i hele poeng (`payoutDecimals`), poengbanken (startbeholdning, saldo,
// ledig) og sjekken av en innsats (tak, saldo, én side). Med `Ruleset.BetRules.pwa` (to
// desimaler, ingen automatisk annullering) gir motoren PWA-ens svar; det kjører paritetstestene.

// MARK: - Regelsettet

extension Ruleset {
    /// Veddemålene: låsing, tak, beløpsknapper og poengbanken.
    public struct BetRules: Hashable, Sendable {
        /// Hvor mange hull foran der spilleren står det første åpne hullet ligger
        /// (`VEDDEMAAL_FORSPRANG`). 1: veddemål på hull N stenger i det hull N−1 er ført.
        public var lockAheadHoles: Int
        /// Mest én spiller kan ha på ett veddemål, summert over innsatsene (`VEDD_TAK`).
        public var maxStakePerBet: Int
        /// Beløpsknappene i vedd-arket (`VEDD_BELOP`).
        public var stakeOptions: [Int]
        /// Beløpet som er valgt når arket åpnes (`aapneUtfordring`).
        public var defaultStake: Int
        /// Poengbanken: det hver spiller starter sesongen med. `nil`: ingen bank, saldoen kan gå
        /// under null og bare taket per veddemål gjelder (som PWA-ens skyldliste).
        public var startingPoints: Int?
        /// Antall desimaler i oppgjøret. 0: hele poeng. Hver vinners gevinst rundes med
        /// `floor(x + 0.5)`, og resten fordeles på vinnerne etter største innsats (så id), så
        /// et veddemål verken skaper eller fjerner poeng. PWA-en hadde to (`rund2`).
        public var payoutDecimals: Int
        /// Delt hull, delt match og likt resultat annulleres av feiingen (alle får innsatsen
        /// tilbake). `false`: arrangøren tar dem for hånd, som i PWA-en.
        public var voidTies: Bool

        public init(lockAheadHoles: Int, maxStakePerBet: Int, stakeOptions: [Int], defaultStake: Int,
                    startingPoints: Int?, payoutDecimals: Int = 0, voidTies: Bool = true) {
            self.lockAheadHoles = lockAheadHoles
            self.maxStakePerBet = maxStakePerBet
            self.stakeOptions = stakeOptions
            self.defaultStake = defaultStake
            self.startingPoints = startingPoints
            self.payoutDecimals = payoutDecimals
            self.voidTies = voidTies
        }

        /// Golfgutu: forsprang 1, tak 200, knappene 50/100/200, 100 valgt (som PWA-en), og
        /// brukerens valg 07.10.2026: 1000 i startbeholdning per sesong, oppgjør i hele poeng og
        /// automatisk annullering av delt hull og likt resultat.
        public static let golfgutu = BetRules(lockAheadHoles: 1, maxStakePerBet: 200, stakeOptions: [50, 100, 200],
                                              defaultStake: 100, startingPoints: 1000, payoutDecimals: 0, voidTies: true)

        /// PWA-ens oppgjør og feiing: to desimaler, ingen automatisk annullering, ingen bank.
        /// Paritetstestene mot `db-nytt.js` kjører med dette.
        public static let pwa = BetRules(lockAheadHoles: 1, maxStakePerBet: 200, stakeOptions: [50, 100, 200],
                                         defaultStake: 100, startingPoints: nil, payoutDecimals: 2, voidTies: false)
    }
}

extension Ruleset.BetRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case lockAheadHoles, maxStakePerBet, stakeOptions, defaultStake, startingPoints, payoutDecimals, voidTies
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.BetRules.golfgutu
        lockAheadHoles = try c.decodeIfPresent(Int.self, forKey: .lockAheadHoles) ?? g.lockAheadHoles
        maxStakePerBet = try c.decodeIfPresent(Int.self, forKey: .maxStakePerBet) ?? g.maxStakePerBet
        stakeOptions = try c.decodeIfPresent([Int].self, forKey: .stakeOptions) ?? g.stakeOptions
        defaultStake = try c.decodeIfPresent(Int.self, forKey: .defaultStake) ?? g.defaultStake
        // `null` er et valg (ingen bank); mangler feltet, gjelder Golfgutu.
        startingPoints = c.contains(.startingPoints)
            ? try c.decodeIfPresent(Int.self, forKey: .startingPoints) : g.startingPoints
        payoutDecimals = try c.decodeIfPresent(Int.self, forKey: .payoutDecimals) ?? g.payoutDecimals
        voidTies = try c.decodeIfPresent(Bool.self, forKey: .voidTies) ?? g.voidTies
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lockAheadHoles, forKey: .lockAheadHoles)
        try c.encode(maxStakePerBet, forKey: .maxStakePerBet)
        try c.encode(stakeOptions, forKey: .stakeOptions)
        try c.encode(defaultStake, forKey: .defaultStake)
        try c.encode(startingPoints, forKey: .startingPoints)
        try c.encode(payoutDecimals, forKey: .payoutDecimals)
        try c.encode(voidTies, forKey: .voidTies)
    }
}

// MARK: - Modellen

/// JA eller NEI (`YES`/`NO` i PWA-en).
public enum BetSide: String, Codable, Hashable, Sendable, CaseIterable {
    case yes
    case no

    public var opposite: BetSide { self == .yes ? .no : .yes }
}

/// Vilkåret appen kan avgjøre selv (`markets.vilkaar`). Uten vilkår er veddemålet fri tekst.
public struct BetCondition: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Netto birdie eller bedre på et hull, av én spiller eller av «noen» (`birdie`).
        case birdie
        /// Netto par eller bedre på et hull (`par`).
        case par
        /// A slår B netto på ett hull (`hull`).
        case hole
        /// A får flere stablefordpoeng enn B i runden (`slaar`).
        case beats
        /// Spilleren vinner longest drive i runden.
        case drive
        /// Spilleren vinner nærmest pinnen i runden.
        case kp
        /// Spilleren vinner matchen sin i runden.
        case match

        /// Gjelder ett hull. Ellers gjelder vilkåret hele runden.
        public var isHoleBet: Bool { self == .birdie || self == .par || self == .hole }
    }

    public var kind: Kind
    /// Runden vilkåret gjelder (`r`).
    public var round: String
    /// Rundens 0-baserte hull (`h`), for hullvilkårene.
    public var hole: Int?
    /// Spilleren (`p`). `nil` på `birdie` betyr «noen».
    public var player: String?
    /// A og B i `hole` og `beats`: «A slår B».
    public var a: String?
    public var b: String?

    public init(kind: Kind, round: String, hole: Int? = nil, player: String? = nil, a: String? = nil, b: String? = nil) {
        self.kind = kind
        self.round = round
        self.hole = hole
        self.player = player
        self.a = a
        self.b = b
    }

    /// `vilkaarSpillere`: spillerne vilkåret handler om. Tom = «noen», og da er det feltet.
    public var players: [String] {
        [player, a, b].compactMap { $0 }.filter { !$0.isEmpty }
    }
}

/// Én innsats på et veddemål (`market_stakes`).
public struct BetStake: Codable, Hashable, Sendable {
    public var id: String?
    public var playerID: String
    public var side: BetSide
    public var points: Double

    public init(id: String? = nil, playerID: String, side: BetSide, points: Double) {
        self.id = id
        self.playerID = playerID
        self.side = side
        self.points = points
    }
}

/// Et veddemål (`markets`) med innsatsene.
public struct Bet: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case open
        case resolved
        /// Annullert av arrangøren: alle får innsatsen tilbake. Ikke i PWA-en.
        case void
    }

    public var id: String?
    public var status: Status
    /// Utfallet når veddemålet er avgjort.
    public var resolution: BetSide?
    /// Stempelet `lukket_at`: når utfallet ble kjent. Et stemplet veddemål forblir lukket.
    public var closedAt: String?
    public var condition: BetCondition?
    /// Spilleren veddemålet er rettet mot (`markets.mot`).
    public var against: String?
    public var creatorID: String?
    public var stakes: [BetStake]

    public init(id: String? = nil, status: Status = .open, resolution: BetSide? = nil, closedAt: String? = nil,
                condition: BetCondition? = nil, against: String? = nil, creatorID: String? = nil,
                stakes: [BetStake] = []) {
        self.id = id
        self.status = status
        self.resolution = resolution
        self.closedAt = closedAt
        self.condition = condition
        self.against = against
        self.creatorID = creatorID
        self.stakes = stakes
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, resolution, closedAt, condition, against, creatorID, stakes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .open
        resolution = try c.decodeIfPresent(BetSide.self, forKey: .resolution)
        closedAt = try c.decodeIfPresent(String.self, forKey: .closedAt)
        condition = try c.decodeIfPresent(BetCondition.self, forKey: .condition)
        against = try c.decodeIfPresent(String.self, forKey: .against)
        creatorID = try c.decodeIfPresent(String.self, forKey: .creatorID)
        stakes = try c.decodeIfPresent([BetStake].self, forKey: .stakes) ?? []
    }

    /// Summen på en side.
    public func pool(_ side: BetSide) -> Double {
        stakes.filter { $0.side == side }.reduce(0) { $0 + $1.points }
    }

    /// Spillerens innsatser summert, og siden til den første (`minPosisjonI`). `nil` = ingen.
    public func position(of playerID: String) -> (side: BetSide, points: Double)? {
        let mine = stakes.filter { $0.playerID == playerID }
        guard let first = mine.first else { return nil }
        return (first.side, mine.reduce(0) { $0 + $1.points })
    }

    /// `handlerOmMeg`: rettet mot spilleren, eller vilkåret nevner ham.
    public func isAbout(_ playerID: String) -> Bool {
        against == playerID || (condition?.players.contains(playerID) ?? false)
    }
}

/// Statuspillen (én betydning per pille, status-del-test.js C7).
public enum BetPhase: String, Codable, Hashable, Sendable {
    /// Tar imot innsatser.
    case open
    /// Åpent, men utfallet har begynt å bli kjent: ingen nye innsatser.
    case closed
    case resolvedYes
    case resolvedNo
    case void
}

/// Avgjøringen av et veddemål: JA, NEI eller annullert (alle får innsatsen tilbake).
public enum BetVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    case yes
    case no
    case void

    public init(_ side: BetSide) { self = side == .yes ? .yes : .no }

    /// Siden som vant, eller `nil` når veddemålet annulleres.
    public var side: BetSide? {
        switch self {
        case .yes: .yes
        case .no: .no
        case .void: nil
        }
    }
}

/// Hva en feiing skal skrive på ett veddemål (`oppdaterMarkeder`).
public struct BetUpdate: Hashable, Sendable {
    public var betID: String?
    /// Sett stempelet `lukket_at` nå.
    public var close: Bool
    /// Avgjør med dette: JA, NEI, eller annullert ved delt resultat (`voidTies`).
    public var verdict: BetVerdict?

    public init(betID: String?, close: Bool, verdict: BetVerdict?) {
        self.betID = betID
        self.close = close
        self.verdict = verdict
    }

    public init(betID: String?, close: Bool, outcome: BetSide?) {
        self.init(betID: betID, close: close, verdict: outcome.map(BetVerdict.init))
    }

    /// Siden som vant (`nil` også når veddemålet annulleres).
    public var outcome: BetSide? { verdict?.side }
}

/// En ferdig påstand i vedd-arket (`utfordringMaler`). Teksten lager appen.
public struct BetTemplate: Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// «Han slår meg netto på hull N».
        case holeDuel
        /// «Han holder par eller bedre på hull N».
        case par
        /// «Han slår meg netto i runden» (fri tekst uten runde).
        case beats
        /// «Han kommer på pallen» (fri tekst).
        case podium
        /// «Jeg får birdie på hull N».
        case myBirdie
        /// «Noen får birdie på hull N».
        case anyBirdie
        /// «Jeg holder par eller bedre på hull N».
        case myPar
        /// «Jeg vinner runden» (fri tekst).
        case winRound
        /// «Jeg kommer på pallen i sesongen» (fri tekst).
        case seasonPodium
    }

    public var kind: Kind
    public var condition: BetCondition?
    /// Siden som er valgt når malen velges.
    public var side: BetSide

    public init(kind: Kind, condition: BetCondition?, side: BetSide) {
        self.kind = kind
        self.condition = condition
        self.side = side
    }
}

/// Poeng som går fra en taper til en vinner (`veddemaalPoster`).
public struct BetTransfer: Hashable, Sendable {
    public var from: String
    public var to: String
    public var points: Double

    public init(from: String, to: String, points: Double) {
        self.from = from
        self.to = to
        self.points = points
    }
}

/// Nettoing per motpart (`skyldOversikt`, uten kassa): det du gir minus det du får.
public struct BetNetting: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public var counterpart: String
        public var points: Double
    }

    /// Motparter du gir poeng til, netto (positivt tall), størst først.
    public var gives: [Line]
    /// Motparter du får poeng fra, netto (positivt tall), størst først.
    public var receives: [Line]
    /// Motparter der det gikk opp i opp.
    public var even: [String]
    public var totalGives: Double
    public var totalReceives: Double
}

/// Én rad i poengtabellen for veddemål.
public struct BetTableRow: Hashable, Sendable {
    public var playerID: String
    public var name: String
    /// Vunnet minus tapt i avgjorte veddemål (`marketNetFor`).
    public var net: Double
    /// Det spilleren har stående i veddemål som ikke er avgjort.
    public var atStake: Double
    /// Startbeholdning + netto. `nil` uten poengbank.
    public var balance: Double?
    /// Saldo minus det som står i åpne veddemål: det som kan settes. `nil` uten poengbank.
    public var available: Double?
    /// Veddemål spilleren har satset på.
    public var bets: Int
    /// Avgjorte veddemål spilleren vant.
    public var won: Int
}

/// Hvorfor en innsats ikke tas imot.
public enum StakeProblem: Hashable, Sendable {
    /// Veddemålet tar ikke imot innsatser (avgjort, lukket, eller utfallet er i ferd med å bli kjent).
    case closed
    /// Under 1 poeng.
    case invalidAmount
    /// Over taket. `already` er det spilleren har på veddemålet fra før.
    case overCap(max: Int, already: Double)
    /// Spilleren har satset på den andre siden fra før.
    case otherSide(BetSide)
    /// Ikke nok ledige poeng i banken.
    case insufficient(available: Double)
}

// MARK: - Regnestykket

public enum Bets {
    /// Grensene for én innsats og taket i databasen (`bet_stakes.points`). Ikke en regelverdi.
    public static let stakeLimits = 1...10_000
    /// Største startbeholdning databasen og regelsettet godtar. Ikke en regelverdi.
    public static let bankLimit = 1_000_000
    /// Desimalene oppgjøret kan rundes til (`payoutDecimals`). Databasen godtar det samme.
    public static let payoutDecimalsLimits = 0...2

    // MARK: Låsing

    /// `frontForSpiller`: hullet spilleren står på nå, høyeste førte hull pluss én. 0 = ikke begynt.
    public static func front(of playerID: String, in round: Round) -> Int {
        guard let scores = round.holeScores[playerID], let top = scores.keys.max() else { return 0 }
        return top + 1
    }

    /// `rundenHarStartet`: har noen ført noe i runden?
    public static func roundHasStarted(_ round: Round) -> Bool {
        round.holeScores.values.contains { !$0.isEmpty }
    }

    /// `frontForVeddemaal`: den av spillerne som har kommet lengst. Tom liste: den som leder feltet.
    public static func front(of players: [String], in round: Round) -> Int {
        let ids = players.isEmpty ? Array(round.holeScores.keys) : players
        return ids.reduce(0) { max($0, front(of: $1, in: round)) }
    }

    /// `forsteApneHull`: første hull det fortsatt går an å vedde på, eller `nil` når runden er
    /// låst eller kommet for langt. Før noen av dem har begynt, er hull 1 åpent.
    public static func firstOpenHole(_ round: Round?, players: [String], rules: Ruleset = .golfgutu) -> Int? {
        guard let round, !round.locked else { return nil }
        let front = front(of: players, in: round)
        let i = front == 0 ? 0 : front + rules.bets.lockAheadHoles
        return i < Truncation.countingHoles(round) ? i : nil
    }

    /// `markedTarInnsatser`: tar veddemålet imot innsatser nå? `round` er runden vilkåret gjelder;
    /// `nil` betyr at den ikke finnes, og da er det ingen score å lekke fra.
    public static func acceptsStakes(_ bet: Bet, round: Round?, rules: Ruleset = .golfgutu) -> Bool {
        guard bet.status == .open, bet.closedAt == nil else { return false }
        guard let c = bet.condition else { return true }
        guard let round, round.id == c.round else { return true }
        if round.locked { return false }
        if c.kind.isHoleBet {
            guard let open = firstOpenHole(round, players: c.players, rules: rules), let hole = c.hole else { return false }
            return hole >= open
        }
        return !roundHasStarted(round)
    }

    /// Statuspillen: åpen, stengt eller avgjort.
    public static func phase(_ bet: Bet, acceptsStakes: Bool) -> BetPhase {
        switch bet.status {
        case .resolved:
            switch bet.resolution {
            case .yes: .resolvedYes
            case .no: .resolvedNo
            case nil: .void
            }
        case .void: .void
        case .open: acceptsStakes ? .open : .closed
        }
    }

    // MARK: Utfallet

    /// `vilkaarUtfall`: utfallet, eller `nil` når det ennå ikke er sikkert eller er delt. Et
    /// veddemål som avgjøres for tidlig er verre enn ett som avgjøres sent.
    public static func outcome(_ round: Round, condition c: BetCondition, roster: [Player], claims: [SideClaim] = [],
                               rules: Ruleset = .golfgutu) -> BetSide? {
        result(round, condition: c, roster: roster, claims: claims, rules: rules)?.side
    }

    /// Som `outcome`, men skiller delt fra ukjent: `.void` når utfallet er kjent og delt (delt
    /// hull, delt match, likt resultat) og regelsettet annullerer slike (`voidTies`). Ellers
    /// `nil`, og da er det arrangørens sak, som i PWA-en.
    public static func verdict(_ round: Round, condition c: BetCondition, roster: [Player], claims: [SideClaim] = [],
                               rules: Ruleset = .golfgutu) -> BetVerdict? {
        switch result(round, condition: c, roster: roster, claims: claims, rules: rules) {
        case .side(let side): BetVerdict(side)
        case .tie: rules.bets.voidTies ? .void : nil
        case nil: nil
        }
    }

    private enum Result {
        case side(BetSide)
        /// Kjent og delt.
        case tie

        var side: BetSide? {
            if case .side(let s) = self { return s }
            return nil
        }
    }

    private static func result(_ round: Round, condition c: BetCondition, roster: [Player], claims: [SideClaim],
                               rules: Ruleset) -> Result? {
        guard round.id == c.round else { return nil }
        let course = round.courseHoles()
        let count = round.numberOfHoles

        // Netto mot par på ett hull. Med ekstern handicap er netto tallet som ble ført.
        func netToPar(_ pid: String?, _ h: Int?) -> Int? {
            guard let pid, let h, h >= 0, h < course.count, let gross = round.holeScores[pid]?[h] else { return nil }
            let hole = course[h]
            let hcp = Handicap.effective(for: roster.first { $0.id == pid }, in: round, roster: roster, rules: rules)
            return Scoring.netStrokes(gross: gross, handicap: hcp, strokeIndex: hole.strokeIndex, holes: count) - hole.par
        }

        switch c.kind {
        case .birdie, .par:
            let limit = c.kind == .birdie ? -1 : 0
            if let p = c.player, !p.isEmpty {
                guard let d = netToPar(p, c.hole) else { return nil }
                return .side(d <= limit ? .yes : .no)
            }
            // «Noen»: JA så snart én klarer det, NEI først når alle i runden har ført hullet.
            var allDone = !round.holeScores.isEmpty
            for pid in round.holeScores.keys {
                let d = netToPar(pid, c.hole)
                if let d, d <= limit { return .side(.yes) }
                if d == nil { allDone = false }
            }
            return (allDone || round.locked) ? .side(.no) : nil

        case .hole:
            guard let ha = netToPar(c.a, c.hole), let hb = netToPar(c.b, c.hole) else { return nil }
            if ha == hb { return .tie }
            return .side(ha < hb ? .yes : .no)

        case .beats:
            guard round.locked else { return nil }
            let a = Scoring.roundNetTotal(round, player: roster.first { $0.id == c.a }, roster: roster, rules: rules)
            let b = Scoring.roundNetTotal(round, player: roster.first { $0.id == c.b }, roster: roster, rules: rules)
            if a == b { return .tie }
            return .side(a > b ? .yes : .no)

        case .drive, .kp:
            guard round.locked else { return nil }
            let list = SidePrizes.claims(c.kind == .drive ? .drive : .kp, in: round, claims: claims)
            guard let first = list.first else { return nil }
            return .side(first.playerId == c.player ? .yes : .no)

        case .match:
            guard let p = c.player,
                  let m = round.matches.first(where: { MatchPlay.involves($0, playerID: p, in: round) }),
                  let st = MatchPlay.standing(m, from: p, in: round, roster: roster, rules: rules) else { return nil }
            if !st.decided && !round.locked { return nil }
            if st.up > 0 { return .side(.yes) }
            if st.up < 0 { return .side(.no) }
            return .tie
        }
    }

    /// `skalLukkes`: skal stempelet settes nå som `hole` er ført? Hullveddemål av sitt eget hull,
    /// veddemål om hele runden av rundens første score.
    public static func shouldClose(_ bet: Bet, round: Round, hole: Int) -> Bool {
        guard bet.status == .open, bet.closedAt == nil, let c = bet.condition, c.round == round.id else { return false }
        return c.kind.isHoleBet ? c.hole == hole : true
    }

    /// `oppdaterMarkeder` uten skrivingen: hva arrangørens telefon skal skrive etter at `hole` er
    /// ført (eller etter en henting, `hole == nil`). Bare åpne veddemål med vilkår i runden. Med
    /// `voidTies` annulleres delt hull, delt match og likt resultat i samme feiing.
    public static func sweep(_ bets: [Bet], round: Round, hole: Int?, roster: [Player], claims: [SideClaim] = [],
                             rules: Ruleset = .golfgutu) -> [BetUpdate] {
        bets.compactMap { bet in
            guard bet.status == .open, let c = bet.condition, c.round == round.id else { return nil }
            let stamp = hole.map { shouldClose(bet, round: round, hole: $0) } ?? false
            let result = verdict(round, condition: c, roster: roster, claims: claims, rules: rules)
            let close = stamp || (result != nil && bet.closedAt == nil)
            guard close || result != nil else { return nil }
            return BetUpdate(betID: bet.id, close: close, verdict: result)
        }
    }

    // MARK: Malene

    /// `utfordringMaler`: påstandene i vedd-arket. Mot en spiller: duellen og par på hullet som
    /// kommer (hver med sitt eget hull), duellen om runden før første slag, og pallen. Om deg selv:
    /// birdie og par på ditt neste åpne hull, ellers runden og sesongen.
    public static func templates(round: Round?, me: String, against: String?, rules: Ruleset = .golfgutu) -> [BetTemplate] {
        let rid = round?.id
        if let him = against {
            var out: [BetTemplate] = []
            if let rid, let h = firstOpenHole(round, players: [him, me], rules: rules) {
                out.append(BetTemplate(kind: .holeDuel, condition: BetCondition(kind: .hole, round: rid, hole: h, a: him, b: me), side: .no))
            }
            if let rid, let h = firstOpenHole(round, players: [him], rules: rules) {
                out.append(BetTemplate(kind: .par, condition: BetCondition(kind: .par, round: rid, hole: h, player: him), side: .no))
            }
            if rid == nil || !(round.map(roundHasStarted) ?? false) {
                out.append(BetTemplate(kind: .beats, condition: rid.map { BetCondition(kind: .beats, round: $0, a: him, b: me) },
                                       side: .no))
            }
            out.append(BetTemplate(kind: .podium, condition: nil, side: .no))
            return out
        }
        guard let rid, let h = firstOpenHole(round, players: [me], rules: rules) else {
            return [BetTemplate(kind: .winRound, condition: nil, side: .yes),
                    BetTemplate(kind: .seasonPodium, condition: nil, side: .yes)]
        }
        return [
            BetTemplate(kind: .myBirdie, condition: BetCondition(kind: .birdie, round: rid, hole: h, player: me), side: .yes),
            BetTemplate(kind: .anyBirdie, condition: BetCondition(kind: .birdie, round: rid, hole: h), side: .yes),
            BetTemplate(kind: .myPar, condition: BetCondition(kind: .par, round: rid, hole: h, player: me), side: .yes),
        ]
    }

    // MARK: Oppgjøret

    /// Hver spillers resultat i ett avgjort veddemål: gevinsten for vinnerne, minus innsatsen for
    /// taperne. Vinnersiden deler taperpotten etter innsats. Gevinsten rundes til
    /// `payoutDecimals` med `floor(x + 0.5)`, og resten (det avrundingen skapte eller fjernet)
    /// fordeles én enhet om gangen på vinnerne etter største innsats, så spiller-id. Summen er
    /// alltid null. Tomt når ingen poeng flytter seg: åpent, annullert, ingen på vinnersiden
    /// eller ingen tapere (alle får innsatsen tilbake). Samme regnestykke som `bet_points_for`
    /// i `sql/012_veddemaal.sql`.
    public static func payouts(_ bet: Bet, rules: Ruleset = .golfgutu) -> [String: Double] {
        guard bet.status == .resolved, let res = bet.resolution else { return [:] }
        // Per spiller: summen av innsatsene, og siden (alltid én side per spiller).
        var order: [String] = []
        var sums: [String: (side: BetSide, points: Double)] = [:]
        for s in bet.stakes {
            if sums[s.playerID] == nil { order.append(s.playerID); sums[s.playerID] = (s.side, 0) }
            sums[s.playerID]!.points += s.points
        }
        let winners = order.filter { sums[$0]!.side == res }
            .sorted { a, b in
                let x = sums[a]!.points, y = sums[b]!.points
                return x != y ? x > y : a < b
            }
        let losers = order.filter { sums[$0]!.side != res }
        let win = winners.reduce(0) { $0 + sums[$1]!.points }
        let lose = losers.reduce(0) { $0 + sums[$1]!.points }
        guard win > 0, lose > 0 else { return [:] }

        let scale = pow(10, Double(max(0, rules.bets.payoutDecimals)))
        // Enheter (hele poeng ved 0 desimaler). Innsatsene er hele poeng, så produktet er eksakt.
        var units = winners.map { JS.round(sums[$0]!.points * lose * scale / win) }
        let rest = Int((lose * scale - units.reduce(0, +)).rounded())
        for k in 0..<abs(rest) {
            units[k % units.count] += rest > 0 ? 1 : -1
        }
        var out: [String: Double] = [:]
        for (i, pid) in winners.enumerated() { out[pid] = units[i] / scale }
        for pid in losers { out[pid] = -sums[pid]!.points }
        return out
    }

    /// `veddemaalPoster`: taperne gir vinnerne poeng i forhold til innsats. Hver taperinnsats
    /// fordeles på vinnersiden etter vinnerinnsats. Ingen på vinnersiden, eller ingen tapere:
    /// alle får innsatsen tilbake, og det blir ingen overføringer. Hver overføring rundes for
    /// seg til `payoutDecimals` (PWA-en: to). Regnestykket per motpart; saldoen regnes av
    /// `payouts`, og summen av overføringene kan avvike med avrundingen (som i PWA-en).
    public static func transfers(_ bet: Bet, rules: Ruleset = .golfgutu) -> [BetTransfer] {
        guard bet.status == .resolved, let res = bet.resolution else { return [] }
        let winners = bet.stakes.filter { $0.side == res }
        let losers = bet.stakes.filter { $0.side != res }
        let pot = winners.reduce(0) { $0 + $1.points }
        guard pot != 0, !losers.isEmpty else { return [] }
        let scale = pow(10, Double(max(0, rules.bets.payoutDecimals)))
        var order: [String] = []
        var sums: [String: (from: String, to: String, points: Double)] = [:]
        for t in losers {
            for w in winners where t.playerID != w.playerID {
                let key = t.playerID + ">" + w.playerID
                if sums[key] == nil { order.append(key); sums[key] = (t.playerID, w.playerID, 0) }
                sums[key]!.points += t.points * w.points / pot
            }
        }
        return order.compactMap { key in
            let s = sums[key]!
            let points = JS.round(s.points * scale) / scale
            return points > 0 ? BetTransfer(from: s.from, to: s.to, points: points) : nil
        }
    }

    /// `marketNetFor`: vunnet minus tapt i avgjorte veddemål (`payouts`, rundet etter
    /// regelsettet). Det som står i åpne og annullerte teller ikke.
    public static func net(for playerID: String, in bets: [Bet], rules: Ruleset = .golfgutu) -> Double {
        bets.reduce(0) { $0 + (payouts($1, rules: rules)[playerID] ?? 0) }
    }

    /// Det spilleren har stående i veddemål som ikke er avgjort.
    public static func atStake(for playerID: String, in bets: [Bet]) -> Double {
        bets.filter { $0.status == .open }
            .flatMap(\.stakes)
            .filter { $0.playerID == playerID }
            .reduce(0) { $0 + $1.points }
    }

    /// Saldoen i poengbanken: startbeholdning + netto. `nil` uten bank.
    public static func balance(for playerID: String, in bets: [Bet], rules: Ruleset = .golfgutu) -> Double? {
        rules.bets.startingPoints.map { Double($0) + net(for: playerID, in: bets, rules: rules) }
    }

    /// Det som kan settes: saldo minus det som står i åpne veddemål. `nil` uten bank.
    public static func available(for playerID: String, in bets: [Bet], rules: Ruleset = .golfgutu) -> Double? {
        balance(for: playerID, in: bets, rules: rules).map { $0 - atStake(for: playerID, in: bets) }
    }

    /// Nettoing per motpart av overføringene, sett fra `playerID` (`skyldOversikt`).
    public static func netting(_ transfers: [BetTransfer], for playerID: String) -> BetNetting {
        var order: [String] = []
        var sums: [String: Double] = [:]
        for t in transfers {
            let other: String
            let signed: Double
            if t.from == playerID { other = t.to; signed = t.points }
            else if t.to == playerID { other = t.from; signed = -t.points }
            else { continue }
            if sums[other] == nil { order.append(other); sums[other] = 0 }
            sums[other]! += signed
        }
        var gives: [BetNetting.Line] = []
        var receives: [BetNetting.Line] = []
        var even: [String] = []
        for other in order {
            let n = JS.round2(sums[other]!)
            if abs(n) < 0.005 { even.append(other) }
            else if n > 0 { gives.append(.init(counterpart: other, points: n)) }
            else { receives.append(.init(counterpart: other, points: -n)) }
        }
        // Stabil sortering: størst først, ellers rekkefølgen motpartene dukket opp i.
        func sorted(_ lines: [BetNetting.Line]) -> [BetNetting.Line] {
            lines.enumerated().sorted { $0.element.points != $1.element.points ? $0.element.points > $1.element.points : $0.offset < $1.offset }
                .map(\.element)
        }
        gives = sorted(gives)
        receives = sorted(receives)
        return BetNetting(gives: gives, receives: receives, even: even,
                          totalGives: JS.round2(gives.reduce(0) { $0 + $1.points }),
                          totalReceives: JS.round2(receives.reduce(0) { $0 + $1.points }))
    }

    /// Poengtabellen for veddemål, separat fra jakketabellen. Sortert på saldo (netto uten bank),
    /// så norsk navn.
    public static func table(players: [Player], bets: [Bet], rules: Ruleset = .golfgutu) -> [BetTableRow] {
        let rows = players.map { p in
            let mine = bets.filter { b in b.stakes.contains { $0.playerID == p.id } }
            let won = mine.filter { b in b.status == .resolved && b.resolution != nil && b.position(of: p.id)?.side == b.resolution }
            return BetTableRow(playerID: p.id, name: p.name, net: net(for: p.id, in: bets, rules: rules),
                               atStake: atStake(for: p.id, in: bets),
                               balance: balance(for: p.id, in: bets, rules: rules),
                               available: available(for: p.id, in: bets, rules: rules),
                               bets: mine.count, won: won.count)
        }
        return rows.sorted { a, b in
            let x = a.balance ?? a.net, y = b.balance ?? b.net
            if x != y { return x > y }
            return NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
    }

    // MARK: Avgjøringen

    /// Kan `playerID` (en arrangør) avgjøre veddemålet for hånd? Bare et åpent veddemål, og bare
    /// når han ikke har innsats i det: den som avgjør, vedder ikke (besluttet 07.10.2026). Samme
    /// regel som `resolve_bet`. Feiingen (vilkåret avgjør) er ikke arrangørens skjønn og gjelder ikke.
    public static func canResolve(_ bet: Bet, by playerID: String) -> Bool {
        bet.status == .open && bet.position(of: playerID) == nil
    }

    // MARK: Innsatsen

    /// Sjekken før en innsats sendes: åpen, minst 1 poeng, under taket summert over dine innsatser,
    /// samme side som før, og nok ledige poeng når sesongen har poengbank. `nil` = i orden.
    /// `bets` er sesongens veddemål (for saldoen); `bet` kan være nytt og mangle der.
    public static func stakeProblem(_ bet: Bet, playerID: String, side: BetSide, points: Int, round: Round?,
                                    bets: [Bet], rules: Ruleset = .golfgutu) -> StakeProblem? {
        guard acceptsStakes(bet, round: round, rules: rules) else { return .closed }
        guard points >= 1 else { return .invalidAmount }
        if let pos = bet.position(of: playerID) {
            if pos.side != side { return .otherSide(pos.side) }
            if pos.points + Double(points) > Double(rules.bets.maxStakePerBet) {
                return .overCap(max: rules.bets.maxStakePerBet, already: pos.points)
            }
        } else if points > rules.bets.maxStakePerBet {
            return .overCap(max: rules.bets.maxStakePerBet, already: 0)
        }
        if let free = available(for: playerID, in: bets, rules: rules), Double(points) > free {
            return .insufficient(available: max(0, free))
        }
        return nil
    }
}
