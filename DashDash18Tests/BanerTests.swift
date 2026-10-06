import Foundation
import GolfgutuCore
import Supabase
import Testing
@testable import DashDash18

/// Et skjema med navn og gitte par, uten indeks og lengde.
private func draft(pars: [Int?], name: String = "Testbanen") -> CourseDraft {
    var draft = CourseDraft(holeCount: pars.count)
    draft.name = name
    for (i, par) in pars.enumerated() { draft.holes[i].par = par }
    return draft
}

private let standard18: [Int?] = Course.defaultPar
private let standard9: [Int?] = Array(Course.defaultPar.prefix(9))

struct BanerDraftTests {
    @Test func nyBaneErTomOgGjetterIkkePar() {
        let draft = CourseDraft()
        #expect(draft.holeCount == 18)
        #expect(draft.holes.allSatisfy { $0.par == nil })
        #expect(draft.par == nil)
        let validation = draft.validate()
        #expect(validation.errors == [.nameMissing])
        #expect(validation.warnings == [.notSetUp])
    }

    @Test func banenUtenParLagresSomIkkeSattOpp() throws {
        var draft = CourseDraft()
        draft.name = "  Ny bane  "
        let values = try #require(draft.validate().values)
        #expect(values.name == "Ny bane")
        #expect(values.holes.isEmpty)
        #expect(values.externalName == nil)
        #expect(values.courseRating == nil)
        #expect(values.slopeRating == nil)
    }

    @Test func gyldigBaneMedIndeks() throws {
        var d = draft(pars: standard18)
        for i in d.holes.indices { d.holes[i].strokeIndexText = "\(18 - i)" }
        d.courseRatingText = "71,4"
        d.slopeText = " 128 "
        d.externalName = "Testbanen GC"
        let validation = d.validate()
        #expect(validation.issues.isEmpty)
        let values = try #require(validation.values)
        #expect(values.courseRating == 71.4)
        #expect(values.slopeRating == 128)
        #expect(values.externalName == "Testbanen GC")
        #expect(values.holes.count == 18)
        #expect(values.holes[0] == CourseHoleInput(number: 1, par: 4, strokeIndex: 18, lengthM: nil))
        #expect(values.coreCourse.isReady)
        #expect(values.coreCourse.hasStrokeIndex)
        #expect(values.coreCourse.par == 72)
        #expect(d.par == 72)
    }

    @Test func manglendeParPaaNoenHullSperrer() {
        var pars = standard18
        pars[2] = nil
        pars[11] = nil
        let validation = draft(pars: pars).validate()
        #expect(validation.errors == [.missingPar(holes: [3, 12])])
        #expect(!validation.canSave)
        #expect(CourseIssue.missingPar(holes: [3, 12]).message == "Par mangler på hull 3 og 12. Les det av skjermen.")
    }

    @Test func likIndeksPaaToHullSperrer() {
        var d = draft(pars: standard9)
        for i in d.holes.indices { d.holes[i].strokeIndexText = "\(i + 1)" }
        d.holes[4].strokeIndexText = "2"
        let validation = d.validate()
        #expect(validation.errors == [.duplicateStrokeIndex(2, holes: [2, 5])])
        #expect(CourseIssue.duplicateStrokeIndex(2, holes: [2, 5]).message == "Hull 2 og 5 har samme indeks (2).")
    }

