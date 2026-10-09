import Foundation
import GolfgutuCore

/// «Kom i gang» på arrangørsiden: det som må være på plass før en runde kan settes opp,
/// i den rekkefølgen det gjøres: turneringen, troppen, banene, kveldene. Står øverst på arrangørsiden
/// i stedet for kvelden når noe mangler.
nonisolated enum GettingStarted {
    enum Item: CaseIterable, Equatable, Sendable {
        /// En turnering i gang (aktiv sesong med regelsett).
        case season
        /// Nok aktive i troppen til en runde.
        case roster
        /// Minst én bane med par på alle hull.
        case courses
        /// En kveld i dag eller senere i terminlista.
        case evening

        func title(_ term: DayTerm = .evening) -> String {
            switch self {
            case .season: "Turneringen"
            case .courses: "Banene"
            case .roster: "Troppen"
            case .evening: DayTerm.capitalized(term.theMany)
            }
        }
    }

    /// Det lista regner ut fra.
    struct Input: Equatable, Sendable {
        var hasActiveSeason: Bool
        var readyCourses: Int
        var activeMembers: Int
        var upcomingEvenings: Int
        /// «Kveld» eller «spilledag» (`DayTerm`).
        var term: DayTerm = .evening
    }

    struct Step: Equatable, Identifiable, Sendable {
        let item: Item
        let isDone: Bool
        /// Hva som står, eller hva som mangler.
        let detail: String
        var term: DayTerm = .evening
        var id: Item { item }
        /// «Lag turneringen» mens den mangler (punktet åpner «Ny turnering»), ellers «Turneringen».
        var title: String { item == .season && !isDone ? "Lag turneringen" : item.title(term) }
        /// Nummeret i lista: 1 Turneringen, 2 Troppen, 3 Banene, 4 Kveldene.
        var number: Int { (Item.allCases.firstIndex(of: item) ?? 0) + 1 }
    }

    /// Like mange som en runde trenger for å kunne startes.
    static let minimumRoster = RoundSetupCheck.minimumPlayers

    static func input(seasons: [SeasonRow], readyCourses: Int, activeMembers: Int, events: [EventRow],
                      today: String, term: DayTerm = .evening) -> Input {
        Input(hasActiveSeason: seasons.contains { $0.status == .active },
              readyCourses: readyCourses,
              activeMembers: activeMembers,
              upcomingEvenings: events.filter { $0.eventDate >= today }.count,
              term: term)
    }

    /// Uferdige punkter som åpner «Ny turnering» i stedet for en side: turneringen, når ingen er i gang.
    static func opensNewTournament(_ step: Step) -> Bool {
        step.item == .season && !step.isDone
    }

    /// Alle punktene i rekkefølge: turnering, tropp, baner, kveld.
    static func steps(_ input: Input) -> [Step] {
        Item.allCases.map { item in
            switch item {
            case .season:
                Step(item: item, isDone: input.hasActiveSeason,
                     detail: input.hasActiveSeason ? "En turnering er i gang."
                                                   : "Lag turneringen og velg hvordan dere spiller.")
            case .courses:
                Step(item: item, isDone: input.readyCourses > 0,
                     detail: input.readyCourses > 0 ? courseCount(input.readyCourses)
                                                    : "Legg inn par på alle hull for minst én bane.")
            case .roster:
                Step(item: item, isDone: input.activeMembers >= minimumRoster,
                     detail: input.activeMembers >= minimumRoster
                        ? "\(input.activeMembers) i troppen."
                        : "Minst \(minimumRoster) må være med i troppen før dere kan spille.")
            case .evening:
                Step(item: item, isDone: input.upcomingEvenings > 0,
                     detail: input.upcomingEvenings > 0 ? eveningCount(input.upcomingEvenings, input.term)
                                                        : "Legg inn neste \(input.term.one).",
                     term: input.term)
            }
        }
    }

    /// «Inviter spillere» står rett under Troppen, så det er der arrangøren finner den.
    static func showsInvite(after step: Step) -> Bool {
        step.item == .roster
    }

    /// Lista vises når minst ett punkt mangler.
    static func isVisible(_ steps: [Step]) -> Bool {
        steps.contains { !$0.isDone }
    }

    /// «1 av 4 klar», til overskriften.
    static func progressText(_ steps: [Step]) -> String {
        "\(steps.filter(\.isDone).count) av \(steps.count) klar"
    }

    private static func courseCount(_ n: Int) -> String {
        n == 1 ? "1 bane er klar." : "\(n) baner er klare."
    }

    private static func eveningCount(_ n: Int, _ term: DayTerm) -> String {
        n == 1 ? "1 kommende \(term.one)." : "\(n) kommende \(term.many)."
    }
}
