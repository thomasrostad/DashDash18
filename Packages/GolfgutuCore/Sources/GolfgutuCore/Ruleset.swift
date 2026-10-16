import Foundation

/// Regelsettet som styrer turneringen (B12). Alle regelverdier regelmotoren bruker, ligger her;
/// faste tall finnes bare i `Ruleset.golfgutu`, som gjengir PWA-en. Se REGELSETT.md.
///
/// JSON: versjon 2 er gruppert (`scoring`, `table`, `sidePrizes`, `handicap`, `formats`).
/// Versjon 1 (flat, uten `version` eller med `version: 1`) leses fortsatt. Felt som mangler,
/// får Golfgutu-verdien.
public struct Ruleset: Hashable, Sendable {
    /// Versjonen som skrives.
    public static let currentVersion = 2

    /// Antall kvelder i sesongen.
    public var evenings: Int
    public var scoring: ScoringRules
    public var table: TableRules
    public var sidePrizes: SidePrizeRules
    public var handicap: HandicapRules
    public var formats: FormatRules
    /// Tippekupongen: frist, innsats og linje når kvelden ikke har egne (se Tips.swift).
    public var tips: TipsRules
    /// Veddemål med poeng: låsing, tak, beløp og poengbank (se Bets.swift).
    public var bets: BetRules
    /// Hullene (antall hull fra start) der ledelsen underveis meldes, stigende, 1…18
    /// (PWA: `LEDELSE_SJEKKPUNKT`). Tom liste: ledelsen meldes ikke.
    public var leadCheckpoints: [Int]
    /// Liga, cup og morroturnering (fase 15, Competitions.swift). `nil`: malene gjelder. Golfgutu-
    /// oppsettet har ingen, så jakkeracet og JSON-en for sesongen er som før.
    public var competition: CompetitionRules?
    /// Hva en dag i turneringen heter (`DayTerm`). `nil`: «kveld», som Golfgutu-oppsettet og alle
    /// regelsett fra før 09.10.2026. Bare ord, ikke en regel.
    public var dayTerm: DayTerm?
    /// Regelverdiene for formene fra steg 7: poengspillene (Amerikaner, Københavner), skins som form og
    /// lag mot lag (FormPlay.swift). Standard: `FormPlayRules.standard`, og da skrives gruppen ikke.
    public var formPlay: FormPlayRules
    /// Føring og visning i runden: maks slag per hull, låst kort etter levering og antall skjulte hull
    /// (PlayRules.swift). Standard: `PlayRules.standard`, og da skrives gruppen ikke.
    public var play: PlayRules = .standard

    /// Ordet som gjelder: `dayTerm`, ellers «kveld».
    public var day: DayTerm { dayTerm ?? .evening }

    public init(evenings: Int, scoring: ScoringRules, table: TableRules, sidePrizes: SidePrizeRules,
                handicap: HandicapRules, formats: FormatRules, tips: TipsRules = .golfgutu,
                bets: BetRules = .golfgutu, leadCheckpoints: [Int] = Ruleset.golfgutuLeadCheckpoints,
                competition: CompetitionRules? = nil, dayTerm: DayTerm? = nil, formPlay: FormPlayRules = .standard) {
        self.evenings = evenings
        self.scoring = scoring
        self.table = table
        self.sidePrizes = sidePrizes
        self.handicap = handicap
        self.formats = formats
        self.tips = tips
        self.bets = bets
        self.leadCheckpoints = leadCheckpoints
        self.competition = competition
        self.dayTerm = dayTerm
        self.formPlay = formPlay
    }

    // MARK: Gruppene

    /// Stablefordpoeng per hull: `max(minimumPoints, par − netto + netParPoints)`.
    public struct ScoringRules: Codable, Hashable, Sendable {
        /// Poeng for netto par. Også det et uspilt hull gir med avkortingen `nettopar`.
        public var netParPoints: Int
        /// Laveste poeng på et hull.
        public var minimumPoints: Int

        public init(netParPoints: Int, minimumPoints: Int) {
            self.netParPoints = netParPoints
            self.minimumPoints = minimumPoints
        }
    }

