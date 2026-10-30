import Foundation

// Tippekupongen (db-nytt.js linje 3215–3483: TIPS_SPORSMAAL, tipsStarttid, osloTidspunkt, tipsAapen,
// tipsFasit, tipsRiktig, tipsBeste, tipsKomplett, tipsResultat og potten i tipsOppgjor).
//
// Innsatsen er poeng, ikke kroner (B10). Her regnes bare hvem som vant og hvor stor potten er
// (innsats · antall kuponger). Ingen overføringer og ingen poengbank før fase 10.

// MARK: - Regelsettet

extension Ruleset {
    /// Standardene for tippekupongen. Kvelden kan overstyre innsats og linje (`events.tips_stake_points`,
    /// `events.tips_line`); tom verdi på kvelden betyr regelsettets standard.
    public struct TipsRules: Hashable, Sendable {
        /// Fristen når kvelden ikke har et klokkeslett, `HH:MM` i Oslo-tid (`TIPS_START_STANDARD`).
        public var defaultStartTime: String
        /// Innsats per kupong i poeng (`TIPS_INNSATS_STANDARD`). 0 = for æra.
        public var defaultStakePoints: Int
        /// Valgene arrangøren får for innsatsen (`TIPS_INNSATS_VALG`).
        public var stakeOptions: [Int]
        /// Linja på over/under: netto slag over par per ni hull, snitt for feltet (`TIPS_LINJE_STANDARD`).
        public var defaultLine: Double
        /// Hvor mye linja flyttes per trykk hos arrangøren (PWA-en: ett slag).
        public var lineStep: Double
        /// Spørsmålene på kupongen, i kupongens rekkefølge. Bare disse vises, må besvares og gir poeng.
        public var questions: [TipsQuestion]
        /// Linja på «antall birdier»: netto birdie eller bedre for hele feltet, hele kvelden.
        public var birdieCountLine: Double
        /// Linja på «vinnerens poeng»: stablefordpoengene til kveldens vinner.
        public var winnerPointsLine: Double
        /// Linjene på de andre over/under-spørsmålene der arrangøren har endret dem. Mangler et
        /// spørsmål, gjelder `golfgutuLines`. Les og skriv med `line(_:)` og `setLine(_:_:)`.
        public var lines: [TipsQuestion: Double]

        public init(defaultStartTime: String, defaultStakePoints: Int, stakeOptions: [Int], defaultLine: Double,
                    lineStep: Double, questions: [TipsQuestion] = TipsRules.golfgutuQuestions,
                    birdieCountLine: Double = TipsRules.golfgutuBirdieCountLine,
                    winnerPointsLine: Double = TipsRules.golfgutuWinnerPointsLine,
                    lines: [TipsQuestion: Double] = [:]) {
            self.defaultStartTime = defaultStartTime
            self.defaultStakePoints = defaultStakePoints
            self.stakeOptions = stakeOptions
            self.defaultLine = defaultLine
            self.lineStep = lineStep
            self.questions = questions
            self.birdieCountLine = birdieCountLine
            self.winnerPointsLine = winnerPointsLine
            self.lines = lines
        }

        /// Linja et over/under-spørsmål har i regelsettet. `nil` for snittet (kvelden har linja)
        /// og for spørsmål uten linje.
        public func line(_ q: TipsQuestion) -> Double? {
            switch q {
            case .birdieCount: birdieCountLine
            case .winnerPoints: winnerPointsLine
            default: lines[q] ?? Self.golfgutuLines[q]
            }
        }

        /// Endrer linja. Standarden lagres ikke, så JSON-en er som før til noe er endret.
        public mutating func setLine(_ q: TipsQuestion, _ value: Double) {
            switch q {
            case .birdieCount: birdieCountLine = value
            case .winnerPoints: winnerPointsLine = value
            default:
                guard Self.golfgutuLines[q] != nil else { return }
                lines[q] = value == Self.golfgutuLines[q] ? nil : value
            }
        }

        /// PWA-ens fem spørsmål (`TIPS_SPORSMAAL`), i kupongens rekkefølge.
        public static let golfgutuQuestions: [TipsQuestion] = TipsTemplate.classic.questions
        /// Standardlinjene for spørsmålene PWA-en ikke har. Et anslag; arrangøren kan endre dem.
        public static let golfgutuBirdieCountLine = 14.5
        public static let golfgutuWinnerPointsLine = 37.5
        /// Standardlinjene for de morsomme over/under-spørsmålene. Et anslag; arrangøren kan endre dem.
        public static let golfgutuLines: [TipsQuestion: Double] = [
            .lastPlacePoints: 25.5, .winningMargin: 2.5, .blankHoles: 20.5, .parOrBetterPlayers: 2.5,
        ]

        /// Golfgutu: frist 17:00, 50 poeng (0/20/50/100), linje +2,5, ett slag per trykk, de fem spørsmålene.
        /// Linjene for antall birdier (14,5) og vinnerens poeng (37,5) brukes bare når de spørsmålene er med.
        public static let golfgutu = TipsRules(defaultStartTime: "17:00", defaultStakePoints: 50,
                                               stakeOptions: [0, 20, 50, 100], defaultLine: 2.5, lineStep: 1,
                                               questions: golfgutuQuestions,
                                               birdieCountLine: golfgutuBirdieCountLine,
                                               winnerPointsLine: golfgutuWinnerPointsLine)
    }
}

