import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 20b: hull per tee fra slope.no (sql/030, `SlopeNoFeature.usesHoles`). Tallene er fra slope.no-
// eksporten 08.10.2026: Valdres Golfklubb (id 154) har par 73 fra «Svart 73» og par 66 fra «Grønn 66»,
// Losby Østmork (id 16) har like par og indeks på alle tees, men ulik lengde.

private enum V {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-020b-%012d", n))! }
    static let course = id(1)
    static let round = id(2)
    static let svartID = id(11)
    static let gronnID = id(13)
    static let rodID = id(14)

    /// Par og indeks fra Svart 73 (banens hull).
    static let svartPar = [5, 4, 3, 4, 5, 4, 3, 4, 4, 5, 4, 3, 4, 5, 4, 3, 4, 5]
    /// Grønn 66: kortere bane med andre par og en annen indeks.
    static let gronnPar = [4, 3, 3, 4, 4, 4, 3, 4, 4, 4, 3, 3, 4, 4, 4, 3, 4, 4]

    static func holes(_ pars: [Int], shift: Int = 0, course: UUID = course) -> [CourseHoleRecord] {
        pars.indices.map {
            CourseHoleRecord(courseID: course, holeNumber: $0 + 1, par: pars[$0], strokeIndex: ($0 + shift) % pars.count + 1,
                             lengthM: 100 + 10 * ($0 + 1))
        }
    }

    static let svart = CourseTeeRow(id: svartID, courseID: course, name: "Svart 73", gender: .men, courseRating: 72.4,
                                    slopeRating: 130, par: 73, sortOrder: 1, holes: holes(svartPar))
    static let gronn = CourseTeeRow(id: gronnID, courseID: course, name: "Grønn 66", gender: .men, courseRating: 63.1,
                                    slopeRating: 110, par: 66, sortOrder: 3, holes: holes(gronnPar, shift: 4))
    /// Dametee uten hull hos kilden.
    static let rod = CourseTeeRow(id: rodID, courseID: course, name: "Rød", gender: .women, courseRating: 70,
                                  slopeRating: 125, sortOrder: 4)

    static let row = CourseRow(id: course, clubID: nil, name: "Valdres Golfklubb", externalName: nil, courseRating: 72.4,
                               slopeRating: 130, inUse: true, confirmedBy: nil, confirmedAt: nil)

    static var item: CourseListItem {
        CourseListItem(course: row, holes: holes(svartPar), storedKind: .course, tees: [svart, gronn, rod], isFromSource: true)
    }

    static func roundRow(teeID: UUID?, cr: Double?, slope: Int?, teePar: Int?) -> RoundRow {
        var row = RoundRow(id: round, clubID: nil, eventID: nil, courseID: course, roundNo: 1, name: nil,
                           status: .active, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                           handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: true, ldHoleIndex: nil,
                           kpEnabled: true, kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                           parConfirmedAt: nil, startedAt: nil, lockedAt: nil)
        row.teeID = teeID
        row.courseRating = cr
        row.slopeRating = slope
        row.teePar = teePar
        return row
    }
}

struct SlopeNoHoleFlagTests {
    @Test func hulleneErPåNårSqlOgSynkenHarGått() {
        #expect(SlopeNoFeature.usesHoles == true)
        #expect(RoundRow.columns.contains("tee_par") == SlopeNoFeature.usesHoles, "kolonnen hentes bare med flagget")
        #expect(StatsRoundRow.columns.contains("tee_par") == SlopeNoFeature.usesHoles)
        #expect(SlopeNoCredit.text == SlopeNoCredit.text(usesHoles: SlopeNoFeature.usesHoles))
        #expect(SlopeNoCredit.text(usesHoles: false) == "Slope og course rating fra slope.no")
        #expect(SlopeNoCredit.text(usesHoles: true) == "Hull, slope og course rating fra slope.no")
        #expect(RoundRow.teeParColumn == "tee_par")
    }
}

