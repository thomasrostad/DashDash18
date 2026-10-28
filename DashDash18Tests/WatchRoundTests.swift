import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Klokka får runden ferdig regnet fra telefonen: hullkortet med tekst for hvert slagantall, og «Bayen nå».
/// Anders er markør i bås 1 og har spillehandicap 18 (ett slag per hull), som i `SpillformRundeTests`.
struct WatchRoundTests {
    private let me = F.id(F.anders)

    private func players() -> [F.P] {
        var ps = F.markorPlayers()
        ps[0].handicap = 18
        ps[0].playing = 18
        return ps
    }

    private func game(_ format: String = "stableford", scores: [(Int, Int, Int)] = []) -> RoundGame {
        RoundGame(F.snapshot(players(), round: F.round(format: format), scores: scores))
    }

    private func round(_ format: String = "stableford", scores: [(Int, Int, Int)] = []) -> WatchRound {
        game(format, scores: scores).watchRound(for: F.viewer(F.anders), now: Date(timeIntervalSince1970: 100))!
    }

    /// Anders sin rad på hull 3 (par 3).
    private func myRow(_ r: WatchRound) -> WatchRound.Row {
        r.holes[2].rows.first { $0.memberID == me }!
    }

    @Test func helRundeMedBaasenPaaKortet() {
        let r = round()
        #expect(r.roundID == F.roundID)
        #expect(r.title == "Testbanen")
        #expect(r.holes.count == 18)
        #expect(r.currentHole == 0)
        #expect(r.holes[2].number == 3)
        #expect(r.holes[2].par == 3)
        // Markøren fører hele båsen.
        #expect(r.holes[2].rows.map(\.name) == ["Anders", "Bjørn", "Cato", "Dag"])
        #expect(r.holes[2].rows.filter(\.editable).count == 4)
        #expect(myRow(r).strokesReceived == 1)
        // Forvalget er par, ingenting er lagret.
        #expect(myRow(r).value == 3)
        #expect(myRow(r).saved == nil)
    }

    /// Teksten for hvert slagantall er den hullkortet viser for samme tall.
    @Test func tekstenErHullkortets() {
        let g = game()
        let row = myRow(round())
        #expect(row.options.map(\.strokes) == Array(1...12))
        for strokes in [2, 3, 4, 7] {
            var drafts = HoleDrafts()
            drafts[2, me] = strokes
            let card = g.card(hole: 2, drafts: drafts, viewer: F.viewer(F.anders)).rows.first { $0.memberID == me }!
            #expect(row.option(strokes)?.text == card.formText)
            #expect(row.option(strokes)?.tone == card.scoreName?.rawValue)
        }
        #expect(row.option(4)?.text == "2 p · netto par")
        #expect(row.option(4)?.tone == "par")
    }

    @Test func slagspillBruttoViserBruttoNavn() {
        #expect(myRow(round("slag-brutto")).option(4)?.text == "brutto bogey")
        #expect(myRow(round("slag-brutto")).strokesReceived == 0)
    }

    /// Maksimumscore: stepperen på klokka stopper ved taket, som på telefonen (par 3 + 2 + 1 slag = 6).
    @Test func maksimumscoreStopperVedTaket() {
        let row = myRow(round("maks-score"))
        #expect(row.options.last?.strokes == 6)
        #expect(row.option(6)?.text == "tak 6 slag")
        #expect(row.clamp(12) == 6)
        #expect(row.clamp(0) == 1)
    }

    @Test func lagretHullStaar() {
        let r = round(scores: [(F.anders, 2, 5)])
        #expect(myRow(r).saved == 5)
        #expect(myRow(r).value == 5)
        #expect(r.currentHole == 0)
    }

    /// «Bayen nå» for båsen min, med summen i formen.
    @Test func bayenNaaForBaasen() {
        let r = round("slag-brutto", scores: [(F.anders, 0, 5), (F.anders, 1, 6), (F.anders, 2, 4),
                                               (F.bjorn, 0, 4), (F.bjorn, 1, 5), (F.bjorn, 2, 3)])
        #expect(r.standings.first?.name == "Bjørn")
        #expect(r.standings.first?.value == "12 slag")
        #expect(r.standings.first { $0.isMe }?.value == "15 slag")
        // Bås 2 er ikke med.
        #expect(!r.standings.contains { $0.name == "Erik" })
    }

    @Test func ingenRundeNaarDenErLaast() {
        let g = RoundGame(F.snapshot(players(), round: F.round(status: .locked)))
        #expect(g.watchRound(for: F.viewer(F.anders)) == nil)
    }

    @Test func hullFraKlokkaBlirInnsending() {
        let entry = WatchHoleEntry(roundID: F.roundID, holeIndex: 2,
                                   scores: [.init(memberID: me, strokes: 4), .init(memberID: F.id(F.bjorn), strokes: 3)],
                                   recordedAt: Date(timeIntervalSince1970: 50))
        let submission = HoleSubmission(watch: entry)
        #expect(submission.roundID == F.roundID)
        #expect(submission.holeIndex == 2)
        #expect(submission.entries == [.init(memberID: me, strokes: 4), .init(memberID: F.id(F.bjorn), strokes: 3)])
        #expect(submission.recordedAt == Date(timeIntervalSince1970: 50))
    }

    /// Et sendt hull står på klokka til telefonen har fått det og sendt en nyere runde.
    @Test func sendteHullStaarTilTelefonenHarSvart() {
        let r = round()   // laget ved 100
        let entry = WatchHoleEntry(roundID: F.roundID, holeIndex: 2, scores: [.init(memberID: me, strokes: 6)],
                                   recordedAt: Date(timeIntervalSince1970: 90))
        let waiting = WatchOutgoing(entry: entry, deliveredAt: nil)
        let deliveredAfter = WatchOutgoing(entry: entry, deliveredAt: Date(timeIntervalSince1970: 110))
        let deliveredBefore = WatchOutgoing(entry: entry, deliveredAt: Date(timeIntervalSince1970: 95))
        let otherRound = WatchOutgoing(entry: WatchHoleEntry(roundID: F.id(1234), holeIndex: 2, scores: [],
                                                             recordedAt: .distantPast), deliveredAt: nil)
        #expect(WatchRound.keeping([waiting, deliveredAfter, deliveredBefore, otherRound], round: r)
                == [waiting, deliveredAfter])
        #expect(r.value(hole: 2, member: me, outgoing: [waiting]) == 6)
        #expect(r.value(hole: 2, member: me, outgoing: []) == 3)
    }

    @Test func meldingenKommerFramLik() {
        let r = round(scores: [(F.anders, 2, 5)])
        let payload = WatchMessage.payload(r, key: WatchMessage.round)!
        #expect(WatchMessage.value(WatchRound.self, key: WatchMessage.round, in: payload) == r)
        // Under grensen for application context (WatchConnectivity), med god margin.
        #expect((payload[WatchMessage.round] as! Data).count < 20_000)
    }
}