    @Test func indeksenMaaVaere1TilAntallHull() {
        var d = draft(pars: standard9)
        for i in d.holes.indices { d.holes[i].strokeIndexText = "\(i + 1)" }
        d.holes[8].strokeIndexText = "10"
        d.holes[7].strokeIndexText = "0"
        #expect(d.validate().errors == [
            .strokeIndexOutOfRange(hole: 8, max: 9),
            .strokeIndexOutOfRange(hole: 9, max: 9),
        ])
        d.holes[7].strokeIndexText = "x"
        #expect(d.validate().errors.contains(.strokeIndexOutOfRange(hole: 8, max: 9)))
    }

    @Test func manglendeIndeksErBareAdvarsel() throws {
        var d = draft(pars: standard9)
        d.holes[0].strokeIndexText = "1"
        let validation = d.validate()
        #expect(validation.errors.isEmpty)
        #expect(validation.warnings == [.missingStrokeIndex(holes: [2, 3, 4, 5, 6, 7, 8, 9])])
        let values = try #require(validation.values)
        #expect(values.holes[1].strokeIndex == nil)
    }

    /// Som `lengdePasserParet`: par 4 på 165 m er rart, men lagres (PWA-ens Quail Hollow hull 4).
    @Test func rarLengdeGirAdvarselMenSperrerIkke() throws {
        var d = draft(pars: standard9)
        d.holes[0].lengthText = "165"   // par 4
        d.holes[2].lengthText = "150"   // par 3, passer
        d.holes[1].lengthText = "585"   // par 5, over 580
        let validation = d.validate()
        #expect(validation.errors.isEmpty)
        #expect(validation.warnings.contains(.oddLength(hole: 1, par: 4, meters: 165)))
        #expect(validation.warnings.contains(.oddLength(hole: 2, par: 5, meters: 585)))
        #expect(!validation.warnings.contains { if case .oddLength(hole: 3, _, _) = $0 { true } else { false } })
        let values = try #require(validation.values)
        #expect(values.holes[0].lengthM == 165)
    }

    @Test func lengdeUtenforDatabasensGrenseSperrer() {
        var d = draft(pars: standard9)
        d.holes[0].lengthText = "701"
        d.holes[1].lengthText = "49"
        d.holes[2].lengthText = "lang"
        #expect(d.validate().errors == [.lengthOutOfRange(hole: 1), .lengthOutOfRange(hole: 2), .lengthOutOfRange(hole: 3)])
    }

    @Test func ugyldigParSperrer() {
        var d = draft(pars: standard9)
        d.holes[3].par = 7
        #expect(d.validate().errors == [.invalidPar(hole: 4)])
    }

    @Test(arguments: [
        ("72", 72.0 as Double?),
        ("71,4", 71.4),
        ("71.46", 71.5),
        ("", nil),
        ("  ", nil),
    ])
    func courseRating(_ text: String, _ expected: Double?) throws {
        var d = draft(pars: standard9)
        d.courseRatingText = text
        #expect(try #require(d.validate().values).courseRating == expected)
    }

    @Test(arguments: ["49,9", "90,1", "abc"])
    func courseRatingUtenforGrensene(_ text: String) {
        var d = draft(pars: standard9)
        d.courseRatingText = text
        #expect(d.validate().errors == [.courseRatingOutOfRange])
    }

    @Test(arguments: ["54", "156", "113,5", "x"])
    func slopeUtenforGrensene(_ text: String) {
        var d = draft(pars: standard9)
        d.slopeText = text
        #expect(d.validate().errors == [.slopeOutOfRange])
    }

    @Test func navnetsLengde() {
        var d = draft(pars: standard9, name: String(repeating: "x", count: 81))
        #expect(d.validate().errors == [.nameTooLong])
        d.name = String(repeating: "x", count: 80)
        d.externalName = String(repeating: "y", count: 81)
        #expect(d.validate().errors == [.externalNameTooLong])
    }

    @Test func byttAntallHullBeholderDeNiFoerste() {
        var d = draft(pars: standard18)
        d.holes[0].strokeIndexText = "7"
        d.setHoleCount(9)
        #expect(d.holeCount == 9)
        #expect(d.holes[0].strokeIndexText == "7")
        #expect(d.par == 36)
        d.setHoleCount(18)
        #expect(d.holeCount == 18)
        #expect(d.holes[9] == HoleDraft(number: 10))
        #expect(d.par == nil)
        d.setHoleCount(12)
        #expect(d.holeCount == 18)
    }

    @Test func fraLagredeRader() {
        let id = UUID()
        let course = CourseRow(id: id, clubID: UUID(), name: "Ni hull", externalName: nil, courseRating: 35.5,
                               slopeRating: 120, inUse: false, confirmedBy: nil, confirmedAt: nil)
        let rows = (1...9).reversed().map {
            CourseHoleRecord(courseID: id, holeNumber: $0, par: 4, strokeIndex: $0 == 1 ? nil : $0, lengthM: $0 * 50)
        }
        let d = CourseDraft(course: course, holes: rows)
        #expect(d.holeCount == 9)
        #expect(d.name == "Ni hull")
        #expect(d.courseRatingText == "35,5")
        #expect(d.slopeText == "120")
        #expect(!d.inUse)
        #expect(d.holes[0] == HoleDraft(number: 1, par: 4, strokeIndexText: "", lengthText: "50"))
        #expect(d.holes[8] == HoleDraft(number: 9, par: 4, strokeIndexText: "9", lengthText: "450"))
        #expect(CourseDraft(course: course, holes: []).holeCount == 18)
    }

    @Test func hullListe() {
        #expect(CourseInput.holeList([4]) == "hull 4")
        #expect(CourseInput.holeList([4, 9]) == "hull 4 og 9")
        #expect(CourseInput.holeList([1, 2, 3]) == "hull 1, 2 og 3")
    }

    @Test func parSum() {
        #expect(CourseMath.par([4, 5, 3]) == 12)
        #expect(CourseMath.par([4, nil, 3]) == nil)
        #expect(CourseMath.par([]) == nil)
    }
}

