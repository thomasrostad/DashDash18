import Foundation

/// Regelsettet som styrer turneringen (B12). Minimalt: bare det fase 2 trenger, og det som
/// skal til for at antall og telling ikke er låst. `Ruleset.golfgutu` gjengir PWA-en.
public struct Ruleset: Codable, Hashable, Sendable {
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

    /// Sidepremier (longest drive og nærmest pinnen).
    public struct SidePrizes: Codable, Hashable, Sendable {
        public var enabled: Bool
        /// Poeng per premie. Deles likt ved lik lengde.
        public var points: Double

        public init(enabled: Bool, points: Double) {
            self.enabled = enabled
            self.points = points
        }
    }

    /// Fast handicaptildeling for alle former. `nil`: formens anbefalte andel når kortet er
    /// per spiller, ellers 1 (som PWA-en lagrer på runden når den startes).
    public var allowanceOverride: Double?
    /// Seedede grupper med faste tall. Tom liste: ingen seeding.
    public var seedingGroups: [SeedingGroup]
    /// Simulatoren deler ut slagene på nye runder (`hcp_extern`).
    public var externalHandicap: Bool
    /// Formen en ny runde starter med.
    public var defaultFormID: String
    /// Største lag som får plass i en bås.
    public var maxPerBay: Int
    /// Antall kvelder i sesongen.
    public var evenings: Int
    /// Kvelder som teller i tabellen: `nil` = alle, ellers de beste N.
    public var countingEvenings: Int?
    /// Kvelder som teller i stablefordsummen (tiebreak og profil): `nil` = alle, ellers de beste N.
    public var stablefordCountingEvenings: Int?
    public var matchPoints: MatchPoints
    public var sidePrizes: SidePrizes

    public init(allowanceOverride: Double? = nil, seedingGroups: [SeedingGroup], externalHandicap: Bool,
                defaultFormID: String, maxPerBay: Int, evenings: Int, countingEvenings: Int?,
                stablefordCountingEvenings: Int?, matchPoints: MatchPoints, sidePrizes: SidePrizes) {
        self.allowanceOverride = allowanceOverride
        self.seedingGroups = seedingGroups
        self.externalHandicap = externalHandicap
        self.defaultFormID = defaultFormID
        self.maxPerBay = maxPerBay
        self.evenings = evenings
        self.countingEvenings = countingEvenings
        self.stablefordCountingEvenings = stablefordCountingEvenings
        self.matchPoints = matchPoints
        self.sidePrizes = sidePrizes
    }

    /// Golfgutu-oppsettet: verdiene fra db-nytt.js og app-nytt.js.
    /// 7 kvelder, alle teller (`TELLENDE_MATCHER = 0`), stablefordsummen teller beste 5
    /// (`TELLENDE_RUNDER`), duellpoeng 1/0,5/0, LD og KP 1 poeng, seeding 0/5/10,
    /// 4 per bås, stableford som standard og appen som deler ut slagene.
    public static let golfgutu = Ruleset(
        allowanceOverride: nil,
        seedingGroups: SeedingGroup.golfgutu,
        externalHandicap: false,
        defaultFormID: CompetitionForm.defaultID,
        maxPerBay: CompetitionForm.golfgutuMaxPerBay,
        evenings: 7,
        countingEvenings: nil,
        stablefordCountingEvenings: 5,
        matchPoints: MatchPoints(win: 1, draw: 0.5, loss: 0),
        sidePrizes: SidePrizes(enabled: true, points: 1)
    )

    /// Tildelingen en ny runde i denne formen får (`hcp_allowance`).
    public func allowance(for form: CompetitionForm) -> Double {
        if let allowanceOverride { return allowanceOverride }
        if let a = form.allowance, form.card == .perPlayer { return a }
        return 1
    }

    /// `effectiveHandicap` med regelsettets seeding.
    public func effectiveHandicap(for player: Player?, in round: Round, roster: [Player]) -> Double {
        Handicap.effective(for: player, in: round, roster: roster, groups: seedingGroups)
    }

    /// `roundNetTotalForPlayer` med regelsettets seeding.
    public func roundNetTotal(_ round: Round, player: Player?, roster: [Player]) -> Int {
        Scoring.roundNetTotal(round, player: player, roster: roster, groups: seedingGroups)
    }

    /// `oppsettForAntall` med regelsettets bås-størrelse.
    public func setup(formID: String?, players: Int) -> FormSetup {
        CompetitionForm.setup(formID: formID, players: players, maxPerBay: maxPerBay)
    }

    /// `formerSomPasser` med regelsettets bås-størrelse.
    public func suggestions(players: Int) -> [FormSuggestion] {
        CompetitionForm.suggestions(players: players, maxPerBay: maxPerBay)
    }
}
