import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Tavla (V4): delt plass, bevegelse siden forrige kveld, delt ledelse, fremdrift og neste kveld.
/// Stableford-serien med handicap 0 og par 4 på alle hull: par gir 36 poeng, ett over 18, to over 0.
private enum B {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(880)
    static let courseID = id(881)
    static let anne = 1, berit = 2, cecilie = 3
    static let par = Array(repeating: 4, count: 18)

    static let members = [(anne, "Anne"), (berit, "Berit"), (cecilie, "Cecilie")].map { n, name in
        ClubMemberRow(id: id(n), clubID: club, userID: nil, displayName: name, handicapIndex: 0, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static var rules: Ruleset {
        var r = RulesetTemplate.stablefordSeries.rules
        r.evenings = 7
        r.dayTerm = .evening
        return r
    }

    /// `over[spiller]` slag over par på hvert hull.
    static func round(_ n: Int, date: String, over: [Int: Int]) -> RoundSnapshot {
        let rid = id(100 + n)
        let row = RoundRow(id: rid, clubID: club, eventID: id(200 + n), courseID: courseID, roundNo: 1, name: nil,
                           status: .locked, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                           handicapAllowance: 1, externalHandicap: false, weight: 1,
                           ldEnabled: false, ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil,
                           cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
                           startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: row)
        s.eventDate = date
        s.players = over.keys.sorted().map { p in
            RoundPlayerRow(roundID: rid, memberID: id(p), clubID: club, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: nil)
        }
        s.scores = over.flatMap { p, extra in
            par.indices.map { h in
                HoleScoreRow(roundID: rid, memberID: id(p), holeIndex: h, strokes: par[h] + extra, recordedAt: nil,
                             updatedBy: nil, updatedAt: nil)
            }
        }
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: courseID, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return s
    }

    static func standings(_ rounds: [RoundSnapshot], rules: Ruleset = rules, status: SeasonStatus = .active,
                          next: String? = nil, compares: Bool = true) -> TavlaStandings {
        let season = SeasonRow(id: id(882), clubID: club, name: "Høst 2026", status: status, rules: rules)
        return TavlaStandings(TavlaInput(season: season, members: members, rounds: rounds, nextEventDate: next),
                              me: id(anne), comparesPrevious: compares)
    }

    static func row(_ s: TavlaStandings, _ n: Int) -> TavlaStandings.Row { s.row(id(n))! }

    /// Kveld 1: Anne 36, Berit 18, Cecilie 0.
    static let first = round(1, date: "2026-09-01", over: [anne: 0, berit: 1, cecilie: 2])
}

struct TavlaBoardTests {
    @Test func bevegelseSidenForrigeKveld() {
        // Kveld 2: Anne 0, Berit 36, Cecilie 18. Totalt: Berit 54, Anne 36, Cecilie 18.
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 2, B.berit: 0, B.cecilie: 1])])
        #expect(s.showsMovement)
        #expect(s.movement(B.row(s, B.berit)) == .up(1))
        #expect(s.movement(B.row(s, B.anne)) == .down(1))
        #expect(s.movement(B.row(s, B.cecilie)) == .same)
        #expect(TavlaStandings.Movement.up(1).text == "▲1")
        #expect(TavlaStandings.Movement.down(2).text == "▼2")
        #expect(TavlaStandings.Movement.same.text == "–")
        #expect(TavlaStandings.Movement.down(2).spoken == "ned 2 plasser")
    }

    @Test func ingenBevegelseEtterFørsteKveld() {
        let s = B.standings([B.first])
        #expect(s.previousPlaces == nil)
        #expect(!s.showsMovement)
        #expect(s.movement(B.row(s, B.anne)) == nil)
    }

    @Test func bevegelseRegnesBareNårTavlaBerOmDen() {
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 0, B.berit: 0, B.cecilie: 0])],
                            compares: false)
        #expect(s.previousPlaces == nil)
        #expect(!s.showsMovement)
    }

    @Test func toRunderSammeKveldErÉnKveld() {
        // Bevegelsen er mot tabellen før hele siste kveld, ikke før siste runde.
        let late = B.round(3, date: "2026-09-08", over: [B.anne: 2, B.berit: 0, B.cecilie: 2])
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 2, B.berit: 0, B.cecilie: 2]), late])
        #expect(s.previousPlaces?[B.id(B.anne)] == 1)
        #expect(s.previousPlaces?[B.id(B.berit)] == 2)
    }

    @Test func deltPlassVisesMedLikhetstegn() {
        // Kveld 2: Anne 18, Berit 36. Begge 54, og stablefordsummen (skillet) er også lik.
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])])
        #expect(s.boardPlace(B.row(s, B.anne)) == "1=")
        #expect(s.boardPlace(B.row(s, B.berit)) == "1=")
        #expect(s.boardPlace(B.row(s, B.cecilie)) == "3")
        #expect(s.tiedLeaders.map(\.name) == ["Anne", "Berit"])
    }

    @Test func plassFørFørsteKveldErStrek() {
        let s = B.standings([])
        #expect(s.boardPlace(B.row(s, B.anne)) == "–")
        #expect(s.tiedLeaders.isEmpty)
        #expect(s.leadTieText == nil)
        #expect(s.progressText == "0 av 7 kvelder spilt")
    }

    @Test func deltLedelseMedSkilletegn() {
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])])
        #expect(s.leadTieText == "Anne og Berit står likt på 54 poeng. Blir det likt etter kveld 7, skiller stablefordsummen.")
    }

    @Test func deltLedelseMedPlayoff() {
        var rules = B.rules
        rules.table.tieRule = .playoff
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])],
                            rules: rules)
        #expect(s.leadTieText == "Anne og Berit står likt på 54 poeng. Blir det likt etter kveld 7, avgjør playoff førsteplassen.")
    }

    @Test func deltLedelseUtenSkilleDelerDe() {
        var rules = B.rules
        rules.table.tiebreaks = []
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])],
                            rules: rules)
        #expect(s.leadTieText == "Anne og Berit står likt på 54 poeng. Blir det likt etter kveld 7, deler de førsteplassen.")
    }

    /// Jakke-ordene hører til Golfgutu-oppsettet. En annen klubb med matchspill får turneringsnavnet.
    @Test func jakkaBareMedGolfgutuOppsettet() {
        let golfgutu = B.standings([B.first], rules: .golfgutu)
        #expect(golfgutu.boardTitle == "Jakkeracet · Høst 2026")
        #expect(golfgutu.share.eyebrow == "Jakkeracet")

        var annen = Ruleset.golfgutu
        annen.evenings = 5
        let s = B.standings([B.first], rules: annen)
        #expect(!s.countsStableford)
        #expect(s.boardTitle == "Høst 2026")
        #expect(s.share.eyebrow == "Tavla")
        #expect(s.share.heading == "Tavla · Høst 2026")
    }

    @Test func ingenHeroNårTurneringenErFerdig() {
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])],
                            status: .finished)
        #expect(s.tiedLeaders.count == 2)
        #expect(s.leadTieText == nil)
    }

    @Test func etterSisteKveldSierDetHvaSomAvgjør() {
        var rules = B.rules
        rules.evenings = 2
        rules.table.tieRule = .playoff
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 1, B.berit: 0, B.cecilie: 2])],
                            rules: rules)
        #expect(s.leadTieText == "Anne og Berit står likt på 54 poeng. Playoff avgjør førsteplassen.")
    }

    @Test func fremdriftOgNesteKveld() {
        let s = B.standings([B.first, B.round(2, date: "2026-09-08", over: [B.anne: 0, B.berit: 0, B.cecilie: 0])],
                            next: "2026-10-21")
        #expect(s.progressText == "Kveld 2 av 7 spilt")
        #expect(s.nextText(today: "2026-10-14") == "Neste: onsdag 21. oktober")
        #expect(s.nextText(today: "2026-10-21") == "Neste: i dag")
        #expect(B.standings([B.first], status: .finished, next: "2026-10-21").nextText(today: "2026-10-14") == nil)
        #expect(B.standings([B.first]).nextText(today: "2026-10-14") == nil)
    }

    @Test func nesteKveldErFørsteUspilteFraIDag() {
        func event(_ n: Int, _ date: String) -> EventRow {
            EventRow(id: B.id(200 + n), clubID: B.club, seasonID: nil, eventDate: date, startTime: nil, venue: nil, note: nil)
        }
        let events = [event(1, "2026-10-07"), event(2, "2026-10-14"), event(3, "2026-10-21"), event(4, "2026-10-28")]
        let played = B.round(2, date: "2026-10-14", over: [B.anne: 0]).round
        #expect(TavlaData.nextEventDate(events: events, rounds: [played], today: "2026-10-14") == "2026-10-21")
        #expect(TavlaData.nextEventDate(events: events, rounds: [], today: "2026-10-14") == "2026-10-14")
        #expect(TavlaData.nextEventDate(events: events, rounds: [], today: "2026-11-01") == nil)
        #expect(TavlaData.today(Date(timeIntervalSince1970: 1_791_928_800)) == "2026-10-14")
    }
}
