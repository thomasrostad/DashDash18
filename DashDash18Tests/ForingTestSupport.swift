import Foundation
import GolfgutuCore
@testable import DashDash18

/// Felles oppsett for føringstestene: runder bygd av rader, slik de kommer fra databasen.
enum ForingFixture {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(900)
    static let roundID = id(901)
    static let courseID = id(902)
    static let eventID = id(903)

    /// Par fra markor-test.js og brutto-test.js.
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    /// brutto-test.js: stroke index i en annen rekkefølge enn hullene.
    static let bruttoSI = [7, 1, 15, 3, 11, 17, 5, 9, 13, 8, 18, 2, 10, 4, 16, 6, 12, 14]

    struct P {
        let n: Int
        let name: String
        var handicap: Double? = 0
        var bay: Int?
        var marker = false
        var team: Int?
        var playing: Int?
    }

    static func round(status: RoundStatus = .active, holeCount: Int = 18, firstHole: Int = 1,
                      format: String = "stableford", externalHandicap: Bool = false,
                      parConfirmed: Bool = true) -> RoundRow {
        RoundRow(id: roundID, clubID: club, eventID: eventID, courseID: courseID, roundNo: 1, name: nil,
                 status: status, holeCount: holeCount, firstHole: firstHole, teeTime: nil, format: format,
                 handicapAllowance: 1, externalHandicap: externalHandicap, weight: 1,
                 ldEnabled: true, ldHoleIndex: nil, kpEnabled: true, kpHoleIndex: nil,
                 cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                 parConfirmedAt: parConfirmed ? Date(timeIntervalSince1970: 0) : nil,
                 startedAt: nil, lockedAt: nil)
    }

    static func snapshot(_ players: [P], round: RoundRow = round(), si: [Int]? = nil,
                         scores: [(Int, Int, Int)] = []) -> RoundSnapshot {
        var s = RoundSnapshot(round: round)
        s.players = players.map { p in
            RoundPlayerRow(roundID: roundID, memberID: id(p.n), clubID: club, handicapIndex: p.handicap,
                           seedGroup: nil, playingHandicap: p.playing, bayNo: p.bay, isMarker: p.marker,
                           teamNo: p.team)
        }
        s.names = Dictionary(uniqueKeysWithValues: players.map { (id($0.n), $0.name) })
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        let indexes = si ?? Array(1...18)
        s.courseHoles = par.indices.map { i in
            CourseHoleRecord(courseID: courseID, holeNumber: i + 1, par: par[i], strokeIndex: indexes[i], lengthM: nil)
        }
        s.scores = scores.map { member, hole, strokes in
            HoleScoreRow(roundID: roundID, memberID: id(member), holeIndex: hole, strokes: strokes,
                         recordedAt: nil, updatedBy: nil, updatedAt: nil)
        }
        return s
    }

    // markor-test.js: åtte spillere, to båser. Anders markør i bås 1, Erik i bås 2.
    // Gunnar er arrangør og sitter i bås 2 uten å være markør.
    static let anders = 1, bjorn = 2, cato = 3, dag = 4, erik = 5, frode = 6, gunnar = 7, halvor = 8

    static func markorPlayers(bays: Bool = true) -> [P] {
        let rows: [(Int, String, Int, Bool)] = [
            (anders, "Anders", 1, true), (bjorn, "Bjørn", 1, false), (cato, "Cato", 1, false), (dag, "Dag", 1, false),
            (erik, "Erik", 2, true), (frode, "Frode", 2, false), (gunnar, "Gunnar", 2, false), (halvor, "Halvor", 2, false),
        ]
        return rows.map { P(n: $0.0, name: $0.1, bay: bays ? $0.2 : nil, marker: bays && $0.3) }
    }

    static func viewer(_ n: Int) -> Viewer { Viewer(memberID: id(n), isOrganizer: n == gunnar) }
}
