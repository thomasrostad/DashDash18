import SwiftUI

/// Navn og handicap under «Deg». Spilleren endrer bare sin egen rad.
struct DegProfileSection: View {
    @State private var model: DegProfileModel
    @Environment(ClubModel.self) private var club
    @State private var draft = DegProfileDraft(name: "", handicap: "")
    @State private var savedMessage: String?

    init(context: ClubContext) {
        _model = State(initialValue: DegProfileModel(context: context))
    }

    var body: some View {
        Section {
            if let row = model.row {
                TextField("Navn i troppen", text: $draft.name)
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                TextField("Handicapindeks (valgfritt)", text: $draft.handicap)
                    .keyboardType(.numbersAndPunctuation)
                if draft.hasChanges(from: row) {
                    Button("Lagre") {
                        Task { await save() }
                    }
                    .disabled(model.isSaving)
                } else if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("Last inn på nytt") {
                    Task { await model.load() }
                }
            }
        } header: {
            Text("Navn og handicap")
        } footer: {
            Text("Komma eller punktum. Plusshandicap skrives med «+», f.eks. +2,3.")
        }
        .task {
            if model.row == nil { await model.load() }
            if let row = model.row { draft = DegProfileDraft(row: row) }
        }
        .alert(
            "Kunne ikke lagre",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
            presenting: model.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private func save() async {
        savedMessage = nil
        guard let saved = await model.save(draft) else { return }
        draft = DegProfileDraft(row: saved)
        savedMessage = "Lagret"
        // Navnet står også i medlemskapet (klubbvelger, «Navn i troppen»).
        if let userID = saved.userID {
            await club.load(userID: userID)
        }
    }
}
