import GolfgutuCore
import SwiftUI

/// Ny eller endre kveld.
struct EventEditor: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: TerminlisteModel
    @State var draft: EventDraft
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false
    @State private var confirmDelete = false

    var body: some View {
        DDForm {
            // Øverst, ved «Lagre»: lenger ned havner den under troppen og ses ikke.
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }

            Section {
                DatePicker("Dato", selection: $draft.date, displayedComponents: .date)
                Toggle("Klokkeslett", isOn: $draft.hasTime)
                if draft.hasTime {
                    DatePicker("Starter", selection: $draft.time, displayedComponents: .hourAndMinute)
                }
                TextField("Sted", text: $draft.venue)
                    .textInputAutocapitalization(.words)
                TextField("Notat (valgfritt)", text: $draft.note, axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                DDFooter("Én \(dayTerm.one) per dato.")
            }

            Section {
                ForEach(model.members) { member in
                    Button {
                        toggle(member.id)
                    } label: {
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            if draft.committee.contains(member.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(Color.ddInk)
                    .accessibilityAddTraits(draft.committee.contains(member.id) ? .isSelected : [])
                }
            } header: {
                DDHeader("Sosialkomité (\(draft.committee.count))")
            }

            if draft.id != nil {
                Section {
                    Button("Slett \(dayTerm.the)", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .navigationTitle(draft.id == nil ? "Ny \(dayTerm.one)" : "Endre \(dayTerm.one)")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: done)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isBusy {
                    ProgressView()
                } else {
                    Button("Lagre", action: save)
                }
            }
        }
        .confirmationDialog("Slette \(dayTerm.the)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Slett", role: .destructive, action: delete)
        } message: {
            Text("Påmeldingene og sosialkomiteen for \(dayTerm.the) slettes også.")
        }
    }

    private func toggle(_ id: UUID) {
        if draft.committee.contains(id) {
            draft.committee.remove(id)
        } else {
            draft.committee.insert(id)
        }
    }

    private func save() {
        run { () async throws(DataError) in try await model.save(draft) }
    }

    private func delete() {
        guard let id = draft.id, let event = model.events.first(where: { $0.id == id }) else { return }
        run { () async throws(DataError) in try await model.delete(event) }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await action()
                done()
            } catch {
                self.error = error.message
            }
        }
    }
}

/// Identifiserbar innpakning, så et utkast kan styre et ark.
struct EventEditItem: Identifiable {
    let id = UUID()
    let draft: EventDraft
}
