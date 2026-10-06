import SwiftUI
import WidgetKit

/// «Tavla topp 3»: plass, navn og poeng i sesongens tabell.
struct TopThreeWidget: Widget {
    let kind = "TopThreeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            TopThreeView(entry: entry)
        }
        .configurationDisplayName("Tavla topp 3")
        .description("De tre øverste i sesongens tabell.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TopThreeView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var top: [WidgetSnapshot.Leader] { entry.snapshot.top }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular { Color.clear } else { WidgetPalette.background }
            }
    }

    @ViewBuilder
    private var content: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text("Tavla").font(.caption2.weight(.semibold)).widgetAccentable()
                if top.isEmpty {
                    Text("Ingen tabell ennå").font(.caption)
                } else {
                    ForEach(top, id: \.place) { leader in
                        HStack(spacing: 4) {
                            Text("\(leader.place). \(leader.name)").lineLimit(1)
                            Spacer(minLength: 2)
                            Text(leader.pointsText).monospacedDigit()
                        }
                        .font(.caption)
                        .fontWeight(leader.isMe ? .semibold : .regular)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            system
        }
    }

    private var system: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 6) {
            HStack {
                Text("TAVLA")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.inkSecondary)
                Spacer(minLength: 4)
                if family == .systemMedium, let season = entry.snapshot.seasonName {
                    Text(season)
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetPalette.inkSecondary)
                        .lineLimit(1)
                }
            }
            if top.isEmpty {
                Spacer(minLength: 0)
                Text("Ingen tabell ennå")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetPalette.forestInk)
                Spacer(minLength: 0)
            } else {
                ForEach(top, id: \.place) { leader in
                    row(leader)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ leader: WidgetSnapshot.Leader) -> some View {
        HStack(spacing: 8) {
            Text("\(leader.place)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(leader.place == 1 ? WidgetPalette.yellowInk : WidgetPalette.forestInk)
                .frame(width: 20, height: 20)
                .background(leader.place == 1 ? WidgetPalette.yellow : WidgetPalette.card, in: Circle())
                .overlay(Circle().stroke(WidgetPalette.hairline, lineWidth: leader.place == 1 ? 0 : 0.5))
            Text(leader.name)
                .font(.system(size: family == .systemSmall ? 14 : 16, weight: leader.isMe ? .semibold : .regular))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(leader.pointsText)
                .font(.system(size: family == .systemSmall ? 14 : 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.forestInk)
        }
        .padding(.horizontal, leader.isMe ? 4 : 0)
        .padding(.vertical, family == .systemSmall ? 1 : 3)
        .background(leader.isMe ? WidgetPalette.youRow : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview("Liten", as: .systemSmall) {
    TopThreeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
    SnapshotEntry(date: .now, snapshot: .empty)
}

#Preview("Middels", as: .systemMedium) {
    TopThreeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .preview)
}
