import GolfgutuCore
import SwiftUI

/// Ny sesong: forslaget er ferdig utfylt («Sesongen <år>» og reglene fra forrige sesong).
/// Sesongen starter som planlagt.
struct NySesongView: View {
    let model: SesongAdminModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var template: SeasonLifecycle.Template = .golfgutu
    @State private var isBusy = false
    @State private var error: DataError?

    var body: some View {
        DDForm {
            DDSection("Navn") {
                TextField("For eksempel «Sesongen 2027»", text: $name)
                    .textInputAutocapitalization(.sentences)
            }
            Section {
                Picker("Mal", selection: $template) {
                    Text("Golfgutu-oppsettet").tag(SeasonLifecycle.Template.golfgutu)
                    ForEach(model.seasons) { season in
                        Text("Kopi av «\(season.name)»").tag(SeasonLifecycle.Template.copy(season.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                DDHeader("Regler")
            } footer: {
                DDFooter(model.seasons.isEmpty
                         ? "Golfgutu-oppsettet er reglene fra GolfGutu Invitational. Du kan endre alt etterpå."
                         : "Forslaget er reglene fra forrige sesong. Golfgutu-oppsettet er reglene fra GolfGutu Invitational. Du kan endre alt etterpå.")
            }
            RulesetSummarySection(rules: SeasonLifecycle.rules(for: template, seasons: model.seasons), title: "Slik blir det")
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle("Ny sesong")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lag") { create() }
                    .disabled(isBusy)
            }
        }
        .disabled(isBusy)
        .onAppear {
            template = SeasonLifecycle.defaultTemplate(seasons: model.seasons)
            if name.isEmpty { name = SeasonLifecycle.suggestedName(seasons: model.seasons) }
        }
    }

    private func create() {
        guard let name = ClubInput.normalizedName(name, maxLength: 60) else {
            error = .invalid("Skriv inn et navn på sesongen (høyst 60 tegn).")
            return
        }
        error = nil
        isBusy = true
        Task {
            do {
                try await model.create(name: name, template: template)
                dismiss()
            } catch {
                self.error = DataError.from(error)
            }
            isBusy = false
        }
    }
}
