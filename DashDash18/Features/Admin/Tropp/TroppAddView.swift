import SwiftUI

/// Legg til et ledig navn i troppen. Spilleren tar det selv med invitasjonskoden.
struct TroppAddView: View {
    let model: TroppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var handicapText = ""
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            DDForm {
                Section {
                    TextField("Navn", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                    TextField("Handicapindeks (valgfritt)", text: $handicapText)
                        .keyboardType(.numbersAndPunctuation)
                } footer: {
                    DDFooter("Navnet står som ledig til spilleren logger inn og velger det. Plusshandicap skrives med «+».")
                }
            }
            .navigationTitle("Nytt navn")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isBusy)
            .discardChangesGuard(hasChanges: !(name.isEmpty && handicapText.isEmpty) && !isBusy, alwaysShowsCancel: true)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Verktøylinja arves ikke av `.disabled` over, så dobbelttrykk sperres her.
                    Button("Legg til", action: add)
                        .disabled(isBusy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .troppErrorAlert(model: model)
        }
    }

    private func add() {
        isBusy = true
        Task {
            if await model.add(name: name, handicap: handicapText) {
                dismiss()
            }
            isBusy = false
        }
    }
}
