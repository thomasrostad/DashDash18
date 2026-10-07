import Foundation
import GolfgutuCore

/// Én løs runde i «Mine runder»: bane, dato, hvem som var med og resultatet slik «Bayen nå» viser det.
nonisolated struct MyRoundItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    /// «Onsdag 7. oktober · 18 hull · 4 spillere».
    let subtitle: String
    let status: RoundStatus
    /// «Du: 2. plass · 34 p», eller nil når du ikke spiller.
    let mine: String?
    /// «Vinner: Per · 38 p» (ferdig) eller «Leder: Per · 21 p etter 9» (pågår).
    let leader: String?
    /// Sorteres nyeste først.
    let sortKey: Date
}

nonisolated enum MyRounds {
    /// Pågående og ferdige løse runder, nyeste først. Kladder vises ikke (de startes med en gang).
    static func lists(_ snapshots: [RoundSnapshot], userID: UUID,
                      referenceYear: Int? = nil) -> (ongoing: [MyRoundItem], finished: [MyRoundItem]) {
        let items = snapshots
            .filter { $0.isLoose && $0.round.status != .draft }
            .map { item($0, userID: userID, referenceYear: referenceYear) }
            .sorted { $0.sortKey > $1.sortKey }
        return (items.filter { $0.status == .active }, items.filter { $0.status == .locked })
    }

    static func item(_ snapshot: RoundSnapshot, userID: UUID, referenceYear: Int? = nil) -> MyRoundItem {
        let game = RoundGame(snapshot)
        let viewer = LooseRoundRights.viewer(info: snapshot.loose, userID: userID)
        let rows = game.bayenNaa(viewer: viewer)
        let players = snapshot.players.count
        var parts: [String] = []
        if let day = snapshot.eventDate {
            parts.append(EveningDates.longText(day, referenceYear: referenceYear, capitalized: true))
        }
        parts.append(snapshot.round.firstHole == 10 ? "hull 10–18" : "\(snapshot.round.holeCount) hull")
        parts.append(players == 1 ? "1 spiller" : "\(players) spillere")
        let finished = snapshot.round.status == .locked
        return MyRoundItem(
            id: snapshot.round.id,
            title: snapshot.course?.name ?? "Runde",
            subtitle: parts.joined(separator: " · "),
            status: snapshot.round.status,
            mine: rows.first(where: \.isMe).map { "Du: " + placeText($0) + value($0) },
            leader: leaderLine(rows, finished: finished, holeCount: game.holeCount),
            sortKey: snapshot.round.lockedAt ?? snapshot.round.startedAt ?? .distantPast
        )
    }

    /// Verdien slik den deles (`ResultShare`): stillingen i en hullmatch, ellers poengene.
    static func value(_ row: BayenRow) -> String {
        row.match != nil ? row.value : "\(row.total) p"
    }

    private static func placeText(_ row: BayenRow) -> String {
        row.place.map { "\($0). plass · " } ?? ""
    }

    /// Den som leder (eller vant). Ingen når ingen har ført noe, eller runden avgjøres hull for hull
    /// (da er det ingen plass å vise).
    static func leaderLine(_ rows: [BayenRow], finished: Bool, holeCount: Int) -> String? {
        guard let top = rows.first, top.place == 1, top.thru > 0 else { return nil }
        let tied = rows.filter { $0.place == 1 }.count
        let names = tied > 1 ? "\(top.name) m.fl." : top.name
        if finished { return "Vinner: \(names) · \(value(top))" }
        let thru = top.thru >= holeCount ? "" : " etter \(top.thru)"
        return "Leder: \(names) · \(value(top))\(thru)"
    }
}