    /// Poeng for utfallet av en duell.
    public struct MatchPoints: Codable, Hashable, Sendable {
        public var win: Double
        public var draw: Double
        public var loss: Double

        public init(win: Double, draw: Double, loss: Double) {
            self.win = win
            self.draw = draw
            self.loss = loss
        }
    }

    /// Hva som teller: de beste N av en enhet, eller alle.
    public struct Counting: Codable, Hashable, Sendable {
        public enum Unit: String, Codable, Hashable, Sendable, CaseIterable {
            /// Kvelden: summen av rundene med samme dato.
            case evening
            /// Hver match for seg (`TELLENDE_MATCHER`). Bare for tabellen.
            case match
            /// Hver runde for seg (`TELLENDE_RUNDER`).
            case round
        }

        public var unit: Unit
        /// `nil`: alle teller.
        public var best: Int?

        public init(unit: Unit, best: Int? = nil) {
            self.unit = unit
            self.best = best
        }

        private enum CodingKeys: String, CodingKey { case unit, best }

        /// `best: null` skrives ut, så det står i JSON-en at alle teller.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(unit, forKey: .unit)
            try c.encode(best, forKey: .best)
        }
    }

    /// Et skille ved poenglikhet i tabellen.
    public enum Tiebreak: String, Codable, Hashable, Sendable, CaseIterable {
        /// Samlet hulldifferanse i de tellende matchene (høyest først).
        case holeDifference
        /// Stablefordsummen (`seasonTotalNytt`, høyest først).
        case stableford
    }

    /// Hvordan de tellende poengene blir til totalen i tabellen.
    public enum Aggregation: String, Codable, Hashable, Sendable, CaseIterable {
        /// Summen (Golfgutu).
        case sum
        /// Snittet per spilte kveld som teller (summen delt på antall kvelder).
        case average
    }

    /// Hva som skjer når spillere står likt i tabellen.
    public enum TieRule: String, Codable, Hashable, Sendable, CaseIterable {
        /// Skillene i `tiebreaks`, så navn. Like på alle skillene gir delt plass (Golfgutu).
        case tiebreaks
        /// Delt førsteplass avgjøres med playoff (`Playoff`). Til den er spilt, viser tabellen delt
        /// plass. Andre likheter er delt plass; `tiebreaks` brukes ikke.
        case playoff
    }

    /// En navngitt poengtabell (f.eks. «finale» som teller dobbelt). Kvelden peker på den med
    /// `Round.pointsTable`; poengene ganges med `multiplier` i tillegg til rundevekten.
    public struct PointsTable: Codable, Hashable, Sendable {
        public var multiplier: Double

        public init(multiplier: Double) {
            self.multiplier = multiplier
        }
    }

    /// Trekningen av matcher.
    public enum DrawMethod: String, Codable, Hashable, Sendable, CaseIterable {
        /// Etter tabellen (sveitsisk, `Triangle.drawMatches`). Golfgutu.
        case standings
        /// Tilfeldig, med færrest mulig møter som har vært før i sesongen (`Draw.avoidingRepeats`).
        case avoidRepeats
        /// Arrangøren setter opp matchene selv. Motoren sjekker bare oppsettet (`Draw.validate`).
        case manual
    }

    /// Hva tabellpoengene kommer fra.
    public enum TablePointsSource: String, Codable, Hashable, Sendable, CaseIterable {
        /// Matcher og trekanter (`matchPoints`, `trianglePoints`), pluss sidepremiene. Golfgutu.
        case matches
        /// Stablefordpoengene i runden (vektet), pluss sidepremiene. Matcher og trekanter gir ingen
        /// tabellpoeng.
        case stableford
    }

    /// Tabellen (jakketavla).
    public struct TableRules: Hashable, Sendable {
        /// Hva tabellpoengene kommer fra. Golfgutu: `matches`.
        public var pointsSource: TablePointsSource
        public var matchPoints: MatchPoints
        /// Poeng i en trekant etter plass (beste først). Delt plass deler summen av plassene.
        public var trianglePoints: [Double]
        /// Det som teller i tabellen: `match`, `round` eller `evening`. Sidepremiene strykes aldri med `match`;
        /// med `round` og `evening` er de en del av rundens eller kveldens poeng. Med `pointsSource`
        /// `stableford` gir `match` ingen mening (valideringen sier fra) og regnes som `round`.
        public var counting: Counting
        /// Det som teller i stablefordsummen (skilletegn og profil): `round` eller `evening` (`match` regnes
        /// som `round`). Vekten legges på før utvelgelsen.
        public var stablefordCounting: Counting
        /// Skillene ved likt totalpoeng, i rekkefølge. Norsk navnesortering er alltid det siste.
        public var tiebreaks: [Tiebreak]
        /// Poengene rundes til nærmeste multiplum av dette (0,5 = halve poeng). `nil`: ingen avrunding.
        public var roundingStep: Double?
        /// Minste antall spilte kvelder (som teller) for å få plass i tabellen. De som har færre, står
        /// under de rangerte, uten plass. `nil` eller 0: alle rangeres (Golfgutu).
        public var minEvenings: Int?
        /// Sum (Golfgutu) eller snitt per spilte kveld som teller.
        public var aggregation: Aggregation
        /// Navngitte poengtabeller (navn → tabell). Tom: ingen (Golfgutu).
        public var pointsTables: [String: PointsTable]
        /// Likhet: skillene (Golfgutu) eller playoff om førsteplassen.
        public var tieRule: TieRule
        /// Med `pointsSource` `stableford`: rundens poeng i tabellen er formens egne (skins vunnet,
        /// Amerikaner- og Københavnerpoeng; stableford for de andre formene, `FormPlay.tablePoints`).
        /// Av (Golfgutu): stablefordpoengene for alle former.
        public var formPoints: Bool

        public init(matchPoints: MatchPoints, trianglePoints: [Double], counting: Counting,
                    stablefordCounting: Counting, tiebreaks: [Tiebreak], roundingStep: Double?,
                    pointsSource: TablePointsSource = .matches, minEvenings: Int? = nil,
                    aggregation: Aggregation = .sum, pointsTables: [String: PointsTable] = [:],
                    tieRule: TieRule = .tiebreaks, formPoints: Bool = false) {
            self.pointsSource = pointsSource
            self.matchPoints = matchPoints
            self.trianglePoints = trianglePoints
            self.counting = counting
            self.stablefordCounting = stablefordCounting
            self.tiebreaks = tiebreaks
            self.roundingStep = roundingStep
            self.minEvenings = minEvenings
            self.aggregation = aggregation
            self.pointsTables = pointsTables
            self.tieRule = tieRule
            self.formPoints = formPoints
        }
    }

    /// Én sidepremie.
    public struct SidePrize: Codable, Hashable, Sendable {
        public var enabled: Bool
        public var points: Double

        public init(enabled: Bool, points: Double) {
            self.enabled = enabled
            self.points = points
        }
    }

    /// Longest drive og nærmest pinnen.
    public struct SidePrizeRules: Hashable, Sendable {
        public var longestDrive: SidePrize
        public var closestToPin: SidePrize
        /// Lik lengde deler poenget (1/n hver). Av: alle på delt førsteplass får fullt.
        public var splitTies: Bool

        public init(longestDrive: SidePrize, closestToPin: SidePrize, splitTies: Bool) {
            self.longestDrive = longestDrive
            self.closestToPin = closestToPin
            self.splitTies = splitTies
        }

        public subscript(kind: SideClaim.Kind) -> SidePrize {
            get { kind == .drive ? longestDrive : closestToPin }
            set { if kind == .drive { longestDrive = newValue } else { closestToPin = newValue } }
        }
    }

    /// Hvordan et lag får ett handicap av grunnlagene (sortert, lavest først).
    public struct TeamHandicapRule: Codable, Hashable, Sendable {
        public enum Method: String, Codable, Hashable, Sendable, CaseIterable {
            /// Snittet av grunnlagene.
            case average
            /// Vektet sum: `weights[i] · grunnlag[i]`, lavest først. Spillere utover vektene teller ikke.
            case weighted
            /// Laveste grunnlag · rundens andel.
            case lowest
        }

        public var method: Method
        public var weights: [Double]?

        public init(method: Method, weights: [Double]? = nil) {
            self.method = method
            self.weights = weights
        }

        public static let average = TeamHandicapRule(method: .average)
        public static let lowest = TeamHandicapRule(method: .lowest)

        /// WHS-anbefalingen for formene der laget spiller én ball (World Handicap System, «Rules of
        /// Handicapping», Appendix C «Handicap Allowances», i bruk fra 2020 og uendret i 2024-utgaven; NGF
        /// følger WHS). Vektene er lavest først:
        /// - foursome: 50 % av summen av lagets banehandicap;
        /// - greensome og chapman/pinehurst: 60 % av laveste + 40 % av høyeste;
        /// - scramble 2: 35 % av laveste + 15 % av høyeste;
        /// - scramble 4: 25 / 20 / 15 / 10 %, lavest først.
        /// Golfgutu-oppsettet bruker PWA-ens regler (`Ruleset.golfgutu`): snitt for toerformene og
        /// 25/20/15/10 for scramble 4. Arrangøren tar WHS-tallene i bruk med `HandicapRules.useWHSTeamHandicap()`.
        public static let whsRecommended: [String: TeamHandicapRule] = [
            "foursome": TeamHandicapRule(method: .weighted, weights: [0.5, 0.5]),
            "greensome": TeamHandicapRule(method: .weighted, weights: [0.6, 0.4]),
            "chapman": TeamHandicapRule(method: .weighted, weights: [0.6, 0.4]),
            "scramble-2": TeamHandicapRule(method: .weighted, weights: [0.35, 0.15]),
            "scramble-4": TeamHandicapRule(method: .weighted, weights: [0.25, 0.20, 0.15, 0.10]),
        ]
    }

    /// Handicapmodellen.
    public struct HandicapRules: Hashable, Sendable {
        /// Fast andel for alle former. `nil`: andelen per form.
        public var allowanceOverride: Double?
        /// Andelen en ny runde i formen får (`hcp_allowance`), per form-id. Mangler formen: 1.
        public var formAllowances: [String: Double]
        /// Seedede grupper med faste tall. Tom liste: ingen seeding.
        public var seedingGroups: [SeedingGroup]
        /// Simulatoren deler ut slagene på nye runder (`hcp_extern`).
        public var externalHandicap: Bool
        /// Lagshandicap per form-id. Mangler formen: `lowest`.
        public var teamHandicap: [String: TeamHandicapRule]

        public init(allowanceOverride: Double?, formAllowances: [String: Double], seedingGroups: [SeedingGroup],
                    externalHandicap: Bool, teamHandicap: [String: TeamHandicapRule]) {
            self.allowanceOverride = allowanceOverride
            self.formAllowances = formAllowances
            self.seedingGroups = seedingGroups
            self.externalHandicap = externalHandicap
            self.teamHandicap = teamHandicap
        }

        /// Lagshandicap-regelen for formen.
        public func teamHandicapRule(for formID: String) -> TeamHandicapRule {
            teamHandicap[formID] ?? .lowest
        }

        /// Lagshandicapet for formene med én ball etter WHS-anbefalingen (`TeamHandicapRule.whsRecommended`).
        /// De andre formene er som før.
        public mutating func useWHSTeamHandicap() {
            teamHandicap.merge(TeamHandicapRule.whsRecommended) { _, whs in whs }
        }

        /// Lagshandicapet for formene med én ball er WHS-anbefalingen.
        public var usesWHSTeamHandicap: Bool {
            TeamHandicapRule.whsRecommended.allSatisfy { teamHandicap[$0.key] == $0.value }
        }
    }

    /// Slagene i en match.
    public enum MatchStrokes: String, Codable, Hashable, Sendable, CaseIterable {
        /// Den laveste i matchen spiller fra scratch; de andre får forskjellen (`matchSlag`).
        case lowestFromScratch
        /// Alle spiller på sitt fulle handicap.
        case fullHandicap
    }

    /// Former og oppsett av kvelden.
    public struct FormatRules: Hashable, Sendable {
        /// Formen en ny runde starter med.
        public var defaultFormID: String
        /// Formene arrangøren kan velge.
        public var allowedFormIDs: [String]
        /// Største lag som får plass i en bås.
        public var maxPerBay: Int
        public var matchStrokes: MatchStrokes
        /// Trekningen av matcher. Golfgutu: etter tabellen.
        public var drawMethod: DrawMethod

        public init(defaultFormID: String, allowedFormIDs: [String], maxPerBay: Int, matchStrokes: MatchStrokes,
                    drawMethod: DrawMethod = .standings) {
            self.defaultFormID = defaultFormID
            self.allowedFormIDs = allowedFormIDs
            self.maxPerBay = maxPerBay
            self.matchStrokes = matchStrokes
            self.drawMethod = drawMethod
        }
    }

    // MARK: Golfgutu

    /// Golfgutu: ledelsen meldes etter hull 3, 6, 9, 12, 15 og 18 (`LEDELSE_SJEKKPUNKT`).
    public static let golfgutuLeadCheckpoints = [3, 6, 9, 12, 15, 18]

    /// Golfgutu-oppsettet: verdiene fra db-nytt.js og app-nytt.js. 7 kvelder, alle matcher teller
    /// (`TELLENDE_MATCHER = 0`), stablefordsummen teller beste 5 runder (`TELLENDE_RUNDER`),
    /// duellpoeng 1/0,5/0, trekant 1/0,5/0, LD og KP 1 poeng delt ved likt, halve poeng,
    /// netto par 2 og bunn 0, seeding 0/5/10, andel per form som `handleStartRunde`,
    /// lagshandicap snitt for toere og 25/20/15/10 i scramble-4, laveste fra scratch i match,
    /// 4 per bås, stableford som standard og appen som deler ut slagene.
    public static let golfgutu = Ruleset(
        evenings: 7,
        scoring: ScoringRules(netParPoints: 2, minimumPoints: 0),
        table: TableRules(
            matchPoints: MatchPoints(win: 1, draw: 0.5, loss: 0),
            trianglePoints: [1, 0.5, 0],
            counting: Counting(unit: .match, best: nil),
            stablefordCounting: Counting(unit: .round, best: 5),
            tiebreaks: [.holeDifference, .stableford],
            roundingStep: 0.5
        ),
        sidePrizes: SidePrizeRules(longestDrive: SidePrize(enabled: true, points: 1),
                                   closestToPin: SidePrize(enabled: true, points: 1),
                                   splitTies: true),
        handicap: HandicapRules(
            allowanceOverride: nil,
            // app-nytt.js: `(form.hcpAndel !== null && form.kort === 'per spiller') ? form.hcpAndel : 1`.
            formAllowances: Dictionary(uniqueKeysWithValues: CompetitionForm.all.map { f in
                (f.id, (f.card == .perPlayer ? f.allowance : nil) ?? 1)
            }),
            seedingGroups: SeedingGroup.golfgutu,
            externalHandicap: false,
            // `lagHandicap`: toerformer snitt, scramble-4 vektet, ellers laveste · andel.
            teamHandicap: Dictionary(uniqueKeysWithValues: CompetitionForm.all.compactMap { f in
                if f.teamSize == 2 { return (f.id, TeamHandicapRule.average) }
                if f.id == "scramble-4" { return (f.id, TeamHandicapRule(method: .weighted, weights: [0.25, 0.20, 0.15, 0.10])) }
                return nil
            })
        ),
        formats: FormatRules(defaultFormID: "stableford", allowedFormIDs: CompetitionForm.all.map(\.id),
                             maxPerBay: 4, matchStrokes: .lowestFromScratch)
    )

    // MARK: Bruk

    /// Tildelingen en ny runde i denne formen får (`hcp_allowance`).
    public func allowance(for form: CompetitionForm) -> Double {
        handicap.allowanceOverride ?? handicap.formAllowances[form.id] ?? 1
    }

    /// `effectiveHandicap` med regelsettet.
    public func effectiveHandicap(for player: Player?, in round: Round, roster: [Player]) -> Double {
        Handicap.effective(for: player, in: round, roster: roster, rules: self)
    }

    /// `roundNetTotalForPlayer` med regelsettet.
    public func roundNetTotal(_ round: Round, player: Player?, roster: [Player]) -> Int {
        Scoring.roundNetTotal(round, player: player, roster: roster, rules: self)
    }

    /// `oppsettForAntall` med regelsettets bås-størrelse.
    public func setup(formID: String?, players: Int) -> FormSetup {
        CompetitionForm.setup(formID: formID, players: players, maxPerBay: formats.maxPerBay)
    }

    /// `formerSomPasser` blant de tillatte formene, med regelsettets bås-størrelse.
    public func suggestions(players: Int) -> [FormSuggestion] {
        CompetitionForm.suggestions(players: players, forms: allowedForms, maxPerBay: formats.maxPerBay)
    }

    /// De tillatte formene, i katalogens rekkefølge.
    public var allowedForms: [CompetitionForm] {
        CompetitionForm.catalog.filter { formats.allowedFormIDs.contains($0.id) }
    }

    /// Avrunding av tabellpoeng etter regelsettet (JS `Math.round`).
    public func roundTablePoints(_ x: Double) -> Double {
        Ruleset.round(x, step: table.roundingStep)
    }

    static func round(_ x: Double, step: Double?) -> Double {
        guard let step, step > 0 else { return x }
        return JS.round(x / step) * step
    }
}

