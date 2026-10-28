import Foundation
import GolfgutuCore

// Runden → klokka. Bare oppslag i det `RoundGame` allerede regner ut (hullkortet, bayHole og
// «Bayen nå»): ingen spillogikk her, så klokka viser det samme som telefonen.

nonisolated extension RoundGame {
    /// Skal klokka vise runden for `viewer`? Når runden går og han har et kort å føre eller se.
    func wantsWatch(for viewer: Viewer) -> Bool {
        status == .active && !cardPlayers(for: viewer).isEmpty
    }

    /// Runden slik klokka viser den. Nil når klokka ikke skal vise den.
    func watchRound(for viewer: Viewer, now: Date = .now) -> WatchRound? {
        guard wantsWatch(for: viewer) else { return nil }
        let myBay = bay(of: viewer.memberID)?.number
        let standings = bayenNaa(viewer: viewer)
            .filter { myBay == nil || $0.bay == myBay }
            .map { WatchRound.Standing(memberID: $0.memberID, place: $0.place, name: $0.name,
                                       isMe: $0.isMe, thru: $0.thru, value: $0.resultText) }
        return WatchRound(roundID: roundID,
                          title: liveActivityAttributes(for: viewer).courseName,
                          currentHole: bayHole(for: viewer),
                          holes: (0..<holeCount).map { watchHole($0, viewer: viewer) },
                          standings: standings,
                          updatedAt: now)
    }

    /// Hullkortet for hullet, med teksten hullkortet ville vist for hvert slagantall stepperen kan stå på.
    func watchHole(_ index: Int, viewer: Viewer) -> WatchRound.Hole {
        let card = card(hole: index, drafts: HoleDrafts(), viewer: viewer)
        let editable = card.rows.filter(\.editable)
        // En rad regnes bare av sitt eget tall, så alle radene står på samme tall i ett kort: ett kort
        // per slagantall, ikke ett per rad og slagantall.
        let top = editable.map { StrokeInput.clamp(StrokeInput.range.upperBound, max: $0.maxStrokes) }.max() ?? 0
        let cards: [Int: [UUID: HoleCard.Row]] = Dictionary(uniqueKeysWithValues:
            (top < StrokeInput.range.lowerBound ? [] : Array(StrokeInput.range.lowerBound...top)).map { strokes in
                var drafts = HoleDrafts()
                for row in editable { drafts[index, row.memberID] = strokes }
                let rows = self.card(hole: index, drafts: drafts, viewer: viewer).rows
                return (strokes, Dictionary(uniqueKeysWithValues: rows.map { ($0.memberID, $0) }))
            })
        let rows = card.rows.map { row in
            let options: [WatchRound.Option]
            if row.editable {
                let top = StrokeInput.clamp(StrokeInput.range.upperBound, max: row.maxStrokes)
                options = (StrokeInput.range.lowerBound...top).map { strokes in
                    WatchRound.Option(watch: cards[strokes]?[row.memberID], strokes: strokes)
                }
            } else {
                options = [WatchRound.Option(watch: row, strokes: row.value)]
            }
            return WatchRound.Row(memberID: row.memberID, name: row.name, isMe: row.isMe,
                                  editable: row.editable, saved: row.saved, value: row.value,
                                  strokesReceived: row.strokesReceived, options: options)
        }
        return WatchRound.Hole(index: index, number: card.number, par: card.par,
                               strokeIndex: card.strokeIndex, rows: rows)
    }
}

nonisolated extension WatchRound.Option {
    /// Teksten under tallet på hullkortet: formen («2 p · netto par»), ellers navnet (match).
    init(watch row: HoleCard.Row?, strokes: Int) {
        self.init(strokes: strokes,
                  text: row?.formText ?? row?.scoreName?.label,
                  tone: row?.scoreName?.rawValue)
    }
}

nonisolated extension HoleSubmission {
    /// Hullet fra klokka, slik hullkortet lagrer det: alle radene i én innsending, med tastetiden.
    init(watch entry: WatchHoleEntry) {
        self.init(roundID: entry.roundID,
                  holeIndex: entry.holeIndex,
                  entries: entry.scores.map { Entry(memberID: $0.memberID, strokes: $0.strokes) },
                  recordedAt: entry.recordedAt)
    }
}