extension Ruleset.TipsRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case defaultStartTime, defaultStakePoints, stakeOptions, defaultLine, lineStep, questions
        case birdieCountLine, winnerPointsLine, lines
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.TipsRules.golfgutu
        defaultStartTime = try c.decodeIfPresent(String.self, forKey: .defaultStartTime) ?? g.defaultStartTime
        defaultStakePoints = try c.decodeIfPresent(Int.self, forKey: .defaultStakePoints) ?? g.defaultStakePoints
        stakeOptions = try c.decodeIfPresent([Int].self, forKey: .stakeOptions) ?? g.stakeOptions
        defaultLine = try c.decodeIfPresent(Double.self, forKey: .defaultLine) ?? g.defaultLine
        lineStep = try c.decodeIfPresent(Double.self, forKey: .lineStep) ?? g.lineStep
        // Et spørsmål appen ikke kjenner (fra en nyere versjon), hoppes over i stedet for å stoppe hele regelsettet.
        questions = try c.decodeIfPresent([String].self, forKey: .questions)?.compactMap(TipsQuestion.init(rawValue:))
            ?? g.questions
        birdieCountLine = try c.decodeIfPresent(Double.self, forKey: .birdieCountLine) ?? g.birdieCountLine
        winnerPointsLine = try c.decodeIfPresent(Double.self, forKey: .winnerPointsLine) ?? g.winnerPointsLine
        // Som spørsmålene: en linje appen ikke kjenner, hoppes over.
        let raw = try c.decodeIfPresent([String: Double].self, forKey: .lines) ?? [:]
        lines = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            TipsQuestion(rawValue: k).flatMap { Self.golfgutuLines[$0] == nil ? nil : ($0, v) }
        })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultStartTime, forKey: .defaultStartTime)
        try c.encode(defaultStakePoints, forKey: .defaultStakePoints)
        try c.encode(stakeOptions, forKey: .stakeOptions)
        try c.encode(defaultLine, forKey: .defaultLine)
        try c.encode(lineStep, forKey: .lineStep)
        // Bare når spørsmålene ikke er Golfgutus fem, så JSON-en for regelsett fra før er som før.
        let g = Ruleset.TipsRules.golfgutu
        if questions != g.questions { try c.encode(questions, forKey: .questions) }
        if birdieCountLine != g.birdieCountLine { try c.encode(birdieCountLine, forKey: .birdieCountLine) }
        if winnerPointsLine != g.winnerPointsLine { try c.encode(winnerPointsLine, forKey: .winnerPointsLine) }
        if !lines.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: lines.map { ($0.key.rawValue, $0.value) }), forKey: .lines)
        }
    }
}

// MARK: - Spørsmålene og kupongen

/// Spørsmålene en kupong kan ha. Hvilke som er med, og i hvilken rekkefølge, står i regelsettet
/// (`Ruleset.TipsRules.questions`); Golfgutu har de fem fra `TIPS_SPORSMAAL`. De fem første er PWA-ens,
/// de andre er nye (avgjøres automatisk fra hullscorene, som de fem).
public enum TipsQuestion: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case winner
    case frontNine
    case mostPars
    case birdie
    case over
    /// Antall netto birdier (eller bedre) i feltet, over eller under en linje.
    case birdieCount
    /// Flest netto birdier (eller bedre).
    case mostBirdies
    /// Lavest netto på banens hull 10–18.
    case backNine
    /// Vinnerens stablefordpoeng, over eller under en linje.
    case winnerPoints
    /// Færrest stablefordpoeng.
    case lastPlace
    /// Færrest brutto slag, bare blant dem som har ført alle hullene.
    case lowestGross
    /// Størst framgang i poeng fra banens første ni til siste ni.
    case comeback
    /// Flest hull med laveste poeng (0 i Golfgutu).
    case mostBlanks
    /// Flest stablefordpoeng på par 3-hullene.
    case bestParThrees
    /// Flest stablefordpoeng på par 5-hullene.
    case bestParFives
    /// Flest netto par eller bedre på rad.
    case parStreak
    /// Minst én netto eagle eller bedre.
    case eagle
    /// Minst én brutto birdie eller bedre.
    case grossBirdie
    /// Den som leder etter banens første ni, vinner kvelden.
    case leaderWins
    /// Flere står likt øverst.
    case sharedWin
    /// Vinneren har høyere handicap enn medianen i feltet.
    case highHandicapWins
    /// Poengene til den som blir sist, over eller under en linje.
    case lastPlacePoints
    /// Vinnerens poeng minus nummer to, over eller under en linje.
    case winningMargin
    /// Hull med laveste poeng i feltet, over eller under en linje.
    case blankHoles
    /// Spillere med netto par eller bedre i snitt (poeng for netto par per hull), over eller under en linje.
    case parOrBetterPlayers

    /// Alle spørsmålene i rekkefølgen de står på kupongen når de er med. De ni fra før står i samme
    /// innbyrdes rekkefølge som før, så en lagret kupong får samme rekkefølge.
    public static let catalog: [TipsQuestion] = [
        .winner, .frontNine, .backNine, .mostPars,
        .lastPlace, .lowestGross, .comeback, .mostBlanks, .bestParThrees, .bestParFives, .parStreak,
        .birdie, .eagle, .grossBirdie, .leaderWins, .sharedWin, .highHandicapWins,
        .birdieCount, .mostBirdies, .over, .winnerPoints,
        .lastPlacePoints, .winningMargin, .blankHoles, .parOrBetterPlayers,
    ]

    /// Flest spørsmål på én kupong. Databasen tar høyst 20 svar utenom de fem gamle (sql/070);
    /// over et dusin blir kupongen dessuten for lang å fylle ut.
    public static let maxPerCoupon = 12

    public enum Kind: String, Codable, Sendable {
        /// Svaret er en spiller.
        case player
        /// Ja eller nei.
        case yesNo
        /// Over (true) eller under (false) linja.
        case overUnder
    }

    public var id: String { rawValue }

    public var kind: Kind {
        switch self {
        case .winner, .frontNine, .mostPars, .mostBirdies, .backNine, .lastPlace, .lowestGross, .comeback,
             .mostBlanks, .bestParThrees, .bestParFives, .parStreak: .player
        case .birdie, .eagle, .grossBirdie, .leaderWins, .sharedWin, .highHandicapWins: .yesNo
        case .over, .birdieCount, .winnerPoints, .lastPlacePoints, .winningMargin, .blankHoles,
             .parOrBetterPlayers: .overUnder
        }
    }

    /// `tittel`. Over/under har linja i tittelen; se `Tips.title(_:line:)`.
    public var title: String {
        switch self {
        case .winner: "Hvem vinner kvelden?"
        case .frontNine: "Lavest netto på første ni?"
        case .mostPars: "Flest par eller bedre?"
        case .birdie: "Blir det slått en birdie?"
        case .over: "Over eller under linja?"
        case .birdieCount: "Antall birdier: over eller under?"
        case .mostBirdies: "Hvem får flest birdier?"
        case .backNine: "Lavest netto på siste ni?"
        case .winnerPoints: "Vinnerens poeng: over eller under?"
        case .lastPlace: "Hvem blir sist?"
        case .lowestGross: "Lavest brutto?"
        case .comeback: "Kveldens comeback?"
        case .mostBlanks: "Hvem får flest blanke hull?"
        case .bestParThrees: "Best på par 3-hullene?"
        case .bestParFives: "Best på par 5-hullene?"
        case .parStreak: "Lengst rekke med par eller bedre?"
        case .eagle: "Blir det en eagle?"
        case .grossBirdie: "Blir det en ekte birdie?"
        case .leaderWins: "Vinner lederen etter ni hull?"
        case .sharedWin: "Blir det delt seier?"
        case .highHandicapWins: "Vinner en med høyt handicap?"
        case .lastPlacePoints: "Sistemannens poeng: over eller under?"
        case .winningMargin: "Seiersmarginen: over eller under?"
        case .blankHoles: "Antall blanke hull: over eller under?"
        case .parOrBetterPlayers: "Antall på par eller bedre: over eller under?"
        }
    }

    /// `under`.
    public var subtitle: String {
        switch self {
        case .winner: "Flest stablefordpoeng over alle hullene i kveld."
        case .frontNine: "Banens hull 1–9. Færrest netto slag vinner."
        case .mostPars: "Hull på netto par, birdie eller eagle, hele kvelden."
        case .birdie: "Minst én netto birdie eller bedre, av hvem som helst."
        case .over: "Snittet for alle som spiller: netto slag over par per ni hull."
        case .birdieCount: "Netto birdie eller bedre, alle til sammen, hele kvelden."
        case .mostBirdies: "Netto birdie eller bedre, hele kvelden. Ingen birdier: strøket."
        case .backNine: "Banens hull 10–18. Færrest netto slag vinner."
        case .winnerPoints: "Stablefordpoengene til den som vinner kvelden."
        case .lastPlace: "Færrest stablefordpoeng over alle hullene i kveld."
        case .lowestGross: "Færrest slag uten handicap. Bare de som fører alle hullene."
        case .comeback: "Flest poeng mer på siste ni enn på første ni."
        case .mostBlanks: "Hull uten poeng, hele kvelden. Ingen blanke: strøket."
        case .bestParThrees: "Flest stablefordpoeng på banens par 3-hull."
        case .bestParFives: "Flest stablefordpoeng på banens par 5-hull."
        case .parStreak: "Netto par eller bedre på hull etter hull, hele kvelden. Ingen: strøket."
        case .eagle: "Minst én netto eagle eller bedre, av hvem som helst."
        case .grossBirdie: "Birdie eller bedre uten handicap, av hvem som helst."
        case .leaderWins: "Den med flest poeng etter banens hull 1–9 vinner kvelden."
        case .sharedWin: "To eller flere står likt på flest poeng."
        case .highHandicapWins: "Vinneren har høyere handicap enn midten av feltet."
        case .lastPlacePoints: "Stablefordpoengene til den som blir sist."
        case .winningMargin: "Poengene vinneren har mer enn nummer to. Delt seier: 0."
        case .blankHoles: "Hull uten poeng, alle til sammen, hele kvelden."
        case .parOrBetterPlayers: "Spillere med netto par i snitt eller bedre (36 poeng på 18 hull)."
        }
    }

    /// Enheten bak tallet i fasiten: «3 hull», «1 birdie».
    public func unit(_ n: Double) -> String {
        let one = n == 1
        switch self {
        case .winner, .winnerPoints, .lastPlace, .lastPlacePoints, .comeback, .winningMargin, .bestParThrees,
             .bestParFives:
            return "poeng"
        case .frontNine, .backNine: return "netto"
        case .lowestGross: return "brutto"
        case .mostPars, .mostBlanks, .parStreak, .blankHoles: return "hull"
        case .mostBirdies, .birdieCount: return one ? "birdie" : "birdier"
        case .parOrBetterPlayers: return one ? "spiller" : "spillere"
        case .birdie, .over, .eagle, .grossBirdie, .leaderWins, .sharedWin, .highHandicapWins: return ""
        }
    }
}

