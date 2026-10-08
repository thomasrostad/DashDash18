import Foundation
import GolfgutuCore

/// Radene statistikken bygger på, slik databasen leverer dem: rundene spilleren har vært med i,
/// spillerens egne slag og føring, banene og regelsettene. Ingenting er regnet ut.
nonisolated struct StatsInput: Equatable, Sendable {
    var rounds: [StatsRoundRow] = []
    var roundHoles: [RoundHoleRow] = []
    /// Spillerens rad i hver runde (én per runde).
    var players: [StatsPlayerRow] = []
    var scores: [HoleScoreRow] = []
    var details: [HoleStatRow] = []
    var courses: [StatsCourseRow] = []
    var courseHoles: [CourseHoleRecord] = []
    /// Kveldens dato (`YYYY-MM-DD`) per kveld.
    var eventDates: [UUID: String] = [:]
    /// Regelsettet per kveld (sesongens). Mangler det, gjelder Golfgutu-oppsettet.
    var eventRules: [UUID: Ruleset] = [:]
    var clubNames: [UUID: String] = [:]
}

nonisolated extension StatsInput {
    /// Rundene for statistikkmotoren. Kladder og runder uten dato eller hull er ikke med.
    func statsRounds() -> [StatsRound] {
        rounds.compactMap { r in
            guard r.status != .draft, let player = players.first(where: { $0.roundID == r.id }),
                  let date = date(of: r) else { return nil }
            let round = makeRound(r)
            let played = round.courseHoles()
            guard !played.isEmpty else { return nil }
            let offset = round.holeStart == 9 ? 9 : 0
            let holes = played.enumerated().map { i, h in
                StatsHole(par: h.par, strokeIndex: h.strokeIndex, number: i + 1 + offset)
            }
            let rules = r.eventID.flatMap { eventRules[$0] } ?? .golfgutu
            let course = courses.first { $0.id == r.courseID }
            var scoreMap: [Int: Int] = [:]
            for s in scores where s.roundID == r.id && s.memberID == player.memberID {
                scoreMap[s.holeIndex] = s.strokes
            }
            var detailMap: [Int: HoleDetail] = [:]
            for d in details where d.roundID == r.id && d.memberID == player.memberID {
                detailMap[d.holeIndex] = d.detail
            }
            return StatsRound(
                id: r.id.uuidString, date: date, kind: r.clubID == nil ? .loose : .club, title: r.name,
                clubName: r.clubID.flatMap { clubNames[$0] }, courseID: r.courseID?.uuidString,
                courseName: course?.name, holes: holes,
                playingHandicap: playingHandicap(r, player: player, round: round, rules: rules),
                handicapIndex: player.handicapIndex, courseRating: r.courseRating ?? course?.courseRating,
                slopeRating: (r.slopeRating ?? course?.slopeRating).map(Double.init), scores: scoreMap, details: detailMap,
                scoring: rules.scoring
            )
        }
    }

    /// Kveldens dato for klubbrunder, ellers dagen runden startet (norsk tid).
    func date(of r: StatsRoundRow) -> String? {
        if let event = r.eventID, let d = eventDates[event] { return d }
        return r.startedAt.map { StatsFormat.day($0) }
    }

    /// Spillehandicapet i runden: 0 når simulatoren deler ut slagene, ellers det som ble frosset
    /// ved start. Eldre runder uten frosset tall regnes som i føringen (`effectiveHandicap`), men
    /// bare med spilleren selv (lagkameratene er ikke hentet).
    func playingHandicap(_ r: StatsRoundRow, player: StatsPlayerRow, round: Round, rules: Ruleset) -> Double {
        if r.externalHandicap { return 0 }
        if let frozen = player.playingHandicap { return Double(frozen) }
        let me = Player(id: player.memberID.uuidString, handicap: player.handicapIndex, seedGroup: player.seedGroup)
        return Handicap.effective(for: me, in: round, roster: [me], rules: rules)
    }

    /// GolfgutuCore-runden med banen og rundens egne hull, som i føringen (`RoundGame.makeRound`).
    func makeRound(_ r: StatsRoundRow) -> Round {
        let overrides = Dictionary(roundHoles.filter { $0.roundID == r.id }.map { h in
            (h.holeIndex, RoundHole(par: h.par, strokeIndex: h.strokeIndex, meters: h.lengthM.map(Double.init)))
        }, uniquingKeysWith: { first, _ in first })
        return Round(id: r.id.uuidString, gameType: r.format, holeCount: r.holeCount,
                     holeStart: r.firstHole == 10 ? 9 : 0, course: makeCourse(r.courseID, round: r),
                     holes: overrides.isEmpty ? nil : overrides, hcpAllowance: r.handicapAllowance,
                     hcpExtern: r.externalHandicap)
    }

    /// Banen med hullene. Er runden spilt fra en tee (sql/029), gjelder rundens CR og slope.
    func makeCourse(_ id: UUID?, round: StatsRoundRow? = nil) -> Course? {
        guard let id, let row = courses.first(where: { $0.id == id }) else { return nil }
        let mine = courseHoles.filter { $0.courseID == id }.map { h in
            CourseHoleRow(courseId: id.uuidString, holeNumber: h.holeNumber, par: h.par, hcpIndex: h.strokeIndex,
                          distanceMeters: h.lengthM.map(Double.init))
        }
        let played = Course.holesFromRows(mine)[id.uuidString] ?? nil
        let par = played.map { $0.reduce(0) { $0 + ($1.par ?? 0) } }
        return Course(id: id.uuidString, name: row.name, par: par, courseRating: round?.courseRating ?? row.courseRating,
                      slopeRating: (round?.slopeRating ?? row.slopeRating).map(Double.init), holes: played)
    }
}
