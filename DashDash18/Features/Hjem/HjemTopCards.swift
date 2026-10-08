import SwiftUI

// Toppen av Hjem (fase 19, docs/hjem-feed.md 1a + 1b): filterpillene, oppsummeringen,
// «Pågår nå» og «Neste kveld».

extension HomeFeedTone {
    var ddTone: DDTone {
        switch self {
        case .lime: .lime
        case .sun: .sun
        case .earth: .earth
        case .blush: .blush
        case .gold: .gold
        }
    }
}

/// Filterpillene: vannrett rull, valgt i aksent-lime (`DDChoiceButtonStyle`-logikken).
struct HjemFilterBar: View {
    let pills: [HomeFeedPill]
    let select: (HomeFeedFilter) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    Button { select(pill.filter) } label: {
                        Text(pill.title)
                            .font(.dd(.sans, size: 14.5, weight: pill.isSelected ? .semibold : .medium,
                                      relativeTo: .subheadline))
                            .foregroundStyle(pill.isSelected ? Color.ddLimeOnAccent : Color.ddInkSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(pill.isSelected ? Color.ddLime : Color.ddCard))
                            .overlay(Capsule().strokeBorder(pill.isSelected ? Color.clear : Color.ddHairline,
                                                            lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(pill.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// 1b: «Siden sist» i grønt hero-kort, med én setning og tre tall.
struct HjemSummaryCard: View {
    let summary: HomeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.eyebrow)
                    .ddEyebrow(color: .ddGold)
                Text(summary.sentence)
                    .font(.dd(.sans, size: 24, weight: .light, relativeTo: .title2))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(summary.stats, id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.value)
                            .font(.dd(.sans, size: 26, weight: .light, relativeTo: .title))
                            .monospacedDigit()
                        Text(stat.label)
                            .font(.dd(.sans, size: 12, relativeTo: .caption))
                            .foregroundStyle(Color.ddOnDark.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ddOnDark.opacity(0.12), in: .rect(cornerRadius: DDRadius.input))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .ddCard(.hero)
    }
}

/// «Pågår nå»: svart stat-kort med live-pillen, bayen topp 3 og «Fortsett føringen».
struct HjemLiveCard: View {
    let live: HomeLive
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(Color(uiColor: DDToken.rust.values.light.uiColor)).frame(width: 8, height: 8)
                    Text("Runden pågår")
                }
                .font(.ddPill)
                .tracking(1.1)
                .textCase(.uppercase)
                // Det svarte kortet er likt i lys og mørk modus, så pillen har faste farger.
                .foregroundStyle(Color(uiColor: DDToken.blushInk.values.light.uiColor))
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(uiColor: DDToken.blushBackground.values.light.uiColor)))
                Spacer(minLength: 8)
                Text(live.progress)
                    .ddEyebrow(color: .ddStatSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(live.title)
                    .font(.ddTitle)
                if let detail = live.detail {
                    Text(detail)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddStatSecondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(HjemDisplay.liveRows(live)) { row in
                    HStack(spacing: 12) {
                        Text(row.place)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddStatSecondary)
                            .frame(width: 22, alignment: .leading)
                        Text(HjemDisplay.liveName(row))
                            .font(.ddNumber)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                            .font(.ddNumber)
                            .monospacedDigit()
                    }
                    .foregroundStyle(row.isMe ? Color.ddYellow : Color.ddStatText)
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Button(live.actionTitle, action: onContinue)
                .buttonStyle(.dd(.primary, fullWidth: true))
        }
        .ddCard(.stat)
    }
}

/// «Neste kveld»: dato, nedtelling, tid og sted, svarknappene og arrangørens knapp for neste steg.
/// Trykk på toppen åpner Kveld-skjermen.
struct HjemEveningCard: View {
    let evening: HomeNextEvening
    /// «Svaret ditt: Kommer» mens svaret kan angres.
    var pendingText: String?
    var error: String?
    let onOpen: () -> Void
    let onAnswer: (SignupStatus) -> Void
    let onUndo: () -> Void
    /// Arrangørens knapp for neste steg.
    var organizer: HjemOrganizerStep?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) { header }
                .buttonStyle(.plain)
                .accessibilityHint("Åpner kvelden: hvem som kommer, tråden og tipsen.")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(SignupStatus.allCases, id: \.self) { status in
                    let selected = evening.answer == status
                    Button { onAnswer(status) } label: {
                        Text(status.title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .buttonStyle(DDChoiceButtonStyle(selected: selected, tint: status.tint))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let pendingText {
                HStack {
                    Text(pendingText)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                    Spacer()
                    Button("Angre", action: onUndo)
                        .buttonStyle(.ddText)
                }
                .accessibilityElement(children: .combine)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .ddErrorStyle()
            }
            if evening.isOrganizer, let organizer {
                Button(action: organizer.perform) {
                    HStack(spacing: 8) {
                        Text(organizer.title)
                        if organizer.isBusy { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(organizer.isBusy)
                .accessibilityHint(organizer.hint)
            }
        }
        .animation(.default, value: pendingText)
        .ddCard()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evening.eyebrow)
                        .ddEyebrow()
                    Text(evening.title)
                        .font(.ddTitleSmall)
                        .foregroundStyle(Color.ddForestInk)
                }
                Spacer(minLength: 8)
                DDPill(evening.countdown, tone: .sun)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                Text(evening.detail)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}
