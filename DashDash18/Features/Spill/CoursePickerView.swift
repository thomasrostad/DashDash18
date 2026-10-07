import SwiftUI

/// Banene i det felles biblioteket, med søk: dine egne først, så resten. Med `onSelect` velger du en
/// bane til runden; uten er det biblioteket der du legger inn og retter dine egne baner.
/// «Ny bane» er den enkle baneflyten fra fase 11 (`CourseEditView`).
struct CoursePickerView: View {
    let model: CourseLibraryModel
    var selected: UUID?
    var onSelect: ((CourseListItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var isCreating = false

    private var matching: [CourseListItem] {
        CourseSearch.filter(model.items, query: search)
    }

    var body: some View {
        let matching = matching
        let mine = matching.filter(model.canEdit)
        let others = matching.filter { !model.canEdit($0) }
        DDList {
            if let error = model.error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle").ddErrorStyle()
                }
            }
            if !mine.isEmpty {
                section("Dine baner", items: mine)
            }
            if !others.isEmpty {
                section("Biblioteket", items: others)
            }
        }
        .overlay {
            if model.hasLoaded, matching.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "Ingen baner ennå" : "Fant ingen bane", systemImage: "map")
                } description: {
                    Text("Legg inn banen med «Ny bane». Den havner i det felles biblioteket, så andre kan spille den.")
                } actions: {
                    Button("Ny bane") { isCreating = true }
                        .buttonStyle(.dd(.primary))
                }
            } else if !model.hasLoaded, model.isLoading {
                ProgressView()
            }
        }
        .searchable(text: $search, prompt: "Søk etter bane")
        .refreshable { await model.load() }
        .task { if !model.hasLoaded { await model.load() } }
        .navigationTitle(onSelect == nil ? "Banebiblioteket" : "Velg bane")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ny bane", systemImage: "plus") { isCreating = true }
            }
        }
        .navigationDestination(isPresented: $isCreating) {
            CourseEditView(model: model, item: nil)
        }
    }

    private func section(_ title: String, items: [CourseListItem]) -> some View {
        Section {
            ForEach(items) { item in
                row(item)
            }
        } header: {
            DDHeader(title)
        }
    }

    @ViewBuilder
    private func row(_ item: CourseListItem) -> some View {
        let label = CourseLibraryRow(item: item, isSelected: item.id == selected)
        if let onSelect, item.isReady {
            Button {
                onSelect(item)
                dismiss()
            } label: { label }
                .buttonStyle(.plain)
                .contextMenu {
                    if model.canEdit(item) {
                        NavigationLink("Rett banen") { CourseEditView(model: model, item: item) }
                    }
                }
        } else if model.canEdit(item) {
            NavigationLink { CourseEditView(model: model, item: item) } label: { label }
        } else {
            label
        }
    }
}

/// Banebiblioteket fra «Spill»: bla, legg inn og rett dine egne.
struct LibraryCoursesView: View {
    @State var model: CourseLibraryModel

    var body: some View {
        CoursePickerView(model: model)
    }
}

/// Én bane i biblioteket: navn, type og hva den har.
struct CourseLibraryRow: View {
    let item: CourseListItem
    var isSelected = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.course.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text("\(item.kind.title) · \(item.summary)")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.ddForestInk)
                    .accessibilityLabel("Valgt")
            } else if !item.isReady {
                DDPill("Ikke klar", tone: .outlineRust)
                    .fixedSize()
            }
        }
        .contentShape(.rect)
    }
}

/// Søk i banelista: alle ordene må finnes i navnet, uten hensyn til store bokstaver og aksenter.
nonisolated enum CourseSearch {
    static func filter(_ items: [CourseListItem], query: String) -> [CourseListItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let name = normalize(item.course.name)
            return words.allSatisfy { name.contains($0) }
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nb_NO"))
    }
}
