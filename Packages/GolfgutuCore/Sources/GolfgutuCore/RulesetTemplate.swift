import Foundation

/// Oppsettene arrangøren velger mellom i «Ny turnering» (fase 18). Hvert oppsett er et ferdig
/// regelsett; detaljene kan tilpasses etterpå. Golfgutu er ett av oppsettene (`matchSeries`),
/// ikke målestokken.
///
/// Regelsettet husker ikke hvilket oppsett det kom fra. Oppsettet kjennes igjen på innholdet
/// (`matching`, `closest`), og turneringstypen (`competitions.kind`) skiller cup og morroturnering,
/// som har samme grunnregelsett. Se `differences(in:)` for hva som er endret fra et oppsett.
public enum RulesetTemplate: String, Codable, Hashable, Sendable, CaseIterable {
    /// Stableford-poeng hver kveld, de beste kveldene teller. Ingen matcher, seeding eller sidepremier.
    case stablefordSeries
    /// Golfgutu-oppsettet: matcher hver kveld, sidepremier og seeding.
    case matchSeries
    /// Utslag i matchspill (`CupRules`).
    case cup
    /// Morroturnering (`LeagueRules.fun`).
    case fun

    /// Navnet i «Ny turnering».
    public var title: String {
        switch self {
        case .stablefordSeries: "Stableford-serie"
        case .matchSeries: "Matchspill-serie"
        case .cup: "Cup"
        case .fun: "Morroturnering"
        }
    }

    /// Én kort setning om oppsettet.
    public var summary: String {
        switch self {
        case .stablefordSeries: "Stableford-poeng hver kveld. De beste kveldene teller."
        case .matchSeries: "Matcher hver kveld gir poeng i tabellen, med sidepremier og seeding."
        case .cup: "Utslag i matchspill. Den som vinner, går videre."
        case .fun: "Stableford-poengene teller rett fram, runde for runde."
        }
    }

    /// Regelsettet oppsettet gir.
    public var rules: Ruleset {
        switch self {
        case .stablefordSeries: Self.stablefordSeriesRules
        case .matchSeries: Ruleset.golfgutu
        case .cup, .fun: Self.competitionRules
        }
    }

    // MARK: Regelsettene

    /// Stableford-serie: Golfgutu-oppsettet med disse endringene:
    /// - tabellpoengene er stablefordpoengene (vektet), ikke matcher;
    /// - de beste 5 av 7 kveldene teller, både i tabellen og i stablefordsummen (så en spiller kan
    ///   stå over to kvelder uten å tape på det, og de to tallene er de samme);
    /// - skille ved likt: stablefordsummen (hulldifferanse finnes ikke uten matcher);
    /// - ingen sidepremier og ingen seeding.
    /// Handicapandelen er Golfgutu sin: 95 % i stableford (WHS-anbefalingen for individuell
    /// stableford), standardform stableford og 4 per bås.
    static let stablefordSeriesRules: Ruleset = {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .stableford
        r.table.counting = Ruleset.Counting(unit: .evening, best: 5)
        r.table.stablefordCounting = Ruleset.Counting(unit: .evening, best: 5)
        r.table.tiebreaks = [.stableford]
        r.sidePrizes.longestDrive.enabled = false
        r.sidePrizes.closestToPin.enabled = false
        r.handicap.seedingGroups = []
        r.formats.defaultFormID = "stableford"
        return r
    }()

    /// Cup og morroturnering: det «Ny konkurranse» lagrer med malen i dag (`CompetitionDraft.rules`):
    /// Golfgutu-oppsettet med konkurransemalene under `competition`.
    static let competitionRules: Ruleset = {
        var r = Ruleset.golfgutu
        r.competition = .standard
        return r
    }()

    // MARK: Gjenkjenning

    /// Oppsettet regelsettet er helt likt, eller `nil` når det er tilpasset. Cup og morroturnering har
    /// samme regelsett; gi `among` etter turneringstypen for å skille dem (f.eks. `[.fun]`).
    public static func matching(_ rules: Ruleset, among candidates: [RulesetTemplate] = allCases,
                                asLeague: Bool = false) -> RulesetTemplate? {
        // Ordet for dagen er ikke en regel (`DayTerm`).
        var rules = rules
        rules.dayTerm = nil
        return candidates.first { (asLeague ? $0.leagueRules : $0.rules) == rules }
    }

    /// Oppsettet som ligger nærmest: færrest felt endret (`differences`). Likt: det første i `among`.
    /// `nil` bare når `among` er tom.
    public static func closest(to rules: Ruleset, among candidates: [RulesetTemplate] = allCases,
                               asLeague: Bool = false) -> RulesetTemplate? {
        var best: (template: RulesetTemplate, count: Int)?
        for t in candidates {
            let n = t.differences(in: rules, asLeague: asLeague).count
            if best == nil || n < best!.count { best = (t, n) }
        }
        return best?.template
    }

    /// Feltene i `rules` som er endret fra oppsettet (`Ruleset.changedFields(from:)`).
    public func differences(in rules: Ruleset, asLeague: Bool = false) -> [String] {
        rules.changedFields(from: asLeague ? leagueRules : self.rules)
    }

    /// Regelsettet når oppsettet lages som liga (en serie uten klubb, `kind = league`). For
    /// stableford-serien regner ligaen tabellen (`League`), så ligareglene er serien sin: stableford-poeng
    /// og de beste rundene. De andre oppsettene lages aldri som liga og gir `rules`.
    public var leagueRules: Ruleset {
        guard self == .stablefordSeries else { return rules }
        var r = rules
        var competition = CompetitionRules.standard
        competition.league = .stablefordSeries
        r.competition = competition
        return r
    }
}

extension LeagueRules {
    /// Stableford-serien som liga: stableford-poeng uten deltakerpoeng, og like mange tellende runder
    /// som serien har tellende kvelder.
    public static let stablefordSeries: LeagueRules = {
        var league = LeagueRules.fun
        league.bestRounds = RulesetTemplate.stablefordSeries.rules.table.counting.best
        return league
    }()
}

extension Ruleset {
    /// Feltene som er forskjellige fra `base`, som stier i JSON-en (samme form som
    /// `RulesetIssue.field`), sortert: `table.counting`, `handicap.formAllowances.stableford`,
    /// `table.pointsSource`. Objekter sammenlignes felt for felt; lister og tall som én verdi. Et felt
    /// som bare står i det ene (f.eks. `competition`), er endret. Dekker hele regelsettet, også felt
    /// som kommer til senere.
    public func changedFields(from base: Ruleset) -> [String] {
        guard let a = Self.jsonObject(self), let b = Self.jsonObject(base) else { return self == base ? [] : [""] }
        var out: [String] = []
        Self.diff(a, b, path: "", into: &out)
        // Ordet for dagen er ikke en regel (`DayTerm`).
        return out.filter { $0 != "dayTerm" }.sorted()
    }

    private static func jsonObject(_ rules: Ruleset) -> Any? {
        guard let data = try? JSONEncoder().encode(rules) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func diff(_ a: Any?, _ b: Any?, path: String, into out: inout [String]) {
        if let da = a as? [String: Any], let db = b as? [String: Any] {
            for key in Set(da.keys).union(db.keys) {
                diff(da[key], db[key], path: path.isEmpty ? key : "\(path).\(key)", into: &out)
            }
            return
        }
        switch (a, b) {
        case (nil, nil): return
        case let (x?, y?) where (x as AnyObject).isEqual(y as AnyObject): return
        default: out.append(path)
        }
    }
}
