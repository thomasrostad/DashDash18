import Foundation

/// Widgetene er av til widget-targetet (DashDash18Widgets) og App Group-en finnes.
/// Se docs/widgets-oppsett.md.
nonisolated enum WidgetFeature {
    static let isEnabled = true
}

// Kveld og Tavla → widget-data. Bare oppslag og formatering av det modellene allerede har.

nonisolated extension WidgetSnapshot.NextEvening {
    /// Kvelden slik Kveld viser den. `referenceYear` gir året i teksten når det er et annet.
    init(event: EventRow, referenceYear: Int? = nil) {
        let day = EveningDates.date(from: event.eventDate)
        let start = day.flatMap { day in event.startTime.flatMap { EveningDates.time(from: $0, on: day) } } ?? day
        let venue = event.venue?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(eventDate: event.eventDate,
                  dateText: EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true),
                  timeText: EveningDates.timeText(event.startTime),
                  startsAt: start,
                  venue: venue?.isEmpty == false ? venue : nil)
    }
}

nonisolated extension WidgetSnapshot {
    /// Topp 3 i tabellens rekkefølge, med plass og poeng slik Tavla viser dem.
    static func topThree(_ standings: TavlaStandings) -> [Leader] {
        topThree(standings.rows, format: standings.points)
    }

    static func topThree(_ rows: [TavlaStandings.Row], format: (Double) -> String) -> [Leader] {
        rows.prefix(3).map { row in
            Leader(place: row.place, name: row.name, points: row.total, pointsText: format(row.total), isMe: row.isMe)
        }
    }
}

/// Skriver widget-data når Kveld og Tavla har lastet. Av til `WidgetFeature.isEnabled`.
enum WidgetSnapshotPublisher {
    /// Neste kveld fra Kveld (nil: ingen kveld satt opp).
    static func publish(nextEvening event: EventRow?, today: String) {
        guard WidgetFeature.isEnabled else { return }
        let next = event.map { WidgetSnapshot.NextEvening(event: $0, referenceYear: EveningDates.year(of: today)) }
        WidgetSnapshotStore.shared.update { $0.nextEvening = next }
    }

    /// Topp 3 fra Tavla (nil: ingen sesong).
    static func publish(standings: TavlaStandings?) {
        guard WidgetFeature.isEnabled else { return }
        WidgetSnapshotStore.shared.update { snapshot in
            snapshot.seasonName = standings?.seasonName
            snapshot.top = standings.map(WidgetSnapshot.topThree) ?? []
        }
    }
}
