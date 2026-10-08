import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 11: Kveldene og Kvelden på arrangørsiden.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)

private func round(_ n: Int, no: Int = 1, status: RoundStatus, players: Int = 0, firstHole: Int = 1,
                   teeTime: String? = nil, venue: String? = nil) -> RoundRow {
    RoundRow(id: id(n), clubID: club, eventID: id(500), courseID: id(701), roundNo: no, name: nil,
             status: status, holeCount: 18, firstHole: firstHole, teeTime: teeTime, format: "stableford",
             handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: true, ldHoleIndex: nil,
             kpEnabled: true, kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
             parConfirmedAt: nil, startedAt: nil, lockedAt: nil, venue: venue)
}

private func member(_ n: Int, _ name: String) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: name, handicapIndex: 10, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

private func signup(_ n: Int, _ status: SignupStatus) -> SignupRow {
    SignupRow(eventID: id(500), memberID: id(n), clubID: club, status: status, comment: nil)
}

struct KveldeneRundestatusTests {
    @Test func ingenRunder() {
        #expect(EveningRounds.phase([]) == .none)
        #expect(EveningRounds.text([]) == "Ingen runder")
    }

    @Test func enRundeGaar() {
        let rounds = [round(1, no: 1, status: .active), round(2, no: 2, status: .draft)]
        #expect(EveningRounds.phase(rounds) == .active)
        #expect(EveningRounds.text(rounds) == "2 runder · 1 pågår · 1 kladd")
        #expect(EveningRounds.text([round(1, status: .locked), round(2, no: 2, status: .active)]) == "2 runder · 1 pågår")
    }

    @Test func bareKladder() {
        #expect(EveningRounds.phase([round(1, status: .draft)]) == .draft)
        #expect(EveningRounds.text([round(1, status: .draft)]) == "1 runde · 1 kladd")
        let mixed = [round(1, status: .locked), round(2, no: 2, status: .draft), round(3, no: 3, status: .draft)]
        #expect(EveningRounds.phase(mixed) == .draft)
        #expect(EveningRounds.text(mixed) == "3 runder · 2 kladder")
    }

    @Test func ferdigNaarAlleErLaast() {
        let rounds = [round(1, status: .locked), round(2, no: 2, status: .locked)]
        #expect(EveningRounds.phase(rounds) == .done)
        #expect(EveningRounds.text(rounds) == "Ferdig")
    }
}

struct KveldenPaameldingTests {
    private let roster = [member(1, "Anders"), member(2, "Bjørn"), member(3, "Cato"), member(4, "Dag")]

    @Test func gruppeneSomHarNoen() {
        let summary = SignupSummary(members: roster, signups: [signup(1, .yes), signup(2, .yes), signup(3, .maybe)])
        let groups = EveningSignup.groups(summary)
        #expect(groups.map(\.title) == ["Kommer", "Usikker", "Ikke svart"])
        #expect(groups.map(\.names) == [["Anders", "Bjørn"], ["Cato"], ["Dag"]])
    }

    @Test func purringBareForKommendeKvelderMedManglendeSvar() {
        let missing = SignupSummary(members: roster, signups: [signup(1, .yes)])
        #expect(EveningSignup.offersNudge(eventDate: "2026-10-08", today: "2026-10-08", summary: missing))
        #expect(EveningSignup.offersNudge(eventDate: "2026-10-15", today: "2026-10-08", summary: missing))
        #expect(!EveningSignup.offersNudge(eventDate: "2026-10-01", today: "2026-10-08", summary: missing))
        let all = SignupSummary(members: roster, signups: (1...4).map { signup($0, .no) })
        #expect(!EveningSignup.offersNudge(eventDate: "2026-10-15", today: "2026-10-08", summary: all))
    }
}

struct RundeRadTests {
    @Test func undertekstenTilRunden() {
        #expect(RoundListing.subtitle(round(1, status: .draft), players: 0, bays: 0) == "18 hull · Stableford (netto)")
        #expect(RoundListing.subtitle(round(1, status: .active, firstHole: 10, teeTime: "18:30:00"), players: 12, bays: 3)
                == "18 hull fra hull 10 · Stableford (netto) · 12 med · 3 båser · 18:30")
    }

    @Test func nyRundeBareForKvelderSomIkkeErPassert() {
        let past = EventRow(id: id(1), clubID: club, seasonID: nil, eventDate: "2026-10-01", startTime: nil, venue: nil, note: nil)
        let next = EventRow(id: id(2), clubID: club, seasonID: nil, eventDate: "2026-10-08", startTime: nil, venue: nil, note: nil)
        #expect(!RoundGroups.allowsNewRound(past, today: "2026-10-08"))
        #expect(RoundGroups.allowsNewRound(next, today: "2026-10-08"))
    }
}