@MainActor
struct SlopeNoTeeHoleTests {
    @Test func hullradeneFestesPaTeeneSineSortertPaNummer() {
        let rows = [
            TeeHoleRow(teeID: V.gronnID, holeNumber: 2, par: 3, strokeIndex: 6, lengthM: 120),
            TeeHoleRow(teeID: V.gronnID, holeNumber: 1, par: 4, strokeIndex: 5, lengthM: nil),
            TeeHoleRow(teeID: UUID(), holeNumber: 1, par: 5, strokeIndex: 1, lengthM: 400),
        ]
        let bare = CourseTeeRow(id: V.gronnID, courseID: V.course, name: "Grønn 66", gender: .men, courseRating: 63.1,
                                slopeRating: 110)
        let attached = TeeHoles.attach(rows, to: [bare, V.rod])
        #expect(attached[0].holes.map(\.holeNumber) == [1, 2])
        #expect(attached[0].holes.allSatisfy { $0.courseID == V.course }, "som banens hullrader")
        #expect(attached[0].holes[1].lengthM == 120)
        #expect(attached[1].holes.isEmpty)
        #expect(TeeHoles.attach([], to: [bare]) == [bare])
    }

    @Test func etHeltSettEr9Eller18HullMedGyldigPar() {
        #expect(TeeHoles.isComplete(V.holes(V.svartPar)))
        #expect(TeeHoles.isComplete(V.holes(Array(V.svartPar.prefix(9)))))
        #expect(!TeeHoles.isComplete(V.holes(Array(V.svartPar.prefix(17)))))
        #expect(!TeeHoles.isComplete([]))
        var gap = V.holes(V.svartPar)
        gap.remove(at: 4)
        gap.append(CourseHoleRecord(courseID: V.course, holeNumber: 19, par: 4, strokeIndex: nil, lengthM: nil))
        #expect(!TeeHoles.isComplete(gap))
        var badPar = V.holes(V.svartPar)
        badPar[3].par = 7
        #expect(!TeeHoles.isComplete(badPar))
    }

    @Test func teensHullGjelderNarTeenHarEgneEllersBanens() {
        let course = V.holes(V.svartPar)
        #expect(TeeHoles.effective(course: course, tee: V.gronn) == V.gronn.holes)
        #expect(TeeHoles.effective(course: course, tee: V.rod) == course, "tee uten hull: banens")
        #expect(TeeHoles.effective(course: course, tee: nil) == course, "uten tee: banens")
        #expect(TeeHoles.par(of: V.gronn) == 66)
        #expect(TeeHoles.par(of: V.svart) == 73)
        #expect(TeeHoles.par(of: V.rod) == nil)
    }

    @Test func lengdenSummeresBareNarAlleHullHarLengde() {
        #expect(TeeHoles.totalLength(V.svart.holes) == (1...18).reduce(0) { $0 + 100 + 10 * $1 })
        var missing = V.svart.holes
        missing[0].lengthM = nil
        #expect(TeeHoles.totalLength(missing) == nil)
        #expect(TeeHoles.totalLength([]) == nil)
        #expect(TeeHoles.lengthText(6178).hasSuffix(" m"))
        #expect(TeeHoles.lengthText(6178).filter(\.isNumber) == "6178")
    }

    @Test func teeRadenViserParOgLengdeFraHullene() {
        let detail = TeeChoice.detail(V.gronn)
        #expect(detail.contains("par 66"))
        #expect(detail.contains("CR 63,1"))
        #expect(detail.hasSuffix(" m"))
        #expect(TeeChoice.detail(V.rod) == "dame · CR 70 · slope 125", "uten hull som før")
        let losby = SlopeNoSamples.losbyTees(holes: true)[0]
        #expect(TeeHoles.totalLength(losby.holes) == 6178, "Losby Østmork tee 64 i eksporten")
        #expect(TeeChoice.pickerFooter(hasHoles: false).hasPrefix("Teens course rating og slope gir banehandicapet."))
    }
}

