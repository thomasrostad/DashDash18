import Foundation
import Observation
import Supabase

/// Banebiblioteket for klubben: henter, lagrer, bekrefter, sletter og importerer baner.
///
/// Lagring av bane og hull er flere forespørsler (bane, så sletting av hull som er
/// borte, så upsert av hullene). Feiler en av de siste, står banen lagret med de gamle
/// hullene. `sql/002_baner.sql` foreslår en RPC som gjør alt i én transaksjon.
@Observable
final class CourseLibraryModel {
    private(set) var items: [CourseListItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: DataError?

    private let context: ClubContext
    private let courseSet: GolfgutuCourseSet?

    init(context: ClubContext, courseSet: GolfgutuCourseSet? = try? GolfgutuCourseSet.load()) {
        self.context = context
        self.courseSet = courseSet
    }

    private var client: SupabaseClient { context.client }

    static let courseColumns = "id, club_id, name, external_name, course_rating, slope_rating, in_use, confirmed_by, confirmed_at"

    /// Banene fra Golfgutu-settet som klubben ikke har ennå.
    var missingFromSet: [GolfgutuCourseSet.CourseEntry] {
        courseSet?.missing(existingNames: items.map(\.course.name)) ?? []
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let courses: [CourseRow] = try await client
                .from("courses")
                .select(Self.courseColumns)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            var holes: [CourseHoleRecord] = []
            if !courses.isEmpty {
                holes = try await client
                    .from("course_holes")
                    .select("course_id, hole_number, par, stroke_index, length_m")
                    .in("course_id", values: courses.map(\.id.uuidString))
                    .execute()
                    .value
            }
            items = CourseListItem.make(courses: courses, holes: holes)
            hasLoaded = true
            error = nil
        } catch {
            self.error = DataError.from(error)
        }
    }

    /// Lagrer en ny bane (`id == nil`) eller endrer en som finnes. Gir den lagrede banen.
    @discardableResult
    func save(_ values: CourseInputValues, id: UUID?) async throws(DataError) -> CourseListItem {
        do {
            let write = CourseWrite(clubID: context.clubID, values: values)
            let course: CourseRow
            if let id {
                course = try await client
                    .from("courses")
                    .update(write)
                    .eq("id", value: id)
                    .select(Self.courseColumns)
                    .single()
                    .execute()
                    .value
            } else {
                course = try await client
                    .from("courses")
                    .insert(write)
                    .select(Self.courseColumns)
                    .single()
                    .execute()
                    .value
            }

            // Hull som ikke lenger finnes (18 → 9, eller banen tømt). Slettes før upsert,
            // så en indeks som flyttes fra hull 12 til hull 3 ikke kolliderer.
            if id != nil {
                try await client
                    .from("course_holes")
                    .delete()
                    .eq("course_id", value: course.id)
                    .gt("hole_number", value: values.holes.count)
                    .execute()
            }

            var holes: [CourseHoleRecord] = []
            if !values.holes.isEmpty {
                holes = try await client
                    .from("course_holes")
                    .upsert(values.holes.map { HoleWrite($0.record(courseID: course.id)) },
                            onConflict: "course_id,hole_number")
                    .select("course_id, hole_number, par, stroke_index, length_m")
                    .execute()
                    .value
                guard holes.count == values.holes.count else { throw DataError.notAllowed }
            }

            let item = CourseListItem(course: course, holes: holes)
            replace(item)
            return item
        } catch {
            throw Self.saveError(error, name: values.name)
        }
    }

    /// «Bekreft mot skjermen»: hvem og når tallene sist ble sjekket mot simulatoren.
    func confirm(_ item: CourseListItem) async throws(DataError) {
        struct Confirm: Encodable {
            let confirmed_by: UUID
            let confirmed_at: Date
        }
        do {
            let course: CourseRow = try await client
                .from("courses")
                .update(Confirm(confirmed_by: context.memberID, confirmed_at: Date()))
                .eq("id", value: item.id)
                .select(Self.courseColumns)
                .single()
                .execute()
                .value
            replace(CourseListItem(course: course, holes: item.holes))
        } catch {
            throw Self.saveError(error, name: item.course.name)
        }
    }

