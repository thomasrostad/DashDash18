import Observation
import Supabase
import SwiftUI

/// Banene fra slope.no i det felles biblioteket (sql/029, fylt av synken): hentes én gang og søkes i
/// lokalt. Teene hentes for banen som velges.
@Observable
final class SlopeCatalogModel {
    private(set) var courses: [SlopeCourseRow] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: DataError?

    private let client: SupabaseClient?
    /// Teene i skjermprøvene, per bane.
    private var previewTees: [UUID: [CourseTeeRow]] = [:]

    init(client: SupabaseClient) {
        self.client = client
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview courses: [SlopeCourseRow], tees: [UUID: [CourseTeeRow]]) {
        client = nil
        self.courses = SlopeCourseSearch.sorted(courses)
        previewTees = tees
        hasLoaded = true
    }
    #endif

    /// Alle hentede baner som ikke er borte fra kilden. PostgREST gir høyst 1000 om gangen.
    func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let page = 1000
        do {
            var all: [SlopeCourseRow] = []
            for start in stride(from: 0, to: 20 * page, by: page) {
                let rows: [SlopeCourseRow] = try await client.from("courses")
                    .select(SlopeCourseRow.columns)
                    .eq("source", value: "slope")
                    .is("club_id", value: nil)
                    .is("missing_at", value: nil)
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
struct SlopeNoCreditLink: View {
    var body: some View {
        Link(destination: SlopeNoCredit.url) {
            Label(SlopeNoCredit.text, systemImage: "arrow.up.right.square")
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

/// Søk i banene fra slope.no: navn, sted eller land, norske først. Valgt bane gis tilbake med teene.
struct SlopeCourseSearchView: View {
    let model: SlopeCatalogModel
    let onPick: (SlopeCourseRow, [CourseTeeRow]) -> Void
    var initialQuery = ""

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var loadingID: UUID?
    @State private var error: DataError?
    /// Lista vises bare med de første treffene, så den er rask med over tusen baner.
    private let shownLimit = 150

    var body: some View {
        let matching = SlopeCourseSearch.filter(model.courses, query: search)
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
                    DDFooter("Navn, tees, course rating og slope fylles inn. Par og indeks per hull står ikke her: de leser du av scorekortet.")
                    SlopeNoCreditLink()
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
        .navigationTitle("Baner fra slope.no")
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
                let tees = try await model.tees(for: course)
                onPick(course, tees)
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
                    DDFooter("Teens course rating og slope gir banehandicapet. Tallene lagres på runden når den starter, så en ny rating senere endrer ikke gamle runder.")
                    SlopeNoCreditLink()
                }
            }
        }
        .navigationTitle("Tee")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }
}
