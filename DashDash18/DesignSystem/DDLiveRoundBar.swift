import SwiftUI

/// Runden som pågår, som tilbehør over fanelinja (utbedringsplanen V1 og 1.5): lime live-prikk,
/// «Losby · hull 10 av 18», «Bås 2 · du er 3. med 21 p» og den gule «Fortsett» (44 pt).
/// Trykk på baren åpner føringen. Når fanelinja er krympet (`.inline`), står bare prikken, tittelen
/// og «Fortsett». `more` står foran «Fortsett» (for eksempel «+1 runde til»).
struct DDLiveRoundBar<More: View>: View {
    let title: String
    var detail: String?
    var actionTitle = "Fortsett"
    let open: () -> Void
    @ViewBuilder var more: More
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    init(title: String, detail: String? = nil, actionTitle: String = "Fortsett", open: @escaping () -> Void,
         @ViewBuilder more: () -> More = { EmptyView() }) {
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.open = open
        self.more = more()
    }

    private var isInline: Bool { placement == .inline }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 10) {
                    DDLiveDot()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Color.ddInk)
                        if let detail, !isInline {
                            Text(detail)
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(["Runden pågår", title, detail].compactMap { $0 }.joined(separator: ". "))
            .accessibilityHint("Åpner føringen.")
            if !isInline { more }
            Button(actionTitle, action: open)
                .buttonStyle(.dd(.primary, compact: true))
                .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
    }
}

/// Lime prikk for live (planen 1.1: lime betyr bare live). Pynt: teksten sier at runden pågår.
struct DDLiveDot: View {
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color.ddLime)
            .overlay(Circle().strokeBorder(Color.ddLimeInk.opacity(0.5), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Lite valg foran «Fortsett» når flere runder går: «+1» i en chip (VoiceOver: «+1 runde til»), så
/// tittelen får plass. Brukes som label i en `Menu`.
struct DDLiveRoundMoreLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.dd(.sans, size: 13, weight: .semibold, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(Color.ddForestInk)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 32)
            .background(Capsule().fill(Color.ddChipFill))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .fixedSize()
    }
}

#Preview("LiveRoundBar") {
    VStack(spacing: 20) {
        DDLiveRoundBar(title: "Losby · hull 10 av 18", detail: "Bås 2 · du er 3. med 21 p", open: {})
            .glassEffect(.regular, in: .capsule)
        DDLiveRoundBar(title: "Losby · hull 10 av 18", detail: "Bås 2 · du er 3. med 21 p", open: {}) {
            Menu {
                Button("Oslo GK · hull 4 av 18") {}
            } label: {
                DDLiveRoundMoreLabel(text: "+1")
            }
        }
        .glassEffect(.regular, in: .capsule)
    }
    .padding(DDSpacing.gutter)
    .ddScreenBackground()
}
