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
    /// En bane med hull fra slope.no er valgt i «Hent fra slope.no» (fase 20b): den spilles direkte.
    @State private var playable: (course: SlopeCourseRow, tees: [CourseTeeRow])?

    @State private var showsIndex: Bool

    /// - Parameter initialDraft: et ferdig utfylt skjema for en ny bane (skjermprøvene).
    init(model: CourseLibraryModel, item: CourseListItem?, initialDraft: CourseDraft? = nil) {
        self.model = model
        self.item = item
        var empty = initialDraft ?? CourseDraft()
        // Det felles biblioteket er mest ekte baner (løse runder med venner).
        if model.isShared, initialDraft == nil { empty.kind = .course }
        let draft = item.map { CourseDraft(course: $0.course, holes: $0.holes, kind: $0.kind, tees: $0.tees) } ?? empty
        _draft = State(initialValue: draft)
        _original = State(initialValue: draft)
        _showsIndex = State(initialValue: draft.holes.contains { !$0.strokeIndexText.isEmpty || !$0.lengthText.isEmpty })
    }

    /// Banen slik den står i modellen nå (etter en bekreftelse, for eksempel).
    private var current: CourseListItem? {
        guard let item else { return nil }
        return model.items.first { $0.id == item.id } ?? item
    }

    var body: some View {
        let validation = draft.validate()
        DDForm {
            if item == nil, let catalog = model.slopeCatalog, draft.kind == .course {
                slopeSection(catalog)
            }
            courseSection
            readinessSection
            parSection(title: draft.holeCount > 9 ? "Par, hull 1–9" : "Par", range: 0..<min(9, draft.holeCount))
            if draft.holeCount > 9 {
                parSection(title: "Par, hull 10–18", range: 9..<draft.holeCount)
            }
            indexSection
            ratingSection
            CourseTeesSection(tees: $draft.tees)

            issuesSection(validation)

            if let current {
                // Det felles biblioteket har ingen klubb å bekrefte for.
                if !model.isShared {
                    confirmSection(current)
                }
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
        .alert(playable.map { "«\($0.course.name)» kan spilles direkte" } ?? "",
               isPresented: Binding(get: { playable != nil }, set: { if !$0 { playable = nil } })) {
            Button("OK") {
                playable = nil
                dismiss()
            }
            Button("Lag en egen kopi") {
                if let playable { draft.prefill(from: playable.course, tees: playable.tees) }
                playable = nil
            }
        } message: {
            Text(SlopeCourseSearch.playableNotice)
        }
    }

    // MARK: Delene

    /// «Hent fra slope.no»: navn, tees, CR og slope fylles inn. Hullene leses av scorekortet som før.
    private func slopeSection(_ catalog: SlopeCatalogModel) -> some View {
        Section {
            NavigationLink {
                SlopeCourseSearchView(model: catalog, onPick: { course, tees in
                    if catalog.usesHoles, course.hasHoles {
                        playable = (course, tees)
                    } else {
                        draft.prefill(from: course, tees: tees)
                    }
                })
            } label: {
                Label(draft.tees == nil ? "Hent fra slope.no" : "Hent en annen bane fra slope.no",
                      systemImage: "magnifyingglass")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                DDFooter(catalog.usesHoles
                         ? "Søk blant de nordiske banene. Har banen hull hos slope.no, spilles den direkte. Ellers fylles navn, tees, course rating og slope inn, og par og indeks leser du av scorekortet."
                         : "Søk blant de nordiske banene. Navn, tees, course rating og slope fylles inn. Par og indeks per hull står på scorekortet.")
                SlopeNoCreditLink(usesHoles: catalog.usesHoles)
            }
        }
    }

    /// Navn, type, antall hull og navnet i simulatoren.
    private var courseSection: some View {
        Section {
            TextField("Navn", text: $draft.name)
                .textInputAutocapitalization(.words)
            if CourseKindFeature.isEnabled {
                Picker("Type", selection: $draft.kind) {
                    ForEach(CourseKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Picker("Antall hull", selection: Binding(get: { draft.holeCount }, set: { draft.setHoleCount($0) })) {
                ForEach(CourseDraft.holeCounts, id: \.self) { Text("\($0) hull").tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.usesExternalName && !model.isShared {
                TextField("Navn i simulatoren (valgfritt)", text: $draft.externalName)
                    .autocorrectionDisabled()
            }
        } header: {
            DDHeader("Banen")
        } footer: {
            DDFooter(model.isShared
                     ? "Banen legges i det felles biblioteket, så alle kan spille den. Bare du kan rette den."
                     : draft.usesExternalName
                     ? "Navnet i simulatoren er det dere slår opp i båsen, hvis det er et annet enn vårt."
                     : "En ekte bane spilles ute. Les tallene av scorekortet.")
        }
    }

    /// «Klar» eller hva som mangler, med hva som kreves.
    private var readinessSection: some View {
        let readiness = draft.readiness
        let missing = draft.holesMissingPar
        return Section {
            HStack {
                CourseReadinessChip(readiness: readiness)
                Spacer()
                if let par = draft.par {
                    Text("Par \(par)")
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !missing.isEmpty {
                Button(missing.count == draft.holeCount
                       ? "Fyll standard par \(draft.standardPar)"
                       : "Fyll tomme hull med standard par",
                       systemImage: "wand.and.stars") {
                    draft.fillStandardPar()
                }
            }
        } footer: {
            DDFooter(readiness.detail(kind: draft.kind)
                     + (missing.isEmpty ? "" : " Standardforslaget er bare et utgangspunkt: sjekk hvert hull mot \(draft.kind.source)."))
        }
    }

    private func parSection(title: String, range: Range<Int>) -> some View {
        Section {
            ForEach(range, id: \.self) { index in
                HoleParRow(hole: draft.holes[index]) { par in
                    draft.tapPar(par, hole: draft.holes[index].number)
                }
            }
        } header: {
            DDHeader(title)
        } footer: {
            if range.lowerBound == 0 {
                DDFooter("Trykk par for hvert hull. Trykk en gang til for å tømme. Hold inne for par 6.")
            }
        }
    }

    /// Indeks og lengde, sammenlagt til arrangøren ber om dem.
    private var indexSection: some View {
        Section {
            DisclosureGroup("Indeks og lengde (valgfritt)", isExpanded: $showsIndex) {
                HStack {
                    Text("Hull").frame(width: 44, alignment: .leading)
                    Spacer()
                    Text("Indeks").frame(width: 72)
                    Text("Meter").frame(width: 72)
                }
                .font(.dd(.sans, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ddInkSecondary)
                ForEach(draft.holes.indices, id: \.self) { index in
                    HoleIndexRow(hole: $draft.holes[index])
                }
            }
        } footer: {
            DDFooter("Indeksen sier hvilke hull som gir slag først. Den trengs bare når appen selv deler ut slagene. Deler simulatoren ut slagene, kan den stå tom.")
        }
    }

    private var ratingSection: some View {
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
            if !model.isShared {
                Toggle("I bruk", isOn: $draft.inUse)
            }
        } header: {
            DDHeader("Rating (valgfritt)")
        } footer: {
            DDFooter("Tomt felt regnes som banens par og slope 113. Da får spilleren handicapindeksen sin rett, som når simulatoren deler ut slagene."
                     + (model.isShared ? "" : " Baner som ikke er i bruk, vises ikke når en runde settes opp."))
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
            ConfirmationText(course: item.course, kind: item.kind)
            Button("Bekreft mot \(item.kind.source)", systemImage: "checkmark.seal") { confirm(item) }
                .disabled(draft != original || !item.isReady)
        } header: {
            DDHeader(item.kind == .simulator ? "Simulatorskjermen" : "Scorekortet")
        } footer: {
            if draft != original {
                Text("Lagre endringene før du bekrefter.")
            } else if !item.isReady {
                Text("Banen må ha par på alle hull før den kan bekreftes.")
            } else {
                Text(item.kind == .simulator
                     ? "Trykk når par og indeks over stemmer med det simulatoren viser for banen."
                     : "Trykk når par og indeks over stemmer med scorekortet.")
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

/// Ett hull i par-rutenettet: nummeret og hurtigknapper for 3, 4 og 5 (6 ved å holde inne).
private struct HoleParRow: View {
    let hole: HoleDraft
    let onTap: (Int) -> Void

    /// 3, 4 og 5, og 6 bare når hullet alt har det.
    private var choices: [Int] {
        if let par = hole.par, par > 5 { return [3, 4, 5, par] }
        return [3, 4, 5]
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(hole.number)")
                .monospacedDigit()
                .foregroundStyle(hole.par == nil ? Color.ddRustText : Color.ddInk)
                .frame(width: 28, alignment: .leading)
            ForEach(choices, id: \.self) { par in
                Button("\(par)") { onTap(par) }
                    .buttonStyle(DDChoiceButtonStyle(selected: hole.par == par))
                    .accessibilityLabel("Par \(par) på hull \(hole.number)")
                    .accessibilityAddTraits(hole.par == par ? .isSelected : [])
            }
        }
        .monospacedDigit()
        .contextMenu {
            ForEach(CourseInput.parChoices, id: \.self) { par in
                Button("Par \(par)") { if hole.par != par { onTap(par) } }
            }
            if let par = hole.par {
                Button("Tøm hullet", role: .destructive) { onTap(par) }
            }
        }
    }
}

/// Indeks og lengde for ett hull.
private struct HoleIndexRow: View {
    @Binding var hole: HoleDraft

    var body: some View {
        HStack {
            Text("\(hole.number)")
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            Spacer()
            TextField("–", text: $hole.strokeIndexText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .accessibilityLabel("Indeks på hull \(hole.number)")
            TextField("–", text: $hole.lengthText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .accessibilityLabel("Lengde i meter på hull \(hole.number)")
        }
        .monospacedDigit()
    }
}
