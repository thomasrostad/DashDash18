import SwiftUI

/// «Maler»: gi nytt navn og slette (sql/049). Samme liste for runde- og turneringsmaler.
struct TemplateListView: View {
    let store: SetupTemplateStore
    @State private var renaming: SetupTemplateRow?
    @State private var newName = ""
    @State private var pendingDelete: SetupTemplateRow?
    @State private var error: String?

    var body: some View {
        DDList {
            Section {
                if (store.templates ?? []).isEmpty {
                    Text("Ingen maler ennå.").foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(store.templates ?? []) { row in
                    Button {
                        newName = row.name
                        renaming = row
                    } label: {
                        HStack {
                            Text(row.name).foregroundStyle(Color.ddInk)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(Color.ddInkSecondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Gi nytt navn")
                    .swipeActions {
                        Button("Slett", systemImage: "trash", role: .destructive) { pendingDelete = row }
                    }
                }
            } footer: {
                DDFooter(store.clubID == nil ? "Dine egne maler. Bare du ser dem."
                         : "Klubbens maler. Alle som setter opp runder eller turneringer, ser dem.")
            }
        }
        .navigationTitle("Maler")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .alert("Nytt navn", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Navn", text: $newName)
            Button("Lagre") { if let row = renaming { rename(row) } }
            Button("Avbryt", role: .cancel) {}
        }
        .confirmationDialog("Slette malen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                  set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { row in
            Button("Slett «\(row.name)»", role: .destructive) { delete(row) }
        } message: { _ in
            Text("Det som er laget med malen, står.")
        }
        .messageAlert("Det gikk ikke", text: $error)
    }

    private func rename(_ row: SetupTemplateRow) {
        let name = newName
        Task {
            do throws(DataError) {
                try await store.rename(row, to: name)
            } catch {
                self.error = error.message
            }
        }
    }

    private func delete(_ row: SetupTemplateRow) {
        Task {
            do throws(DataError) {
                try await store.delete(row)
            } catch {
                self.error = error.message
            }
        }
    }
}

/// «Lagre som mal»: navnet i et lite varsel.
struct SaveTemplatePrompt: ViewModifier {
    @Binding var isPresented: Bool
    let suggestion: String
    let save: (String) async throws(DataError) -> Void
    @State private var name = ""
    @State private var error: String?
    @State private var saved: String?

    func body(content: Content) -> some View {
        content
            .alert("Lagre som mal", isPresented: $isPresented) {
                TextField("Navn", text: $name)
                Button("Lagre") { run(name) }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Malen husker oppsettet, ikke spillerne.")
            }
            .onChange(of: isPresented) { _, shown in
                if shown { name = suggestion }
            }
            .messageAlert("Det gikk ikke", text: $error)
            .messageAlert("Malen er lagret", text: $saved)
    }

    private func run(_ name: String) {
        Task {
            do throws(DataError) {
                try await save(name)
                saved = "«\(name.trimmingCharacters(in: .whitespacesAndNewlines))» står under «Bruk mal»."
            } catch {
                self.error = error.message
            }
        }
    }
}

extension View {
    func saveTemplatePrompt(isPresented: Binding<Bool>, suggestion: String,
                            save: @escaping (String) async throws(DataError) -> Void) -> some View {
        modifier(SaveTemplatePrompt(isPresented: isPresented, suggestion: suggestion, save: save))
    }
}

/// «Samme som sist» i oppsettet: hvor forslaget kom fra, og valget mellom samme spillere og ny trekning.
struct PreviousRoundSection: View {
    let previous: PreviousRoundSetup
    let term: GroupTerm
    let samePlayers: () -> Void
    let freshDraw: () -> Void

    var body: some View {
        Section {
            Button("Samme spillere og \(term.plural)", systemImage: "arrow.uturn.backward", action: samePlayers)
                .foregroundStyle(Color.ddForestInk)
            Button("Ny trekning", systemImage: "dice", action: freshDraw)
                .foregroundStyle(Color.ddForestInk)
        } header: {
            DDHeader("Samme som sist")
        } footer: {
            DDFooter(previous.sourceText + ". Bane og valg er fylt inn.")
        }
    }
}