/// Ferdige utvalg av spørsmål arrangøren kan starte fra. Regelsettet husker ikke malen; den kjennes
/// igjen på spørsmålene (`matching`).
public enum TipsTemplate: String, CaseIterable, Hashable, Sendable {
    /// Golfgutus fem (PWA-en).
    case classic
    /// Birdiene i sentrum.
    case birdieHunt
    /// De ni spørsmålene fra før de morsomme kom (navnet er beholdt, så lagrede regelsett kjennes igjen).
    case full
    /// Sist, comeback, blanke hull, eagle og andre morsomme.
    case fun

    public var title: String {
        switch self {
        case .classic: "Klassisk"
        case .birdieHunt: "Birdiejakt"
        case .full: "Full kupong"
        case .fun: "Moro-kupong"
        }
    }

    public var questions: [TipsQuestion] {
        switch self {
        case .classic: [.winner, .frontNine, .mostPars, .birdie, .over]
        case .birdieHunt: [.winner, .birdie, .birdieCount, .mostBirdies, .over]
        case .full: [.winner, .frontNine, .backNine, .mostPars, .birdie, .birdieCount, .mostBirdies, .over, .winnerPoints]
        case .fun: [.winner, .lastPlace, .comeback, .mostBlanks, .eagle, .grossBirdie, .leaderWins, .winningMargin]
        }
    }

    /// Malen med akkurat disse spørsmålene i denne rekkefølgen, ellers `nil` (tilpasset).
    public static func matching(_ questions: [TipsQuestion]) -> TipsTemplate? {
        allCases.first { $0.questions == questions }
    }
}

/// Ett svar på kupongen.
public enum TipsAnswer: Hashable, Sendable {
    /// Spiller-id på et spillerspørsmål.
    case player(String)
    /// Ja/nei eller over/under.
    case flag(Bool)
}

/// Én spillers kupong. Et spørsmål uten svar er ikke besvart.
///
/// JSON: `playerID` og ett felt per besvart spørsmål (spørsmålets id), som før.
public struct TipsCoupon: Hashable, Sendable {
    public var playerID: String
    /// Svarene, nøkkel = spørsmålet. Et svar har alltid riktig type for spørsmålet.
    public private(set) var answers: [TipsQuestion: TipsAnswer] = [:]

    public init(playerID: String, winner: String? = nil, frontNine: String? = nil, mostPars: String? = nil,
                birdie: Bool? = nil, over: Bool? = nil, birdieCount: Bool? = nil, mostBirdies: String? = nil,
                backNine: String? = nil, winnerPoints: Bool? = nil) {
        self.playerID = playerID
        setPlayer(.winner, winner)
        setPlayer(.frontNine, frontNine)
        setPlayer(.mostPars, mostPars)
        setFlag(.birdie, birdie)
        setFlag(.over, over)
        setFlag(.birdieCount, birdieCount)
        setPlayer(.mostBirdies, mostBirdies)
        setPlayer(.backNine, backNine)
        setFlag(.winnerPoints, winnerPoints)
    }

