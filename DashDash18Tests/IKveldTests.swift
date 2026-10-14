import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// V12 og 4.4 (UI-utbedringen): «I kveld» på arrangørsiden. Båsene (hull, fremdrift, synkstatus),
// sidepremiene, det som gjenstår før «Ferdig» og påmeldingslinja.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)
private let date = "2026-10-13"
/// 13. oktober 2026 kl. 20:00 i Oslo.
private let now = EveningDates.time(from: "20:00", on: EveningDates.date(from: date)!)!

private func round(holes: Int = 18, firstHole: Int = 1, cutAfter: Int? = nil, teeTime: String? = "18:00:00",
                   venue: String? = nil, kp: Int? = 6, ld: Int? = 17) -> RoundRow {
    RoundRow(id: id(1), clubID: club, eventID: id(2), courseID: nil, roundNo: 1, name: nil, status: .active,
             holeCount: holes, firstHole: firstHole, teeTime: teeTime, format: "stableford", handicapAllowance: 1,
             externalHandicap: false, weight: 1, ldEnabled: ld != nil, ldHoleIndex: ld, kpEnabled: kp != nil,
             kpHoleIndex: kp, cutRule: nil, cutAfter: cutAfter, parConfirmedBy: nil, parConfirmedAt: nil,
             startedAt: nil, lockedAt: nil, venue: venue)
}

private func player(_ member: Int, bay: Int) -> RoundPlayerRow {
    RoundPlayerRow(roundID: id(1), memberID: id(member), clubID: club, handicapIndex: 10, seedGroup: nil,
                   playingHandicap: 10, bayNo: bay, isMarker: false, teamNo: nil)
}

/// Slag for spillerne på hullene, sist ført `minutesAgo` minutter før `now`.
private func scores(_ members: [Int], holes: Range<Int>, minutesAgo: Double?) -> [HoleScoreRow] {
    members.flatMap { m in
        holes.map { h in
            HoleScoreRow(roundID: id(1), memberID: id(m), holeIndex: h, strokes: 4,
                         recordedAt: minutesAgo.map { now.addingTimeInterval(-$0 * 60) }, updatedBy: nil, updatedAt: nil)
        }
    }
}

private func bays(_ round: RoundRow, players: [RoundPlayerRow], scores: [HoleScoreRow],
                  groups: [StartGroupDraft] = []) -> [BayLive] {
    TonightLive.bays(round: round, eventDate: date, players: players, scores: scores, groups: groups,
                     name: { "Spiller \($0.uuidString.suffix(2))" }, scorerName: { _ in "Bjørn" }, now: now)
}

struct IKveldBasTests {
    @Test func hullOgFremdrift() {
        let players = [player(11, bay: 1), player(12, bay: 1), player(21, bay: 2)]
        // Bås 1: hull 1–13 ført for begge, hull 14 bare for én. Bås 2: ingenting.
        let all = scores([11, 12], holes: 0..<13, minutesAgo: 2) + scores([11], holes: 13..<14, minutesAgo: 1)
        let result = bays(round(), players: players, scores: all)
        #expect(result.map(\.groupNo) == [1, 2])
        #expect(result[0].holesDone == 13)
        #expect(result[0].currentHole == 14)
        #expect(TonightLive.holeText(result[0]) == "Hull 14")
        #expect(abs(result[0].fraction - 13.0 / 18.0) < 0.0001)
        #expect(result[0].title == "Bås 1")
        #expect(result[0].startsAt == "18:00")
        #expect(result[1].currentHole == nil)
        #expect(TonightLive.holeText(result[1]) == "Ikke startet")
    }

    @Test func synketOgRust() {
        let players = [player(11, bay: 1), player(21, bay: 2)]
        let all = scores([11], holes: 0..<5, minutesAgo: 2) + scores([21], holes: 0..<5, minutesAgo: 18)
        let result = bays(round(), players: players, scores: all)
        #expect(result[0].sync == .synced(minutes: 2))
        #expect(TonightLive.syncText(result[0].sync) == "Synket for 2 min siden")
        #expect(result[1].sync == .stale(minutes: 18))
        #expect(result[1].sync.isWarning)
        #expect(TonightLive.syncText(result[1].sync) == "Ingen data på 18 min")
    }

