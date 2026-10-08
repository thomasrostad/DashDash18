import Foundation
import GolfgutuCore

// Baner og tees fra slope.no (fase 20). Skjemaet er sql/029_slope_baner.sql (forslag): `course_tees`,
// teen på runden (`rounds.tee_id` med CR og slope slik de var ved start) og hentede baner i det felles
// biblioteket (`courses.source = 'slope'`, fylt av Edge Function `slope-sync`). Ren logikk her, uten
// nettverk og SwiftUI.

/// Baner og tees fra slope.no. På siden 08.10.2026: sql/029 er kjørt på test, og `slope-sync` har hentet
/// 1306 baner (synk hver natt kl. 03:17 UTC). Slås det av, leser og skriver appen ingen av de nye
/// kolonnene og tabellene, og alt ser ut som før fase 20.
nonisolated enum SlopeNoFeature {
    static let isEnabled = true

    /// Hull per tee fra slope.no (fase 20b, sql/030_slope_hull.sql). På siden 08.10.2026: 030 er kjørt
    /// på test, og slope-sync v2 har skrevet hull for 937 baner og 6146 tees. Av: appen leser verken `course_tee_holes` eller
    /// `rounds.tee_par`, hentede baner vises bare under «Hent fra slope.no» (kopi og scorekort), og alt
    /// er som i fase 20. På: hentede baner med hull kan velges direkte i runde-oppsettet og i løse
    /// runder, og runden spilles med teens hull.
    static let usesHoles = true
}

/// Krediteringen eieren av slope.no ber om: tekst og lenke der tee-data vises eller velges.
nonisolated enum SlopeNoCredit {
    static var text: String { text(usesHoles: SlopeNoFeature.usesHoles) }
    static let url = URL(string: "https://slope.no")!

    /// Med hullene (fase 20b) kommer også par, indeks og lengde fra slope.no.
    static func text(usesHoles: Bool) -> String {
        usesHoles ? "Hull, slope og course rating fra slope.no" : "Slope og course rating fra slope.no"
    }
}

/// Herre, dame eller begge (`course_tees.gender`).
nonisolated enum TeeGender: String, Codable, CaseIterable, Hashable, Sendable {
    case men
    case women
    case mixed

    var title: String {
        switch self {
        case .men: "Herre"
        case .women: "Dame"
        case .mixed: "Alle"
        }
    }
}

/// Én tee på en bane (`course_tees`, sql/029).
nonisolated struct CourseTeeRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let courseID: UUID
    var name: String
    var gender: TeeGender
    var courseRating: Double
    var slopeRating: Int
    var par: Int?
    var sortOrder: Int
    /// Borte fra kilden siden (hentede tees slettes aldri). Slike vises ikke.
    var missingAt: Date?
    /// Teens egne hull fra kilden (`course_tee_holes`, sql/030), som banens hullrader. Ikke en kolonne i
    /// `course_tees`: festes på etter lesingen (`TeeHoles.attach`). Tom = banens hull gjelder.
    var holes: [CourseHoleRecord] = []

    init(id: UUID = UUID(), courseID: UUID, name: String, gender: TeeGender, courseRating: Double, slopeRating: Int,
         par: Int? = nil, sortOrder: Int = 0, missingAt: Date? = nil, holes: [CourseHoleRecord] = []) {
        self.id = id
        self.courseID = courseID
        self.name = name
        self.gender = gender
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.par = par
        self.sortOrder = sortOrder
        self.missingAt = missingAt
        self.holes = holes.sorted { $0.holeNumber < $1.holeNumber }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case courseID = "course_id"
        case name
        case gender
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
        case sortOrder = "sort_order"
        case missingAt = "missing_at"
    }

    static let columns = "id, course_id, name, gender, course_rating, slope_rating, par, sort_order, missing_at"
}

