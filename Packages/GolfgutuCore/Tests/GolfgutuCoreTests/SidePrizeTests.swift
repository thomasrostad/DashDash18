import Foundation
import Testing
@testable import GolfgutuCore

/// Longest drive og nærmest pinnen. Tall: Fixtures/sidepremier.json, regnet ut av db-nytt.js
/// (hullsakene fra sidepremie-valgfritt-test.js; innmeldinger, lik lengde og sesonglister er egne).
struct SidePrizeTests {
    struct Fil: Decodable {
        let hull: [Hull]
        let claims: [SideClaim]
        let runder: [RundeClaims]
        let sesong: Sesong
        let fmtMeter: [Meter]
    }
    struct Hull: Decodable {
        let navn: String
        let runde: Round
        let harLongestDrive, harKp: Bool
        let longestDriveHullFor, kpHullFor, foreslaattLongestDriveHull, foreslaattKpHull: Int
    }
    struct RundeClaims: Decodable {
        let runde: Round
        let longestDrive, kp: [String]
        let vinnereLongestDrive, vinnereKp: [String]
    }
    struct Sesong: Decodable { let longestDrive, kp: [String] }
    struct Meter: Decodable {
        let meter: Double, tekst: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            meter = try c.decode(Double.self)
            tekst = try c.decode(String.self)
        }
    }

    let fil: Fil

    init() throws {
        fil = try Fixture.load(Fil.self, "sidepremier")
    }

    @Test func hullene() {
        for h in fil.hull {
            let r = h.runde
            #expect(SidePrizes.hasLongestDrive(r) == h.harLongestDrive, "\(h.navn)")
            #expect(SidePrizes.hasClosestToPin(r) == h.harKp, "\(h.navn)")
            #expect((SidePrizes.longestDriveHole(r) ?? -1) == h.longestDriveHullFor, "\(h.navn): LD-hull")
            #expect((SidePrizes.closestToPinHole(r) ?? -1) == h.kpHullFor, "\(h.navn): KP-hull")
            #expect(SidePrizes.suggestedLongestDriveHole(r) == h.foreslaattLongestDriveHull, "\(h.navn): LD-forslag")
            #expect(SidePrizes.suggestedClosestToPinHole(r) == h.foreslaattKpHull, "\(h.navn): KP-forslag")
        }
    }

    /// sidepremie-valgfritt-test.js §1: uten feltene er begge med; av gir ikke noe hull.
    @Test func valgfrittSomPWA() {
        #expect(SidePrizes.hasLongestDrive(Round()) && SidePrizes.hasClosestToPin(Round()))
        let ldAv = Round(ldEnabled: false, ldHoleIndex: 4, kpHoleIndex: 2)
        #expect(SidePrizes.longestDriveHole(ldAv) == nil && SidePrizes.closestToPinHole(ldAv) == 2)
        let kpAv = Round(kpEnabled: false, ldHoleIndex: 4, kpHoleIndex: 2)
        #expect(SidePrizes.closestToPinHole(kpAv) == nil && SidePrizes.longestDriveHole(kpAv) == 4)
        // §2: innmeldinger på en runde uten premiene teller ikke.
        let claims = [SideClaim(id: "c1", kind: .drive, playerId: "a", roundId: "r1", meters: 260, ts: "1"),
                      SideClaim(id: "c2", kind: .kp, playerId: "b", roundId: "r1", meters: 3.4, ts: "2")]
        let av = Round(id: "r1", ldEnabled: false, kpEnabled: false)
        #expect(SidePrizes.longestDriveClaims(av, claims: claims).isEmpty)
        #expect(SidePrizes.closestToPinClaims(av, claims: claims).isEmpty)
        let paa = Round(id: "r1")
        #expect(SidePrizes.winners(SidePrizes.longestDriveClaims(paa, claims: claims)) == ["a"])
        #expect(SidePrizes.winners(SidePrizes.closestToPinClaims(paa, claims: claims)) == ["b"])
    }

    @Test func innmeldingerOgVinnere() {
        for rc in fil.runder {
            let r = rc.runde
            let ld = SidePrizes.longestDriveClaims(r, claims: fil.claims)
            let kp = SidePrizes.closestToPinClaims(r, claims: fil.claims)
            #expect(ld.map { $0.id ?? "" } == rc.longestDrive, "\(r.id ?? ""): LD")
            #expect(kp.map { $0.id ?? "" } == rc.kp, "\(r.id ?? ""): KP")
            #expect(SidePrizes.winners(ld) == rc.vinnereLongestDrive, "\(r.id ?? ""): LD-vinnere")
            #expect(SidePrizes.winners(kp) == rc.vinnereKp, "\(r.id ?? ""): KP-vinnere")
            #expect(SidePrizes.claims(.drive, in: r, claims: fil.claims) == ld)
        }
        // Egen: lik lengde deler (272,5 m to ganger i r1, 2 m to ganger i KP i r2). Lista sorterer
        // den som meldte først øverst, men begge er vinnere.
        #expect(fil.runder[0].vinnereLongestDrive == ["c", "b"])
        #expect(fil.runder[1].vinnereKp == ["a", "d"])
    }

    @Test func sesonglister() {
        #expect(SidePrizes.seasonLongestDrive(fil.claims).map { $0.id ?? "" } == fil.sesong.longestDrive)
        #expect(SidePrizes.seasonClosestToPin(fil.claims).map { $0.id ?? "" } == fil.sesong.kp)
        // besteClaimPerSpiller: én per spiller, i rekkefølgen de dukker opp.
        let beste = SidePrizes.bestClaimPerPlayer(fil.claims.filter { $0.kind == .drive }, isBetter: >)
        #expect(beste.map(\.playerId) == ["a", "b", "c", "d"])
        #expect(beste.map(\.meters) == [280, 300, 272.5, 240])
    }

    @Test func fmtMeter() {
        for m in fil.fmtMeter {
            #expect(SidePrizes.formatMeters(m.meter) == m.tekst, "\(m.meter)")
        }
        #expect(SideClaim.Kind.drive.label == "Longest drive")
        #expect(SideClaim.Kind.kp.label == "Nærmest pinnen")
    }
}
