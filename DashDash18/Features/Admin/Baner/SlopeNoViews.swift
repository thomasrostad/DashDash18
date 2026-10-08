import Observation
import Supabase
import SwiftUI

/// Banene fra slope.no i det felles biblioteket (sql/029, fylt av synken): hentes én gang og søkes i
/// lokalt. Teene hentes for banen som velges. Med hull (sql/030, `usesHoles`) vet lista hvilke baner som
/// har hull og kan spilles direkte, og en slik bane hentes med hull og tees (`item(for:)`).
@Observable
final class SlopeCatalogModel {
    private(set) var courses: [SlopeCourseRow] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: DataError?
    /// Hullene brukes (`SlopeNoFeature.usesHoles`; skjermprøvene setter den selv).
    let usesHoles: Bool

    private let client: SupabaseClient?
    /// Teene i skjermprøvene, per bane.
    private var previewTees: [UUID: [CourseTeeRow]] = [:]
    /// Banene med hull i skjermprøvene, per bane.
    private var previewItems: [UUID: CourseListItem] = [:]

    init(client: SupabaseClient, usesHoles: Bool = SlopeNoFeature.usesHoles) {
        self.client = client
        self.usesHoles = usesHoles
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview courses: [SlopeCourseRow], tees: [UUID: [CourseTeeRow]], items: [CourseListItem] = [],
         usesHoles: Bool = false) {
        client = nil
        self.courses = SlopeCourseSearch.sorted(courses)
        previewTees = tees
        previewItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.usesHoles = usesHoles
        hasLoaded = true
    }
    #endif

    /// Banene som kan spilles direkte: de med hull (bare når hullene brukes).
    var playable: [SlopeCourseRow] {
        usesHoles ? courses.filter(\.hasHoles) : []
    }

    /// Banen med hull og tees, klar til å velges i en runde (fase 20b).
    func item(for course: SlopeCourseRow) async throws(DataError) -> CourseListItem {
        guard let client else {
            guard let item = previewItems[course.id] else { throw .notAllowed }
            return item
        }
        do {
            guard let item = try await CourseLibraryModel.loadSourceItems(client: client, ids: [course.id]).first,
                  item.isReady else {
                throw DataError.invalid("Fant ikke hullene til «\(course.name)». Prøv igjen senere.")
            }
            return item
        } catch {
            throw DataError.from(error)
        }
    }

    /// Alle hentede baner som ikke er borte fra kilden. PostgREST gir høyst 1000 om gangen.
    func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let page = 1000
        do {
            var all: [SlopeCourseRow] = []
            for start in stride(from: 0, to: 20 * page, by: page) {
                var query = client.from("courses")
                    .select(usesHoles ? SlopeCourseRow.holeColumns : SlopeCourseRow.columns)
                    .eq("source", value: "slope")
                    .is("club_id", value: nil)
                    .is("missing_at", value: nil)
                if usesHoles {
                    // Bare hull 1 som innebygd rad: tom liste = banen har ingen hull.
                    query = query.eq("course_holes.hole_number", value: 1)
                }
                let rows: [SlopeCourseRow] = try await query
                    .order("id")
                    .range(from: start, to: start + page - 1)
                    .execute().value
                all += rows
                if rows.count < page { break }
            }
            courses = SlopeCourseSearch.sorted(all)
            hasLoaded = true
            error = nil
        } catch {
            self.error = DataError.from(error)
        }
    }

    /// Teene til banen, i rekkefølge.
    func tees(for course: SlopeCourseRow) async throws(DataError) -> [CourseTeeRow] {
        guard let client else { return TeeChoice.visible(previewTees[course.id] ?? []) }
        do {
            let rows: [CourseTeeRow] = try await client.from("course_tees")
                .select(CourseTeeRow.columns)
                .eq("course_id", value: course.id)
                .is("missing_at", value: nil)
                .execute().value
            return TeeChoice.visible(rows)
        } catch {
            throw DataError.from(error)
        }
    }
}

/// «Slope og course rating fra slope.no» med lenke. Eieren av slope.no ber om dette der tee-data vises.
/// Med hullene (fase 20b): «Hull, slope og course rating fra slope.no».
struct SlopeNoCreditLink: View {
    var usesHoles = SlopeNoFeature.usesHoles

    var body: some View {
        Link(destination: SlopeNoCredit.url) {
            Label(SlopeNoCredit.text(usesHoles: usesHoles), systemImage: "arrow.up.right.square")
                .font(.ddCaption)
        }
        .foregroundStyle(Color.ddForestInk)
        .accessibilityHint("Åpner slope.no")
    }
}

/// Raden under «Om appen» i Deg: hvor banedataene kommer fra, med lenke.
struct SlopeNoAboutRow: View {
    var body: some View {
        Link(destination: SlopeNoCredit.url) {
            LabeledContent {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.ddInkSecondary)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Banedata")
                        .foregroundStyle(Color.ddInk)
                    Text(SlopeNoCredit.text)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
        }
        .accessibilityHint("Åpner slope.no")
    }
}

