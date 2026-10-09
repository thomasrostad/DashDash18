import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 21: arrangørsiden som tidslinje. Stegrekka (Påmelding → Oppsett → Spilles → Ferdig), neste steg,
// kvelden som står for tur og tidslinja.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)
private let today = "2026-10-08"

private func event(_ n: Int, _ date: String, season: Int? = nil) -> EventRow {
    EventRow(id: id(n), clubID: club, seasonID: season.map(id), eventDate: date, startTime: nil, venue: nil, note: nil)
}

private func round(_ n: Int, event: Int, no: Int = 1, status: RoundStatus, course: Int? = nil) -> RoundRow {
    RoundRow(id: id(n), clubID: club, eventID: id(event), courseID: course.map(id), roundNo: no, name: nil,
             status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
             handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: true, ldHoleIndex: nil,
             kpEnabled: true, kpHoleIndex: nil, cutRule: nil, cutAfter: nil,
             parConfirmedBy: nil, parConfirmedAt: nil, startedAt: nil, lockedAt: nil, venue: nil)
}

private let tonight = event(1, today)
private let nextWeek = event(2, "2026-10-15")
private let lastWeek = event(3, "2026-10-01")

private func progress(_ event: EventRow?, _ rounds: [RoundRow] = [], active: RoundRow? = nil,
                      complete: Bool = false, notAnswered: Int = 0) -> EveningProgress {
    Tonight.progress(event: event, rounds: rounds, activeRound: active, activeComplete: complete,
                     notAnswered: notAnswered, today: today)
}

struct NesteStegTilstandTests {
    @Test func ingenKveld() {
        let p = progress(nil)
        #expect(p == EveningProgress(stage: nil, action: .noEvening))
        #expect(p.action.buttonTitle() == "Legg inn en kveld")
        #expect(p.steps.allSatisfy { $0.state == .upcoming })
    }

    @Test func kommendeKveldUtenSvarGirPurring() {
        let p = progress(nextWeek, notAnswered: 12)
        #expect(p == EveningProgress(stage: .signup, action: .nudge(12)))
        #expect(p.action.buttonTitle() == "Purr de 12")
        #expect(EveningProgress(stage: .signup, action: .nudge(1)).action.buttonTitle() == "Purr den ene")
        #expect(p.steps.map(\.state) == [.current, .upcoming, .upcoming, .upcoming])
    }

    @Test func paameldingPaagaarMedNoenSomMangler() {
        #expect(progress(nextWeek, notAnswered: 3).action == .nudge(3))
    }

    @Test func alleHarSvartGirOppsett() {
        let p = progress(nextWeek, notAnswered: 0)
        #expect(p == EveningProgress(stage: .setup, action: .setUp))
        #expect(p.action.buttonTitle() == "Sett opp runden")
        #expect(p.steps.map(\.state) == [.done, .current, .upcoming, .upcoming])
    }

    @Test func iDagSettesRundenOppSelvOmNoenIkkeHarSvart() {
        #expect(progress(tonight, notAnswered: 4) == EveningProgress(stage: .setup, action: .setUp))
    }

    @Test func kladdGirFortsettKladd() {
        let p = progress(tonight, [round(10, event: 1, status: .draft)], notAnswered: 4)
        #expect(p == EveningProgress(stage: .setup, action: .continueDraft(id(10))))
        #expect(p.action.buttonTitle() == "Fortsett kladd")
    }

    @Test func flereKladderGirDenSiste() {
        let drafts = [round(10, event: 1, no: 1, status: .draft), round(11, event: 1, no: 2, status: .draft)]
        #expect(progress(tonight, drafts).action == .continueDraft(id(11)))
    }

    @Test func rundePaagaar() {
        let live = round(10, event: 1, status: .active)
        let p = progress(tonight, [live, round(11, event: 1, no: 2, status: .draft)], active: live)
        #expect(p == EveningProgress(stage: .playing, action: .goToRound(id(10))))
        #expect(p.action.buttonTitle() == "Gå til runden")
        #expect(p.steps.map(\.state) == [.done, .done, .current, .upcoming])
    }

