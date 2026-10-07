import SwiftUI

/// Ny bane (`item == nil`) eller endre en som finnes: navn, rating, i bruk og hullene.
struct CourseEditView: View {
    let model: CourseLibraryModel
    let item: CourseListItem?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CourseDraft
    @State private var original: CourseDraft
    @State private var triedToSave = false
    @State private var isBusy = false
    @State private var error: DataError?
    @State private var askDelete = false

    init(model: CourseLibraryModel, item: CourseListItem?) {
        self.model = model
        self.item = item
        let draft = item.map { CourseDraft(course: $0.course, holes: $0.holes) } ?? CourseDraft()
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
    }

    /// Banen slik den står i modellen nå (etter en bekreftelse, for eksempel).
    private var current: CourseListItem? {
        guard let item else { return nil }
        return model.items.first { $0.id == item.id } ?? item
    }

    var body: some View {
        let validation = draft.validate()
        DDForm {
            Section {
                TextField("Navn", text: $draft.name)
                    .textInputAutocapitalization(.words)
                TextField("Navn i simulatoren", text: $draft.externalName)
                    .autocorrectionDisabled()
                Toggle("I bruk", isOn: $draft.inUse)
            } header: {
                DDHeader("Banen")
            } footer: {
                DDFooter("Navnet i simulatoren er det dere slår opp i båsen, hvis det er et annet enn vårt. Baner som ikke er i bruk, vises ikke når en runde settes opp.")
            }

            Section {
                LabeledContent("Course Rating") {
                    TextField("Par", text: $draft.courseRatingText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Slope") {
                    TextField("113", text: $draft.slopeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                DDHeader("Rating")
            } footer: {
                DDFooter("Tomt felt regnes som banens par og slope 113. Da får spilleren handicapindeksen sin rett, som når simulatoren deler ut slagene.")
            }

            Section {
                Picker("Antall hull", selection: Binding(get: { draft.holeCount }, set: { draft.setHoleCount($0) })) {
                    ForEach(CourseDraft.holeCounts, id: \.self) { Text("\($0) hull").tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Par", value: draft.par.map(String.init) ?? "–")
            } footer: {
                DDFooter("Les par, indeks og lengde av skjermen i båsen. Tomme felt betyr at appen ikke vet. Indeks kan stå tom; den brukes bare når appen selv deler ut slagene.")
            }

            holeSection(title: "Hull 1–9", range: 0..<min(9, draft.holeCount))
            if draft.holeCount > 9 {
                holeSection(title: "Hull 10–18", range: 9..<draft.holeCount)
            }

            issuesSection(validation)

            if let current {
                confirmSection(current)
                Section {
                    Button("Slett banen", role: .destructive) { askDelete = true }
                } footer: {
                    DDFooter("Går bare når ingen runder bruker banen.")
                }
            }

            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle(item == nil ? "Ny bane" : draft.name.isEmpty ? "Bane" : draft.name)
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .discardChangesGuard(hasChanges: draft != original && !isBusy, alwaysShowsCancel: item == nil)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lagre") { save(validation) }
                    .disabled(isBusy || (item != nil && draft == original))
            }
        }
        .confirmationDialog("Slette \(item?.course.name ?? "banen")?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Slett", role: .destructive) { delete() }
        } message: {
            Text("Banen og hullene forsvinner fra biblioteket.")
        }
    }

    private func holeSection(title: String, range: Range<Int>) -> some View {
        Section {
            HStack {
                Text("Hull").frame(width: 44, alignment: .leading)
                Text("Par").frame(maxWidth: .infinity)
                Text("Indeks").frame(width: 64)
                Text("Meter").frame(width: 64)
            }
            .font(.dd(.sans, size: 12, relativeTo: .caption))
            .foregroundStyle(Color.ddInkSecondary)
            ForEach(range, id: \.self) { index in
                HoleRowEditor(hole: $draft.holes[index])
            }
        } header: {
            DDHeader(title)
        }
    }

    @ViewBuilder
    private func issuesSection(_ validation: CourseValidation) -> some View {
        let shown = validation.issues.filter { !$0.isBlocking || triedToSave }
        if !shown.isEmpty {
            Section {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, issue in
                    Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .foregroundStyle(issue.isBlocking ? Color.ddError : Color.ddRustText)
                        .font(.dd(.sans, size: 15, relativeTo: .callout))
                }
            }
        }
    }

    private func confirmSection(_ item: CourseListItem) -> some View {
        Section {
            ConfirmationText(course: item.course)
            Button("Bekreft mot skjermen", systemImage: "checkmark.seal") { confirm(item) }
                .disabled(draft != original || !item.isReady)
        } header: {
            DDHeader("Simulatorskjermen")
        } footer: {
            if draft != original {
                Text("Lagre endringene før du bekrefter.")
            } else if !item.isReady {
                Text("Banen må ha par på alle hull før den kan bekreftes.")
            } else {
                Text("Trykk når par og indeks over stemmer med det simulatoren viser for banen.")
            }
        }
    }

    private func save(_ validation: CourseValidation) {
        triedToSave = true
        guard let values = validation.values else { return }
        run {
            try await model.save(values, id: item?.id)
            dismiss()
        }
    }

    private func confirm(_ item: CourseListItem) {
        run { try await model.confirm(item) }
    }

    private func delete() {
        guard let current else { return }
        run {
            try await model.delete(current)
            dismiss()
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        isBusy = true
        Task {
            do {
                try await action()
            } catch {
                self.error = DataError.from(error)
            }
            isBusy = false
        }
    }
}

/// Én rad i hullnettet: nummer, par, indeks og lengde.
private struct HoleRowEditor: View {
    @Binding var hole: HoleDraft

    var body: some View {
        HStack {
            Text("\(hole.number)")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            Picker("Par på hull \(hole.number)", selection: $hole.par) {
                Text("–").tag(Int?.none)
                ForEach(CourseInput.parChoices, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            TextField("–", text: $hole.strokeIndexText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .accessibilityLabel("Indeks på hull \(hole.number)")
            TextField("–", text: $hole.lengthText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 64)
                .accessibilityLabel("Lengde i meter på hull \(hole.number)")
        }
        .monospacedDigit()
    }
}