// MARK: - JSON

extension Ruleset: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, evenings, scoring, table, sidePrizes, handicap, formats, tips, bets, leadCheckpoints, competition
        case dayTerm, formPlay, play
    }

    /// Versjon 1: flat.
    private enum V1Keys: String, CodingKey {
        case allowanceOverride, seedingGroups, externalHandicap, defaultFormID, maxPerBay, evenings,
             countingEvenings, stablefordCountingEvenings, matchPoints, sidePrizes, trianglePoints, tiebreaks
    }

    private struct V1SidePrizes: Decodable {
        var enabled: Bool
        var points: Double
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        let g = Ruleset.golfgutu
        if version >= 2 {
            evenings = try c.decodeIfPresent(Int.self, forKey: .evenings) ?? g.evenings
            scoring = try c.decodeIfPresent(ScoringRules.self, forKey: .scoring) ?? g.scoring
            table = try c.decodeIfPresent(TableRules.self, forKey: .table) ?? g.table
            sidePrizes = try c.decodeIfPresent(SidePrizeRules.self, forKey: .sidePrizes) ?? g.sidePrizes
            handicap = try c.decodeIfPresent(HandicapRules.self, forKey: .handicap) ?? g.handicap
            formats = try c.decodeIfPresent(FormatRules.self, forKey: .formats) ?? g.formats
            tips = try c.decodeIfPresent(TipsRules.self, forKey: .tips) ?? g.tips
            bets = try c.decodeIfPresent(BetRules.self, forKey: .bets) ?? g.bets
            leadCheckpoints = try c.decodeIfPresent([Int].self, forKey: .leadCheckpoints) ?? g.leadCheckpoints
            competition = try c.decodeIfPresent(CompetitionRules.self, forKey: .competition)
            dayTerm = try c.decodeIfPresent(DayTerm.self, forKey: .dayTerm)
            formPlay = try c.decodeIfPresent(FormPlayRules.self, forKey: .formPlay) ?? g.formPlay
            play = try c.decodeIfPresent(PlayRules.self, forKey: .play) ?? g.play
            return
        }
        // Versjon 1. `countingEvenings` gjaldt matcher (`TELLENDE_MATCHER`), `stablefordCountingEvenings` runder.
        let v1 = try decoder.container(keyedBy: V1Keys.self)
        self = g
        evenings = try v1.decodeIfPresent(Int.self, forKey: .evenings) ?? g.evenings
        handicap.allowanceOverride = try v1.decodeIfPresent(Double.self, forKey: .allowanceOverride)
        handicap.seedingGroups = try v1.decodeIfPresent([SeedingGroup].self, forKey: .seedingGroups) ?? g.handicap.seedingGroups
        handicap.externalHandicap = try v1.decodeIfPresent(Bool.self, forKey: .externalHandicap) ?? g.handicap.externalHandicap
        formats.defaultFormID = try v1.decodeIfPresent(String.self, forKey: .defaultFormID) ?? g.formats.defaultFormID
        formats.maxPerBay = try v1.decodeIfPresent(Int.self, forKey: .maxPerBay) ?? g.formats.maxPerBay
        table.counting = Counting(unit: .match, best: try v1.decodeIfPresent(Int.self, forKey: .countingEvenings))
        if v1.contains(.stablefordCountingEvenings) {
            table.stablefordCounting = Counting(unit: .round,
                                                best: try v1.decodeIfPresent(Int.self, forKey: .stablefordCountingEvenings))
        }
        table.matchPoints = try v1.decodeIfPresent(MatchPoints.self, forKey: .matchPoints) ?? g.table.matchPoints
        table.trianglePoints = try v1.decodeIfPresent([Double].self, forKey: .trianglePoints) ?? g.table.trianglePoints
        table.tiebreaks = try v1.decodeIfPresent([Tiebreak].self, forKey: .tiebreaks) ?? g.table.tiebreaks
        if let s = try v1.decodeIfPresent(V1SidePrizes.self, forKey: .sidePrizes) {
            let prize = SidePrize(enabled: s.enabled, points: s.points)
            sidePrizes.longestDrive = prize
            sidePrizes.closestToPin = prize
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Ruleset.currentVersion, forKey: .version)
        try c.encode(evenings, forKey: .evenings)
        try c.encode(scoring, forKey: .scoring)
        try c.encode(table, forKey: .table)
        try c.encode(sidePrizes, forKey: .sidePrizes)
        try c.encode(handicap, forKey: .handicap)
        try c.encode(formats, forKey: .formats)
        try c.encode(tips, forKey: .tips)
        try c.encode(bets, forKey: .bets)
        try c.encode(leadCheckpoints, forKey: .leadCheckpoints)
        // Bare når konkurransen har egne regler, så sesongens JSON er som før.
        try c.encodeIfPresent(competition, forKey: .competition)
        // Bare når ordet er valgt, så JSON-en for regelsett fra før er som før.
        try c.encodeIfPresent(dayTerm, forKey: .dayTerm)
        // Bare når formreglene ikke er standard, så JSON-en for regelsett fra før er som før.
        if formPlay != .standard { try c.encode(formPlay, forKey: .formPlay) }
        // Bare når føringsreglene ikke er standard, av samme grunn.
        if play != .standard { try c.encode(play, forKey: .play) }
    }
}