/// Søk i banene fra slope.no: navn, sted eller land, norske først. Valgt bane gis tilbake med teene
/// (`onPick`, til en egen kopi i «Ny bane»). Med `onPlay` (fase 20b) vises bare baner med hull, og valgt
/// bane gis tilbake ferdig til å spilles direkte.
struct SlopeCourseSearchView: View {
    let model: SlopeCatalogModel
    var onPick: (SlopeCourseRow, [CourseTeeRow]) -> Void = { _, _ in }
    var initialQuery = ""
    var onPlay: ((CourseListItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var loadingID: UUID?
    @State private var error: DataError?
    /// Lista vises bare med de første treffene, så den er rask med over tusen baner.
    private let shownLimit = 150

    private var isPlaying: Bool { onPlay != nil }

    var body: some View {
        let matching = SlopeCourseSearch.filter(isPlaying ? model.playable : model.courses, query: search)
        DDList {
            if let error = error ?? model.error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle").ddErrorStyle()
                }
            }
            Section {
                ForEach(matching.prefix(shownLimit)) { course in
                    row(course)
                }
            } header: {
                if model.hasLoaded {
                    DDHeader(matching.count == 1 ? "1 bane" : "\(matching.count) baner")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if matching.count > shownLimit {
                        DDFooter("Viser de første \(shownLimit). Skriv mer av navnet eller stedet.")
                    }
                    DDFooter(SlopeCourseSearch.footer(playing: isPlaying, usesHoles: model.usesHoles))
                    SlopeNoCreditLink(usesHoles: model.usesHoles)
                }
            }
        }
        .overlay {
            if model.hasLoaded, matching.isEmpty {
                ContentUnavailableView.search(text: search)
            } else if !model.hasLoaded, model.isLoading {
                ProgressView()
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Bane, sted eller land")
        .task {
            if search.isEmpty, !initialQuery.isEmpty { search = initialQuery }
            if !model.hasLoaded { await model.load() }
        }
        .navigationTitle(isPlaying ? "Fra slope.no" : "Baner fra slope.no")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(loadingID != nil)
    }

    private func row(_ course: SlopeCourseRow) -> some View {
        Button {
            pick(course)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddInk)
                    let place = SlopeCourseSearch.place(course)
                    if !place.isEmpty {
                        Text(place)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    if !isPlaying, model.usesHoles, course.hasHoles {
                        Label("Har hull: kan spilles direkte", systemImage: "flag")
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddForestInk)
                    }
                }
                Spacer(minLength: 8)
                if loadingID == course.id { ProgressView() }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func pick(_ course: SlopeCourseRow) {
        loadingID = course.id
        error = nil
        Task {
            do {
                if let onPlay {
                    onPlay(try await model.item(for: course))
                } else {
                    let tees = try await model.tees(for: course)
                    onPick(course, tees)
                }
                dismiss()
            } catch {
                self.error = DataError.from(error)
            }
            loadingID = nil
        }
    }
}

/// Teene i banens skjema: navn, kjønn, CR og slope. Sveip for å fjerne en tee.
struct CourseTeesSection: View {
    @Binding var tees: [TeeInput]?

    var body: some View {
        if let list = tees, !list.isEmpty {
            Section {
                ForEach(list, id: \.self) { tee in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tee.name)
                            .foregroundStyle(Color.ddInk)
                        Text(Self.detail(tee))
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    tees?.remove(atOffsets: offsets)
                }
            } header: {
                DDHeader(list.count == 1 ? "1 tee" : "\(list.count) tees")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    DDFooter("Teen velges når runden settes opp, og dens course rating og slope brukes i handicapet. Par og indeks per hull står på scorekortet: skriv dem inn over.")
                    SlopeNoCreditLink()
                }
            }
        }
    }

    static func detail(_ tee: TeeInput) -> String {
        var parts = [tee.gender.title, "CR \(CourseInput.decimalText(tee.courseRating))", "slope \(tee.slopeRating)"]
        if let par = tee.par { parts.append("par \(par)") }
        return parts.joined(separator: " · ")
    }
}

/// Velg tee: teene på banen med CR og slope. Valget lukker skjermen.
struct TeePickerView: View {
    let tees: [CourseTeeRow]
    @Binding var selected: UUID?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DDList {
            Section {
                ForEach(TeeChoice.visible(tees)) { tee in
                    Button {
                        selected = tee.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tee.name)
                                    .foregroundStyle(Color.ddInk)
                                Text(TeeChoice.detail(tee))
                                    .font(.ddCaption)
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                            Spacer()
                            if tee.id == selected {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.ddForestInk)
                                    .accessibilityLabel("Valgt")
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tee.id == selected ? .isSelected : [])
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    DDFooter(TeeChoice.pickerFooter(hasHoles: tees.contains { TeeHoles.hasOwnHoles($0) }))
                    SlopeNoCreditLink(usesHoles: SlopeNoFeature.usesHoles || tees.contains { !$0.holes.isEmpty })
                }
            }
        }
        .navigationTitle("Tee")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }
}
