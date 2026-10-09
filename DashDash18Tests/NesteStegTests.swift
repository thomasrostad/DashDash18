import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 11: arrangørsidens «Neste kveld» og «Kom i gang».

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)

private func event(_ n: Int, _ date: String) -> EventRow {
    EventRow(id: id(n), clubID: club, seasonID: nil, eventDate: date, startTime: nil, venue: nil, note: nil)
}

private func season(_ status: SeasonStatus) -> SeasonRow {
    SeasonRow(id: id(800), clubID: club, name: "Høst 2026", status: status, rules: .golfgutu)
}

struct NesteKveldTests {
    @Test func overskriftenSierIKveldBareSammeDag() {
        #expect(Tonight.sectionTitle(daysUntil: 0) == "I kveld")
        #expect(Tonight.sectionTitle(daysUntil: 1) == "Neste kveld")
        #expect(Tonight.sectionTitle(daysUntil: 5) == "Neste kveld")
        #expect(Tonight.sectionTitle(daysUntil: nil) == "Neste kveld")
        // Alle kveldene er passert.
        #expect(Tonight.sectionTitle(daysUntil: -3) == "Siste kveld")
    }
}

struct KomIGangTests {
    private let allDone = GettingStarted.Input(hasActiveSeason: true, readyCourses: 2, activeMembers: 12,
                                               upcomingEvenings: 3)

    /// Fase 21: i sesongens rekkefølge, nummerert.
    @Test func rekkefolgenErTurneringTroppBanerKveld() {
        #expect(GettingStarted.steps(allDone).map(\.item) == [.season, .roster, .courses, .evening])
        #expect(GettingStarted.Item.allCases.map { $0.title() } == ["Turneringen", "Troppen", "Banene", "Kveldene"])
        #expect(GettingStarted.steps(allDone).map(\.number) == [1, 2, 3, 4])
    }

    @Test func skjultNaarAltErIOrden() {
        let steps = GettingStarted.steps(allDone)
        #expect(steps.filter(\.isDone).count == 4)
        #expect(!GettingStarted.isVisible(steps))
        #expect(steps.map(\.detail) == ["En turnering er i gang.", "12 i troppen.", "2 baner er klare.",
                                        "3 kommende kvelder."])
    }

    @Test func hvertPunktKanMangle() {
        var input = allDone
        input.hasActiveSeason = false
        #expect(GettingStarted.steps(input).filter { !$0.isDone }.map(\.item) == [.season])
        #expect(GettingStarted.isVisible(GettingStarted.steps(input)))

        input = allDone
        input.readyCourses = 0
        #expect(GettingStarted.steps(input)[2] == .init(item: .courses, isDone: false,
                                                       detail: "Legg inn par på alle hull for minst én bane."))

        input = allDone
        input.upcomingEvenings = 0
        #expect(GettingStarted.steps(input)[3] == .init(item: .evening, isDone: false, detail: "Legg inn neste kveld."))
    }

    @Test func troppenTrengerLikeMangeSomEnRunde() {
        var input = allDone
        input.activeMembers = RoundSetupCheck.minimumPlayers - 1
        #expect(GettingStarted.steps(input)[1].isDone == false)
        #expect(GettingStarted.steps(input)[1].detail == "Minst 2 må være med i troppen før dere kan spille.")
        input.activeMembers = RoundSetupCheck.minimumPlayers
        #expect(GettingStarted.steps(input)[1].isDone)
    }

    @Test func entallOgFremdrift() {
        let input = GettingStarted.Input(hasActiveSeason: false, readyCourses: 1, activeMembers: 0, upcomingEvenings: 1)
        let steps = GettingStarted.steps(input)
        #expect(steps[2].detail == "1 bane er klar.")
        #expect(steps[3].detail == "1 kommende kveld.")
        #expect(GettingStarted.progressText(steps) == "2 av 4 klar")
    }

    @Test func inndataFraRadene() {
        let events = [event(1, "2026-09-24"), event(2, "2026-10-08"), event(3, "2026-10-15")]
        let input = GettingStarted.input(seasons: [season(.finished), season(.active)], readyCourses: 1,
                                         activeMembers: 5, events: events, today: "2026-10-08")
        #expect(input == .init(hasActiveSeason: true, readyCourses: 1, activeMembers: 5, upcomingEvenings: 2))
        // Bare tidligere kvelder og ingen aktiv sesong.
        let old = GettingStarted.input(seasons: [season(.finished)], readyCourses: 0, activeMembers: 0,
                                       events: [event(1, "2026-09-24")], today: "2026-10-08")
        #expect(old == .init(hasActiveSeason: false, readyCourses: 0, activeMembers: 0, upcomingEvenings: 0))
    }
}