/// Valget av tee: rekkefølgen, forslaget og tallene runden regner med.
nonisolated enum TeeChoice {
    /// Teene som vises: ikke borte fra kilden, i kildens rekkefølge (så navn).
    static func visible(_ tees: [CourseTeeRow]) -> [CourseTeeRow] {
        tees.filter { $0.missingAt == nil }.sorted { a, b in
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
    }

    /// Forslaget: teen som ble brukt sist på banen, ellers første herre-tee, ellers første tee.
    static func suggested(_ tees: [CourseTeeRow], previous: UUID?) -> CourseTeeRow? {
        let shown = visible(tees)
        if let previous, let tee = shown.first(where: { $0.id == previous }) { return tee }
        return shown.first { $0.gender == .men } ?? shown.first
    }

    /// Teen som ble brukt i den siste runden på banen: den som startet sist, ellers høyest rundenummer.
    static func previousTeeID(rounds: [RoundRow], courseID: UUID?) -> UUID? {
        guard let courseID else { return nil }
        return rounds
            .filter { $0.courseID == courseID && $0.teeID != nil }
            .max { a, b in
                switch (a.startedAt, b.startedAt) {
                case let (x?, y?): x < y
                case (nil, _?): true
                case (_?, nil): false
                case (nil, nil): a.roundNo < b.roundNo
                }
            }?.teeID
    }

    /// Banen med teens CR og slope. Uten tee er banen uendret (Golfgutu-paritet).
    static func applying(_ tee: CourseTeeRow?, to course: Course?) -> Course? {
        guard var course, let tee else { return course }
        course.courseRating = tee.courseRating
        course.slopeRating = Double(tee.slopeRating)
        return course
    }

    /// «herre · CR 71,2 · slope 129 · par 72», og lengden når teen har egne hull («· 6 040 m»).
    static func detail(_ tee: CourseTeeRow) -> String {
        var parts = [tee.gender.title.lowercased(), "CR \(CourseInput.decimalText(tee.courseRating))", "slope \(tee.slopeRating)"]
        if let par = TeeHoles.par(of: tee) ?? tee.par { parts.append("par \(par)") }
        if let meters = TeeHoles.totalLength(tee.holes) { parts.append(TeeHoles.lengthText(meters)) }
        return parts.joined(separator: " · ")
    }

    /// Forklaringen under tee-valget. Med egne hull (fase 20b) gjelder også teens par og indeks.
    static func pickerFooter(hasHoles: Bool) -> String {
        hasHoles
            ? "Teens hull (par, indeks og lengde), course rating og slope gjelder i runden. De lagres på runden når den starter, så en endring hos slope.no senere endrer ikke gamle runder."
            : "Teens course rating og slope gir banehandicapet. Tallene lagres på runden når den starter, så en ny rating senere endrer ikke gamle runder."
    }

    /// Verdien i tee-raden: «Gul (herre)».
    static func value(_ tee: CourseTeeRow?) -> String {
        guard let tee else { return "Banens tall" }
        return "\(tee.name) (\(tee.gender.title.lowercased()))"
    }
}

// MARK: - Søk i slope.no-banene

/// En bane fra slope.no i det felles biblioteket (`courses` med `source = 'slope'`), slik søket trenger den.
nonisolated struct SlopeCourseRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var city: String?
    /// ISO-kode (NO, SE, DK, FI, IS).
    var country: String?
    /// Banen har hull fra kilden (sql/030): den kan spilles direkte, uten kopi. Leses bare med
    /// `SlopeNoFeature.usesHoles` (`holeColumns`), ellers false.
    var hasHoles: Bool

    init(id: UUID, name: String, city: String? = nil, country: String? = nil, hasHoles: Bool = false) {
        self.id = id
        self.name = name
        self.city = city
        self.country = country
        self.hasHoles = hasHoles
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        struct HoleRef: Decodable { let hole_number: Int }
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        country = try c.decodeIfPresent(String.self, forKey: .country)
        hasHoles = !(try c.decodeIfPresent([HoleRef].self, forKey: .courseHoles) ?? []).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, name, city, country
        case courseHoles = "course_holes"
    }

    static let columns = "id, name, city, country"
    /// Med hull: hull nummer 1 som innebygd rad (filtrert med `course_holes.hole_number=eq.1`), så
    /// lista over 1300 baner ikke tar med 17 000 hull.
    static let holeColumns = columns + ", course_holes(hole_number)"
}

