import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture
private func id(_ n: Int) -> UUID { F.id(n) }

/// sidepremie-valgfritt-test.js: Anders, Bjørn og arrangøren Thomas Rostad. LD på hull 5
/// (indeks 4), KP på hull 3 (indeks 2). Anders 260 m drive, Bjørn 3,4 m KP.
struct MatchSidepremieTests {
    static let anders = 1, bjorn = 2, rostad = 3
    static let andersClaim = id(101), bjornClaim = id(102)

    static func game(ld: Bool = true, kp: Bool = true, status: RoundStatus = .active,
                     claims: [(UUID, Int, SideClaimKind, Double)]? = nil, rules: Ruleset = .golfgutu) -> RoundGame {
        var round = F.round(status: status)
        round.ldEnabled = ld
        round.kpEnabled = kp
        round.ldHoleIndex = 4
        round.kpHoleIndex = 2
        var s = F.snapshot([F.P(n: anders, name: "Anders", handicap: 8), F.P(n: bjorn, name: "Bjørn", handicap: 12),
                            F.P(n: rostad, name: "Thomas Rostad", handicap: 15)], round: round)
        s.rules = rules
        let list = claims ?? [(andersClaim, anders, .drive, 260), (bjornClaim, bjorn, .kp, 3.4)]
        s.sideClaims = list.map { c in
            SideClaimRow(id: c.0, roundID: F.roundID, memberID: id(c.1), kind: c.2, meters: c.3,
                         holeIndex: c.2 == .drive ? 4 : 2)
        }
        return RoundGame(s)
    }

    static let me = Viewer(memberID: id(anders), isOrganizer: false)
    static let organizer = Viewer(memberID: id(rostad), isOrganizer: true)

    // MARK: Boksen

    @Test func boksenStaarPaaRiktigHull() {
        let g = Self.game()
        #expect(g.sidePrizeBox(.drive, hole: 4, viewer: Self.me) != nil)
        #expect(g.sidePrizeBox(.drive, hole: 2, viewer: Self.me) == nil)
        #expect(g.sidePrizeBox(.kp, hole: 2, viewer: Self.me) != nil)
        #expect(g.sidePrizeBox(.kp, hole: 4, viewer: Self.me) == nil)
    }

    @Test func avPremieHarIngenBoks() {
        let g = Self.game(ld: false)
        #expect(g.sidePrizeBox(.drive, hole: 4, viewer: Self.me) == nil)
        #expect(g.sidePrizeBox(.kp, hole: 2, viewer: Self.me) != nil)
        #expect(Self.game(kp: false).sidePrizeBox(.kp, hole: 2, viewer: Self.me) == nil)
    }

    @Test func lederenMedMeter() {
        let g = Self.game()
        let ld = g.sidePrizeBox(.drive, hole: 4, viewer: Self.me)
        #expect(ld?.title == "Longest drive nå")
        #expect(ld?.leader == "260 m · Anders")
        #expect(ld?.tieNote == nil)
        #expect(ld?.lines.first?.isMe == true)
        let kp = g.sidePrizeBox(.kp, hole: 2, viewer: Self.me)
        #expect(kp?.title == "Nærmest pinnen nå")
        #expect(kp?.leader == "3,4 m · Bjørn")
    }

    @Test func ingenEnna() {
        let box = Self.game(claims: []).sidePrizeBox(.drive, hole: 4, viewer: Self.me)
        #expect(box?.leader == "Ingen ennå")
        #expect(box?.lines.isEmpty == true)
    }

    @Test func driveLengstForstKpNaermestForst() {
        let g = Self.game(claims: [(id(201), Self.anders, .drive, 240), (id(202), Self.bjorn, .drive, 262.5),
                                   (id(203), Self.anders, .kp, 5.1), (id(204), Self.bjorn, .kp, 1.2)])
        let ld = g.sidePrizeBox(.drive, hole: 4, viewer: Self.me)
        #expect(ld?.lines.map(\.name) == ["Bjørn", "Anders"])
        #expect(ld?.lines.map(\.meters) == ["262,5 m", "240 m"])
        #expect(ld?.lines.map(\.isLeader) == [true, false])
        let kp = g.sidePrizeBox(.kp, hole: 2, viewer: Self.me)
        #expect(kp?.lines.map(\.name) == ["Bjørn", "Anders"])
        #expect(kp?.leader == "1,2 m · Bjørn")
    }

    @Test func liktDelerPoenget() {
        // Golfgutu: 1 poeng, delt ved likt → 0,5 hver.
        let g = Self.game(claims: [(id(201), Self.anders, .drive, 250), (id(202), Self.bjorn, .drive, 250)])
        let box = g.sidePrizeBox(.drive, hole: 4, viewer: Self.me)
        #expect(box?.leader == "250 m · Anders og Bjørn")
        #expect(box?.tieNote == "Delt · 0,5 poeng hver")
        #expect(box?.lines.allSatisfy(\.isLeader) == true)
    }