struct BanerListeTests {
    private func item(_ name: String, pars: [Int]? = nil, inUse: Bool = true, confirmed: Bool = false,
                      external: String? = nil) -> CourseListItem {
        let id = UUID()
        let course = CourseRow(id: id, clubID: UUID(), name: name, externalName: external, courseRating: 71,
                               slopeRating: 113, inUse: inUse, confirmedBy: nil,
                               confirmedAt: confirmed ? Date(timeIntervalSince1970: 0) : nil)
        let holes = (pars ?? []).enumerated().map {
            CourseHoleRecord(courseID: id, holeNumber: $0.offset + 1, par: $0.element, strokeIndex: nil, lengthM: nil)
        }
        return CourseListItem(course: course, holes: holes.reversed())
    }

    @Test func parRegnesFraHullene() {
        let full = item("Full", pars: Course.defaultPar)
        #expect(full.isReady)
        #expect(full.par == 72)
        #expect(full.holeCount == 18)
        #expect(full.holes.map(\.holeNumber) == Array(1...18))
        #expect(full.summary == "18 hull · par 72 · CR 71 · slope 113 · uten indeks")

        let nine = item("Ni", pars: [3, 3, 3, 3, 3, 3, 3, 3, 3])
        #expect(nine.par == 27)
        #expect(nine.isReady)
    }

    @Test func banenUtenHellHullErIkkeSattOpp() {
        let empty = item("Tom")
        #expect(!empty.isReady)
        #expect(empty.par == nil)
        #expect(empty.summary == "Ikke satt opp. Skriv inn parene fra skjermen.")
        let twelve = item("Tolv", pars: Array(repeating: 4, count: 12))
        #expect(!twelve.isReady)
        #expect(twelve.par == nil)
    }

    @Test func bekreftet() {
        #expect(item("A", confirmed: true).isConfirmed)
        #expect(!item("A").isConfirmed)
    }

    @Test func navnISimulatorenBareNaarDetErEtAnnet() {
        #expect(item("Losby Golfklubb (Østmork)", external: "Losby Ostmork Course").differentExternalName == "Losby Ostmork Course")
        #expect(item("Adare Manor", external: "adare manor").differentExternalName == nil)
        #expect(item("Adare Manor", external: "").differentExternalName == nil)
        #expect(item("Adare Manor").differentExternalName == nil)
    }

    @Test func sorteringIBrukFoerstSaaNorskAlfabet() {
        let items = [item("Ålesund"), item("Øya"), item("Bergen"), item("Arendal", inUse: false), item("adare")]
        #expect(CourseListItem.sorted(items).map(\.course.name) == ["adare", "Bergen", "Øya", "Ålesund", "Arendal"])
    }

    @Test func settSammenFraToSpoerringer() {
        let a = item("A", pars: [4, 4, 4, 4, 4, 4, 4, 4, 4])
        let b = item("B")
        let made = CourseListItem.make(courses: [b.course, a.course], holes: a.holes)
        #expect(made.map(\.course.name) == ["A", "B"])
        #expect(made[0].par == 36)
        #expect(made[1].holes.isEmpty)
    }
}

struct BanerSkrivingTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func tommeFeltSendesSomNull() throws {
        let values = CourseInputValues(name: "X", externalName: nil, courseRating: nil, slopeRating: nil, inUse: true, holes: [])
        let object = try json(CourseWrite(clubID: UUID(), values: values))
        #expect(Set(object.keys) == ["club_id", "name", "external_name", "course_rating", "slope_rating", "in_use"])
        #expect(object["external_name"] is NSNull)
        #expect(object["course_rating"] is NSNull)
        #expect(object["slope_rating"] is NSNull)
    }

    @Test func hulletHarAlleKolonner() throws {
        let record = CourseHoleRecord(courseID: UUID(), holeNumber: 3, par: 4, strokeIndex: nil, lengthM: nil)
        let object = try json(HoleWrite(record))
        #expect(Set(object.keys) == ["course_id", "hole_number", "par", "stroke_index", "length_m"])
        #expect(object["stroke_index"] is NSNull)
        #expect(object["par"] as? Int == 4)
    }

    @Test func slettingAvBaneIBrukGirForklaring() {
        let error = CourseLibraryModel.deleteError(PostgrestError(code: "23503", message: "violates foreign key constraint"))
        guard case .invalid(let text) = error else {
            Issue.record("Ventet .invalid, fikk \(error)")
            return
        }
        #expect(text.hasPrefix("Banen er brukt i en runde"))
        #expect(CourseLibraryModel.deleteError(PostgrestError(code: "42501", message: "x")) == .notAllowed)
    }

    @Test func navnSomFinnesFraFoer() {
        let error = CourseLibraryModel.saveError(PostgrestError(code: "23505", message: "duplicate key value violates unique constraint \"courses_unique_name\""), name: "Adare Manor")
        #expect(error == .invalid("Det finnes allerede en bane som heter «Adare Manor»."))
        let index = CourseLibraryModel.saveError(PostgrestError(code: "23505", message: "duplicate key value violates unique constraint \"course_holes_unique_stroke_index\""), name: "X")
        #expect(index == .invalid("To hull har samme indeks."))
        #expect(CourseLibraryModel.saveError(PostgrestError(code: "PGRST116", message: "0 rows"), name: "X") == .notAllowed)
    }
}