nonisolated enum SlopeCourseSearch {
    /// Landet på norsk, for lista og søket.
    static func countryName(_ code: String?) -> String? {
        switch code?.uppercased() {
        case "NO": "Norge"
        case "SE": "Sverige"
        case "DK": "Danmark"
        case "FI": "Finland"
        case "IS": "Island"
        case "PL": "Polen"
        case "DE": "Tyskland"
        case nil: nil
        case let other?: other
        }
    }

    /// Hvor mange baner fra slope.no bane-velgeren viser om gangen (fase 20b).
    static let pickerLimit = 25

    /// Baner med hull i bane-velgeren: de som passer søket, uten dem som alt står i lista.
    static func playable(_ courses: [SlopeCourseRow], query: String, excluding: Set<UUID>) -> [SlopeCourseRow] {
        filter(courses.filter { $0.hasHoles && !excluding.contains($0.id) }, query: query)
    }

    /// Linja under en bane fra slope.no i velgeren: «Ekte bane · Lørenskog, Norge».
    static func pickerDetail(_ course: SlopeCourseRow) -> String {
        let place = place(course)
        return place.isEmpty ? CourseKind.course.title : "\(CourseKind.course.title) · \(place)"
    }

    /// Når en bane med hull velges i «Ny bane» (fase 20b): den trenger ingen kopi.
    static let playableNotice = "Banen har par, indeks og lengde per tee fra slope.no, så den trenger ikke legges inn. Velg den under «Fra slope.no» når du setter opp runden, og velg tee."

    /// Teksten under søket. `playing`: bare baner med hull, valgt i runden (fase 20b).
    static func footer(playing: Bool, usesHoles: Bool) -> String {
        if playing {
            return "Banene med par, indeks og lengde per hull. Velg tee etterpå: teens hull, course rating og slope gjelder i runden."
        }
        if usesHoles {
            return "Har banen hull, kan den spilles direkte: velg den når runden settes opp. Ellers fylles navn, tees, course rating og slope inn, og par og indeks leser du av scorekortet."
        }
        return "Navn, tees, course rating og slope fylles inn. Par og indeks per hull står ikke her: de leser du av scorekortet."
    }

    /// «Oslo, Norge».
    static func place(_ course: SlopeCourseRow) -> String {
        [course.city, countryName(course.country)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Alle ordene må finnes i navnet, stedet eller landet (uten hensyn til store bokstaver og aksenter).
    /// Norske baner først, så resten; hver gruppe norsk alfabetisk.
    static func filter(_ courses: [SlopeCourseRow], query: String) -> [SlopeCourseRow] {
        let words = query.split(whereSeparator: \.isWhitespace).map { CourseSearch.normalize(String($0)) }
        let matching = words.isEmpty ? courses : courses.filter { course in
            let haystack = CourseSearch.normalize([course.name, course.city ?? "", countryName(course.country) ?? "",
                                                   course.country ?? ""].joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
        return sorted(matching)
    }

    static func sorted(_ courses: [SlopeCourseRow]) -> [SlopeCourseRow] {
        courses.sorted { a, b in
            let aNorway = a.country == "NO"
            let bNorway = b.country == "NO"
            if aNorway != bNorway { return aNorway }
            return NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
    }
}

// MARK: - «Ny bane» fra slope.no

/// En tee i skjemaet: det som lagres med `save_course_tees`.
nonisolated struct TeeInput: Equatable, Hashable, Sendable, Encodable {
    var name: String
    var gender: TeeGender
    var courseRating: Double
    var slopeRating: Int
    var par: Int?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, gender
        case courseRating = "course_rating"
        case slopeRating = "slope_rating"
        case par
        case sortOrder = "sort_order"
    }

    init(name: String, gender: TeeGender, courseRating: Double, slopeRating: Int, par: Int? = nil, sortOrder: Int = 0) {
        self.name = name
        self.gender = gender
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.par = par
        self.sortOrder = sortOrder
    }

    init(_ row: CourseTeeRow) {
        self.init(name: row.name, gender: row.gender, courseRating: row.courseRating, slopeRating: row.slopeRating,
                  par: row.par, sortOrder: row.sortOrder)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(gender, forKey: .gender)
        try c.encode(courseRating, forKey: .courseRating)
        try c.encode(slopeRating, forKey: .slopeRating)
        try c.encode(par, forKey: .par)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

nonisolated extension CourseDraft {
    /// Fyller skjemaet fra en bane på slope.no: navn, ekte bane, teene, og banens CR og slope fra
    /// forslaget (første herre-tee) når de passer skjemaets grenser. Hullene røres ikke: en bane uten
    /// hull hos kilden leses av scorekortet som før. (En bane med hull spilles direkte, se
    /// `SlopeCourseSearchView`; velger arrangøren likevel en egen kopi, fylles hullene ikke inn.)
    mutating func prefill(from course: SlopeCourseRow, tees rows: [CourseTeeRow]) {
        name = String(course.name.prefix(CourseInput.maxNameLength))
        kind = .course
        externalName = ""
        let shown = TeeChoice.visible(rows)
        tees = shown.map(TeeInput.init)
        if let standard = TeeChoice.suggested(shown, previous: nil),
           CourseInput.courseRatingRange.contains(standard.courseRating),
           CourseInput.slopeRange.contains(standard.slopeRating) {
            courseRatingText = CourseInput.decimalText(standard.courseRating)
            slopeText = String(standard.slopeRating)
        } else {
            courseRatingText = ""
            slopeText = ""
        }
        // En 9-hullsbane på slope.no har par under 40 på alle tees.
        if let par = shown.compactMap(\.par).max(), par < 40 { setHoleCount(9) }
    }
}