    public var winner: String? {
        get { player(.winner) }
        set { setPlayer(.winner, newValue) }
    }
    public var frontNine: String? {
        get { player(.frontNine) }
        set { setPlayer(.frontNine, newValue) }
    }
    public var mostPars: String? {
        get { player(.mostPars) }
        set { setPlayer(.mostPars, newValue) }
    }
    public var birdie: Bool? {
        get { flag(.birdie) }
        set { setFlag(.birdie, newValue) }
    }
    public var over: Bool? {
        get { flag(.over) }
        set { setFlag(.over, newValue) }
    }
    public var birdieCount: Bool? {
        get { flag(.birdieCount) }
        set { setFlag(.birdieCount, newValue) }
    }
    public var mostBirdies: String? {
        get { player(.mostBirdies) }
        set { setPlayer(.mostBirdies, newValue) }
    }
    public var backNine: String? {
        get { player(.backNine) }
        set { setPlayer(.backNine, newValue) }
    }
    public var winnerPoints: Bool? {
        get { flag(.winnerPoints) }
        set { setFlag(.winnerPoints, newValue) }
    }

    /// Spilleren som er tippet på et spillerspørsmål.
    public func player(_ q: TipsQuestion) -> String? {
        if case .player(let id) = answers[q] { id } else { nil }
    }

    /// Ja/nei eller over/under.
    public func flag(_ q: TipsQuestion) -> Bool? {
        if case .flag(let b) = answers[q] { b } else { nil }
    }

    /// Setter spilleren på et spillerspørsmål (`nil` = ikke svart). Andre spørsmål røres ikke.
    public mutating func setPlayer(_ q: TipsQuestion, _ id: String?) {
        guard q.kind == .player else { return }
        answers[q] = id.map(TipsAnswer.player)
    }

    /// Setter ja/nei eller over/under (`nil` = ikke svart). Andre spørsmål røres ikke.
    public mutating func setFlag(_ q: TipsQuestion, _ value: Bool?) {
        guard q.kind != .player else { return }
        answers[q] = value.map(TipsAnswer.flag)
    }

    /// Er spørsmålet besvart?
    public func isAnswered(_ q: TipsQuestion) -> Bool {
        q.kind == .player ? !(player(q) ?? "").isEmpty : flag(q) != nil
    }

    /// `tipsKomplett`: alle spørsmålene på kupongen (regelsettets liste) er besvart.
    public func isComplete(for questions: [TipsQuestion]) -> Bool { questions.allSatisfy(isAnswered) }

    /// Antall besvarte spørsmål av dem på kupongen.
    public func answeredCount(for questions: [TipsQuestion]) -> Int { questions.filter(isAnswered).count }

    /// `isComplete(for:)` med Golfgutus fem spørsmål.
    public var isComplete: Bool { isComplete(for: Ruleset.golfgutu.tips.questions) }

    /// `answeredCount(for:)` med Golfgutus fem spørsmål.
    public var answeredCount: Int { answeredCount(for: Ruleset.golfgutu.tips.questions) }

    /// Samme svar (spilleren som eier kupongen teller ikke).
    public func hasSameAnswers(as other: TipsCoupon) -> Bool { answers == other.answers }
}

extension TipsCoupon: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static let playerID = Key(stringValue: "playerID")
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        playerID = try c.decode(String.self, forKey: .playerID)
        // Et spørsmål appen ikke kjenner, eller et svar av feil type, hoppes over.
        for q in TipsQuestion.allCases {
            let key = Key(stringValue: q.rawValue)
            if q.kind == .player {
                setPlayer(q, try? c.decodeIfPresent(String.self, forKey: key))
            } else {
                setFlag(q, try? c.decodeIfPresent(Bool.self, forKey: key))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(playerID, forKey: .playerID)
        for q in TipsQuestion.allCases {
            switch answers[q] {
            case .player(let id): try c.encode(id, forKey: Key(stringValue: q.rawValue))
            case .flag(let b): try c.encode(b, forKey: Key(stringValue: q.rawValue))
            case nil: break
            }
        }
    }
}

/// En runde på kvelden slik tippekupongen ser den.
public struct TipsRound: Hashable, Sendable {
    public var round: Round
    /// Spillerne i runden. En score fra en spiller som ikke står her, teller ikke (`playerById`).
    public var roster: [Player]
    /// Handicap i hele slag per spiller-id når det er fastsatt (f.eks. lagret spillehandicap).
    /// Mangler spilleren, regnes `effectiveHandicap` med regelsettet.
    public var handicaps: [String: Double]
    /// Kladd: ikke spilt, teller ikke i fasiten (`erKladd`). Men en kladd gjør at kvelden ikke er ferdig.
    public var isDraft: Bool

    public init(round: Round, roster: [Player], handicaps: [String: Double] = [:], isDraft: Bool = false) {
        self.round = round
        self.roster = roster
        self.handicaps = handicaps
        self.isDraft = isDraft
    }
}

/// Fasiten for kvelden (`tipsFasit`). `nil` på et svar betyr at spørsmålet er strøket.
public struct TipsAnswerKey: Hashable, Sendable {
    /// Alle rundene på kvelden er låst (`kveldErFerdig`). Først da gir fasiten en vinner.
    public var finished: Bool
    /// De som har ført minst ett tellende hull, sortert på id.
    public var field: [String]
    /// Flest stablefordpoeng. Likt øverst: alle er riktige, norsk navnesortering.
    public var winner: [String]?
    /// Lavest netto på banens hull 1–9.
    public var frontNine: [String]?
    /// Flest tellende hull på netto par eller bedre.
    public var mostPars: [String]?
    public var birdie: Bool?
    /// Snittet over linja. Rett på linja: `nil`.
    public var over: Bool?
    /// Stablefordpoengene til vinneren.
    public var winnerPoints: Int?
    /// Netto slag på første ni for den beste.
    public var frontNineNet: Int?
    /// Hull på par eller bedre for den beste.
    public var mostParsHoles: Int?
    /// Feltets snitt, netto over par per ni hull, to desimaler.
    public var average: Double?
    public var line: Double

    // De nye spørsmålene (ikke i PWA-en). `nil` på et svar betyr strøket, som over.