extension Ruleset.TableRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case pointsSource, matchPoints, trianglePoints, counting, stablefordCounting, tiebreaks, roundingStep
        case minEvenings, aggregation, pointsTables, tieRule, formPoints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.golfgutu.table
        pointsSource = try c.decodeIfPresent(Ruleset.TablePointsSource.self, forKey: .pointsSource) ?? g.pointsSource
        matchPoints = try c.decodeIfPresent(Ruleset.MatchPoints.self, forKey: .matchPoints) ?? g.matchPoints
        trianglePoints = try c.decodeIfPresent([Double].self, forKey: .trianglePoints) ?? g.trianglePoints
        counting = try c.decodeIfPresent(Ruleset.Counting.self, forKey: .counting) ?? g.counting
        stablefordCounting = try c.decodeIfPresent(Ruleset.Counting.self, forKey: .stablefordCounting) ?? g.stablefordCounting
        tiebreaks = try c.decodeIfPresent([Ruleset.Tiebreak].self, forKey: .tiebreaks) ?? g.tiebreaks
        // `null` er et valg (ingen avrunding); mangler feltet, gjelder Golfgutu.
        roundingStep = c.contains(.roundingStep) ? try c.decodeIfPresent(Double.self, forKey: .roundingStep) : g.roundingStep
        minEvenings = try c.decodeIfPresent(Int.self, forKey: .minEvenings) ?? g.minEvenings
        aggregation = try c.decodeIfPresent(Ruleset.Aggregation.self, forKey: .aggregation) ?? g.aggregation
        pointsTables = try c.decodeIfPresent([String: Ruleset.PointsTable].self, forKey: .pointsTables) ?? g.pointsTables
        tieRule = try c.decodeIfPresent(Ruleset.TieRule.self, forKey: .tieRule) ?? g.tieRule
        formPoints = try c.decodeIfPresent(Bool.self, forKey: .formPoints) ?? g.formPoints
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(matchPoints, forKey: .matchPoints)
        try c.encode(trianglePoints, forKey: .trianglePoints)
        try c.encode(counting, forKey: .counting)
        try c.encode(stablefordCounting, forKey: .stablefordCounting)
        try c.encode(tiebreaks, forKey: .tiebreaks)
        try c.encode(roundingStep, forKey: .roundingStep)
        // Bare når tabellen ikke teller matcher, så Golfgutu-JSON-en og eldre regelsett er som før.
        if pointsSource != .matches { try c.encode(pointsSource, forKey: .pointsSource) }
        // Tabellreglene fra steg 6 skrives bare når de ikke er standard, av samme grunn.
        try c.encodeIfPresent(minEvenings, forKey: .minEvenings)
        if aggregation != .sum { try c.encode(aggregation, forKey: .aggregation) }
        if !pointsTables.isEmpty { try c.encode(pointsTables, forKey: .pointsTables) }
        if tieRule != .tiebreaks { try c.encode(tieRule, forKey: .tieRule) }
        if formPoints { try c.encode(formPoints, forKey: .formPoints) }
    }
}

