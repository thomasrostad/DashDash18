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
                                courseName: snapshot.course?.name ?? DayTerm.capitalized(snapshot.rules.day.the),
                                playerName: name(viewer.memberID))
    }

    /// Det som vises nå. Nil når `viewer` ikke spiller i runden.
    func liveActivityContent(for viewer: Viewer, now: Date = .now) -> RoundActivityAttributes.ContentState? {
        let me = viewer.memberID
        guard isPlaying(me) else { return nil }
        let mine = scores(me)

        // Stillingen i båsen: «Bayen nå» på poeng, avgrenset til båsen min. Uten bås: hele runden.
        // Andre former enn netto stableford (slagspill, maksimumscore, par/bogey, stableford brutto):
        // rekkefølgen og summen fra «Bayen nå», som regner etter formen.
        let myBay = bay(of: me)?.number
        let place: Int?, count: Int
        var valueText: String?
        if FormPlay.formResult(round, roster: roster, rules: rules) != nil {
            let rows = bayenNaa(viewer: viewer).filter { myBay == nil || $0.bay == myBay }
            let i = rows.firstIndex { $0.members.contains(me) }
            place = i.map { $0 + 1 }
            count = rows.count
            valueText = i.map { rows[$0].formTotal ?? "\(rows[$0].total) p" }
        } else {
            let rows = standings(viewer: viewer).filter { myBay == nil || $0.bay == myBay }
            place = rows.firstIndex { $0.memberID == me }.map { $0 + 1 }
            count = rows.count
        }

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
            bayCount: place == nil ? nil : count,
            bayNumber: myBay,
            matchText: match?.text,
            matchTone: tone,
            updatedAt: now,
            valueText: valueText
        )
    }
}