    @Test func rettetScoreTellerSomSisteData() {
        var row = scores([11], holes: 0..<1, minutesAgo: 40)[0]
        row.updatedAt = now.addingTimeInterval(-3 * 60)
        #expect(TonightLive.sync(scores: [row], isFinished: false, start: nil, now: now) == .synced(minutes: 3))
    }

    @Test func starterSenere() {
        let players = [player(31, bay: 3)]
        let group = StartGroupDraft(groupNo: 3, startsAt: "20:25", startHole: 1, resourceLabel: "Bås 3", scorerID: nil,
                                    memberIDs: [id(31)])
        let result = bays(round(), players: players, scores: [], groups: [group])
        #expect(result[0].sync == .startsIn(minutes: 25))
        #expect(TonightLive.syncText(result[0].sync, startsAt: "20:25") == "Om 25 min")
        #expect(TonightLive.syncText(.startsIn(minutes: 90), startsAt: "21:30") == "Starter 21:30")
    }

    @Test func startetUtenDataBlirRustEtterGrensen() {
        let players = [player(11, bay: 1)]
        // Tee-tid 18:00, ingen scorer kl. 20:00.
        #expect(bays(round(), players: players, scores: [])[0].sync == .stale(minutes: 120))
        #expect(bays(round(teeTime: "19:50:00"), players: players, scores: [])[0].sync == .waiting)
        // Uten starttid og uten scorer: ingen linje.
        #expect(bays(round(teeTime: nil), players: players, scores: [])[0].sync == .unknown)
        #expect(TonightLive.syncText(.unknown) == nil)
    }

    @Test func scorerUtenTidGirIngenLinje() {
        let all = scores([11], holes: 0..<3, minutesAgo: nil)
        #expect(bays(round(), players: [player(11, bay: 1)], scores: all)[0].sync == .unknown)
    }

    @Test func ferdigEtterAvkorting() {
        let all = scores([11], holes: 0..<12, minutesAgo: 30)
        let result = bays(round(cutAfter: 12), players: [player(11, bay: 1)], scores: all)
        #expect(result[0].holeCount == 12)
        #expect(result[0].isFinished)
        #expect(result[0].sync == .finished)
        #expect(TonightLive.holeText(result[0]) == "Ferdig")
    }

    @Test func kanonstartOgSisteNi() {
        // Starter på hull 10 av 18: etter tre ferdige hull står båsen på hull 13.
        let done: Set<Int> = [9, 10, 11]
        #expect(TonightLive.currentHole(done: done, holes: 18, startHole: 10, firstHole: 1, hasScores: true) == 13)
        // Rundt: hull 18 ferdig fra start på 18 gir hull 1.
        #expect(TonightLive.currentHole(done: [17], holes: 18, startHole: 18, firstHole: 1, hasScores: true) == 1)
        // «Siste ni» (firstHole 10): indeks 0 er hull 10.
        #expect(TonightLive.currentHole(done: [0, 1], holes: 9, startHole: nil, firstHole: 10, hasScores: true) == 12)
    }

    @Test func funksjonarOgNavnFraStartlista() {
        let group = StartGroupDraft(groupNo: 2, startsAt: "18:10", startHole: 1, resourceLabel: "Simulator 2",
                                    scorerID: id(77), memberIDs: [id(21)])
        let result = bays(round(), players: [player(21, bay: 2)], scores: [], groups: [group])
        #expect(result[0].title == "Simulator 2")
        #expect(result[0].scorer == "Bjørn")
        #expect(result[0].startsAt == "18:10")
    }

    @Test func flightPaBane() {
        let result = bays(round(venue: "course"), players: [player(11, bay: 1)], scores: [])
        #expect(result[0].title == "Flight 1")
    }