    /// Antall birdier over linja. Rett på linja: `nil`.
    public var birdieCount: Bool?
    /// Netto birdier eller bedre i feltet. En lagball (ett kort per lag) teller én gang, som i snittet.
    public var birdies: Int?
    public var birdieCountLine: Double?
    /// Flest netto birdier eller bedre. Ingen birdier: `nil` (strøket).
    public var mostBirdies: [String]?
    /// Birdiene til den beste.
    public var mostBirdiesCount: Int?
    /// Lavest netto på banens hull 10–18.
    public var backNine: [String]?
    /// Netto slag på siste ni for den beste.
    public var backNineNet: Int?
    /// Vinnerens poeng over linja. Rett på linja: `nil`.
    public var overWinnerPoints: Bool?
    public var winnerPointsLine: Double?

    /// Svarene på de morsomme spørsmålene. Mangler et spørsmål, er det strøket.
    public var outcomes: [TipsQuestion: TipsOutcome] = [:]

    /// Spillerne som er riktig svar på et spillerspørsmål.
    public func players(_ q: TipsQuestion) -> [String]? {
        switch q {
        case .winner: winner
        case .frontNine: frontNine
        case .mostPars: mostPars
        case .mostBirdies: mostBirdies
        case .backNine: backNine
        default: outcomes[q]?.players
        }
    }

    /// Ja/nei- og over/under-svaret.
    public func flag(_ q: TipsQuestion) -> Bool? {
        switch q {
        case .birdie: birdie
        case .over: over
        case .birdieCount: birdieCount
        case .winnerPoints: overWinnerPoints
        default: outcomes[q]?.flag
        }
    }

    /// Spørsmålet kan ikke avgjøres og gir ingen poeng til noen.
    public func isVoid(_ q: TipsQuestion) -> Bool {
        q.kind == .player ? players(q) == nil : flag(q) == nil
    }

    /// Tallet bak svaret: poeng, netto slag, hull eller birdier. `nil` for ja/nei og snittet.
    public func figure(_ q: TipsQuestion) -> Int? {
        switch q {
        case .winner, .winnerPoints: winnerPoints
        case .frontNine: frontNineNet
        case .mostPars: mostParsHoles
        case .mostBirdies: mostBirdiesCount
        case .backNine: backNineNet
        case .birdieCount: birdies
        case .birdie, .over: nil
        default: outcomes[q]?.figure.map { Int(JS.round($0)) }
        }
    }
}

/// Svaret på et morsomt spørsmål. Bare feltet som passer spørsmålets type, er satt.
public struct TipsOutcome: Hashable, Sendable {
    /// Spillerspørsmål: de som er riktig svar. `nil`: strøket.
    public var players: [String]?
    /// Ja/nei og over/under. `nil`: strøket.
    public var flag: Bool?
    /// Tallet bak svaret (poeng, slag, hull, spillere). `nil` når ingen har tall.
    public var figure: Double?
    /// Linja på over/under.
    public var line: Double?

    public init(players: [String]? = nil, flag: Bool? = nil, figure: Double? = nil, line: Double? = nil) {
        self.players = players
        self.flag = flag
        self.figure = figure
        self.line = line
    }
}

/// Resultatlista (`tipsResultat`).
public struct TipsResult: Hashable, Sendable {
    public struct Row: Hashable, Sendable {
        public var playerID: String
        public var coupon: TipsCoupon
        /// Per spørsmål på kupongen: riktig, feil eller `nil` (strøket).
        public var correct: [TipsQuestion: Bool?]
        /// Ett poeng per riktig svar.
        public var points: Int
    }

    public var finished: Bool
    public var answerKey: TipsAnswerKey
    /// Flest poeng først, så norsk navnesortering.
    public var rows: [Row]
    /// Spørsmål som ikke er strøket.
    public var possible: Int
    /// Høyeste poengsum.
    public var best: Int
    /// Tippekongen(e). Tom til kvelden er ferdig.
    public var winners: [String]
}

/// Potten i poeng (`tipsOppgjor` uten overføringene).
public struct TipsPot: Hashable, Sendable {
    /// Innsats per kupong. 0 = for æra.
    public var stake: Int
    /// Antall kuponger i resultatlista.
    public var entries: Int
    /// `stake · entries`.
    public var total: Int
    /// Vinnerne (de deler potten). Tom til kvelden er ferdig.
    public var winners: [String]
    /// For æra: ingen poeng står på spill.
    public var isForHonour: Bool { stake <= 0 }
}

// MARK: - Regelmotoren

public enum Tips {
    /// Tidssonen fristen regnes i. Samme som `tips_deadline()` i databasen.
    public static let timeZone = TimeZone(identifier: "Europe/Oslo")!

    /// Grensene i databasen (`events_tips_stake_points_check`, `events_tips_line_check`).
    public static let stakeLimits = 0...1000
    public static let lineLimits = -9.5...18.5
    /// Grensene for linjene på antall birdier og vinnerens poeng (regelsettet; ingen kolonne i databasen).
    public static let birdieCountLineLimits = 0.5...99.5
    public static let winnerPointsLineLimits = 0.5...149.5

    /// Grensene for linja på et over/under-spørsmål i regelsettet. `nil` for snittet (databasens
    /// grenser, `lineLimits`) og for spørsmål uten linje.
    public static func lineLimits(for q: TipsQuestion) -> ClosedRange<Double>? {
        switch q {
        case .birdieCount, .winningMargin, .parOrBetterPlayers: birdieCountLineLimits
        case .winnerPoints, .lastPlacePoints: winnerPointsLineLimits
        case .blankHoles: 0.5...499.5
        default: nil
        }
    }

    // MARK: Innsats og linje

    /// `tipsInnsats`: kveldens innsats, ellers regelsettets standard. Negativ verdi regnes som standard.
    public static func stake(_ eventValue: Int?, rules: Ruleset = .golfgutu) -> Int {
        if let n = eventValue, n >= 0 { return n }
        return rules.tips.defaultStakePoints
    }

    /// `tipsLinje`: kveldens linje, ellers regelsettets standard.
    public static func line(_ eventValue: Double?, rules: Ruleset = .golfgutu) -> Double {
        if let n = eventValue, n.isFinite { return n }
        return rules.tips.defaultLine
    }

    /// En lovlig linje i databasen: innenfor grensene og alltid et halvt slag.
    public static func isValidLine(_ x: Double) -> Bool {
        isHalf(x, in: lineLimits)
    }

