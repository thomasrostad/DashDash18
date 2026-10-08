#if DEBUG
import Foundation
import GolfgutuCore

/// Oppdiktet sesong for forhåndsvisning og skjermbilder av Tavla (`-DDDesignScreen tavla`).
enum TavlaSamples {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(9000)
    static let courseID = id(9001)
    static let par = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
    static let names = ["Bjørn", "Lars", "Kåre", "Knut", "Ola", "Per", "Odd", "Thomas"]
    static let me = id(8)

    static let members: [ClubMemberRow] = names.enumerated().map { i, name in
        ClubMemberRow(id: id(i + 1), clubID: club, userID: nil, displayName: name, handicapIndex: Double(8 + i * 2),
                      seedGroup: nil, isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    /// Brutto per hull: par + et mønster som varierer med spiller og runde.
    static func strokes(_ player: Int, _ round: Int) -> [Int] {
        par.enumerated().map { h, p in p + ((player * 3 + h * (round + 1)) % 4 == 0 ? 0 : (h + player + round) % 3) }
    }

    static func round(_ n: Int, date: String, status: RoundStatus = .locked) -> RoundSnapshot {
        let rid = id(100 + n)
        let row = RoundRow(id: rid, clubID: club, eventID: id(200 + n), courseID: courseID, roundNo: 1, name: nil,
                           status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                           handicapAllowance: 1, externalHandicap: false, weight: 1,
                           ldEnabled: true, ldHoleIndex: 6, kpEnabled: true, kpHoleIndex: 2,
                           cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
                           startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: row)
        s.eventDate = date
        s.players = members.enumerated().map { i, m in
            RoundPlayerRow(roundID: rid, memberID: m.id, clubID: club, handicapIndex: m.handicapIndex,
                           seedGroup: nil, playingHandicap: nil, bayNo: i / 4 + 1, isMarker: i % 4 == 0, teamNo: nil)
        }
        s.scores = members.enumerated().flatMap { i, m in
            strokes(i, n).enumerated().map { h, g in
                HoleScoreRow(roundID: rid, memberID: m.id, holeIndex: h, strokes: g, recordedAt: nil, updatedBy: nil,
                             updatedAt: nil)
            }
        }
        s.matches = stride(from: 0, to: members.count, by: 2).enumerated().map { k, i in
            RoundMatchRow(roundID: rid, matchNo: k + 1, playerA: members[i].id, playerB: members[(i + 1 + n) % members.count].id,
                          playerC: nil, teamA: nil, teamB: nil, result: nil)
        }
        s.sideClaims = [
            SideClaimRow(id: id(300 + n), roundID: rid, memberID: members[n % members.count].id, kind: .drive,
                         meters: 230 + Double(n * 7), holeIndex: 6),
        ]
        s.course = CourseRow(id: courseID, clubID: club, name: "Marco Simone", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: courseID, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return s
    }

    /// Sesongen med Golfgutu-oppsettet, eller en stableford-serie (`tavlastableford`, 6 kvelder spilt).
    static func standings(finished: Bool = false, stableford: Bool = false) -> TavlaStandings {
        let season = SeasonRow(id: id(9002), clubID: club, name: stableford ? "Høst 2026" : "Sesongen 2026",
                               status: finished ? .finished : .active,
                               rules: stableford ? RulesetTemplate.stablefordSeries.rules : .golfgutu)
        let rounds = stableford
            ? (1...6).map { round($0, date: "2026-\(String(format: "%02d", $0 + 3))-14") }
            : (1...5).map { round($0, date: "2026-0\($0 + 4)-14") }
        return TavlaStandings(TavlaInput(season: season, members: members, rounds: rounds), me: me)
    }
}
#endif
