#if DEBUG
import GolfgutuCore
import SwiftUI

/// Oppdiktede runder for skjermprøvene (`-DDDesignScreen statoversikt` osv.).
enum StatsSamples {
    static let par18 = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    static let si18 = [7, 1, 17, 3, 11, 15, 5, 9, 13, 8, 16, 2, 10, 4, 18, 12, 6, 14]
    static let today = StatsFormat.date("2026-10-07")!

    static var rounds: [StatsRound] {
        let courses = [("c1", "Bjaavann", 71.4, 128.0), ("c2", "Larvik", 70.1, 124.0), ("c3", "Marco Simone", 73.2, 135.0)]
        let holes = par18.indices.map { StatsHole(par: par18[$0], strokeIndex: si18[$0], number: $0 + 1) }
        var out: [StatsRound] = []
        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33) % 100
        }
        for i in 0..<16 {
            let course = courses[i % 3]
            let month = 4 + i / 3
            let day = 3 + (i % 3) * 9
            var scores: [Int: Int] = [:]
            var details: [Int: HoleDetail] = [:]
            let form = i / 4   // blir litt bedre utover sesongen
            for (h, hole) in holes.enumerated() {
                let r = next()
                let over = r < 8 ? -1 : r < 48 + form * 3 ? 0 : r < 86 + form * 2 ? 1 : r < 97 ? 2 : 3
                scores[h] = hole.par + over
                if i >= 8 {
                    let putts = over <= 0 ? (r % 3 == 0 ? 1 : 2) : (r % 4 == 0 ? 3 : 2)
                    details[h] = HoleDetail(fairway: hole.par >= 4 ? (r % 5 == 0 ? .left : r % 7 == 0 ? .right : .hit) : nil,
                                            greenInRegulation: over <= 0 && putts <= 2,
                                            putts: putts, bunker: r % 9 == 0, penalties: r > 96 ? 1 : 0)
                }
            }
            if i == 15 { scores = scores.filter { $0.key < 11 } }   // pågår
            out.append(StatsRound(
                id: "s\(i)", date: String(format: "2026-%02d-%02d", month, day), kind: i % 4 == 3 ? .loose : .club,
                clubName: "Golfgutu", courseID: course.0, courseName: course.1, holes: holes, playingHandicap: 15,
                handicapIndex: 14.2 - Double(i) * 0.1, courseRating: course.2, slopeRating: course.3,
                scores: scores, details: details))
        }
        return out
    }

    static func model(empty: Bool = false) -> StatsModel {
        let m = StatsModel(scope: .me(userID: UUID(), memberIDs: [], clubNames: [:]), rounds: empty ? [] : rounds)
        m.today = today
        return m
    }
}

/// Skjermprøve for føringen under hullkortet.
struct StatsEntrySample: View {
    @State private var detail = HoleDetail(fairway: .hit, greenInRegulation: false, putts: 2, bunker: true)
    @State private var par3 = HoleDetail(greenInRegulation: true, putts: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HullkortView(card: DesignScreenSamples.card, isPending: false, isSaving: false, error: nil,
                                 onStep: { _, _ in }, onConfirm: { _ in }, onSave: {}, onGoTo: { _ in },
                                 onScorecard: { _ in })
                    HoleStatsEntryRow(par: 4, holeNumberText: "hull 6", detail: detail) { detail = $0 }
                    HoleStatsEntryRow(par: 3, holeNumberText: "hull 7", detail: par3) { par3 = $0 }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .defaultScrollAnchor(.bottom)
            .ddScreenBackground()
            .navigationTitle("Runde 6")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
        }
    }
}

#Preview("Statistikk") { NavigationStack { StatsView(model: StatsSamples.model()) } }
#Preview("Statistikk tom") { NavigationStack { StatsView(model: StatsSamples.model(empty: true)) } }
#Preview("Føring") { StatsEntrySample() }
#endif