struct ArrangorInngangTests {
    /// 09.10.2026: egen fane for arrangører i stedet for ikonet på Hjem og raden i Deg.
    @Test func egenFaneBareForArrangorer() {
        #expect(AppTab.tabs(isOrganizer: true).contains(.arrangor))
        #expect(!AppTab.tabs(isOrganizer: false).contains(.arrangor))
        #expect(!AppTab.tabs().contains(.arrangor))
        #expect(AppTab.arrangor.title == "Arrangør")
    }
}

/// «Spilledag» for nye turneringer (09.10.2026): samme steg og knapper, andre ord.
struct SpilledagTests {
    @Test func overskrifterOgKnapper() {
        #expect(Tonight.sectionTitle(daysUntil: 0, term: .playingDay) == "I dag")
        #expect(Tonight.sectionTitle(daysUntil: 2, term: .playingDay) == "Neste spilledag")
        #expect(Tonight.sectionTitle(daysUntil: -1, term: .playingDay) == "Siste spilledag")
        #expect(TonightAction.noEvening.buttonTitle(.playingDay) == "Legg inn en spilledag")
        #expect(TonightAction.closeEvening(UUID()).buttonTitle(.playingDay) == "Avslutt spilledagen")
        #expect(Tonight.statusText(action: .noEvening, rounds: [], activeTitle: nil, term: .playingDay)
            == "Ingen spilledag i terminlista")
    }

    @Test func komIGang() {
        let input = GettingStarted.Input(hasActiveSeason: true, readyCourses: 1, activeMembers: 8,
                                         upcomingEvenings: 0, term: .playingDay)
        let step = GettingStarted.steps(input)[3]
        #expect(step.title == "Spilledagene" && step.detail == "Legg inn neste spilledag.")
        var two = input
        two.upcomingEvenings = 2
        #expect(GettingStarted.steps(two)[3].detail == "2 kommende spilledager.")
    }

    @Test func nyTurneringSierSpilledag() {
        var draft = TournamentDraft(template: .stablefordSeries, clubID: UUID(), name: "Vår", today: "2026-10-09")
        #expect(draft.seasonRules.day == .playingDay)
        // Oppsettets regler er urørt; ordet er ikke en regel.
        #expect(draft.rules == RulesetTemplate.stablefordSeries.rules)
        draft.dayTerm = .evening
        #expect(draft.seasonRules.day == .evening)
        #expect(Ruleset.golfgutu.day == .evening)
    }

    @Test func avslutning() {
        #expect(EveningClose.summary(locked: ["Runde 1"], drafts: [], failed: [], term: .playingDay)
            == "Runde 1 er låst. Spilledagen er ferdig, og neste spilledag står øverst.")
    }
}

/// Regelteksten med «spilledag» (09.10.2026). Golfgutu-teksten er som før.
struct SpilledagRegeltekstTests {
    @Test func oppsummeringOgForklaring() {
        var rules = RulesetTemplate.stablefordSeries.rules
        #expect(RulesetSummary.eveningsAndCounting(rules) == "Beste 5 av 7 kvelder teller")
        rules.dayTerm = .playingDay
        #expect(RulesetSummary.eveningsAndCounting(rules) == "Beste 5 av 7 spilledager teller")
        #expect(RulesetExplanation.sentences(for: rules).first == "Turneringen har 7 spilledager.")
        #expect(RuleNames.title(.evening, term: .playingDay) == "Spilledager")
        #expect(RulesetExplanation.sentences(for: .golfgutu).first == "Turneringen har 7 kvelder.")
    }

    @Test func nyTurneringsLinjer() {
        var draft = TournamentDraft(template: .matchSeries, clubID: UUID(), name: "Vår", today: "2026-10-09")
        #expect(TournamentSetup.ruleLines(draft).contains { $0.hasPrefix("Matcher hver spilledag") })
        draft.dayTerm = .evening
        #expect(TournamentSetup.ruleLines(draft).contains { $0.hasPrefix("Matcher hver kveld") })
    }
}
