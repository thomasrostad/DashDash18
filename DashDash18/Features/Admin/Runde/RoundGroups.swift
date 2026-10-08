import Foundation

/// Rundene på én kveld, slik de står i «Alle runder». Kvelden er `nil` for runder uten kveld.
nonisolated struct RoundGroup: Identifiable, Equatable, Sendable {
    let event: EventRow?
    /// I rundenummerets rekkefølge.
    let rounds: [RoundRow]

    var id: UUID { event?.id ?? RoundGroups.noEventID }

    /// «Torsdag 8. oktober», eller «Uten kveld».
    var title: String {
        event.map { EveningDates.longText($0.eventDate, capitalized: true) } ?? "Uten kveld"
    }
}

/// Én liste for alle rundene, gruppert per kveld.
nonisolated enum RoundGroups {
    static let noEventID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Nyeste kveld først, innen kvelden stigende rundenummer. Runder uten kveld sist.
    /// Bare kvelder med runder er med.
    static func make(rounds: [RoundRow], events: [EventRow]) -> [RoundGroup] {
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var byEvent: [UUID?: [RoundRow]] = [:]
        for round in rounds {
            let key: UUID? = round.eventID.flatMap { byID[$0] }?.id
            byEvent[key, default: []].append(round)
        }
        var groups = byEvent.compactMap { key, rows -> RoundGroup? in
            guard let key else { return nil }
            return RoundGroup(event: byID[key], rounds: rows.sorted { $0.roundNo < $1.roundNo })
        }
        groups.sort { a, b in
            let da = a.event?.eventDate ?? "", db = b.event?.eventDate ?? ""
            return da != db ? da > db : a.id.uuidString < b.id.uuidString
        }
        if let loose = byEvent[nil], !loose.isEmpty {
            groups.append(RoundGroup(event: nil, rounds: loose.sorted { $0.roundNo < $1.roundNo }))
        }
        return groups
    }

    /// Kan det settes opp en ny runde på kvelden? Bare kvelder som ikke er passert.
    static func allowsNewRound(_ event: EventRow, today: String) -> Bool {
        event.eventDate >= today
    }
}
