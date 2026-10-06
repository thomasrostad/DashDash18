import SwiftUI

/// Banebiblioteket: klubbens baner, med import av Golfgutu-banene, ny bane og redigering.
struct BanerAdminView: View {
    @Environment(\.clubContext) private var context
    @State private var model: CourseLibraryModel?

    var body: some View {
        Group {
            if let model {
                CourseListView(model: model, isOrganizer: context?.isOrganizer ?? false)
            } else {
                ContentUnavailableView("Ingen klubb", systemImage: "map", description: Text("Velg en klubb først."))
            }
        }
        .navigationTitle("Banene")
        .ddNavigationChrome()
        .task {
            guard model == nil, let context else { return }
            let model = CourseLibraryModel(context: context)
            self.model = model
            await model.load()
        }
    }
}

private struct CourseListView: View {
    let model: CourseLibraryModel
    let isOrganizer: Bool

    @State private var isCreating = false
    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        DDList {
            if let error = model.error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
            if isOrganizer, model.hasLoaded, !model.missingFromSet.isEmpty {
                importSection
            }
            if let importMessage {
                Section {
                    Label(importMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(Color.ddForestInk)
                }
            }
            if !model.items.isEmpty {
                Section {
                    ForEach(model.items) { item in
                        NavigationLink {
                            CourseEditView(model: model, item: item)
                        } label: {
                            CourseRowView(item: item)
                        }
                    }
                } footer: {
                    let unconfirmed = model.items.filter { !$0.isConfirmed }.count
                    if unconfirmed > 0 {
                        Text("\(unconfirmed) av \(model.items.count) baner er aldri bekreftet mot en simulatorskjerm. Første gang dere spiller en bane, sjekker markøren tallene mot skjermen.")
                    }
                }
            }
        }
        .overlay {
            if model.hasLoaded, model.items.isEmpty, model.missingFromSet.isEmpty {
                ContentUnavailableView("Ingen baner ennå", systemImage: "map",
                                       description: Text("Legg til banen dere spiller med «+»."))
            } else if !model.hasLoaded, model.isLoading {
                ProgressView()
            }
        }
        .refreshable { await model.load() }
        .toolbar {
            if isOrganizer {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ny bane", systemImage: "plus") { isCreating = true }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                CourseEditView(model: model, item: nil)
            }
        }
    }

    private var importSection: some View {
        let missing = model.missingFromSet.count
        return Section {
            Button {
                runImport()
            } label: {
                HStack {
                    Label("Importer Golfgutu-banene", systemImage: "square.and.arrow.down")
                    if isImporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isImporting)
        } footer: {
            DDFooter(missing == 1
                 ? "Én av banene fra GolfGutu-appen mangler her. Den legges inn med par, indeks og lengde."
                 : "\(missing) av banene fra GolfGutu-appen mangler her. De legges inn med par, indeks og lengde. Baner som alt finnes med samme navn, røres ikke.")
        }
    }

    private func runImport() {
        isImporting = true
        importMessage = nil
        model.error = nil
        Task {
            do {
                let added = try await model.importMissing()
                importMessage = added == 1 ? "La inn 1 bane." : "La inn \(added) baner."
            } catch {
                model.error = DataError.from(error)
                await model.load()
            }
            isImporting = false
        }
    }
}

private struct CourseRowView: View {
    let item: CourseListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.course.name)
                if !item.course.inUse {
                    Text("skjult")
                        .font(.dd(.sans, size: 11, relativeTo: .caption2))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.ddEarth, in: Capsule())
                }
            }
            Text(item.summary)
                .font(.dd(.sans, size: 12, relativeTo: .caption))
                .foregroundStyle(item.isReady ? Color.ddInkSecondary : Color.ddRustText)
            if let external = item.differentExternalName {
                Text("I simulatoren: \(external)")
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ConfirmationText(course: item.course)
                .font(.dd(.sans, size: 12, relativeTo: .caption))
        }
        .padding(.vertical, 2)
    }
}

/// «Bekreftet mot skjermen for 3 dager siden» eller «Aldri bekreftet mot en skjerm».
struct ConfirmationText: View {
    let course: CourseRow

    var body: some View {
        if let confirmedAt = course.confirmedAt {
            Label {
                Text("Bekreftet mot skjermen \(confirmedAt, format: .relative(presentation: .named))")
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .foregroundStyle(Color.ddForestInk)
        } else {
            Label("Aldri bekreftet mot en skjerm", systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.ddRustText)
        }
    }
}
