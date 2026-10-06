import ActivityKit
import SwiftUI
import WidgetKit

/// Live Activity under runden: låseskjerm og Dynamic Island. Dataene kommer fra
/// `RoundActivityController` i appen (`RoundActivityAttributes`).
struct RoundLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RoundActivityAttributes.self) { context in
            RoundLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(WidgetPalette.forest)
                .activitySystemActionForegroundColor(WidgetPalette.onDark)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RoundStat(label: "HULL", value: "\(state.holeNumber)", detail: "\(state.holesPlayed)/\(state.holeCount) ført")
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RoundStat(label: "POENG", value: "\(state.points)", detail: "\(state.strokes) slag", alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.courseName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetPalette.onDarkSecondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let place = RoundText.place(state) {
                            Label(place, systemImage: "person.3")
                        }
                        Spacer(minLength: 8)
                        if let match = state.matchText {
                            Text(match)
                                .fontWeight(.semibold)
                                .foregroundStyle(RoundText.matchColor(state.matchTone))
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetPalette.onDark)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text("H\(state.holeNumber)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.gold)
            } compactTrailing: {
                Text(state.matchText.map(RoundText.shortMatch) ?? "\(state.points) p")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(state.matchText == nil ? WidgetPalette.onDark : RoundText.matchColor(state.matchTone))
            } minimal: {
                Text("\(state.holeNumber)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.gold)
            }
            .keylineTint(WidgetPalette.gold)
        }
    }
}

/// Låseskjermen: bane og hull øverst, så poeng, plass i båsen og matchen.
struct RoundLockScreenView: View {
    let attributes: RoundActivityAttributes
    let state: RoundActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(attributes.courseName.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.onDarkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(isStale ? "Ikke oppdatert" : "Oppdatert \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetPalette.onDarkSecondary)
            }
            HStack(alignment: .bottom, spacing: 16) {
                RoundStat(label: "HULL", value: "\(state.holeNumber)", detail: "\(state.holesPlayed)/\(state.holeCount) ført")
                RoundStat(label: "POENG", value: "\(state.points)", detail: "\(state.strokes) slag")
                if let place = state.bayPlace, let count = state.bayCount {
                    RoundStat(label: state.bayNumber.map { "BÅS \($0)" } ?? "PLASS", value: "\(place)", detail: "av \(count)")
                }
                Spacer(minLength: 0)
            }
            if let match = state.matchText {
                HStack(spacing: 6) {
                    Image(systemName: "flag.2.crossed")
                    Text(match).fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .foregroundStyle(RoundText.matchColor(state.matchTone))
            }
            ProgressView(value: Double(state.holesPlayed), total: Double(max(state.holeCount, 1)))
                .tint(WidgetPalette.gold)
        }
        .padding(16)
        .foregroundStyle(WidgetPalette.onDark)
    }
}

/// Et tall med etikett over og forklaring under («HULL / 7 / 6/18 ført»).
struct RoundStat: View {
    let label: String
    let value: String
    let detail: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(WidgetPalette.onDarkSecondary)
            Text(value)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetPalette.onDark)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(WidgetPalette.onDarkSecondary)
        }
    }
}

nonisolated enum RoundText {
    /// «2. av 4 i bås 1», eller «2. av 8» uten båser.
    static func place(_ state: RoundActivityAttributes.ContentState) -> String? {
        guard let place = state.bayPlace, let count = state.bayCount else { return nil }
        return "\(place). av \(count)" + (state.bayNumber.map { " i bås \($0)" } ?? "")
    }

    /// Kort matchtekst til Dynamic Island: «2 opp etter 5» → «2 opp».
    static func shortMatch(_ text: String) -> String {
        text.components(separatedBy: " etter ").first ?? text
    }

    /// Grønn opp, rust ned, ellers lys tekst (alt på mørk flate).
    static func matchColor(_ tone: RoundActivityAttributes.ContentState.MatchTone) -> Color {
        switch tone {
        case .up: WidgetPalette.lime
        case .down: WidgetPalette.rustOnDark
        case .neutral: WidgetPalette.onDark
        }
    }
}

extension RoundActivityAttributes {
    nonisolated static let preview = RoundActivityAttributes(roundID: UUID(), courseName: "Losby", playerName: "Anders")
}

extension RoundActivityAttributes.ContentState {
    nonisolated static let preview = RoundActivityAttributes.ContentState(
        holeNumber: 7, holeCount: 18, holesPlayed: 6, strokes: 27, points: 13, bayPlace: 2, bayCount: 4,
        bayNumber: 1, matchText: "2 opp etter 6", matchTone: .up, updatedAt: .now)
}

#Preview("Låseskjerm", as: .content, using: RoundActivityAttributes.preview) {
    RoundLiveActivityWidget()
} contentStates: {
    RoundActivityAttributes.ContentState.preview
}

#Preview("Utvidet", as: .dynamicIsland(.expanded), using: RoundActivityAttributes.preview) {
    RoundLiveActivityWidget()
} contentStates: {
    RoundActivityAttributes.ContentState.preview
}

#Preview("Kompakt", as: .dynamicIsland(.compact), using: RoundActivityAttributes.preview) {
    RoundLiveActivityWidget()
} contentStates: {
    RoundActivityAttributes.ContentState.preview
}