struct BanerImportTests {
    private static func loadResource() throws -> GolfgutuCourseSet {
        let bundle = Bundle(for: CourseLibraryModel.self)
        return try GolfgutuCourseSet.load(bundle: bundle)
    }

    @Test func ressursenHarDe18BaneneOgAlleErGyldige() throws {
        let set = try Self.loadResource()
        #expect(set.courses.count == 18)
        #expect(Set(set.courses.map { GolfgutuCourseSet.nameKey($0.name) }).count == 18)
        for entry in set.courses {
            let validation = entry.draft.validate()
            #expect(validation.errors.isEmpty, "\(entry.name): \(validation.errors)")
            let values = try #require(validation.values, "\(entry.name)")
            #expect(values.coreCourse.isReady, "\(entry.name) er ikke klar (baneErKlar)")
            #expect(values.holes.count == 18, "\(entry.name)")
            #expect(values.holes.compactMap(\.strokeIndex).sorted() == Array(1...18), "\(entry.name)")
            #expect(values.name == entry.name)
        }
    }

    /// Stikkprøver mot SQL-filene i kjørerekkefølgen.
    @Test func stikkproeverMotReferansen() throws {
        let set = try Self.loadResource()
        func course(_ name: String) throws -> GolfgutuCourseSet.CourseEntry {
            try #require(set.courses.first { $0.name == name }, "\(name) mangler")
        }
        // adare-manor-indeks.sql: hull 1 par 4 indeks 11; lengden fra baner-kartlagt.sql.
        let adare = try course("Adare Manor")
        #expect(adare.holes[0] == .init(holeNumber: 1, par: 4, strokeIndex: 11, lengthM: 396))
        #expect(adare.holes.reduce(0) { $0 + $1.par } == 72)
        // barseback-indeks.sql: par 73, hull 18 indeks 1.
        let barseback = try course("Barsebäck (Ocean)")
        #expect(barseback.holes.reduce(0) { $0 + $1.par } == 73)
        #expect(barseback.holes[17].strokeIndex == 1)
        #expect(barseback.externalName == "Barsebäck Golf & Country Club Ocean")
        // Le Golf National står bare i trackman-baner.sql.
        let national = try course("Le Golf National")
        #expect(national.courseRating == 71)
        #expect(national.slopeRating == 113)
        // Navnet i simulatoren.
        #expect(try course("Losby Golfklubb (Østmork)").externalName == "Losby Ostmork Course")
    }

    @Test func manglendeBanerSammenlignesUtenStoreOgSmaaBokstaver() throws {
        let set = try Self.loadResource()
        #expect(set.missing(existingNames: []).count == 18)
        let missing = set.missing(existingNames: ["adare manor", " PEBBLE BEACH GOLF LINKS ", "Min egen bane"])
        #expect(missing.count == 16)
        #expect(!missing.contains { $0.name == "Adare Manor" })
        #expect(set.missing(existingNames: set.courses.map(\.name)).isEmpty)
    }

    @Test func dekodingAvLitenFil() throws {
        let data = Data("""
        {"kilde": "test", "baner": [{"name": "A", "external_name": null, "course_rating": null, "slope_rating": null,
          "holes": [{"hole_number": 2, "par": 3, "stroke_index": null, "length_m": null},
                    {"hole_number": 1, "par": 4, "stroke_index": 1, "length_m": 300}]}]}
        """.utf8)
        let set = try GolfgutuCourseSet.decode(data)
        let draft = try #require(set.courses.first).draft
        #expect(draft.holes.map(\.number) == [1, 2])
        #expect(draft.holes[0] == HoleDraft(number: 1, par: 4, strokeIndexText: "1", lengthText: "300"))
        #expect(draft.externalName == "")
    }
}
