import SwiftUI

/// Forklaringen på NGF-nummeret, under skjemaet og seksjonene.
private let ngfExplanation = "NGF-nummeret brukes når du melder deg på turneringer på ekte bane. På simulator trengs det ikke."

/// Skjemaet for egen profil, i et ark: navn, handicapindeks og NGF-nummer (uten klubb), eller bare
/// NGF-nummeret (med klubb, der navnet og handicapet står i medlemskapet).
struct OwnProfileEditSheet: View {
    let model: OwnProfileModel
    let scope: OwnProfileScope
    var onSaved: (OwnProfileRow) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var draft: OwnProfileDraft
    @FocusState private var focusedName: Bool

    init(model: OwnProfileModel, scope: OwnProfileScope, onSaved: @escaping (OwnProfileRow) -> Void = { _ in }) {
        self.model = model
        self.scope = scope
        self.onSaved = onSaved
        let empty = OwnProfileDraft(name: "", handicap: "", ngf: "", scope: scope)
        _draft = State(initialValue: model.row.map { OwnProfileDraft(row: $0, scope: scope) } ?? empty)
    }

    var body: some View {
        NavigationStack {
            DDForm {
                if scope == .full {
                    Section {
                        TextField("Navnet ditt", text: $draft.name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .focused($focusedName)
                        TextField("Handicapindeks (valgfritt)", text: $draft.handicap)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                    } header: {
                        DDHeader("Navn og handicap")
                    } footer: {
                        DDFooter("Navnet er det de andre ser i rundene og søket. Handicap med komma eller punktum, f.eks. 12,4. Plusshandicap skrives med «+», f.eks. +2,3.")
                    }
                }
                Section {
                    TextField("NGF-medlemsnummer (valgfritt)", text: $draft.ngf)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    DDHeader("NGF-nummer")
                } footer: {
                    DDFooter(ngfExplanation)
                }
            }
            .navigationTitle(scope == .full ? "Navn og handicap" : "NGF-nummer")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDCancelToolbarItem {
                    Button("Avbryt") { dismiss() }
                }
                DDConfirmToolbarItem {
                    if model.isSaving {
                        ProgressView()
                    } else {
                        Button("Lagre") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .task {
                // Åpnet før profilen er hentet (fra Spill): hent den og fyll skjemaet.
                if model.row == nil {
                    await model.load()
                    if let row = model.row { draft = OwnProfileDraft(row: row, scope: scope) }
                }
                if scope == .full, OwnProfile.needsName(model.row?.displayName) { focusedName = true }
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
        .tint(Color.ddForestInk)
    }

    private var canSave: Bool {
        guard let row = model.row else { return false }
        return draft.hasChanges(from: row)
    }

    private func save() async {
        guard let saved = await model.save(draft) else { return }
        onSaved(saved)
        dismiss()
    }
}

/// Oppfordringen når profilen mangler navn (vennemodus). Ikke-blokkerende: et trykk åpner skjemaet.
struct OwnProfileNamePrompt: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DDInfoStripe(tone: .sun) {
                Label("Legg inn navnet ditt, så ser de andre hvem du er", systemImage: "person.text.rectangle")
                    .fontWeight(.medium)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Åpner navn og handicap")
        .accessibilityIdentifier("profil.navnOppfordring")
    }
}

/// Deg uten klubb: profilen (navn, handicap og NGF-nummer) med «Endre».
struct OwnProfileSections: View {
    let model: OwnProfileModel
    @State private var editing = false

    var body: some View {
        Section {
            HStack(spacing: DDSpacing.m) {
                DDAvatar(name: model.row?.displayName ?? "?", size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.ddName)
                        .foregroundStyle(Color.ddInk)
                    Text("Spiller uten klubb · " + DegHandicapText.short(model.row?.handicapIndex))
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .padding(.vertical, 6)
            if model.row != nil, OwnProfile.needsName(model.row?.displayName) {
                OwnProfileNamePrompt { editing = true }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
        Section {
            if let row = model.row {
                LabeledContent("Navn", value: OwnProfile.needsName(row.displayName) ? "Ikke satt" : row.displayName ?? "")
                LabeledContent("Handicapindeks", value: row.handicapIndex.map { TroppInput.handicapText($0) } ?? "Ikke oppgitt")
                LabeledContent("NGF-nummer", value: row.ngfNumber ?? "Ikke oppgitt")
                Button("Endre navn og handicap") { editing = true }
                    .fontWeight(.medium)
                    .accessibilityIdentifier("profil.endre")
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("Last inn på nytt") { Task { await model.load() } }
                    .fontWeight(.medium)
            }
        } header: {
            DDHeader("Navn og handicap")
        } footer: {
            DDFooter("Navnet og handicapet brukes i rundene dine og når du blir med i en turnering. " + ngfExplanation)
        }
        .task {
            if model.row == nil { await model.load() }
        }
        .sheet(isPresented: $editing) {
            OwnProfileEditSheet(model: model, scope: .full)
        }
    }

    private var displayName: String {
        guard let name = model.row?.displayName, !OwnProfile.needsName(name) else { return "Ditt navn" }
        return name
    }
}

/// Deg med klubb: NGF-nummeret på profilen. Navnet og handicapet står i medlemskapet over.
struct OwnProfileNGFSection: View {
    @State private var model: OwnProfileModel
    @State private var editing = false

    init(context: ClubContext) {
        _model = State(initialValue: OwnProfileModel(client: context.client, userID: context.user.id))
    }

    var body: some View {
        Section {
            if let row = model.row {
                LabeledContent("NGF-nummer", value: row.ngfNumber ?? "Ikke oppgitt")
                Button(row.ngfNumber == nil ? "Legg inn NGF-nummer" : "Endre NGF-nummer") { editing = true }
                    .fontWeight(.medium)
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("Last inn på nytt") { Task { await model.load() } }
                    .fontWeight(.medium)
            }
        } header: {
            DDHeader("NGF-medlemsnummer")
        } footer: {
            DDFooter(ngfExplanation)
        }
        .task {
            if model.row == nil { await model.load() }
        }
        .sheet(isPresented: $editing) {
            OwnProfileEditSheet(model: model, scope: .ngfOnly)
        }
    }
}

#if DEBUG
#Preview("Deg uten navn") {
    NavigationStack {
        DDList {
            OwnProfileSections(model: OwnProfileModel(preview: OwnProfileRow(id: UUID(), displayName: nil, handicapIndex: nil, ngfNumber: nil)))
        }
        .navigationTitle("Deg")
    }
}

#Preview("Skjema") {
    OwnProfileEditSheet(
        model: OwnProfileModel(preview: OwnProfileRow(id: UUID(), displayName: "Kari", handicapIndex: 12.4, ngfNumber: "12345")),
        scope: .full
    )
}
#endif