    @Test func liktUtenDelingGirFulltPoeng() {
        var rules = Ruleset.golfgutu
        rules.sidePrizes.splitTies = false
        rules.sidePrizes.longestDrive.points = 2
        let g = Self.game(claims: [(id(201), Self.anders, .drive, 250), (id(202), Self.bjorn, .drive, 250)],
                          rules: rules)
        #expect(g.sidePrizeBox(.drive, hole: 4, viewer: Self.me)?.tieNote == "Delt · 2 poeng hver")
    }

    // MARK: Hvem kan melde inn

    @Test func spillerenMelderForSegSelv() {
        let box = Self.game().sidePrizeBox(.drive, hole: 4, viewer: Self.me)
        #expect(box?.canClaim == true)
        #expect(box?.claimants == [id(Self.anders)])
        #expect(box?.lines.first { $0.memberID == id(Self.anders) }?.canDelete == true)
        let bjorn = Self.game().sidePrizeBox(.kp, hole: 2, viewer: Self.me)
        #expect(bjorn?.lines.first?.canDelete == false)
    }

    @Test func arrangorenMelderForAlle() {
        let box = Self.game().sidePrizeBox(.drive, hole: 4, viewer: Self.organizer)
        #expect(box?.claimants == [id(Self.anders), id(Self.bjorn), id(Self.rostad)])
        #expect(box?.lines.allSatisfy(\.canDelete) == true)
    }

    @Test func laastRundeBareArrangoren() {
        let g = Self.game(status: .locked)
        #expect(g.sidePrizeBox(.drive, hole: 4, viewer: Self.me)?.canClaim == false)
        #expect(g.sidePrizeBox(.drive, hole: 4, viewer: Self.organizer)?.canClaim == true)
    }

    @Test func ikkeMedIRundenKanIkkeMelde() {
        let outsider = Viewer(memberID: id(99), isOrganizer: false)
        let box = Self.game().sidePrizeBox(.drive, hole: 4, viewer: outsider)
        #expect(box?.canClaim == false)
        #expect(box?.claimants.isEmpty == true)
    }

    // MARK: Innmeldingen

    @Test func nyInnmelding() throws {
        let g = Self.game(claims: [])
        let draft = try g.sideClaimDraft(.drive, member: id(Self.anders), text: "245", viewer: Self.me).get()
        #expect(draft.meters == 245)
        #expect(draft.holeIndex == 4)
        #expect(draft.kind == .drive)
        #expect(draft.existing == nil)
    }

    @Test func rettelseErSammeRad() throws {
        let draft = try Self.game().sideClaimDraft(.drive, member: id(Self.anders), text: "262,5", viewer: Self.me).get()
        #expect(draft.meters == 262.5)
        #expect(draft.existing == Self.andersClaim)
    }

    @Test func ugyldigeMeterGirHint() {
        let r = Self.game().sideClaimDraft(.kp, member: id(Self.anders), text: "0", viewer: Self.me)
        #expect(r == .failure(.invalid(MeterInput.hint)))
    }

    @Test func ikkeForAndreUtenArrangor() {
        let r = Self.game().sideClaimDraft(.kp, member: id(Self.bjorn), text: "2", viewer: Self.me)
        #expect(r == .failure(.notAllowed))
        let ok = Self.game().sideClaimDraft(.kp, member: id(Self.bjorn), text: "2", viewer: Self.organizer)
        #expect((try? ok.get())?.existing == Self.bjornClaim)
    }

    @Test func premienAvGirFeil() {
        let r = Self.game(ld: false).sideClaimDraft(.drive, member: id(Self.anders), text: "200", viewer: Self.me)
        #expect(r == .failure(.invalid("Runden har ikke longest drive.")))
    }

    @Test func svaretFraServerenErstatterRaden() {
        var s = Self.game().snapshot
        s.apply(claim: SideClaimRow(id: Self.andersClaim, roundID: F.roundID, memberID: id(Self.anders),
                                    kind: .drive, meters: 270, holeIndex: 4))
        #expect(s.sideClaims.count == 2)
        #expect(RoundGame(s).sidePrizeBox(.drive, hole: 4, viewer: Self.me)?.leader == "270 m · Anders")
        s.removeClaim(Self.andersClaim)
        #expect(RoundGame(s).sidePrizeBox(.drive, hole: 4, viewer: Self.me)?.leader == "Ingen ennå")
    }
}

/// Meter fra tastaturet: komma eller punktum, én desimal, 0 < m ≤ 500.
struct MatchMeterInputTests {
    @Test(arguments: [
        ("3,4", 3.4), ("3.4", 3.4), ("245", 245), (" 12 m", 12), ("500", 500), ("0,1", 0.1),
        ("3,45", 3.5), ("262,54", 262.5), ("0,05", 0.1),
    ])
    func gyldige(text: String, meters: Double) {
        #expect(MeterInput.parse(text) == meters)
    }

    @Test(arguments: ["", "0", "0,0", "0,04", "-3", "500,1", "501", "abc", "1.2.3", "3,4,5", "1e2", "∞"])
    func ugyldige(text: String) {
        #expect(MeterInput.parse(text) == nil)
    }

    @Test func tilFeltet() {
        #expect(MeterInput.text(3.4) == "3,4")
        #expect(MeterInput.text(245) == "245")
    }
}
