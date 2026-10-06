import Foundation
import GolfgutuCore

// Runden → Live Activity. Bare oppslag i det `RoundGame` allerede regner ut (bayHole, scorer,
// total, standings, matchCard): ingen spillogikk her.

nonisolated extension RoundGame {
    /// Skal Live Activity gå for `viewer`? Bare når runden går og han spiller i den.
    func wantsLiveActivity(for viewer: Viewer) -> Bool {
        status == .active && isPlaying(viewer.memberID)
    }

    /// Det statiske i aktiviteten.
    func liveActivityAttributes(for viewer: Viewer) -> RoundActivityAttributes {
        RoundActivityAttributes(roundID: roundID,
                                courseName: snapshot.course?.name ?? "Kvelden",
                                playerName: name(viewer.memberID))
    }

    /// Det som vises nå. Nil når `viewer` ikke spiller i runden.
    func liveActivityContent(for viewer: Viewer, now: Date = .now) -> RoundActivityAttributes.ContentState? {
        let me = viewer.memberID
        guard isPlaying(me) else { return nil }
        let mine = scores(me)

        // Stillingen i båsen: «Bayen nå» på poeng, avgrenset til båsen min. Uten bås: hele runden.
        let myBay = bay(of: me)?.number
        let rows = standings(viewer: viewer).filter { myBay == nil || $0.bay == myBay }
        let place = rows.firstIndex { $0.memberID == me }.map { $0 + 1 }

        let match = matchCard(viewer: viewer)?.mine.first
        let tone: RoundActivityAttributes.ContentState.MatchTone = switch match?.tone {
        case .up?: .up
        case .down?: .down
        default: .neutral
        }

        return RoundActivityAttributes.ContentState(
            holeNumber: holeNumber(bayHole(for: viewer)),
            holeCount: holeCount,
            holesPlayed: mine.count,
            strokes: mine.values.reduce(0, +),
            points: total(me),
            bayPlace: place,
            bayCount: place == nil ? nil : rows.count,
            bayNumber: myBay,
            matchText: match?.text,
            matchTone: tone,
            updatedAt: now
        )
    }
}
