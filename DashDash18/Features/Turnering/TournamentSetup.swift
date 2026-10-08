import Foundation
import GolfgutuCore

// «Ny turnering» (fase 18): sesong og konkurranse er ett begrep i appen, turnering, med fire oppsett
// (`RulesetTemplate`). Ren logikk: hvilke oppsett som tilbys, hva som lages, navneforslag og tekster.
// Skjermene er `NyTurneringView` og `AlleTurneringerView`. Ingen nye tabeller: en serie i en klubb er
// en sesong (`seasons`, speilet til `competitions` av triggeren i sql/017), en privat serie er en liga,
// og cup og morro er konkurranser som før.

nonisolated enum TournamentSetup {
    /// Hva «Lag» lager.
    enum Target: Equatable, Sendable {
        /// En sesong i klubben: kvelder, terminliste og Tavla.
        case season
        /// En konkurranse (`create_competition_with_entrants`) av typen.
        case competition(CompetitionKind)

        /// Typen i `competitions.kind` (sesongen speiles som `season`).
        var kind: CompetitionKind {
            switch self {
            case .season: .season
            case .competition(let kind): kind
            }
        }
    }

    /// Oppsettene i steg 1. Uten klubb er matchspill-serien borte: den trenger kvelder og båser i en klubb.
    static func templates(inClub: Bool) -> [RulesetTemplate] {
        inClub ? RulesetTemplate.allCases : RulesetTemplate.allCases.filter(allowsPrivate)
    }

    /// Kan oppsettet lages uten klubb?
    static func allowsPrivate(_ template: RulesetTemplate) -> Bool {
        template != .matchSeries
    }

    /// Symbolet på kortet i steg 1.
    static func icon(_ template: RulesetTemplate) -> String {
        switch template {
        case .stablefordSeries: "list.number"
        case .matchSeries: "person.2"
        case .cup: "point.3.connected.trianglepath.dotted"
        case .fun: "party.popper"
        }
    }

    /// I en klubb er en serie en sesong. Uten klubb er stableford-serien en liga.
    static func target(_ template: RulesetTemplate, clubID: UUID?) -> Target {
        switch template {
        case .stablefordSeries: clubID == nil ? .competition(.league) : .season
        case .matchSeries: .season
        case .cup: .competition(.cup)
        case .fun: .competition(.fun)
        }
    }

    /// Vises «Klubb eller privat» i steg 2? Bare der det er et valg i dag (fra lista over turneringer,
    /// når du er arrangør i klubben), og bare for oppsett som kan være private.
    static func showsOwnerChoice(_ template: RulesetTemplate, canCreateInClub: Bool, offersPrivate: Bool) -> Bool {
        canCreateInClub && offersPrivate && allowsPrivate(template)
    }

    /// Perioden gjelder bare en morroturnering i en klubb: kveldene i perioden merkes på Kveld.
    static func showsPeriod(_ template: RulesetTemplate, clubID: UUID?) -> Bool {
        template == .fun && clubID != nil
    }

    /// En ny sesong startes med en gang når klubben ikke har en i gang, så arrangøren kan legge inn
    /// kvelder og spille uten et ekstra steg. Er en annen i gang, blir den nye planlagt, så den som går,
    /// ikke avsluttes ved et uhell.
    static func activatesNewSeason(existing seasons: [SeasonRow]) -> Bool {
        !seasons.contains { $0.status == .active }
    }

    /// Ligareglene for en privat stableford-serie: stablefordpoengene teller rett fram, uten
    /// deltakerpoeng, og de beste rundene teller (like mange som kveldene i stableford-serien).
    static var privateSeriesLeague: LeagueRules {
        var league = LeagueRules.fun
        league.bestRounds = RulesetTemplate.stablefordSeries.rules.table.counting.best
        return league
    }

    // MARK: Navn

    /// Årstiden som ord: «Vinter», «Vår», «Sommer», «Høst».
    static func seasonWord(month: Int) -> String {
        switch month {
        case 3...5: "Vår"
        case 6...8: "Sommer"
        case 9...11: "Høst"
        default: "Vinter"
        }
    }

    /// Forslaget til navn: «Høst 2026» for en serie, «Høstcupen», «Høstmorro». Er navnet tatt (uten
    /// hensyn til store og små bokstaver eller mellomrom), får det et tall: «Høst 2026 2».
    static func suggestedName(_ template: RulesetTemplate, taken: [String], now: Date = .now,
                              calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: now)
        let word = seasonWord(month: parts.month ?? 1)
        let base = switch template {
        case .stablefordSeries, .matchSeries: "\(word) \(parts.year ?? 2026)"
        case .cup: "\(word)cupen"
        case .fun: "\(word)morro"
        }
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard used.contains(base.lowercased()) else { return base }
        for n in 2...99 where !used.contains("\(base) \(n)".lowercased()) {
            return "\(base) \(n)"
        }
        return base
    }

    // MARK: Tekster

    /// Typen som undertekst i lista: «Stableford-serie», «Matchspill-serie», «Cup», «Morro», «Liga».
    static func typeText(kind: CompetitionKind, rules: Ruleset) -> String {
        switch kind {
        case .season:
            rules.table.pointsSource == .stableford
                ? RulesetTemplate.stablefordSeries.title : RulesetTemplate.matchSeries.title
        case .league: "Liga"
        case .cup: "Cup"
        case .fun: "Morro"
        case .game: "Spill"
        }
    }

    /// Kort om reglene i steg 2, med tallene fra regelsettet.
    static func ruleLines(_ draft: TournamentDraft) -> [String] {
        let rules = draft.rules
        let form = CompetitionForm.form(id: rules.formats.defaultFormID)
        let handicap = RulesetSummary.handicap(rules, form: form)
        switch draft.target {
        case .season:
            var lines = [RulesetSummary.eveningsAndCounting(rules)]
            lines.append(rules.table.pointsSource == .stableford
                         ? "Stablefordpoengene er tabellpoengene"
                         : "Matcher hver kveld, seier gir \(RuleFormat.number(rules.table.matchPoints.win)) poeng")
            lines.append(RulesetSummary.sidePrizes(rules.sidePrizes))
            return lines
        case .competition(.cup):
            let cup = draft.competition.cup
            return ["Seeding: \(CompetitionText.seeding(cup.seeding).lowercased())",
                    "Likt etter siste hull: \(CompetitionText.tie(cup.tie).lowercased())",
                    handicap]
        case .competition:
            let league = draft.competition.leagueRules
            var lines = [league.scoring == .stableford
                         ? "Stablefordpoengene teller rett fram"
                         : "Poeng etter plassen i hver runde"]
            if let best = league.bestRounds {
                lines.append(best == 1 ? "Den beste runden teller" : "De \(best) beste rundene teller")
            } else {
                lines.append("Alle runder teller")
            }
            lines.append(handicap)
            return lines
        }
    }
}

