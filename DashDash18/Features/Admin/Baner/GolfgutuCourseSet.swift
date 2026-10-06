import Foundation

/// PWA-ens 18 baner, lest fra `Resources/golfgutu-baner.json`.
///
/// Slik ble fila laget (06.10.2026), bare med lesing av `referanse/golfgutu-pwa/sql/`:
/// et engangsskript (Python) leste SQL-filene i rekkefølgen de ble kjørt mot PWA-ens
/// database, og lot hver fil overskrive den forrige:
/// 1. `trackman-baner.sql`: navn, `trackman_name` (→ `external_name`), CR, slope og alle hull.
/// 2. `baner-kartlagt.sql`: nuller indeksen og skriver par, indeks og lengde for 17 baner
///    (alle unntatt Le Golf National, som står som i 1).
/// 3. `adare-manor-indeks.sql` og `barseback-indeks.sql`: par og indeks for de to banene.
/// CR og slope er tallene fra `trackman-baner.sql`; ingen senere fil endret dem.
/// (`rett-par.sql` kjørte mellom 1 og 2, men alt den rørte, overskrives av 2.)
/// Hull uten lengde står som `null`. Skriptet sjekket at hver bane har hull 1–18 og
/// indeksene 1–18 én gang hver.
nonisolated struct GolfgutuCourseSet: Decodable, Equatable, Sendable {
    nonisolated struct Hole: Decodable, Equatable, Sendable {
        let holeNumber: Int
        let par: Int
        let strokeIndex: Int?
        let lengthM: Int?

        enum CodingKeys: String, CodingKey {
            case holeNumber = "hole_number"
            case par
            case strokeIndex = "stroke_index"
            case lengthM = "length_m"
        }
    }

    nonisolated struct CourseEntry: Decodable, Equatable, Sendable {
        let name: String
        let externalName: String?
        let courseRating: Double?
        let slopeRating: Int?
        let holes: [Hole]

        enum CodingKeys: String, CodingKey {
            case name
            case externalName = "external_name"
            case courseRating = "course_rating"
            case slopeRating = "slope_rating"
            case holes
        }

        /// Banen som skjema, så den går gjennom samme sjekk som en bane arrangøren skriver inn.
        var draft: CourseDraft {
            var draft = CourseDraft(holeCount: holes.count)
            draft.name = name
            draft.externalName = externalName ?? ""
            draft.courseRatingText = courseRating.map(CourseInput.decimalText) ?? ""
            draft.slopeText = slopeRating.map(String.init) ?? ""
            draft.holes = holes.sorted { $0.holeNumber < $1.holeNumber }.map {
                HoleDraft(
                    number: $0.holeNumber,
                    par: $0.par,
                    strokeIndexText: $0.strokeIndex.map(String.init) ?? "",
                    lengthText: $0.lengthM.map(String.init) ?? ""
                )
            }
            return draft
        }
    }

    let courses: [CourseEntry]

    enum CodingKeys: String, CodingKey {
        case courses = "baner"
    }

    static let resourceName = "golfgutu-baner"

    static func decode(_ data: Data) throws -> GolfgutuCourseSet {
        try JSONDecoder().decode(GolfgutuCourseSet.self, from: data)
    }

    /// Fra app-bunten.
    static func load(bundle: Bundle = .main) throws -> GolfgutuCourseSet {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: url))
    }

    /// Banene fra settet som klubben ikke har. Navnene sammenlignes uten store/små
    /// bokstaver og mellomrom i endene, som den unike indeksen i databasen
    /// (`lower(btrim(name))`).
    func missing(existingNames: [String]) -> [CourseEntry] {
        let existing = Set(existingNames.map(Self.nameKey))
        return courses.filter { !existing.contains(Self.nameKey($0.name)) }
    }

    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