struct SlopeNoCourseHoleTests {
    @Test func medTeeSomHarEgneHullSpillesTeensParIndeksOgLengde() throws {
        let item = V.item
        let course = item.coreCourse(tee: V.gronnID)
        #expect(course.par == 66, "teens par, ikke banens 73")
        #expect(course.courseRating == 63.1)
        #expect(course.slopeRating == 110)
        let holes = try #require(course.holes)
        #expect(holes.map(\.par) == V.gronnPar)
        #expect(holes.map(\.si) == V.gronn.holes.map(\.strokeIndex))
        #expect(item.holeCount(tee: V.gronnID) == 18)
        #expect(item.holes(tee: V.gronnID) == V.gronn.holes)
    }

    @Test func banehandicapetRegnesMedTeensPar() {
        // WHS: indeks · slope/113 + (CR − par). Indeks 18,0 på Grønn: 17,52 − 2,9 = 14,62 → 15.
        let gronn = V.item.coreCourse(tee: V.gronnID)
        #expect(Handicap.courseHandicap(index: 18, courseRating: gronn.courseRating, slopeRating: gronn.slopeRating,
                                        par: gronn.par.map(Double.init)) == 15)
        // Med banens par (73) ville det blitt 17,52 − 9,9 = 7,62 → 8.
        #expect(Handicap.courseHandicap(index: 18, courseRating: 63.1, slopeRating: 110, par: 73) == 8)
    }

    @Test func slagfordelingenFolgerTeensIndeks() {
        let course = V.item.coreCourse(tee: V.gronnID)
        let round = Round(id: "r", gameType: "stableford", holeCount: 18, holeStart: 0, course: course)
        let played = round.courseHoles()
        // Grønn er forskjøvet 4: hull 1 har indeks 5, hull 15 har indeks 1.
        #expect(played[0].cardIndex == 5)
        #expect(played[14].strokeIndex == 1)
        #expect(played.map(\.par) == V.gronnPar)
    }

    @Test func utenTeeEllerMedTeeUtenHullErBanenSomFor() {
        let item = V.item
        #expect(item.coreCourse(tee: nil) == item.coreCourse, "Golfgutu-pariteten: uten tee er banen uendret")
        let rod = item.coreCourse(tee: V.rodID)
        #expect(rod.holes == item.coreCourse.holes)
        #expect(rod.par == 73)
        #expect(rod.courseRating == 70)
        #expect(item.coreCourse(tee: UUID()) == item.coreCourse, "ukjent tee")
    }

    @Test func simulatorbaneUtenTeesErUendret() {
        let row = CourseRow(id: V.id(50), clubID: V.id(51), name: "Pebble Beach", externalName: nil, courseRating: 72,
                            slopeRating: 128, inUse: true, confirmedBy: nil, confirmedAt: nil)
        let sim = CourseListItem(course: row, holes: V.holes(Course.defaultPar, course: row.id), storedKind: .simulator)
        #expect(sim.coreCourse(tee: nil) == sim.coreCourse)
        #expect(sim.holes(tee: nil) == sim.holes)
        #expect(!sim.isFromSource)
        #expect(RoundConfirm.courseDetail(sim) == sim.summary)
    }

    @Test func hentetBaneHarKildeMerke() {
        #expect(V.item.isFromSource)
        #expect(RoundConfirm.courseDetail(V.item).hasSuffix(" · fra slope.no"))
        #expect(V.item.isReady, "banens hull fra hull-teen gjør den klar")
    }

    @Test func hentedeBanerLeggesBakDeAndreOgByttesUtMedSammeId() {
        let other = CourseListItem(course: CourseRow(id: V.id(60), clubID: nil, name: "Annen", externalName: nil,
                                                     courseRating: nil, slopeRating: nil, inUse: true, confirmedBy: nil,
                                                     confirmedAt: nil), holes: [])
        let list = CourseListItem.adding([V.item], to: [other])
        #expect(list.map(\.id) == [other.id, V.course])
        var renamed = V.item
        renamed.course.name = "Valdres GK"
        #expect(CourseListItem.adding([renamed], to: list).map(\.course.name) == ["Annen", "Valdres GK"])
    }
}