extension Ruleset.SidePrizeRules: Codable {
    private enum CodingKeys: String, CodingKey { case longestDrive, closestToPin, splitTies }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.golfgutu.sidePrizes
        longestDrive = try c.decodeIfPresent(Ruleset.SidePrize.self, forKey: .longestDrive) ?? g.longestDrive
        closestToPin = try c.decodeIfPresent(Ruleset.SidePrize.self, forKey: .closestToPin) ?? g.closestToPin
        splitTies = try c.decodeIfPresent(Bool.self, forKey: .splitTies) ?? g.splitTies
    }
}

extension Ruleset.HandicapRules: Codable {
    private enum CodingKeys: String, CodingKey {
        case allowanceOverride, formAllowances, seedingGroups, externalHandicap, teamHandicap
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.golfgutu.handicap
        allowanceOverride = try c.decodeIfPresent(Double.self, forKey: .allowanceOverride)
        formAllowances = try c.decodeIfPresent([String: Double].self, forKey: .formAllowances) ?? g.formAllowances
        seedingGroups = try c.decodeIfPresent([SeedingGroup].self, forKey: .seedingGroups) ?? g.seedingGroups
        externalHandicap = try c.decodeIfPresent(Bool.self, forKey: .externalHandicap) ?? g.externalHandicap
        teamHandicap = try c.decodeIfPresent([String: Ruleset.TeamHandicapRule].self, forKey: .teamHandicap) ?? g.teamHandicap
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(allowanceOverride, forKey: .allowanceOverride)
        try c.encode(formAllowances, forKey: .formAllowances)
        try c.encode(seedingGroups, forKey: .seedingGroups)
        try c.encode(externalHandicap, forKey: .externalHandicap)
        try c.encode(teamHandicap, forKey: .teamHandicap)
    }
}

