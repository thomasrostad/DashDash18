import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Teksten som deles fra Tavla og kvelden: rekkefølge og plass kommer fra modellen, uendret.
struct DelingTests {
    private static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    private static func tavlaRow(_ n: Int, _ name: String, place: Int, total: Double, isMe: Bool = false)
        -> TavlaStandings.Row {
        TavlaStandings.Row(memberID: id(n), name: name, place: place, total: total, duel: total, side: 0,
                           matches: 0, holes: 0, stableford: 0, evenings: 1, isMe: isMe)
    }

    private static func bayenRow(_ n: Int, _ name: String, place: Int?, total: Int, match: MatchStanding? = nil,
                                 value: String) -> BayenRow {
        BayenRow(members: [id(n)], name: name, isMe: false, thru: 18, bay: 1, place: place, total: total,
                 match: match, value: value, tone: MatchTone(match))
    }

    @Test func tekstMedOverskriftUndertittelOgLinjer() {
        let share = ResultShare(eyebrow: "Jakkeracet", title: "Sesong 2026", subtitle: "3 av 7 kvelder spilt",
                                lines: [.init(place: 1, name: "Anders", value: "12,5 p", isMe: false),
                                        .init(place: 2, name: "Bjørn", value: "10 p", isMe: true)])
        #expect(share.text == """
            Jakkeracet · Sesong 2026
            3 av 7 kvelder spilt

            1. Anders – 12,5 p
            2. Bjørn – 10 p
            """)
    }

    @Test func tekstUtenUndertittelOgUtenLinjer() {
        let share = ResultShare(eyebrow: "Kvelden", title: "Testbanen", subtitle: nil, lines: [])
        #expect(share.text == "Kvelden · Testbanen")
    }

    @Test func linjeUtenPlassHarBareNavn() {
        #expect(ResultShare.line(.init(place: nil, name: "Åse", value: "2 opp", isMe: false)) == "Åse – 2 opp")
    }

    /// Tavla: tabellens rekkefølge og plass beholdes, også ved likt poeng og norske navn
    /// (Ø før Å). Poengene formateres med tabellens egen formatering.
    @Test func tavlaBeholderRekkefoelgeOgPlass() {
        let rows = [Self.tavlaRow(1, "Øyvind", place: 1, total: 12.5),
                    Self.tavlaRow(2, "Åse", place: 2, total: 12.5, isMe: true),
                    Self.tavlaRow(3, "Anders", place: 3, total: 3)]
        let lines = ResultShare.lines(from: rows) { Season.formatPoints($0, rules: .golfgutu) }
        #expect(lines.map(\.name) == ["Øyvind", "Åse", "Anders"])
        #expect(lines.map(\.place) == [1, 2, 3])
        #expect(lines.map(\.isMe) == [false, true, false])
        #expect(lines.map(\.value) == rows.map { "\(Season.formatPoints($0.total, rules: .golfgutu)) p" })
    }

    /// Delt plass står slik modellen leverer den; ingenting regnes på nytt.
    @Test func delPlassFraModellenBeholdes() {
        let rows = [Self.tavlaRow(1, "Bjørn", place: 1, total: 10),
                    Self.tavlaRow(2, "Cato", place: 1, total: 10),
                    Self.tavlaRow(3, "Dag", place: 3, total: 4)]
        let text = ResultShare(eyebrow: "Jakkeracet", title: "S", subtitle: nil,
                               lines: ResultShare.lines(from: rows) { "\(Int($0))" }).text
        #expect(text.hasSuffix("1. Bjørn – 10 p\n1. Cato – 10 p\n3. Dag – 4 p"))
    }

    /// Kvelden på poeng: plass og poengsum som i «Bayen nå».
    @Test func kveldenPaaPoeng() {
        let rows = [Self.bayenRow(1, "Anders", place: 1, total: 36, value: "36"),
                    Self.bayenRow(2, "Bjørn + Cato", place: 2, total: 30, value: "30")]
        #expect(ResultShare.lines(from: rows).map(ResultShare.line) == ["1. Anders – 36 p", "2. Bjørn + Cato – 30 p"])
    }

    /// Hull for hull: ingen plass (som i appen), stillingen for matchspillerne, poeng for resten.
    @Test func kveldenHullForHull() {
        let up = MatchStanding(up: 2, played: 10, remaining: 8, decided: false)
        let rows = [Self.bayenRow(1, "Øyvind", place: nil, total: 20, match: up, value: "2 opp"),
                    Self.bayenRow(2, "Åse", place: nil, total: 24, value: "24 p")]
        #expect(ResultShare.lines(from: rows).map(ResultShare.line) == ["Øyvind – 2 opp", "Åse – 24 p"])
    }
}
