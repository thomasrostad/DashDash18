import Foundation
import Observation
import Supabase

/// Banebiblioteket for klubben: henter, lagrer, bekrefter, sletter og importerer baner.
///
/// Bane og hull lagres i én transaksjon med RPC `save_course` (sql/002, kjørt på test 06.10).
@Observable
final class CourseLibraryModel {
    private(set) var items: [CourseListItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: DataError?

    /// nil bare i skjermprøvene (`init(preview:)`): da går ingenting til nettet.
    private let context: ClubContext?
    private let courseSet: GolfgutuCourseSet?

    init(context: ClubContext, courseSet: GolfgutuCourseSet? = try? GolfgutuCourseSet.load()) {
        self.context = context
        self.courseSet = courseSet
    }

    #if DEBUG
    /// Skjermprøve med oppdiktede baner, uten nett.
    init(preview items: [CourseListItem]) {
        context = nil
        courseSet = nil
        self.items = CourseListItem.sorted(items)
        hasLoaded = true
    }
    #endif

    /// Klienten og klubben, eller `.notAllowed` i en skjermprøve.
    private func connection() throws(DataError) -> (client: SupabaseClient, clubID: UUID) {
        guard let context else { throw .notAllowed }
        return (context.client, context.clubID)
    }

    static let courseColumns = "id, club_id, name, external_name, course_rating, slope_rating, in_use, confirmed_by, confirmed_at"

    /// Banene fra Golfgutu-settet som klubben ikke har ennå.
    var missingFromSet: [GolfgutuCourseSet.CourseEntry] {
        courseSet?.missing(existingNames: items.map(\.course.name)) ?? []
    }

    func load() async {
        guard let connection = try? connection() else { return }
        let (client, clubID) = connection
        isLoading = true
        defer { isLoading = false }
        do {
            let courses: [CourseRow] = try await client
                .from("courses")
                .select(Self.courseColumns)
                .eq("club_id", value: clubID)
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
            let kinds = try await Self.loadKinds(client: client, clubID: clubID)
            items = CourseListItem.make(courses: courses, holes: holes, kinds: kinds)
            hasLoaded = true
            error = nil
        } catch {
            self.error = DataError.from(error)
        }
    }

    /// Lagrer en ny bane (`id == nil`) eller endrer en som finnes, med alle hullene i én
    /// transaksjon (RPC `save_course`, sql/002). Gir den lagrede banen slik serveren har den.
    @discardableResult
    func save(_ values: CourseInputValues, id: UUID?) async throws(DataError) -> CourseListItem {
        struct Hole: Encodable {
            let hole_number: Int
            let par: Int
            let stroke_index: Int?
            let length_m: Int?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(hole_number, forKey: .hole_number)
                try c.encode(par, forKey: .par)
                try c.encode(stroke_index, forKey: .stroke_index)
                try c.encode(length_m, forKey: .length_m)
            }

            enum CodingKeys: String, CodingKey { case hole_number, par, stroke_index, length_m }
        }
        struct Params: Encodable {
            let p_club_id: UUID
            let p_course_id: UUID?
            let p_name: String
            let p_external_name: String?
            let p_course_rating: Double?
            let p_slope_rating: Int?
            let p_in_use: Bool
            let p_holes: [Hole]

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_club_id, forKey: .p_club_id)
                try c.encode(p_course_id, forKey: .p_course_id)
                try c.encode(p_name, forKey: .p_name)
                try c.encode(p_external_name, forKey: .p_external_name)
                try c.encode(p_course_rating, forKey: .p_course_rating)
                try c.encode(p_slope_rating, forKey: .p_slope_rating)
                try c.encode(p_in_use, forKey: .p_in_use)
                try c.encode(p_holes, forKey: .p_holes)
            }

            enum CodingKeys: String, CodingKey {
                case p_club_id, p_course_id, p_name, p_external_name, p_course_rating, p_slope_rating, p_in_use, p_holes
            }
        }
        do {
            let (client, clubID) = try connection()
            let params = Params(
                p_club_id: clubID,
                p_course_id: id,
                p_name: values.name,
                p_external_name: values.externalName,
                p_course_rating: values.courseRating,
                p_slope_rating: values.slopeRating,
                p_in_use: values.inUse,
                p_holes: values.holes.map {
                    let r = $0.record(courseID: id ?? UUID())
                    return Hole(hole_number: r.holeNumber, par: r.par, stroke_index: r.strokeIndex, length_m: r.lengthM)
                }
            )
            let savedID: UUID = try await client.rpc("save_course", params: params).execute().value
            try await saveKind(values.kind, id: savedID, client: client)
            let item = try await fetchItem(savedID)
            guard item.holes.count == values.holes.count else { throw DataError.notAllowed }
            replace(item)
            return item
        } catch {
            throw Self.saveError(error, name: values.name)
        }
    }

    /// «Bekreft mot skjermen»: serveren setter hvem og når (RPC `confirm_course`, sql/002).
    func confirm(_ item: CourseListItem) async throws(DataError) {
        struct Params: Encodable { let p_course_id: UUID }
        do {
            let (client, _) = try connection()
            _ = try await client.rpc("confirm_course", params: Params(p_course_id: item.id)).execute()
            replace(try await fetchItem(item.id))
        } catch {
            throw Self.saveError(error, name: item.course.name)
        }
    }

    /// Leser én bane med hull, slik den ligger på serveren.
    private func fetchItem(_ id: UUID) async throws -> CourseListItem {
        let (client, clubID) = try connection()
        let course: CourseRow = try await client
            .from("courses")
            .select(Self.courseColumns)
            .eq("id", value: id)
            .single()
            .execute()
            .value
        let holes: [CourseHoleRecord] = try await client
            .from("course_holes")
            .select("course_id, hole_number, par, stroke_index, length_m")
            .eq("course_id", value: id)
            .execute()
            .value
        let kinds = try await Self.loadKinds(client: client, clubID: clubID, courseID: id)
        return CourseListItem(course: course, holes: holes, storedKind: kinds[id])
    }

    // MARK: Banetype (sql/016)

    /// `courses.kind` per bane. Tom så lenge `CourseKindFeature` er av (kolonnen finnes ikke før 016).
    static func loadKinds(client: SupabaseClient, clubID: UUID, courseID: UUID? = nil) async throws -> [UUID: CourseKind] {
        guard CourseKindFeature.isEnabled else { return [:] }
        struct Row: Decodable { let id: UUID; let kind: CourseKind }
        var query = client.from("courses").select("id, kind").eq("club_id", value: clubID)
        if let courseID { query = query.eq("id", value: courseID) }
        let rows: [Row] = try await query.execute().value
        return Dictionary(rows.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    /// Skriver typen etter `save_course` (som ikke kjenner den). Sjekker at raden kom tilbake.
    private func saveKind(_ kind: CourseKind, id: UUID, client: SupabaseClient) async throws {
        guard CourseKindFeature.isEnabled else { return }
        struct Patch: Encodable { let kind: CourseKind }
        struct Updated: Decodable { let id: UUID }
        let rows: [Updated] = try await client.from("courses").update(Patch(kind: kind))
            .eq("id", value: id).select("id").execute().value
        guard !rows.isEmpty else { throw DataError.notAllowed }
    }

    /// Sletter banen og hullene (cascade). Databasen stopper det når runder bruker banen.
    func delete(_ item: CourseListItem) async throws(DataError) {
        struct Deleted: Decodable { let id: UUID }
        do {
            let (client, _) = try connection()
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