    /// Sletter banen og hullene (cascade). Databasen stopper det når runder bruker banen.
    func delete(_ item: CourseListItem) async throws(DataError) {
        struct Deleted: Decodable { let id: UUID }
        do {
            let deleted: [Deleted] = try await client
                .from("courses")
                .delete()
                .eq("id", value: item.id)
                .select("id")
                .execute()
                .value
            guard !deleted.isEmpty else { throw DataError.notAllowed }
            items.removeAll { $0.id == item.id }
        } catch {
            throw Self.deleteError(error)
        }
    }

    /// Legger inn banene fra Golfgutu-settet som mangler. Gir antall som ble lagt inn.
    /// Stopper ved første feil; det som alt er lagt inn, blir stående.
    func importMissing() async throws(DataError) -> Int {
        var added = 0
        for entry in missingFromSet {
            guard let values = entry.draft.validate().values else {
                throw DataError.invalid("«\(entry.name)» i Golfgutu-settet er ikke gyldig.")
            }
            try await save(values, id: nil)
            added += 1
        }
        return added
    }

    private func replace(_ item: CourseListItem) {
        var list = items.filter { $0.id != item.id }
        list.append(item)
        items = CourseListItem.sorted(list)
    }

    // MARK: Feil

    nonisolated static func saveError(_ error: any Error, name: String) -> DataError {
        if let postgrest = error as? PostgrestError {
            if postgrest.code == "23505" {
                if postgrest.message.contains("stroke_index") {
                    return .invalid("To hull har samme indeks.")
                }
                return .invalid("Det finnes allerede en bane som heter «\(name)».")
            }
            // PGRST116: `.single()` fikk ingen rad tilbake, altså stoppet RLS skrivingen.
            if postgrest.code == "PGRST116" { return .notAllowed }
        }
        return DataError.from(error)
    }

    nonisolated static func deleteError(_ error: any Error) -> DataError {
        if let postgrest = error as? PostgrestError, postgrest.code == "23503" {
            return .invalid("Banen er brukt i en runde og kan ikke slettes. Sett den til «ikke i bruk» i stedet, så forsvinner den fra velgeren.")
        }
        return DataError.from(error)
    }
}

/// Kolonnene appen skriver til `courses`. Tomme felt sendes som `null`, så de tømmes
/// ved endring (standard `Encodable` ville utelatt dem).
nonisolated struct CourseWrite: Encodable, Sendable {
    let clubID: UUID
    let name: String
    let externalName: String?
    let courseRating: Double?
    let slopeRating: Int?
    let inUse: Bool

    init(clubID: UUID, values: CourseInputValues) {
        self.clubID = clubID
        name = values.name
        externalName = values.externalName
        courseRating = values.courseRating
        slopeRating = values.slopeRating
        inUse = values.inUse
    }

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case name
        case externalName = "external_name"
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case inUse = "in_use"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clubID, forKey: .clubID)
        try c.encode(name, forKey: .name)
        try c.encode(externalName, forKey: .externalName)
        try c.encode(courseRating, forKey: .courseRating)
        try c.encode(slopeRating, forKey: .slopeRating)
        try c.encode(inUse, forKey: .inUse)
    }
}

/// Et hull til upsert. Alle nøkler er med (også `null`), så alle radene i forespørselen
/// har samme kolonner og en tømt indeks eller lengde faktisk tømmes.
nonisolated struct HoleWrite: Encodable, Sendable {
    let record: CourseHoleRecord

    init(_ record: CourseHoleRecord) {
        self.record = record
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CourseHoleRecord.CodingKeys.self)
        try c.encode(record.courseID, forKey: .courseID)
        try c.encode(record.holeNumber, forKey: .holeNumber)
        try c.encode(record.par, forKey: .par)
        try c.encode(record.strokeIndex, forKey: .strokeIndex)
        try c.encode(record.lengthM, forKey: .lengthM)
    }
}
