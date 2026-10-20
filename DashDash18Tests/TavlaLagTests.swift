import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Lagtabellen på Tavla: scramble og de andre formene med ett kort per lag står med ett lag per rad.
/// Handicap 0 og par 4 på alle hull: par gir 36 poeng, ett over 18.
private enum L {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(780)
    static let courseID = id(781)
    static let par = Array(repeating: 4, count: 18)
    static let names = [1: "Anne", 2: "Berit", 3: "Cecilie", 4: "Dina", 5: "Eva", 6: "Frida"]

    static let members = names.keys.sorted().map { n in
        ClubMemberRow(id: id(n), clubID: club, userID: nil, displayName: names[n]!, handicapIndex: 0, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static var rules: Ruleset {
        var r = RulesetTemplate.stablefordSeries.rules
        r.evenings = 2
        r.dayTerm = .evening
        return r
    }

    /// `teams[spiller]` er laget; `over[lag]` slag over par på hvert hull for hele laget.
    static func round(_ n: Int, format: String = "scramble-2", teams: [Int: Int], over: [Int: Int]) -> RoundSnapshot {
        let rid = id(100 + n)
        let row = RoundRow(id: rid, clubID: club, eventID: id(200 + n), courseID: courseID, roundNo: 1, name: nil,
                           status: .locked, holeCount: 18, firstHole: 1, teeTime: nil, format: format,
                           handicapAllowance: 1, externalHandicap: false, weight: 1,
                           ldEnabled: false, ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil,
                           cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
                           startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: row)
        s.eventDate = "2026-09-0\(n)"
        s.players = teams.keys.sorted().map { p in
            RoundPlayerRow(roundID: rid, memberID: id(p), clubID: club, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: teams[p])
        }
        s.scores = teams.flatMap { p, team in
            par.indices.map { h in
                HoleScoreRow(roundID: rid, memberID: id(p), holeIndex: h, strokes: par[h] + (over[team] ?? 0),
                             recordedAt: nil, updatedBy: nil, updatedAt: nil)
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

    static func standings(_ rounds: [RoundSnapshot], me: Int = 3) -> TavlaStandings {
        let season = SeasonRow(id: id(782), clubID: club, name: "Scramble", status: .active, rules: rules)
        return TavlaStandings(TavlaInput(season: season, members: members, rounds: rounds), me: id(me), comparesPrevious: true)
    }

    static let pairs = [1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3]
}

struct TavlaLagTests {
    /// Lag 1 og 3 går par (36), lag 2 ett over (18): to lag deler førsteplassen, lag 2 er nummer 3.
    @Test func ettLagPerRad() {
        let s = L.standings([L.round(1, teams: L.pairs, over: [1: 0, 2: 1, 3: 0])])
        #expect(s.isTeamBoard)
        #expect(s.rows.count == 6)
        #expect(s.boardRows.map(\.name) == ["Anne og Berit", "Eva og Frida", "Cecilie og Dina"])
        #expect(s.boardRows.map(\.place) == [1, 1, 3])
        #expect(s.boardRows.map(\.total) == [36, 36, 18])
        #expect(s.boardRows.map(\.isMe) == [false, false, true])
        #expect(s.boardRows.map(s.boardPlace) == ["1=", "1=", "3"])
        #expect(s.leadTieText?.hasPrefix("2 lag står likt på 36 poeng.") == true)
    }

    /// Fire på laget: «Anne, Berit, Cecilie og Dina».
    @Test func navnetErHeleLaget() {
        let teams = [1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 2]
        let s = L.standings([L.round(1, format: "scramble-4", teams: teams, over: [1: 0, 2: 1])])
        #expect(s.boardRows.map(\.name) == ["Anne, Berit, Cecilie og Dina", "Eva og Frida"])
        #expect(s.boardRows.map(\.place) == [1, 2])
    }

    /// Samme lag to kvelder: fortsatt lagtabell, og bevegelsen regnes blant lagene.
    @Test func sammeLagToKvelderGirBevegelse() {
        let s = L.standings([L.round(1, teams: L.pairs, over: [1: 0, 2: 1, 3: 2]),
                             L.round(2, teams: L.pairs, over: [1: 2, 2: 0, 3: 0])])
        #expect(s.isTeamBoard)
        // Kveld 1: lag 1 36, lag 2 18, lag 3 0. Totalt: lag 2 54, lag 3 36, lag 1 36.
        #expect(s.boardRows.map(\.name) == ["Cecilie og Dina", "Anne og Berit", "Eva og Frida"])
        #expect(s.boardRows.map(\.place) == [1, 2, 2])
        #expect(s.boardPreviousPlaces?[L.id(3)] == 2)
        #expect(s.movement(s.boardRows[0]) == .up(1))
    }

    /// Byttes lagene mellom kveldene, eller spilles en runde med hver sin ball, er tabellen per spiller.
    @Test func ulikeLagEllerHverSinBallGirSpillerrader() {
        let swapped = [1: 1, 2: 2, 3: 1, 4: 2, 5: 3, 6: 3]
        let a = L.standings([L.round(1, teams: L.pairs, over: [:]), L.round(2, teams: swapped, over: [:])])
        #expect(!a.isTeamBoard && a.boardRows == a.rows)
        let b = L.standings([L.round(1, format: "fourball", teams: L.pairs, over: [:])])
        #expect(!b.isTeamBoard && b.boardRows.count == 6)
    }
}
