import SwiftUI

/// Segmentvelger i glass med grønn aktiv pille (golfee «Statistics | Notes»).
/// Pillen glir mellom valgene; med Reduser bevegelse bytter den uten å gli.
struct DDSegmentedControl<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.dd(.sans, size: 15, weight: selected ? .semibold : .regular, relativeTo: .subheadline))
                        .foregroundStyle(selected ? Color.ddLimeOnAccent : Color.ddInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.ddLime)
                                    .matchedGeometryEffect(id: "pille", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Gul nedtrekkspille (golfee «Hole 10 ▾»). Bruk som label i en `Menu`.
struct DDDropdownPill: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .subheadline))
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.ddYellowInk)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.ddYellow))
        .contentShape(Capsule())
    }
}

/// Rund flytende knapp i glass (golfee sine runde knapper over kartet).
struct DDGlassIconButtonStyle: ButtonStyle {
    /// Grønn fylt variant (aktiv), ellers klart glass.
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        DDGlassIconBody(configuration: configuration, prominent: prominent)
    }
}

private struct DDGlassIconBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(prominent ? Color.ddLimeOnAccent : Color.ddInk)
            .frame(width: 48, height: 48)
            .glassEffect(prominent ? .regular.tint(Color.ddLime) : .regular, in: .circle)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Én linje i et svart statistikk-kort: etikett til venstre, tall til høyre (hvitt, eller gult når det utheves).
struct DDStatRow: View {
    let label: String
    let value: String
    var secondary: String?
    var highlight = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.ddCallout)
                .foregroundStyle(Color.ddStatText)
            Spacer(minLength: 8)
            Text(value)
                .font(.dd(.sans, size: 15, weight: .medium, relativeTo: .callout))
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.ddYellow : Color.ddStatText)
            if let secondary {
                Text(secondary)
                    .font(.dd(.sans, size: 15, relativeTo: .callout))
                    .monospacedDigit()
                    .foregroundStyle(Color.ddStatSecondary)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Overskrift i et statistikk-kort: «Distances • yds».
struct DDStatHeader: View {
    let title: String
    var unit: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(Color.ddStatText)
            if let unit {
                Text("•").foregroundStyle(Color.ddStatSecondary)
                Text(unit).foregroundStyle(Color.ddYellow)
            }
        }
        .font(.dd(.sans, size: 15, weight: .medium, relativeTo: .callout))
        .accessibilityAddTraits(.isHeader)
    }
}