    /// Et halvt tall innenfor grensene, så svaret aldri havner rett på linja.
    public static func isHalf(_ x: Double, in limits: ClosedRange<Double>) -> Bool {
        limits.contains(x) && x - x.rounded(.down) == 0.5
    }

    /// Linja et over/under-spørsmål har: kveldens linje for snittet, regelsettets for de nye.
    /// `nil` for spørsmål uten linje.
    public static func line(for q: TipsQuestion, eventLine: Double, rules: Ruleset = .golfgutu) -> Double? {
        q == .over ? eventLine : rules.tips.line(q)
    }

    // MARK: Fristen

    /// `tipsStarttid`: første `H:MM` eller `H.MM` i teksten (0–23, 0–59) som `HH:MM`,
    /// ellers regelsettets standard. Tåler både fritekst («17:00–20:00») og `time`-kolonnen («17:00:00»).
    public static func startTime(_ text: String?, rules: Ruleset = .golfgutu) -> String {
        let s = text ?? ""
        if let m = s.firstMatch(of: /([0-9]{1,2})[:.]([0-9]{2})/), let t = Int(m.1), let mi = Int(m.2),
           (0...23).contains(t), (0...59).contains(mi) {
            return (t < 10 ? "0" : "") + String(t) + ":" + m.2
        }
        return rules.tips.defaultStartTime
    }

    /// `osloTidspunkt`: dato (`YYYY-MM-DD`) og `HH:MM` i Oslo-tid som tidspunkt. Sommertid følger med.
    public static func osloTime(date: String, time: String) -> Date? {
        guard let d = date.firstMatch(of: /^([0-9]{4})-([0-9]{2})-([0-9]{2})/),
              let k = time.wholeMatch(of: /([0-9]{1,2}):([0-9]{2})/) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let parts = DateComponents(year: Int(d.1), month: Int(d.2), day: Int(d.3), hour: Int(k.1), minute: Int(k.2))
        return cal.date(from: parts)
    }

    /// `tipsFrist`: kveldens dato + starttid i Oslo-tid.
    public static func deadline(date: String?, startTime text: String?, rules: Ruleset = .golfgutu) -> Date? {
        guard let date, !date.isEmpty else { return nil }
        return osloTime(date: date, time: startTime(text, rules: rules))
    }

    /// `tipsHarScore`: noen har ført en score på en runde den kvelden. Kladder teller med.
    public static func hasScore(_ rounds: [TipsRound]) -> Bool {
        rounds.contains { r in r.round.holeScores.values.contains { !$0.isEmpty } }
    }

    /// `tipsAapen`: før fristen og før første score, det som kommer først.
    public static func isOpen(deadline: Date?, now: Date, hasScore: Bool) -> Bool {
        guard let deadline else { return false }
        return now < deadline && !hasScore
    }

    // MARK: Fasiten

    /// `tipsBeste`: de med høyest (eller lavest) tall, sortert på navn (norsk). Tom → `nil`.
    public static func best(_ values: [String: Int], lowest: Bool, names: [String: String] = [:]) -> [String]? {
        guard let top = lowest ? values.values.min() : values.values.max() else { return nil }
        return values.filter { $0.value == top }.map(\.key).sorted { a, b in
            let order = NorwegianSort.compare(names[a] ?? "", names[b] ?? "")
            return order != .orderedSame ? order == .orderedAscending : a < b
        }
    }

