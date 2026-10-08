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

    /// nil bare i skjermprøvene (`init(preview:)`) og for det felles biblioteket: da går ingenting
    /// til klubben.
    private let context: ClubContext?
    private let courseSet: GolfgutuCourseSet?
    /// Det felles biblioteket (sql/017–018, løse runder): baner uten klubb, som alle leser og den som
    /// la dem inn, retter. nil for klubbens bibliotek.
    private let shared: SharedLibrary?
    /// Banene fra slope.no til «Ny bane» (sql/029). nil når `SlopeNoFeature` er av.
    let slopeCatalog: SlopeCatalogModel?

    struct SharedLibrary {
        let client: SupabaseClient
        /// Den innloggede, for å vite hvilke baner du har lagt inn (og kan rette).
        let userID: UUID
    }

    init(context: ClubContext, courseSet: GolfgutuCourseSet? = try? GolfgutuCourseSet.load()) {
        self.context = context
        self.courseSet = courseSet
        shared = nil
        slopeCatalog = SlopeNoFeature.isEnabled ? SlopeCatalogModel(client: context.client) : nil
    }

    /// Det felles biblioteket (løse runder, `LooseRoundsFeature`).
    init(shared client: SupabaseClient, userID: UUID) {
        context = nil
        courseSet = nil
        shared = SharedLibrary(client: client, userID: userID)
        slopeCatalog = SlopeNoFeature.isEnabled ? SlopeCatalogModel(client: client) : nil
    }

    /// Det felles biblioteket, ikke klubbens.
    var isShared: Bool { shared != nil }

    /// Kan du rette banen? I klubben avgjør arrangørrollen (skjermen). I det felles biblioteket bare
    /// den som la den inn.
    func canEdit(_ item: CourseListItem) -> Bool {
        guard let shared else { return true }
        return item.course.createdByProfile == shared.userID
    }

    #if DEBUG
    /// Skjermprøve av det felles biblioteket, uten nett (henting feiler stille).
    init(previewShared items: [CourseListItem], client: SupabaseClient, userID: UUID,
         slopeCatalog: SlopeCatalogModel? = nil) {
        context = nil
        courseSet = nil
        shared = SharedLibrary(client: client, userID: userID)
        self.slopeCatalog = slopeCatalog
        self.items = CourseListItem.sorted(items)
        hasLoaded = true
    }

    /// Skjermprøve med oppdiktede baner, uten nett.
    init(preview items: [CourseListItem], slopeCatalog: SlopeCatalogModel? = nil) {
        context = nil
        courseSet = nil
        shared = nil
        self.slopeCatalog = slopeCatalog
        self.items = CourseListItem.sorted(items)
        hasLoaded = true
    }
    #endif

    /// Klienten og klubben, eller `.notAllowed` i en skjermprøve.
    private func connection() throws(DataError) -> (client: SupabaseClient, clubID: UUID) {
        guard let context else { throw .notAllowed }
        return (context.client, context.clubID)
    }

    /// Banene fra Golfgutu-settet som klubben ikke har ennå.
    var missingFromSet: [GolfgutuCourseSet.CourseEntry] {
        courseSet?.missing(existingNames: items.map(\.course.name)) ?? []
    }

    func load() async {
        if let shared {
            await loadShared(shared)
            return
        }
        guard let connection = try? connection() else { return }
        let (client, clubID) = connection
        isLoading = true
        defer { isLoading = false }
        do {
            let courses: [CourseRow] = try await client
                .from("courses")
                .select(CourseRow.columns)
                .eq("club_id", value: clubID)
                .execute()
                .value
            var holes: [CourseHoleRecord] = []
            if !courses.isEmpty {
                holes = try await client
                    .from("course_holes")
                    .select(CourseHoleRecord.columns)
                    .in("course_id", values: courses.map(\.id.uuidString))
                    .execute()
                    .value
            }
            let kinds = try await Self.loadKinds(client: client, clubID: clubID)
            let tees = try await Self.loadTees(client: client, courseIDs: courses.map(\.id))
            items = CourseListItem.make(courses: courses, holes: holes, kinds: kinds, tees: tees)
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
        if let shared { return try await saveShared(values, id: id, in: shared) }
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
            try await Self.saveTees(values.tees, id: savedID, client: client)
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
        // Det felles biblioteket har ingen klubb å bekrefte for (`confirm_course` er per klubb).
        guard shared == nil else { throw .notAllowed }
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
            .select(CourseRow.columns)
            .eq("id", value: id)
            .single()
            .execute()
            .value
        let holes: [CourseHoleRecord] = try await client
            .from("course_holes")
            .select(CourseHoleRecord.columns)
            .eq("course_id", value: id)
            .execute()
            .value
        let kinds = try await Self.loadKinds(client: client, clubID: clubID, courseID: id)
        let tees = try await Self.loadTees(client: client, courseIDs: [id])
        return CourseListItem(course: course, holes: holes, storedKind: kinds[id], tees: tees)
    }

    // MARK: Tees (sql/029)

    /// Teene til banene, uten dem som er borte fra kilden. Tom så lenge `SlopeNoFeature` er av. Med
    /// `usesHoles` (sql/030) får teene sine egne hull festet på.
    static func loadTees(client: SupabaseClient, courseIDs: [UUID]) async throws -> [CourseTeeRow] {
        guard SlopeNoFeature.isEnabled, !courseIDs.isEmpty else { return [] }
        let tees: [CourseTeeRow] = try await client.from("course_tees")
            .select(CourseTeeRow.columns)
            .in("course_id", values: courseIDs.map(\.uuidString))
            .is("missing_at", value: nil)
            .execute().value
        guard SlopeNoFeature.usesHoles, !tees.isEmpty else { return tees }
        return TeeHoles.attach(try await loadTeeHoles(client: client, teeIDs: tees.map(\.id)), to: tees)
    }

    /// Hullene til teene (`course_tee_holes`, sql/030), i biter så adressen ikke blir for lang.
    static func loadTeeHoles(client: SupabaseClient, teeIDs: [UUID]) async throws -> [TeeHoleRow] {
        var rows: [TeeHoleRow] = []
        for start in stride(from: 0, to: teeIDs.count, by: 100) {
            let ids = teeIDs[start..<min(start + 100, teeIDs.count)].map(\.uuidString)
            rows += try await client.from("course_tee_holes")
                .select(TeeHoleRow.columns)
                .in("tee_id", values: ids)
                .execute().value
        }
        return rows
    }

    /// Hentede baner (slope.no, sql/029–030) med hull og tees, slik de spilles direkte: ekte baner med
    /// kilde-merke. Brukes når en hentet bane velges, og for runder som alt peker på en.
    static func loadSourceItems(client: SupabaseClient, ids: [UUID]) async throws -> [CourseListItem] {
        guard SlopeNoFeature.usesHoles, !ids.isEmpty else { return [] }
        let rows: [SharedCourseRow] = try await client.from("courses")
            .select(sharedColumns)
            .in("id", values: ids.map(\.uuidString))
            .not("source", operator: .is, value: "null")
            .execute().value
        guard !rows.isEmpty else { return [] }
        let courseIDs = rows.map(\.course.id)
        let holes: [CourseHoleRecord] = try await client.from("course_holes")
            .select(CourseHoleRecord.columns)
            .in("course_id", values: courseIDs.map(\.uuidString))
            .execute().value
        let tees = try await loadTees(client: client, courseIDs: courseIDs)
        return CourseListItem.make(courses: rows.map(\.course), holes: holes,
                                   kinds: Dictionary(rows.map { ($0.course.id, CourseKind.course) }, uniquingKeysWith: { a, _ in a }),
                                   tees: tees, fromSource: Set(courseIDs))
    }

    /// En hentet bane som er valgt i en runde (fase 20b): legges i lista (bak de andre), så runden og
    /// velgeren finner den.
    func adopt(_ item: CourseListItem) {
        replace(item)
    }

    /// Banens egne tees i én transaksjon (`save_course_tees`). nil = teene røres ikke.
    static func saveTees(_ tees: [TeeInput]?, id: UUID, client: SupabaseClient) async throws {
        guard SlopeNoFeature.isEnabled, let tees else { return }
        struct Params: Encodable {
            let p_course_id: UUID
            let p_tees: [TeeInput]
        }
        let count: Int = try await client.rpc("save_course_tees", params: Params(p_course_id: id, p_tees: tees))
            .execute().value
        guard count == tees.count else { throw DataError.invalid("Teene ble ikke lagret slik de sto. Last inn på nytt og sjekk.") }
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
            let client = try shared?.client ?? connection().client
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

    // MARK: Det felles biblioteket (sql/017–018)

    static let sharedColumns = CourseRow.columns + ", created_by_profile, kind"

    /// Banene uten klubb, med hullene og typen.
    private func loadShared(_ shared: SharedLibrary) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Bare baner brukerne har lagt inn. Hentede baner (slope.no, sql/029) søkes opp for seg:
            // uten hull under «Ny bane» (kopi og scorekort), med hull (sql/030, `usesHoles`) i velgeren
            // under «Fra slope.no», og legges hit når de velges (`adopt`). Over tusen baner med hull og
            // tees lastes ikke på forhånd.
            let rows: [SharedCourseRow] = try await shared.client.from("courses")
                .select(Self.sharedColumns)
                .is("club_id", value: nil)
                .is("source", value: nil)
                .execute().value
            var holes: [CourseHoleRecord] = []
            if !rows.isEmpty {
                holes = try await shared.client.from("course_holes")
                    .select(CourseHoleRecord.columns)
                    .in("course_id", values: rows.map(\.course.id.uuidString))
                    .execute().value
            }
            let tees = try await Self.loadTees(client: shared.client, courseIDs: rows.map(\.course.id))
            let own = CourseListItem.make(courses: rows.map(\.course), holes: holes,
                                          kinds: Dictionary(rows.map { ($0.course.id, $0.kind) }, uniquingKeysWith: { a, _ in a }),
                                          tees: tees)
            // Hentede baner som er valgt i denne økten, står til de velges bort.
            items = CourseListItem.sorted(CourseListItem.adding(items.filter(\.isFromSource), to: own))
            hasLoaded = true
            error = nil
        } catch {
            self.error = DataError.from(error)
        }
    }

    /// Bane og hull i én transaksjon (`save_library_course`, sql/018). RLS avgjør: alle kan legge
    /// inn, bare den som la inn banen, kan rette den.
    private func saveShared(_ values: CourseInputValues, id: UUID?, in shared: SharedLibrary) async throws(DataError) -> CourseListItem {
        struct Hole: Encodable {
            let hole_number: Int
            let par: Int
            let stroke_index: Int?
            let length_m: Int?
        }
        struct Params: Encodable {
            let p_course_id: UUID?
            let p_name: String
            let p_kind: String
            let p_course_rating: Double?
            let p_slope_rating: Int?
            let p_holes: [Hole]

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_course_id, forKey: .p_course_id)
                try c.encode(p_name, forKey: .p_name)
                try c.encode(p_kind, forKey: .p_kind)
                try c.encode(p_course_rating, forKey: .p_course_rating)
                try c.encode(p_slope_rating, forKey: .p_slope_rating)
                try c.encode(p_holes, forKey: .p_holes)
            }

            enum CodingKeys: String, CodingKey {
                case p_course_id, p_name, p_kind, p_course_rating, p_slope_rating, p_holes
            }
        }
        do {
            let params = Params(
                p_course_id: id, p_name: values.name, p_kind: values.kind.rawValue,
                p_course_rating: values.courseRating, p_slope_rating: values.slopeRating,
                p_holes: values.holes.map {
                    let r = $0.record(courseID: id ?? UUID())
                    return Hole(hole_number: r.holeNumber, par: r.par, stroke_index: r.strokeIndex, length_m: r.lengthM)
                }
            )
            let savedID: UUID = try await shared.client.rpc("save_library_course", params: params).execute().value
            try await Self.saveTees(values.tees, id: savedID, client: shared.client)
            let rows: [SharedCourseRow] = try await shared.client.from("courses")
                .select(Self.sharedColumns).eq("id", value: savedID).execute().value
            guard let row = rows.first else { throw DataError.notAllowed }
            let holes: [CourseHoleRecord] = try await shared.client.from("course_holes")
                .select(CourseHoleRecord.columns)
                .eq("course_id", value: savedID).execute().value
            let tees = try await Self.loadTees(client: shared.client, courseIDs: [savedID])
            let item = CourseListItem(course: row.course, holes: holes, storedKind: row.kind, tees: tees)
            guard item.holes.count == values.holes.count else { throw DataError.notAllowed }
            replace(item)
            return item
        } catch {
            throw Self.saveError(error, name: values.name)
        }
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

/// En bane i det felles biblioteket med typen (`courses.kind`, sql/016).
nonisolated struct SharedCourseRow: Decodable, Sendable {
    let course: CourseRow
    let kind: CourseKind

    init(from decoder: any Decoder) throws {
        course = try CourseRow(from: decoder)
        kind = try decoder.container(keyedBy: CodingKeys.self).decode(CourseKind.self, forKey: .kind)
    }

    enum CodingKeys: String, CodingKey { case kind }
}