    @Test func alleHullFoertGirAvsluttKvelden() {
        let live = round(10, event: 1, status: .active)
        let p = progress(tonight, [live], active: live, complete: true)
        #expect(p == EveningProgress(stage: .playing, action: .closeEvening(id(10))))
        #expect(p.action.buttonTitle() == "Avslutt kvelden")
    }

    @Test func ferdigGirResultatet() {
        let p = progress(tonight, [round(10, event: 1, status: .locked)])
        #expect(p == EveningProgress(stage: .done, action: .seeResult))
        #expect(p.action.buttonTitle() == "Se resultatet")
        #expect(p.steps.allSatisfy { $0.state == .done })
    }

    @Test func flereRunderPaaKvelden() {
        let locked = round(10, event: 1, no: 1, status: .locked)
        // Første runde låst, andre som kladd: oppsett.
        #expect(progress(tonight, [locked, round(11, event: 1, no: 2, status: .draft)]).action == .continueDraft(id(11)))
        // Andre runde går.
        let live = round(12, event: 1, no: 2, status: .active)
        #expect(progress(tonight, [locked, live], active: live).action == .goToRound(id(12)))
        // Begge låst.
        #expect(progress(tonight, [locked, round(13, event: 1, no: 2, status: .locked)]).stage == .done)
    }

    @Test func passertKveldUtenRunder() {
        let p = progress(lastWeek, notAnswered: 5)
        #expect(p == EveningProgress(stage: nil, action: .notPlayed))
        #expect(p.action.buttonTitle() == nil)
        #expect(Tonight.statusText(action: p.action, rounds: [], activeTitle: nil) == "Ingen runder spilt")
    }

    @Test func passertKveldMedRunder() {
        #expect(progress(lastWeek, [round(10, event: 3, status: .locked)]).action == .seeResult)
    }

    @Test func bareKveldensRunderTeller() {
        // En runde som går på en annen kveld, gjør ikke denne kvelden i gang.
        let other = round(10, event: 3, status: .active)
        #expect(progress(nextWeek, [other], active: other, complete: true).action == .setUp)
        // «Alle hull ført» gjelder bare runden som går i klubben.
        let live = round(11, event: 1, status: .active)
        #expect(progress(tonight, [live], active: other, complete: true).action == .goToRound(id(11)))
    }

    @Test func statusteksten() {
        #expect(Tonight.statusText(action: .nudge(1), rounds: [], activeTitle: nil) == "1 har ikke svart")
        #expect(Tonight.statusText(action: .nudge(4), rounds: [], activeTitle: nil) == "4 har ikke svart")
        #expect(Tonight.statusText(action: .setUp, rounds: [], activeTitle: nil) == "Ikke satt opp")
        #expect(Tonight.statusText(action: .closeEvening(id(1)), rounds: [], activeTitle: nil) == "Alle hull er ført")
        let two = [round(1, event: 1, status: .locked), round(2, event: 1, no: 2, status: .locked)]
        #expect(Tonight.statusText(action: .seeResult, rounds: two, activeTitle: nil) == "Ferdig · 2 runder")
    }