extension Ruleset.FormatRules: Codable {
    private enum CodingKeys: String, CodingKey { case defaultFormID, allowedFormIDs, maxPerBay, matchStrokes, drawMethod }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Ruleset.golfgutu.formats
        defaultFormID = try c.decodeIfPresent(String.self, forKey: .defaultFormID) ?? g.defaultFormID
        allowedFormIDs = try c.decodeIfPresent([String].self, forKey: .allowedFormIDs) ?? g.allowedFormIDs
        maxPerBay = try c.decodeIfPresent(Int.self, forKey: .maxPerBay) ?? g.maxPerBay
        matchStrokes = try c.decodeIfPresent(Ruleset.MatchStrokes.self, forKey: .matchStrokes) ?? g.matchStrokes
        drawMethod = try c.decodeIfPresent(Ruleset.DrawMethod.self, forKey: .drawMethod) ?? g.drawMethod
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultFormID, forKey: .defaultFormID)
        try c.encode(allowedFormIDs, forKey: .allowedFormIDs)
        try c.encode(maxPerBay, forKey: .maxPerBay)
        try c.encode(matchStrokes, forKey: .matchStrokes)
        // Bare når trekningen ikke er etter tabellen, så Golfgutu-JSON-en er som før.
        if drawMethod != .standings { try c.encode(drawMethod, forKey: .drawMethod) }
    }
}
