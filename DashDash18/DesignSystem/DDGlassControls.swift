import SwiftUI

/// Segmentvelger i glass med skogfylt aktiv pille (planen 1.3: valgt er skog, ikke lime).
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
                        .foregroundStyle(selected ? Color.ddSelectedInk : Color.ddInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.ddSelected)
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
        // Kontrollen må holde seg innenfor skjermen: i AX3 dyttet den Tavla ut på sidene.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Nedtrekkspille («Hull 10 ▾»). Bruk som label i en `Menu`. Chip-flate med skogtekst:
/// gul er bare for hovedhandlingen (planen 1.1).
struct DDDropdownPill: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .subheadline))
            Image(systemName: "chevron.down")
                .font(.system(.caption2, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Color.ddForestInk)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(Capsule().fill(Color.ddChipFill))
        .contentShape(Capsule())
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
                .foregroundStyle(highlight ? Color.ddGold : Color.ddStatText)
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