    /// `tipsFasit`: fasiten for kvelden fra hullscorene slik de står nå.
    ///
    /// - Parameter rounds: kveldens runder i opprettelsesrekkefølge. De sorteres på `holeStart`
    ///   (første ni før siste ni); kladder hoppes over.
    /// - Parameter line: kveldens linje (se `line(_:rules:)`).
    ///
    /// De nye spørsmålene regnes på samme hull: birdier er netto birdie eller bedre på tellende hull,
    /// siste ni er banens hull 10–18 (en 9-hullsrunde med start på hull 10, ellers hull 10–18 i
    /// første-ni-runden når den har 18 tellende hull), og linjene for antall birdier og vinnerens
    /// poeng står i regelsettet.
    public static func answerKey(rounds: [TipsRound], line: Double, rules: Ruleset = .golfgutu) -> TipsAnswerKey {
        let played = rounds.enumerated()
            .filter { !$0.element.isDraft || $0.element.round.locked }
            .sorted { a, b in
                let sa = a.element.round.holeStart ?? 0, sb = b.element.round.holeStart ?? 0
                return sa != sb ? sa < sb : a.offset < b.offset
            }
            .map(\.element)
        let firstNine = played.firstIndex { ($0.round.holeStart ?? 0) == 0 }
        let secondNine = played.firstIndex { ($0.round.holeStart ?? 0) == 9 && $0.round.numberOfHoles == 9 }

        var stableford: [String: Int] = [:], parHoles: [String: Int] = [:], frontNine: [String: Int] = [:]
        var birdies: [String: Int] = [:], backNine: [String: Int] = [:]
        var birdie = false
        // De morsomme spørsmålene.
        var frontPoints: [String: Int] = [:], backPoints: [String: Int] = [:], blanks: [String: Int] = [:]
        var parThrees: [String: Int] = [:], parFives: [String: Int] = [:], gross: [String: Int] = [:]
        var incomplete: Set<String> = [], countedHoles: [String: Int] = [:], firstHandicap: [String: Double] = [:]
        var streak: [String: Int] = [:], bestStreak: [String: Int] = [:]
        var eagle = false, grossBirdie = false, ballBlanks = 0
        var sumToPar = 0, ballHoles = 0, ballBirdies = 0
        var field: Set<String> = []
        var names: [String: String] = [:]

        for (index, tr) in played.enumerated() {
            let round = tr.round
            let course = round.courseHoles()
            let counting = Truncation.countingHoles(round)
            let holes = round.numberOfHoles
            let oneCardPerTeam = round.form.card == .perTeam
            var countedTeams: Set<Int> = []
            let nineHoles = index == firstNine ? min(9, counting) : 0
            // Hullene (i runden) som er banens 10–18.
            let backHoles: Range<Int>? = secondNine.map { index == $0 ? 0..<min(9, counting) : nil }
                ?? (index == firstNine && counting >= 18 ? 9..<18 : nil)

            for pid in round.holeScores.keys.sorted() {
                guard let player = tr.roster.first(where: { $0.id == pid }) else { continue }
                names[pid] = player.name
                let scores = round.holeScores[pid] ?? [:]
                let hcp = tr.handicaps[pid] ?? Handicap.effective(for: player, in: round, roster: tr.roster, rules: rules)
                let toPar: [Int?] = (0..<counting).map { i in
                    guard let gross = scores[i], i < course.count else { return nil }
                    let hole = course[i]
                    return Scoring.netStrokes(gross: gross, handicap: hcp, strokeIndex: hole.strokeIndex, holes: holes)
                        - hole.par
                }
                let done = toPar.compactMap { $0 }
                if done.isEmpty { continue }
                field.insert(pid)
                stableford[pid, default: 0] += Scoring.points(from: scores, in: round, handicap: hcp, rules: rules)
                parHoles[pid, default: 0] += done.filter { $0 <= 0 }.count
                let birdiesHere = done.filter { $0 <= -1 }.count
                birdies[pid, default: 0] += birdiesHere
                if birdiesHere > 0 { birdie = true }
                if done.contains(where: { $0 <= -2 }) { eagle = true }

                // Poeng per hull (nil = ikke ført), og det som regnes fra dem.
                let holePoints: [Int?] = (0..<counting).map { i in
                    guard let g = scores[i], i < course.count else { return nil }
                    let hole = course[i]
                    return Scoring.points(par: hole.par, gross: g, handicap: hcp, strokeIndex: hole.strokeIndex,
                                          holes: holes, rules: rules)
                }
                let blanksHere = holePoints.filter { $0 == rules.scoring.minimumPoints }.count
                blanks[pid, default: 0] += blanksHere
                countedHoles[pid, default: 0] += counting
                if firstHandicap[pid] == nil { firstHandicap[pid] = hcp }
                for i in 0..<min(counting, course.count) {
                    guard let p = holePoints[i] else { continue }
                    if course[i].par == 3 { parThrees[pid, default: 0] += p }
                    if course[i].par == 5 { parFives[pid, default: 0] += p }
                    if let g = scores[i], g <= course[i].par - 1 { grossBirdie = true }
                }
                if toPar.allSatisfy({ $0 != nil }) {
                    gross[pid, default: 0] += (0..<counting).reduce(0) { $0 + (scores[$1] ?? 0) }
                } else {
                    incomplete.insert(pid)
                }
                // Rekka går videre fra runde til runde (første ni før siste ni); et hull uten score bryter den.
                for d in toPar {
                    streak[pid] = d.map { $0 <= 0 } == true ? streak[pid, default: 0] + 1 : 0
                    bestStreak[pid] = max(bestStreak[pid] ?? 0, streak[pid] ?? 0)
                }

                let team = oneCardPerTeam ? round.teams[pid].flatMap { $0 == 0 ? nil : $0 } : nil
                if team == nil || !countedTeams.contains(team!) {
                    if let team { countedTeams.insert(team) }
                    sumToPar += done.reduce(0, +)
                    ballHoles += done.count
                    ballBirdies += birdiesHere
                    ballBlanks += blanksHere
                }
                if nineHoles > 0 {
                    let nine = toPar.prefix(nineHoles)
                    if nine.allSatisfy({ $0 != nil }) {
                        frontNine[pid] = zip(nine, course).reduce(0) { $0 + $1.0! + $1.1.par }
                        frontPoints[pid] = holePoints.prefix(nineHoles).reduce(0) { $0 + $1! }
                    }
                }
                if let backHoles, backHoles.upperBound <= course.count {
                    let nine = toPar[backHoles]
                    if nine.allSatisfy({ $0 != nil }) {
                        backNine[pid] = zip(nine, course[backHoles]).reduce(0) { $0 + $1.0! + $1.1.par }
                        backPoints[pid] = holePoints[backHoles].reduce(0) { $0 + $1! }
                    }
                }
            }
        }

        let average: Double? = ballHoles > 0 ? JS.round(Double(sumToPar) / Double(ballHoles) * 9 * 100) / 100 : nil
        let winner = best(stableford, lowest: false, names: names)
        let nine = best(frontNine, lowest: true, names: names)
        let pars = best(parHoles, lowest: false, names: names)
        let over: Bool? = average.flatMap { a in a > line ? true : (a < line ? false : nil) }
        let back = best(backNine, lowest: true, names: names)
        // Ingen birdier: alle står likt på 0, og spørsmålet strykes i stedet for at alle får rett.
        let topBirdies = best(birdies, lowest: false, names: names).flatMap { birdies[$0[0]] == 0 ? nil : $0 }
        let birdieTotal: Int? = field.isEmpty ? nil : ballBirdies
        let winnerPoints = winner.flatMap { stableford[$0[0]] }

        // De morsomme spørsmålene.
        var outcomes: [TipsQuestion: TipsOutcome] = [:]
        func pick(_ q: TipsQuestion, _ values: [String: Int], lowest: Bool, skipZero: Bool = false) {
            guard let top = best(values, lowest: lowest, names: names), let n = values[top[0]] else { return }
            if skipZero && n == 0 { return }
            outcomes[q] = TipsOutcome(players: top, figure: Double(n))
        }
        func overUnderLine(_ q: TipsQuestion, _ x: Int?) {
            guard let x, let l = rules.tips.line(q) else { return }
            outcomes[q] = TipsOutcome(flag: overUnder(Double(x), line: l), figure: Double(x), line: l)
        }
        pick(.lastPlace, stableford, lowest: true)
        pick(.lowestGross, gross.filter { !incomplete.contains($0.key) }, lowest: true)
        pick(.comeback, backPoints.reduce(into: [:]) { out, e in
            if let front = frontPoints[e.key] { out[e.key] = e.value - front }
        }, lowest: false)
        pick(.mostBlanks, blanks, lowest: false, skipZero: true)
        pick(.bestParThrees, parThrees, lowest: false)
        pick(.bestParFives, parFives, lowest: false)
        pick(.parStreak, bestStreak, lowest: false, skipZero: true)
        if !field.isEmpty {
            outcomes[.eagle] = TipsOutcome(flag: eagle)
            outcomes[.grossBirdie] = TipsOutcome(flag: grossBirdie)
        }
        if let winner {
            outcomes[.sharedWin] = TipsOutcome(flag: winner.count > 1)
            if let leaders = best(frontPoints, lowest: false, names: names) {
                outcomes[.leaderWins] = TipsOutcome(flag: !Set(leaders).isDisjoint(with: winner),
                                                    figure: frontPoints[leaders[0]].map(Double.init))
            }
            let hcps = field.compactMap { firstHandicap[$0] }.sorted()
            if hcps.count >= 2 {
                let mid = hcps.count / 2
                let median = hcps.count % 2 == 0 ? (hcps[mid - 1] + hcps[mid]) / 2 : hcps[mid]
                outcomes[.highHandicapWins] = TipsOutcome(flag: winner.contains { (firstHandicap[$0] ?? 0) > median },
                                                          figure: median)
            }
        }
        let ranked = stableford.values.sorted(by: >)
        overUnderLine(.lastPlacePoints, ranked.last)
        overUnderLine(.winningMargin, ranked.count >= 2 ? ranked[0] - ranked[1] : nil)
        overUnderLine(.blankHoles, field.isEmpty ? nil : ballBlanks)
        overUnderLine(.parOrBetterPlayers, field.isEmpty ? nil : field.filter { pid in
            (stableford[pid] ?? 0) >= rules.scoring.netParPoints * (countedHoles[pid] ?? 0)
        }.count)

        return TipsAnswerKey(
            finished: !rounds.isEmpty && rounds.allSatisfy(\.round.locked),
            field: field.sorted(),
            winner: winner,
            frontNine: nine,
            mostPars: pars,
            birdie: field.isEmpty ? nil : birdie,
            over: over,
            winnerPoints: winnerPoints,
            frontNineNet: nine.flatMap { frontNine[$0[0]] },
            mostParsHoles: pars.flatMap { parHoles[$0[0]] },
            average: average,
            line: line,
            birdieCount: birdieTotal.flatMap { overUnder(Double($0), line: rules.tips.birdieCountLine) },
            birdies: birdieTotal,
            birdieCountLine: rules.tips.birdieCountLine,
            mostBirdies: topBirdies,
            mostBirdiesCount: topBirdies.flatMap { birdies[$0[0]] },
            backNine: back,
            backNineNet: back.flatMap { backNine[$0[0]] },
            overWinnerPoints: winnerPoints.flatMap { overUnder(Double($0), line: rules.tips.winnerPointsLine) },
            winnerPointsLine: rules.tips.winnerPointsLine,
            outcomes: outcomes
        )
    }

