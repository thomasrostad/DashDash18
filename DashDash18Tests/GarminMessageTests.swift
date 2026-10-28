import Foundation
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Meldingene til og fra Garmin-appen. Nøklene er de `garmin/source/AttenModel.mc` leser og
/// `garmin/source/Tests.mc` bruker, så de to sidene må endres sammen.
struct GarminMessageTests {
    private let me = F.id(F.anders)

    private func round(scores: [(Int, Int, Int)] = []) -> WatchRound {
        var ps = F.markorPlayers()
        ps[0].handicap = 18
        ps[0].playing = 18
        return RoundGame(F.snapshot(ps, round: F.round(format: "stableford"), scores: scores))
            .watchRound(for: F.viewer(F.anders), now: Date(timeIntervalSince1970: 100))!
    }

    @Test func hulletMedTekstForHvertSlagantall() throws {
        let r = round(scores: [(F.bjorn, 2, 4)])
        let m = try #require(GarminMessage.hole(r, index: 2))
        #expect(m["t"] as? String == "hole")
        #expect(m["r"] as? String == F.roundID.uuidString)
        #expect(m["h"] as? Int == 2)
        #expect(m["n"] as? Int == 3)
        #expect(m["p"] as? Int == 3)
        #expect(m["c"] as? Int == 18)
        #expect(m["i"] as? Int == r.holes[2].strokeIndex)
        let rows = try #require(m["rows"] as? [[String: Any]])
        #expect(rows.count == 4)
        let anders = rows[0]
        #expect(anders["m"] as? String == me.uuidString)
        #expect(anders["me"] as? Bool == true)
        #expect(anders["e"] as? Bool == true)
        #expect(anders["lo"] as? Int == 1)
        #expect(anders["rc"] as? Int == 1)
        #expect(anders["s"] == nil)
        let texts = try #require(anders["tx"] as? [String])
        #expect(texts.count == 12)
        #expect(texts[3] == "2 p · netto par")
        #expect((anders["tn"] as? [String])?[2] == "birdie")
        // Lagret hull: «s» står.
        #expect(rows[1]["s"] as? Int == 4)
    }

    @Test func bayenNaaSomTekst() throws {
        let r = round(scores: [(F.anders, 0, 5), (F.bjorn, 0, 4)])
        let m = try #require(GarminMessage.hole(r, index: 0))
        let table = try #require(m["st"] as? [[String]])
        #expect(table.first?.count == 4)
        #expect(table.contains { $0[1] == "Anders" && $0[3] == "1" })
        #expect(table.allSatisfy { $0[0].hasSuffix(".") || $0[0] == "–" })
    }

    @Test func ukjentHullGirIngenting() {
        #expect(GarminMessage.hole(round(), index: 40) == nil)
    }

    @Test func meldingerFraKlokka() {
        let now = Date(timeIntervalSince1970: 500)
        #expect(GarminMessage.incoming(["t": "hello"], now: now) == .hello)
        #expect(GarminMessage.incoming(["t": "get", "r": F.roundID.uuidString, "h": NSNumber(value: 4)], now: now)
                == .get(roundID: F.roundID, hole: 4))
        let save: [String: Any] = ["t": "save", "r": F.roundID.uuidString, "h": NSNumber(value: 2),
                                   "sc": [[me.uuidString, NSNumber(value: 4)], [F.id(F.bjorn).uuidString, NSNumber(value: Int64(3))]]]
        #expect(GarminMessage.incoming(save, now: now) == .save(WatchHoleEntry(
            roundID: F.roundID, holeIndex: 2,
            scores: [.init(memberID: me, strokes: 4), .init(memberID: F.id(F.bjorn), strokes: 3)], recordedAt: now)))
    }

    @Test func ugyldigeMeldingerTasIkkeImot() {
        let now = Date.now
        #expect(GarminMessage.incoming("hei", now: now) == nil)
        #expect(GarminMessage.incoming(["t": "save", "r": "ikke-en-id", "h": 1, "sc": []], now: now) == nil)
        #expect(GarminMessage.incoming(["t": "save", "r": F.roundID.uuidString, "h": 1, "sc": []], now: now) == nil)
        #expect(GarminMessage.incoming(["t": "ukjent"], now: now) == nil)
    }
}