    @Test func resultatlinjaMedBaner() {
        let rounds = [round(2, event: 1, no: 2, status: .locked, course: 702),
                      round(1, event: 1, no: 1, status: .locked, course: 701),
                      round(3, event: 1, no: 3, status: .locked, course: 701),
                      round(4, event: 1, no: 4, status: .draft, course: 703)]
        let names = [id(701): "Pebble Beach", id(702): "Valderrama", id(703): "St Andrews"]
        #expect(Tonight.result(rounds) { $0.courseID.flatMap { names[$0] } }
                == "Ferdig · 3 runder · Pebble Beach, Valderrama")
        #expect(Tonight.result([round(1, event: 1, status: .locked)]) == "Ferdig · 1 runde")
        #expect(Tonight.result([]) == "Ingen runder spilt")
    }

    @Test func stegeneHeter() {
        #expect(EveningStage.allCases.map(\.title) == ["Påmelding", "Oppsett", "Spilles", "Ferdig"])
    }

    @Test func kveldensDeler() {
        #expect(EveningPart.allCases.map { $0.title() } == ["Før kvelden", "Under kvelden", "Etter kvelden"])
        #expect(EveningPart.allCases.map { $0.title(.playingDay) }
            == ["Før spilledagen", "Under spilledagen", "Etter spilledagen"])
        #expect(EveningPart.current(.signup) == .before)
        #expect(EveningPart.current(.setup) == .during)
        #expect(EveningPart.current(.playing) == .during)
        #expect(EveningPart.current(.done) == .after)
        #expect(EveningPart.current(nil) == nil)
    }
}

struct KveldenForTurTests {
    private let events = [nextWeek, lastWeek, tonight, event(4, "2026-10-22")]

    @Test func kveldenIDagSelvNaarDenErFerdig() {
        #expect(Tonight.focusEvent(events, today: today, activeRound: nil) == tonight)
    }

    @Test func nesteKveldNaarIngenErIDag() {
        #expect(Tonight.focusEvent(events, today: "2026-10-09", activeRound: nil) == nextWeek)
    }

    @Test func kveldenDerEnRundeGaarVinner() {
        let live = round(10, event: 3, status: .active)
        #expect(Tonight.focusEvent(events, today: today, activeRound: live) == lastWeek)
        // Runden hører til en kveld utenfor turneringen: vanlig valg.
        let elsewhere = round(11, event: 77, status: .active)
        #expect(Tonight.focusEvent(events, today: today, activeRound: elsewhere) == tonight)
    }

    @Test func alleErPassert() {
        #expect(Tonight.focusEvent(events, today: "2026-12-01", activeRound: nil)?.id == id(4))
        #expect(Tonight.focusEvent([], today: today, activeRound: nil) == nil)
    }
}

struct TidslinjaTests {
    private let events = [nextWeek, lastWeek, tonight, event(4, "2026-09-24")]

    @Test func tidligereOverKommendeUnderEldstFoerst() {
        let parts = EveningTimeline.parts(events, focus: tonight, today: today)
        #expect(parts.past.map(\.id) == [id(4), id(3)])
        #expect(parts.focus == tonight)
        #expect(parts.upcoming.map(\.id) == [id(2)])
    }

    @Test func utenKveldenForTurDelesDetPaaIDag() {
        // «Kom i gang» står øverst: kvelden i dag står med de kommende.
        let parts = EveningTimeline.parts(events, focus: nil, today: today)
        #expect(parts.past.map(\.id) == [id(4), id(3)])
        #expect(parts.focus == nil)
        #expect(parts.upcoming.map(\.id) == [id(1), id(2)])
    }

    @Test func kveldenForTurKanVaerePassert() {
        let parts = EveningTimeline.parts(events, focus: lastWeek, today: today)
        #expect(parts.past.map(\.id) == [id(4)])
        #expect(parts.upcoming.map(\.id) == [id(1), id(2)])
    }

    @Test func turneringenVelgesMedIdEllersHovedturneringen() {
        let main = SeasonRow(id: id(800), clubID: club, name: "Høst 2026", status: .active, rules: .golfgutu)
        let cup = SeasonRow(id: id(801), clubID: club, name: "Cupen", status: .finished, rules: .golfgutu)
        #expect(Terminliste.tournament([cup, main], id: nil) == main)
        #expect(Terminliste.tournament([cup, main], id: id(801)) == cup)
        #expect(Terminliste.tournament([cup], id: nil) == nil)
        // Kveldene følger turneringen.
        let all = [event(1, today, season: 800), event(2, "2026-10-15", season: 801), event(3, "2026-10-22")]
        #expect(Terminliste.eveningsForSeason(all, activeSeasonID: id(801)).map(\.id) == [id(2), id(3)])
    }
}
