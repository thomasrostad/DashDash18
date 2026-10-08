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
    }
}

struct KomIGangTests {
    private let allDone = GettingStarted.Input(hasActiveSeason: true, readyCourses: 2, activeMembers: 12,
                                               upcomingEvenings: 3)

    @Test func rekkefolgenErSesongBanerTroppKveld() {
        #expect(GettingStarted.steps(allDone).map(\.item) == [.season, .courses, .roster, .evening])
        #expect(GettingStarted.Item.allCases.map(\.title) == ["Sesong og regler", "Banene", "Troppen", "Kveldene"])
    }

    @Test func skjultNaarAltErIOrden() {
        let steps = GettingStarted.steps(allDone)
        #expect(steps.filter(\.isDone).count == 4)
        #expect(!GettingStarted.isVisible(steps))
        #expect(steps.map(\.detail) == ["Aktiv sesong er satt opp.", "2 baner er klare.", "12 i troppen.",
                                        "3 kommende kvelder."])
    }

    @Test func hvertPunktKanMangle() {
        var input = allDone
        input.hasActiveSeason = false
        #expect(GettingStarted.steps(input).filter { !$0.isDone }.map(\.item) == [.season])
        #expect(GettingStarted.isVisible(GettingStarted.steps(input)))

        input = allDone
        input.readyCourses = 0
        #expect(GettingStarted.steps(input)[1] == .init(item: .courses, isDone: false,
                                                       detail: "Legg inn par på alle hull for minst én bane."))

        input = allDone
        input.upcomingEvenings = 0
        #expect(GettingStarted.steps(input)[3] == .init(item: .evening, isDone: false, detail: "Legg inn neste kveld."))
    }

    @Test func troppenTrengerLikeMangeSomEnRunde() {
        var input = allDone
        input.activeMembers = RoundSetupCheck.minimumPlayers - 1
        #expect(GettingStarted.steps(input)[2].isDone == false)
        #expect(GettingStarted.steps(input)[2].detail == "Minst 2 må være med i troppen før dere kan spille.")
        input.activeMembers = RoundSetupCheck.minimumPlayers
        #expect(GettingStarted.steps(input)[2].isDone)
    }

    @Test func entallOgFremdrift() {
        let input = GettingStarted.Input(hasActiveSeason: false, readyCourses: 1, activeMembers: 0, upcomingEvenings: 1)
        let steps = GettingStarted.steps(input)
        #expect(steps[1].detail == "1 bane er klar.")
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
    @Test func knappenBareIKveldForArrangorer() {
        #expect(AppTab.kveld.showsAdminButton(isOrganizer: true))
        #expect(!AppTab.kveld.showsAdminButton(isOrganizer: false))
        #expect(!AppTab.deg.showsAdminButton(isOrganizer: true))
        #expect(!AppTab.tavla.showsAdminButton(isOrganizer: true))
        #expect(!AppTab.spill.showsAdminButton(isOrganizer: true))
    }
}
