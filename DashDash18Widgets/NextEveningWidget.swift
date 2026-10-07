import SwiftUI
import WidgetKit

/// «Neste kveld»: dato, klokkeslett, bane og nedtelling.
struct NextEveningWidget: Widget {
    let kind = "NextEveningWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            NextEveningView(entry: entry)
        }
        .configurationDisplayName("Neste kveld")
        .description("Dato, tid og bane for neste kveld.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextEveningView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Nil også når den lagrede kvelden er spilt og appen ikke har vært åpnet siden.
    private var evening: WidgetSnapshot.NextEvening? { entry.snapshot.upcomingEvening(at: entry.date) }

    /// Når det ikke er noen kveld å vise.
    private var emptyText: String {
        entry.snapshot.eveningIsOver(at: entry.date) ? "Kvelden er spilt" : "Ingen kveld satt opp"
    }

    private var countdown: String? {
        guard let start = evening?.startsAt else { return nil }
        return WidgetText.countdown(days: WidgetText.days(from: entry.date, to: start))
    }

    /// «17:00 · Losby».
    private var detail: String? {
        let parts = [evening?.timeText, evening?.venue].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium: WidgetPalette.background
                default: Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let evening {
                Text("\(countdown ?? evening.dateText)\(evening.timeText.map { " kl. \($0)" } ?? "")")
            } else {
                Text(emptyText)
            }
        case .accessoryCircular:
            if let start = evening?.startsAt {
                let days = max(0, WidgetText.days(from: entry.date, to: start))
                VStack(spacing: 0) {
                    Text(days == 0 ? "I dag" : "\(days)")
                        .font(.system(size: days == 0 ? 14 : 22, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    if days > 0 {
                        Text(days == 1 ? "dag" : "dager").font(.system(size: 10))
                    }
                }
                .widgetAccentable()
            } else {
                Image(systemName: "figure.golf")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Neste kveld").font(.caption2.weight(.semibold)).widgetAccentable()
                if let evening {
                    Text(evening.dateText).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    if let detail { Text(detail).font(.caption).lineLimit(1) }
                } else {
                    Text(emptyText).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            system
        }
    }

    /// Liten og middels: krem flate, grønn tekst, gul nedtelling.
    private var system: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NESTE KVELD")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                Spacer(minLength: 4)
                if family == .systemMedium, let countdown {
                    pill(countdown)
                }
            }
            if let evening {
                Text(evening.dateText)
                    .font(.system(size: family == .systemSmall ? 20 : 24, weight: .medium))
                    .foregroundStyle(WidgetPalette.forestInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if let time = evening.timeText {
                    Label(time, systemImage: "clock")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WidgetPalette.ink)
                }
                if let venue = evening.venue {
                    Label(venue, systemImage: "flag")
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(1)
                }
                if family == .systemSmall, let countdown {
                    pill(countdown)
                }
            } else {
                Spacer(minLength: 0)
                Text(emptyText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetPalette.forestInk)
                Text(entry.snapshot.eveningIsOver(at: entry.date)
                     ? "Åpne appen for neste kveld." : "Åpne appen for å se terminlista.")
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetPalette.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WidgetPalette.yellowInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(WidgetPalette.yellow, in: Capsule())
    }
}

#Preview("Liten", as: .systemSmall) {
    NextEveningWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
    SnapshotEntry(date: .now, snapshot: .empty)
}

#Preview("Middels", as: .systemMedium) {
    NextEveningWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