    @Test func formOgBaser() {
        let players = (0..<12).map { player(10 + $0, bay: $0 / 3 + 1) }
        let result = bays(round(), players: players, scores: [])
        #expect(TonightLive.shapeText(formatName: "Stableford", venue: nil, bays: result) == "Stableford · 4 båser à 3")
        let uneven = bays(round(), players: Array(players.prefix(11)), scores: [])
        #expect(TonightLive.shapeText(formatName: "Stableford", venue: nil, bays: uneven)
                == "Stableford · 4 båser · 11 spillere")
    }

    @Test func varighet() {
        #expect(TonightLive.durationText(18) == "18 min")
        #expect(TonightLive.durationText(65) == "1 t 5 min")
        #expect(TonightLive.durationText(120) == "2 t")
        #expect(TonightLive.syncText(.synced(minutes: 0)) == "Synket nå")
    }
}

struct IKveldGjenstarTests {
    private func claim(_ kind: SideClaimKind) -> SideClaimRow {
        SideClaimRow(id: UUID(), roundID: id(1), memberID: id(11), kind: kind, meters: 2, holeIndex: nil)
    }

    @Test func sidepremierIRekkefolge() {
        let prizes = TonightLive.sidePrizes(round(), claims: [claim(.kp)])
        #expect(prizes.map(\.title) == ["Nærmest pinnen", "Lengste drive"])
        #expect(prizes.map(\.hole) == [7, 18])
        #expect(prizes[0].statusText == "1 innmeldt")
        #expect(prizes[1].statusText == "Ingen innmeldt ennå")
        #expect(TonightLive.sidePrizes(round(kp: nil, ld: nil), claims: []).isEmpty)
    }

    @Test func gjenstarForFerdig() {
        let players = [player(11, bay: 1), player(21, bay: 2)]
        let all = scores([11], holes: 0..<18, minutesAgo: 5) + scores([21], holes: 0..<11, minutesAgo: 5)
        let result = bays(round(), players: players, scores: all)
        let prizes = TonightLive.sidePrizes(round(), claims: [claim(.kp)])
        let items = TonightLive.remaining(bays: result, prizes: prizes, term: .evening, groupTerm: .bay)
        #expect(items.map(\.title) == ["Alle hull ført", "Nærmest pinnen meldt inn", "Lengste drive meldt inn",
                                       "Avslutt kvelden"])
        #expect(items.map(\.isDone) == [false, true, false, false])
        #expect(items[0].detail == "Bås 2 har 7 hull igjen")
        #expect(items[2].detail == "Hull 18")
    }

    @Test func flereBaserIgjen() {
        let players = [player(11, bay: 1), player(21, bay: 2)]
        let items = TonightLive.remaining(bays: bays(round(), players: players, scores: []), prizes: [],
                                          term: .playingDay, groupTerm: .bay)
        #expect(items[0].detail == "2 båser har hull igjen")
        #expect(items.last?.title == "Avslutt spilledagen")
    }
}

struct IKveldPameldingTests {
    @Test func oppfolging() {
        #expect(TonightLive.signupFollowUp(notAnswered: ["Nils"], maybe: ["Magne"])
                == "Nils har ikke svart. Magne er usikker.")
        #expect(TonightLive.signupFollowUp(notAnswered: ["Nils", "Ola"], maybe: ["Magne", "Per"])
                == "Nils og Ola har ikke svart. Magne og Per er usikre.")
        #expect(TonightLive.signupFollowUp(notAnswered: ["A", "B", "C", "D", "E"], maybe: [])
                == "A, B og 3 til har ikke svart.")
        #expect(TonightLive.signupFollowUp(notAnswered: [], maybe: []) == nil)
        #expect(TonightLive.comingText(coming: 12, roster: 14) == "12 av 14 kommer")
    }

    @Test func stegtekst() {
        #expect(EveningStepsText.title(EveningStepMark(stage: .playing, state: .current)) == "Spilles nå")
        #expect(EveningStepsText.title(EveningStepMark(stage: .playing, state: .upcoming)) == "Spilles")
        #expect(EveningStepsText.title(EveningStepMark(stage: .signup, state: .done)) == "Påmelding")
    }
}