    /// Over (true) eller under (false) linja. Rett på linja: `nil` (strøket).
    static func overUnder(_ x: Double, line: Double) -> Bool? {
        x > line ? true : (x < line ? false : nil)
    }

    /// `tipsRiktig`: var tipset riktig? `nil` = spørsmålet er strøket.
    public static func isCorrect(_ q: TipsQuestion, coupon: TipsCoupon?, key: TipsAnswerKey) -> Bool? {
        if key.isVoid(q) { return nil }
        if q.kind == .player {
            guard let v = coupon?.player(q), !v.isEmpty else { return false }
            return key.players(q)?.contains(v) ?? false
        }
        guard let v = coupon?.flag(q) else { return false }
        return v == key.flag(q)
    }

    // MARK: Resultatet

    /// `tipsResultat`: ett poeng per riktig svar. Kuponger fra spillere som ikke finnes i `players`,
    /// er ikke med. Tippekongen kåres først når kvelden er ferdig; står flere likt, deler de.
    /// Bare spørsmålene i regelsettet teller.
    public static func result(coupons: [TipsCoupon], key: TipsAnswerKey, players: [Player],
                              rules: Ruleset = .golfgutu) -> TipsResult {
        let questions = rules.tips.questions
        let names = Dictionary(players.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let rows = coupons
            .filter { names[$0.playerID] != nil }
            .map { coupon -> TipsResult.Row in
                var correct: [TipsQuestion: Bool?] = [:]
                var points = 0
                for q in questions {
                    let r = isCorrect(q, coupon: coupon, key: key)
                    correct[q] = .some(r)
                    if r == true { points += 1 }
                }
                return TipsResult.Row(playerID: coupon.playerID, coupon: coupon, correct: correct, points: points)
            }
            .sorted { a, b in
                if a.points != b.points { return a.points > b.points }
                let order = NorwegianSort.compare(names[a.playerID] ?? "", names[b.playerID] ?? "")
                return order != .orderedSame ? order == .orderedAscending : a.playerID < b.playerID
            }
        let possible = questions.filter { !key.isVoid($0) }.count
        let best = rows.first?.points ?? 0
        let winners = (key.finished && !rows.isEmpty) ? rows.filter { $0.points == best }.map(\.playerID) : []
        return TipsResult(finished: key.finished, answerKey: key, rows: rows, possible: possible, best: best,
                          winners: winners)
    }

    /// Potten: innsats · antall kuponger (`tipsOppgjor`: `pott`, `deltakere`, `vinnere`).
    public static func pot(_ result: TipsResult, stake: Int) -> TipsPot {
        TipsPot(stake: stake, entries: result.rows.count, total: stake * result.rows.count, winners: result.winners)
    }

    // MARK: Tekst

    /// `fmtTipsTall`: «+2,5», «−1,5», «±0,0». Snittet vises med to desimaler.
    public static func formatSigned(_ x: Double, decimals: Int) -> String {
        let s = String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), abs(x))
            .replacingOccurrences(of: ".", with: ",")
        return (x > 0 ? "+" : (x < 0 ? "−" : "±")) + s
    }

    /// `tipsSporsmaalTittel`: over/under har linja i tittelen («Over eller under +2,5?»).
    /// `line` er spørsmålets linje (`line(for:eventLine:rules:)`).
    public static func title(_ q: TipsQuestion, line: Double) -> String {
        switch q {
        case .over: "Over eller under " + formatSigned(line, decimals: 1) + "?"
        case .birdieCount: "Over eller under " + formatPlain(line) + " birdier?"
        case .winnerPoints: "Vinneren: over eller under " + formatPlain(line) + " poeng?"
        case .lastPlacePoints: "Sistemann: over eller under " + formatPlain(line) + " poeng?"
        case .winningMargin: "Seiersmarginen: over eller under " + formatPlain(line) + " poeng?"
        case .blankHoles: "Over eller under " + formatPlain(line) + " blanke hull?"
        case .parOrBetterPlayers: "Over eller under " + formatPlain(line) + " spillere på par?"
        default: q.title
        }
    }

    /// «14,5»: én desimal, norsk komma, uten fortegn.
    public static func formatPlain(_ x: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), x).replacingOccurrences(of: ".", with: ",")
    }
}
