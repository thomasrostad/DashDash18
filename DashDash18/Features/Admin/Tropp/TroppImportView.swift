import SwiftUI

/// Legg til mange ledige navn på én gang: lim inn en liste (fra et regneark, en e-post eller
/// påmeldingslista), se hva som blir lagt til, og lagre alt med ett trykk.
struct TroppImportView: View {
    let model: TroppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var isBusy = false

    private var lines: [TroppImportLine] { TroppImport.parse(text, rows: model.rows) }

    var body: some View {
        let lines = lines
        let valid = TroppImport.valid(lines)
        NavigationStack {
            DDForm {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Navnene")
                } header: {
                    DDHeader("Ett navn per linje")
                } footer: {
                    DDFooter("Handicap kan stå etter navnet, f.eks. «Kari Nordmann 18,4». Fra et regneark kan du lime inn to kolonner. Høyst \(TroppImport.maxLines) navn om gangen.")
                }
                if !lines.isEmpty {
                    Section {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            row(line)
                        }
                    } header: {
                        DDHeader("\(valid.count) av \(lines.count) legges til")
                    }
                }
            }
            .navigationTitle("Legg til mange")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isBusy)
            .discardChangesGuard(hasChanges: !text.isEmpty && !isBusy, alwaysShowsCancel: true)
            .toolbar {
                DDConfirmToolbarItem {
                    Button(valid.isEmpty ? "Legg til" : "Legg til \(valid.count)", action: add)
                        .disabled(isBusy || valid.isEmpty)
                }
            }
            .troppErrorAlert(model: model)
        }
    }

    private func row(_ line: TroppImportLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DDSpacing.s) {
            Image(systemName: line.problem == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(line.problem == nil ? Color.ddForestInk : Color.ddInkSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name.isEmpty ? line.text : line.name)
                    .strikethrough(line.problem != nil)
                if let message = line.message {
                    Text(message)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer()
            if line.problem == nil, line.handicapIndex != nil {
                Text("hcp \(TroppInput.handicapText(line.handicapIndex))")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func add() {
        isBusy = true
        Task {
            if await model.add(lines) != nil {
                dismiss()
            }
            isBusy = false
        }
    }
}
