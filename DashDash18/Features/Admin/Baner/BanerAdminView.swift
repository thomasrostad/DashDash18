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

struct CourseListView: View {
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
            ForEach(CourseListItem.grouped(model.items), id: \.kind) { group in
                Section {
                    ForEach(group.items) { item in
                        NavigationLink {
                            CourseEditView(model: model, item: item)
                        } label: {
                            CourseRowView(item: item)
                        }
                    }
                } header: {
                    DDHeader(group.kind.groupTitle)
                } footer: {
                    DDFooter(Self.footer(group.items, kind: group.kind))
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

    /// «Klar» forklart, og hvor mange som aldri er bekreftet.
    private static func footer(_ items: [CourseListItem], kind: CourseKind) -> String {
        var text = "Klar betyr at alle hullene har par, så banen kan velges i en runde."
        let unconfirmed = items.filter { !$0.isConfirmed }.count
        if unconfirmed > 0 {
            let what = kind == .simulator ? "simulatorskjermen" : "scorekortet"
            text += unconfirmed == items.count
                ? " Ingen er bekreftet mot \(what) ennå."
                : " \(unconfirmed) av \(items.count) er aldri bekreftet mot \(what)."
            text += " Første gang dere spiller en bane, sjekker markøren tallene."
        }
        return text
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.course.name)
                if !item.course.inUse {
                    Text("skjult")
                        .font(.dd(.sans, size: 11, relativeTo: .caption2))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.ddEarth, in: Capsule())
                }
                Spacer(minLength: 8)
                CourseReadinessChip(readiness: item.readiness)
            }
            if item.isReady {
                Text(item.summary)
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if item.kind == .simulator, let external = item.differentExternalName {
                Text("I simulatoren: \(external)")
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if item.isReady {
                ConfirmationText(course: item.course, kind: item.kind)
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// «Klar» i grønt, eller «Mangler par på 3 hull» i rust.
struct CourseReadinessChip: View {
    let readiness: CourseReadiness

    var body: some View {
        DDChip(readiness.title, tone: readiness.isReady ? .lime : .earth, compact: true)
            .fixedSize()
    }
}

/// «Bekreftet mot skjermen for 3 dager siden» eller «Aldri bekreftet mot en skjerm».
/// På ekte baner: scorekortet.
struct ConfirmationText: View {
    let course: CourseRow
    var kind: CourseKind = .simulator

    var body: some View {
        if let confirmedAt = course.confirmedAt {
            Label {
                Text("Bekreftet mot \(kind.source) \(confirmedAt, format: .relative(presentation: .named))")
            } icon: {
                Image(systemName: "checkmark.seal")
            }
            .foregroundStyle(Color.ddForestInk)
        } else {
            Label(kind == .simulator ? "Aldri bekreftet mot en skjerm" : "Aldri bekreftet mot scorekortet",
                  systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.ddRustText)
        }
    }
}