struct SlopeNoRoundHoleTests {
    /// Hullene slik databasen frøs dem ved start (`rounds_holes_snapshot`): teens hull som rundens
    /// overstyringer (0-basert).
    static func frozen(_ tee: CourseTeeRow) -> [RoundHoleRow] {
        tee.holes.map { RoundHoleRow(roundID: V.round, holeIndex: $0.holeNumber - 1, par: $0.par,
                                     strokeIndex: $0.strokeIndex, lengthM: $0.lengthM) }
    }

    @Test func rundenRegnerMedFrosneHullOgTeensParFraStart() {
        let round = V.roundRow(teeID: V.gronnID, cr: 63.1, slope: 110, teePar: 66)
        var snapshot = RoundSnapshot(round: round)
        snapshot.course = V.row
        snapshot.courseHoles = V.holes(V.svartPar)  // banens hull (Svart), som course_holes
        snapshot.roundHoles = Self.frozen(V.gronn)
        let game = RoundGame(snapshot)
        #expect(game.round.course?.par == 66)
        #expect(game.round.course?.courseRating == 63.1)
        #expect(game.holes.map(\.par) == V.gronnPar, "føringen bruker teens par")
        #expect(game.holes[14].strokeIndex == 1, "og teens indeks")
    }

    @Test func utenTeeParErParetSummenAvHulleneSomFor() {
        let plain = RoundGame.makeCourse(V.row, holes: V.holes(V.svartPar), round: V.roundRow(teeID: nil, cr: nil, slope: nil, teePar: nil))
        #expect(plain?.par == 73)
        #expect(plain?.courseRating == 72.4)
        let teed = RoundGame.makeCourse(V.row, holes: V.holes(V.svartPar), round: V.roundRow(teeID: V.rodID, cr: 70, slope: 125, teePar: nil))
        #expect(teed?.par == 73, "tee uten egne hull: banens par")
        #expect(teed?.holes == plain?.holes)
        #expect(TeeHoles.coursePar(holesPar: 73, teePar: nil) == 73)
        #expect(TeeHoles.coursePar(holesPar: 73, teePar: 66) == 66)
    }

    @Test func statistikkenRegnerMedTeensPar() {
        var input = StatsInput()
        input.courses = [StatsCourseRow(id: V.course, name: "Valdres", courseRating: 72.4, slopeRating: 130)]
        input.courseHoles = V.holes(V.svartPar)
        var round = StatsRoundRow(id: V.round, clubID: nil, eventID: nil, courseID: V.course, name: nil, status: .locked,
                                  holeCount: 18, firstHole: 1, format: "stableford", handicapAllowance: 1,
                                  externalHandicap: false, startedAt: nil)
        #expect(input.makeCourse(V.course, round: round)?.par == 73)
        round.courseRating = 63.1
        round.slopeRating = 110
        round.teePar = 66
        #expect(input.makeCourse(V.course, round: round)?.par == 66)
    }

    @Test func rundeRadenLeserTeensPar() throws {
        let json = """
        {"id":"\(V.round.uuidString)","club_id":null,"event_id":null,"course_id":"\(V.course.uuidString)",
         "round_no":1,"name":null,"status":"active","hole_count":18,"first_hole":1,"tee_time":null,
         "format":"stableford","handicap_allowance":1,"external_handicap":false,"weight":1,"ld_enabled":true,
         "ld_hole_index":null,"kp_enabled":true,"kp_hole_index":null,"cut_rule":null,"cut_after":null,
         "par_confirmed_by":null,"par_confirmed_at":null,"started_at":null,"locked_at":null,
         "tee_id":"\(V.gronnID.uuidString)","tee_name":"Grønn 66","course_rating":63.1,"slope_rating":110,"tee_par":66}
        """
        let row = try JSONDecoder().decode(RoundRow.self, from: Data(json.utf8))
        #expect(row.teePar == 66)
        let encoded = try #require(String(data: JSONEncoder().encode(V.roundRow(teeID: nil, cr: nil, slope: nil, teePar: nil)),
                                          encoding: .utf8))
        #expect(!encoded.contains("tee_par"), "tom tee_par sendes ikke")
    }
}

