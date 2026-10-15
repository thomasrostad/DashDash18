import SwiftUI

// K6/6.3 (UI-utbedringen): signalet og arket når to markører førte ulikt (sql/055).

/// Stripa over føringen: «Hull 5: to markører førte ulikt for Kåre.» med «Velg tall».
struct MarkorKonfliktStripe: View {
    let text: String
    let onOpen: () -> Void

    var body: some View {
        DDInfoStripe(tone: .sun) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DDSpacing.s) {
                    label
                    Spacer(minLength: 8)
                    button
                }
                VStack(alignment: .leading, spacing: DDSpacing.s) {
                    label
                    button
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        Label(text, systemImage: "exclamationmark.2")
            .labelStyle(DDIconLabelStyle())
    }

    private var button: some View {
        Button("Velg tall", action: onOpen)
            .buttonStyle(.dd(.primary, compact: true))
            .fixedSize()
    }
}

/// Merket på raden i hullkortet: «To ulike tall · velg».
struct MarkorKonfliktKnapp: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("To ulike tall · velg", systemImage: "exclamationmark.2")
                .font(.ddStatus)
                .foregroundStyle(Color.ddRustText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("To markører førte ulike tall. Velg hvilket som gjelder.")
    }
}

/// Arket: begge tallene, hvem som førte og når, og «Bruk N slag».
struct MarkorKonfliktArk: View {
    /// «Hull 5 · Kåre».
    let title: String
    let options: [MarkerConflicts.Option]
    let onChoose: (Int) async throws(DataError) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Int?
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.m) {
                    Text("To markører førte ulike tall. Velg det som stemmer. Tallet som står nå, teller til du velger.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                    ForEach(options) { option in
                        optionButton(option)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.ddStatus)
                            .ddErrorStyle()
                    }
                    Button(action: choose) {
                        ZStack {
                            Text(chosen.map { "Bruk \($0) slag" } ?? "Velg et tall")
                                .opacity(isSaving ? 0 : 1)
                            if isSaving { ProgressView().tint(DDToken.buttonPrimaryText.color) }
                        }
                    }
                    .buttonStyle(.ddPrimary)
                    .disabled(chosen == nil || isSaving)
                    .padding(.top, DDSpacing.s)
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDCancelToolbarItem {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.ddBackground)
    }

    private func optionButton(_ option: MarkerConflicts.Option) -> some View {
        let selected = chosen == option.strokes
        return Button {
            chosen = option.strokes
            error = nil
        } label: {
            HStack(alignment: .center, spacing: DDSpacing.m) {
                Text("\(option.strokes)")
                    .font(.ddStrokes)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddForestInk)
                    .frame(minWidth: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.strokes == 1 ? "1 slag" : "\(option.strokes) slag")
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddInk)
                    Text(option.byline)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                    if option.isCurrent {
                        DDChip("Står nå", tone: .earth, compact: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? Color.ddForestInk : Color.ddHairline)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .ddCard(.standard)
        .overlay {
            RoundedRectangle(cornerRadius: DDRadius.card)
                .strokeBorder(selected ? Color.ddForestInk : .clear, lineWidth: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose() {
        guard let chosen, !isSaving else { return }
        isSaving = true
        error = nil
        Task {
            do throws(DataError) {
                try await onChoose(chosen)
                dismiss()
            } catch {
                self.error = error.message
            }
            isSaving = false
        }
    }
}
