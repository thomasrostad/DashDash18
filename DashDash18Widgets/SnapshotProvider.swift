import Foundation
import WidgetKit

/// Én tidslinje-oppføring: widget-dataene slik appen sist skrev dem.
nonisolated struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Leser `WidgetSnapshot` fra App Group-en. Appen skriver og ber om omlasting
/// (`WidgetCenter.reloadAllTimelines`) når Kveld eller Tavla har lastet noe nytt.
/// Ellers lages én oppføring per midnatt fram til kvelden, så «I morgen» blir «I dag».
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetSnapshotStore.shared.read()
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.shared.read()
        let now = Date.now
        var dates = [now]
        if let start = snapshot.nextEvening?.startsAt, start > now {
            var day = WidgetText.osloCalendar.startOfDay(for: now)
            // Hver midnatt fram til kvelden (høyst en uke), så nedtellingen stemmer uten appen.
            for _ in 0..<7 {
                guard let next = WidgetText.osloCalendar.date(byAdding: .day, value: 1, to: day), next <= start else { break }
                dates.append(next)
                day = next
            }
        }
        // Midnatt etter kvelden: da er den spilt, og widgeten slutter å vise den som «I dag».
        if let start = snapshot.nextEvening?.startsAt,
           let after = WidgetText.osloCalendar.date(byAdding: .day, value: 1,
                                                     to: WidgetText.osloCalendar.startOfDay(for: start)),
           after > now, after > (dates.last ?? now) {
            dates.append(after)
        }
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        // Etter siste oppføring: les på nytt om noen timer (appen har kanskje ikke vært åpnet).
        let refresh = (dates.last ?? now).addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

extension WidgetSnapshot {
    /// Eksempeldata til widget-galleriet og forhåndsvisninger.
    nonisolated static let preview = WidgetSnapshot(
        nextEvening: NextEvening(eventDate: "2026-10-08", dateText: "Torsdag 8. oktober", timeText: "17:00",
                                 startsAt: Date.now.addingTimeInterval(86_400), venue: "Losby"),
        seasonName: "Høst 2026",
        top: [
            Leader(place: 1, name: "Anders", points: 14.5, pointsText: "14,5", isMe: false),
            Leader(place: 2, name: "Bjørn", points: 12, pointsText: "12", isMe: true),
            Leader(place: 3, name: "Cato", points: 9, pointsText: "9", isMe: false),
        ],
        updatedAt: .now)
}