@MainActor
struct SlopeNoCatalogHoleTests {
    @Test func listaVetHvilkeBanerSomHarHull() throws {
        let json = """
        [{"id":"\(V.id(70).uuidString)","name":"Valdres Golfklubb","city":"Aurdal","country":"NO","course_holes":[{"hole_number":1}]},
         {"id":"\(V.id(71).uuidString)","name":"Helsingin Golfklubi","city":"Helsinki","country":"FI","course_holes":[]},
         {"id":"\(V.id(72).uuidString)","name":"A6 Golfklubb","city":"Jönköping","country":"SE"}]
        """
        let rows = try JSONDecoder().decode([SlopeCourseRow].self, from: Data(json.utf8))
        #expect(rows.map(\.hasHoles) == [true, false, false])
        #expect(SlopeCourseRow.holeColumns == "id, name, city, country, course_holes(hole_number)")
    }

    @Test func velgerenViserBanerMedHullSomPasserSoketOgIkkeStarIListaFraFor() {
        let rows = [
            SlopeCourseRow(id: V.id(80), name: "Valdres Golfklubb", city: "Aurdal", country: "NO", hasHoles: true),
            SlopeCourseRow(id: V.id(81), name: "Helsingin Golfklubi", city: "Helsinki", country: "FI", hasHoles: false),
            SlopeCourseRow(id: V.id(82), name: "Oslo Golfklubb", city: "Oslo", country: "NO", hasHoles: true),
            SlopeCourseRow(id: V.id(83), name: "Aarhus Golf Club", city: "Aarhus", country: "DK", hasHoles: true),
        ]
        #expect(SlopeCourseSearch.playable(rows, query: "", excluding: []).map(\.name)
                == ["Oslo Golfklubb", "Valdres Golfklubb", "Aarhus Golf Club"], "norske først, uten de uten hull")
        #expect(SlopeCourseSearch.playable(rows, query: "aurdal", excluding: []).map(\.id) == [V.id(80)])
        #expect(SlopeCourseSearch.playable(rows, query: "", excluding: [V.id(82)]).count == 2)
        #expect(SlopeCourseSearch.pickerDetail(rows[0]) == "Ekte bane · Aurdal, Norge")
    }

    @Test func katalogenViserBareSpillbareNarHulleneBrukes() async throws {
        let rows = [SlopeCourseRow(id: V.id(90), name: "Valdres Golfklubb", country: "NO", hasHoles: true),
                    SlopeCourseRow(id: V.id(91), name: "A6 Golfklubb", country: "SE", hasHoles: false)]
        let off = SlopeCatalogModel(preview: rows, tees: [:])
        #expect(off.playable.isEmpty, "uten hull: ingen spilles direkte")
        let on = SlopeCatalogModel(preview: rows, tees: [:], items: [V.item], usesHoles: true)
        #expect(on.playable.map(\.id) == [V.id(90)])
        let item = try await on.item(for: SlopeCourseRow(id: V.course, name: "Valdres Golfklubb"))
        #expect(item.isFromSource)
        await #expect(throws: DataError.self) { try await on.item(for: rows[1]) }
    }

    @Test func forklaringeneSierHvaSomSkjer() {
        #expect(SlopeCourseSearch.footer(playing: false, usesHoles: false)
                == "Navn, tees, course rating og slope fylles inn. Par og indeks per hull står ikke her: de leser du av scorekortet.")
        #expect(SlopeCourseSearch.footer(playing: false, usesHoles: true).hasPrefix("Har banen hull"))
        #expect(SlopeCourseSearch.footer(playing: true, usesHoles: true).hasPrefix("Banene med par"))
        #expect(SlopeCourseSearch.playableNotice.contains("trenger ikke legges inn"))
    }
}
