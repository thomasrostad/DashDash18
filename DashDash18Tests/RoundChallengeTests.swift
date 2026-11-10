import Foundation
import Testing
@testable import DashDash18

/// «Challenge etter runden» (I kveld): grunnene og gruppene som blir tilleggspoeng. Samme tall som
/// adminpanelet (web/admin/test/challenge.test.ts).
struct RoundChallengeTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID()
    private var players: [(memberID: UUID, group: Int)] { [(a, 1), (b, 2), (c, 1), (d, 2)] }

    @Test func grunnenHarSammeFormSom2210() {
        #expect(RoundChallenge.reason("CP knockout", round: 1, scope: .group, term: .bay, groupNo: 1) == "CP knockout, bås 1")
        #expect(RoundChallenge.reason("CP knockout", round: 2, scope: .group, term: .bay, groupNo: 2) == "CP knockout runde 2, bås 2")
        #expect(RoundChallenge.reason("CTP", round: 1, scope: .group, term: .flight, groupNo: 3) == "CTP, flight 3")
        #expect(RoundChallenge.reason("  CTP  ", round: 1, scope: .all, term: .bay, groupNo: 0) == "CTP")
        #expect(RoundChallenge.reason("CTP", round: 3, scope: .all, term: .bay, groupNo: 0) == "CTP runde 3")
        // Høyst 80 tegn: navnet kortes, halen står.
        let long = RoundChallenge.reason(String(repeating: "x", count: 100), round: 2, scope: .group, term: .bay, groupNo: 1)
        #expect(long.count == 80)
        #expect(long.hasSuffix(" runde 2, bås 1"))
    }

    @Test func enVinnerPerBasEllerHeleRunden() {
        let g = RoundChallenge.groups(.standard, players: players, term: .bay)
        #expect(g.map(\.no) == [1, 2])
        #expect(g.map(\.title) == ["Bås 1", "Bås 2"])
        #expect(g.map(\.members) == [[a, c], [b, d]])
        #expect(g.map(\.reason) == ["CP knockout, bås 1", "CP knockout, bås 2"])

        var whole = ChallengeSetup.standard
        whole.scope = .all
        let all = RoundChallenge.groups(whole, players: players, term: .bay)
        #expect(all.map(\.no) == [0])
        #expect(all.map(\.title) == ["Hele runden"])
        #expect(all.map(\.members.count) == [4])
        #expect(all.map(\.reason) == ["CP knockout"])

        let noBays = RoundChallenge.groups(.standard, players: players.map { ($0.memberID, 0) }, term: .bay)
        #expect(noBays.map(\.title) == ["Hele runden"])
        let someWithout = RoundChallenge.groups(.standard, players: players + [(e, 0)], term: .bay)
        #expect(someWithout.map(\.title) == ["Bås 1", "Bås 2", "Uten bås"])
    }

    @Test func navnOgPoengMaVaereIOrden() {
        var s = ChallengeSetup.standard
        #expect(RoundChallenge.problem(s) == nil)
        s.name = " "
        #expect(RoundChallenge.problem(s) == "Gi challengen et navn.")
        s = .standard
        s.points = 0
        #expect(RoundChallenge.problem(s) == "Vinneren må få mer enn 0 poeng.")
        s.points = 0.125
        #expect(RoundChallenge.problem(s) == "Poengene kan ha høyst to desimaler.")
    }

    @Test func fortsetterPaRundenDereVarPa() {
        #expect(RoundChallenge.lastRound(.standard, players: players, term: .bay, reasons: []) == 0)
        #expect(RoundChallenge.lastRound(.standard, players: players, term: .bay, reasons: ["CP knockout, bås 2"]) == 1)
        #expect(RoundChallenge.lastRound(.standard, players: players, term: .bay,
                                         reasons: ["CP knockout, bås 1", "CP knockout runde 2, bås 1", "Noe annet"]) == 2)
    }

    @Test func tilleggspoengGarIKvartePoeng() {
        #expect(Tilleggspoeng.step == 0.25)
        #expect(RoundChallenge.step == Tilleggspoeng.step)
    }
}