/// Det arrangøren fyller ut i «Ny turnering». Konkurransedelen (eier, periode, påmelding og reglene for
/// liga, cup og morro) ligger i `competition`, som «Ny konkurranse» hadde før.
nonisolated struct TournamentDraft: Equatable, Sendable {
    let template: RulesetTemplate
    var name: String
    /// Oppsettets regelsett, med det arrangøren har tilpasset.
    var rules: Ruleset
    var competition: CompetitionDraft

    init(template: RulesetTemplate, clubID: UUID?, name: String, today: String) {
        self.template = template
        self.name = name
        rules = template.rules
        competition = CompetitionDraft(clubID: clubID, today: today)
        competition.kind = TournamentSetup.target(template, clubID: clubID).kind
        if template == .stablefordSeries { competition.league = TournamentSetup.privateSeriesLeague }
    }

    /// Klubben som eier turneringen, eller nil: privat.
    var clubID: UUID? {
        get { competition.clubID }
        set {
            competition.clubID = newValue
            competition.kind = TournamentSetup.target(template, clubID: newValue).kind
            competition.normalize()
        }
    }

    var target: TournamentSetup.Target { TournamentSetup.target(template, clubID: clubID) }

    var showsPeriod: Bool { TournamentSetup.showsPeriod(template, clubID: clubID) }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Konkurransen som lagres (`create_competition_with_entrants`): navnet, typen og regelsettet
    /// fra oppsettet. Perioden bare der den gjelder.
    var competitionDraft: CompetitionDraft {
        var d = competition
        d.name = trimmedName
        d.kind = target.kind
        d.baseRules = rules
        if !showsPeriod { d.hasPeriod = false }
        return d
    }

    /// Hva som mangler før turneringen kan lages.
    func issues() -> [String] {
        var out: [String] = []
        if trimmedName.isEmpty { out.append("Gi turneringen et navn.") }
        if trimmedName.count > 60 { out.append("Navnet kan ha høyst 60 tegn.") }
        out.append(contentsOf: rules.validate().map(\.message))
        if case .competition = target {
            out.append(contentsOf: competitionDraft.issues().filter { !out.contains($0) })
        }
        return out
    }
}

// MARK: - Alle turneringer

/// «Alle turneringer» på arrangørsiden: klubbens sesonger og konkurranser i én liste.
nonisolated enum TournamentList {
    enum Item: Identifiable, Equatable, Sendable {
        case season(SeasonRow)
        case competition(CompetitionRow)

        var id: UUID {
            switch self {
            case .season(let s): s.id
            case .competition(let c): c.id
            }
        }

        var name: String {
            switch self {
            case .season(let s): s.name
            case .competition(let c): c.name
            }
        }

        var status: SeasonStatus {
            switch self {
            case .season(let s): s.status
            case .competition(let c): c.status
            }
        }

        /// «Stableford-serie», «Cup» …, og perioden når den finnes.
        var subtitle: String {
            switch self {
            case .season(let s):
                return TournamentSetup.typeText(kind: .season, rules: s.rules)
            case .competition(let c):
                let type = TournamentSetup.typeText(kind: c.kind, rules: c.rules)
                return CompetitionText.period(c).map { "\(type) · \($0)" } ?? type
            }
        }
    }

    struct Group: Equatable, Sendable {
        let status: SeasonStatus
        let items: [Item]

        var title: String {
            switch status {
            case .active: "Pågår"
            case .planned: "Planlagt"
            case .finished: "Ferdig"
            }
        }
    }

    /// Klubbens sesonger og konkurranser (liga, cup, morro). Sesongens speil i `competitions` og spill
    /// på runden er ikke med, så hver turnering står én gang.
    static func items(seasons: [SeasonRow], competitions: [CompetitionRow], clubID: UUID) -> [Item] {
        let own = seasons.filter { $0.clubID == clubID }.map(Item.season)
        let others = competitions
            .filter { $0.clubID == clubID && [.league, .cup, .fun].contains($0.kind) }
            .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
            .map(Item.competition)
        return own + others
    }

    /// Gruppert: pågår, planlagt, ferdig. Tomme grupper er borte.
    static func grouped(_ items: [Item]) -> [Group] {
        [SeasonStatus.active, .planned, .finished].compactMap { status in
            let rows = items.filter { $0.status == status }
            return rows.isEmpty ? nil : Group(status: status, items: rows)
        }
    }
}
