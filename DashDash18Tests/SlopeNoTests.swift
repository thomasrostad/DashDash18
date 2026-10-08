import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 20: baner og tees fra slope.no (sql/029, `SlopeNoFeature`). Tallene for teene er hentet fra
// slope.no-eksporten 08.10.2026 (A6 Golfklubb, id 77: «Gul-Blå - Hvit» herre CR 73 slope 132 osv.).

private enum S {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0020-%012d", n))! }
    static let course = id(1)
    static let club = id(2)
    static let round = id(3)

    static func tee(_ n: Int, _ name: String, _ gender: TeeGender, cr: Double, slope: Int, par: Int? = 72,
                    sort: Int, missing: Bool = false, course: UUID = course) -> CourseTeeRow {
        CourseTeeRow(id: id(100 + n), courseID: course, name: name, gender: gender, courseRating: cr, slopeRating: slope,
                     par: par, sortOrder: sort, missingAt: missing ? Date(timeIntervalSince1970: 1_800_000_000) : nil)
    }

    /// Fire av teene på A6 Golfklubb, i blandet rekkefølge, og én som er borte fra kilden.
    static let a6Tees = [
        tee(5, "Gul-Blå - Gul", .women, cr: 77.4, slope: 134, sort: 5),
        tee(2, "Gul-Blå - Gul", .men, cr: 71.2, slope: 129, sort: 2),
        tee(1, "Gul-Blå - Hvit", .men, cr: 73, slope: 132, sort: 1),
        tee(4, "Gul-Blå - Rød", .men, cr: 66.3, slope: 119, sort: 4),
        tee(9, "Gammel", .men, cr: 70, slope: 120, sort: 0, missing: true),
    ]

    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func courseRow(cr: Double? = 72, slope: Int? = 113) -> CourseRow {
        CourseRow(id: course, clubID: club, name: "A6 Golfklubb", externalName: nil, courseRating: cr,
                  slopeRating: slope, inUse: true, confirmedBy: nil, confirmedAt: nil)
    }

    static var holes: [CourseHoleRecord] {
        par.indices.map { CourseHoleRecord(courseID: course, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil) }
    }

    static func item(tees: [CourseTeeRow] = a6Tees) -> CourseListItem {
        CourseListItem(course: courseRow(), holes: holes, storedKind: .course, tees: tees)
    }

    static func roundRow(teeID: UUID? = nil, cr: Double? = nil, slope: Int? = nil, startedAt: Date? = nil,
                         roundNo: Int = 1, id: UUID = round, courseID: UUID = course) -> RoundRow {
        var row = RoundRow(id: id, clubID: club, eventID: S.id(4), courseID: courseID, roundNo: roundNo, name: nil,
                           status: .active, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                           handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: true, ldHoleIndex: nil,
                           kpEnabled: true, kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                           parConfirmedAt: nil, startedAt: startedAt, lockedAt: nil)
        row.teeID = teeID
        row.courseRating = cr
        row.slopeRating = slope
        return row
    }
}

struct SlopeNoTeeChoiceTests {
    @Test func flaggetErPåNårSqlErKjørtOgSynkenHarGått() {
        #expect(SlopeNoFeature.isEnabled == true)
        #expect(SlopeNoCredit.text == SlopeNoCredit.text(usesHoles: SlopeNoFeature.usesHoles))
        #expect(SlopeNoCredit.text(usesHoles: false) == "Slope og course rating fra slope.no")
        #expect(SlopeNoCredit.url.absoluteString == "https://slope.no")
    }

    @Test func teeneVisesIKildensRekkefolgeUtenDeSomErBorte() {
        let shown = TeeChoice.visible(S.a6Tees)
        #expect(shown.map(\.sortOrder) == [1, 2, 4, 5])
        #expect(!shown.contains { $0.name == "Gammel" })
    }

    @Test func forslagetErForrigeTeeEllersForsteHerreTee() {
        #expect(TeeChoice.suggested(S.a6Tees, previous: nil)?.name == "Gul-Blå - Hvit")
        #expect(TeeChoice.suggested(S.a6Tees, previous: S.id(105))?.gender == .women)
        // En tee som er borte, eller fra en annen bane, er ikke et forslag.
        #expect(TeeChoice.suggested(S.a6Tees, previous: S.id(109))?.name == "Gul-Blå - Hvit")
        #expect(TeeChoice.suggested(S.a6Tees, previous: UUID())?.name == "Gul-Blå - Hvit")
        // Bare dametees: den første.
        let women = [S.tee(7, "Rød", .women, cr: 68, slope: 120, sort: 3), S.tee(8, "Blå", .women, cr: 70, slope: 125, sort: 2)]
        #expect(TeeChoice.suggested(women, previous: nil)?.name == "Blå")
        #expect(TeeChoice.suggested([], previous: nil) == nil)
    }

    @Test func forrigeTeeErFraRundenSomStartetSistPaBanen() {
        let t1 = S.id(101), t2 = S.id(102)
        let rounds = [
            S.roundRow(teeID: t1, startedAt: Date(timeIntervalSince1970: 100), id: S.id(10)),
            S.roundRow(teeID: t2, startedAt: Date(timeIntervalSince1970: 200), id: S.id(11)),
            S.roundRow(teeID: nil, startedAt: Date(timeIntervalSince1970: 300), id: S.id(12)),
            S.roundRow(teeID: S.id(150), startedAt: Date(timeIntervalSince1970: 400), id: S.id(13), courseID: S.id(99)),
        ]
        #expect(TeeChoice.previousTeeID(rounds: rounds, courseID: S.course) == t2)
        #expect(TeeChoice.previousTeeID(rounds: rounds, courseID: nil) == nil)
        // Kladder uten start: høyest rundenummer.
        let drafts = [S.roundRow(teeID: t2, roundNo: 1, id: S.id(20)), S.roundRow(teeID: t1, roundNo: 2, id: S.id(21))]
        #expect(TeeChoice.previousTeeID(rounds: drafts, courseID: S.course) == t1)
    }

    @Test func teensTallErstatterBanensOgUtenTeeErBanenUendret() throws {
        let item = S.item()
        let plain = item.coreCourse
        #expect(item.coreCourse(tee: nil) == plain)
        #expect(item.coreCourse(tee: UUID()) == plain)
        let women = item.coreCourse(tee: S.id(105))
        #expect(women.courseRating == 77.4)
        #expect(women.slopeRating == 134)
        #expect(women.holes == plain.holes)
        #expect(women.par == plain.par)
        #expect(TeeChoice.applying(nil, to: plain) == plain)
        #expect(TeeChoice.applying(S.a6Tees[0], to: nil) == nil)
    }

    /// Golfgutu-paritet: samme CR og slope via en tee gir nøyaktig samme spillehandicap som via banen.
    @Test func sammeTallViaTeeGirSammeHandicap() {
        let viaCourse = CourseListItem(course: S.courseRow(cr: 71.2, slope: 129), holes: S.holes, storedKind: .course)
        let viaTee = CourseListItem(course: S.courseRow(cr: nil, slope: nil), holes: S.holes, storedKind: .course,
                                    tees: S.a6Tees)
        let rules = Ruleset.golfgutu
        for index in [-2.4, 0, 8.7, 18, 36, 54] {
            let player = Player(id: "p", handicap: index)
            let a = Round(id: "r", gameType: "stableford", holeCount: 18, holeStart: 0, course: viaCourse.coreCourse,
                          hcpAllowance: 1)
            let b = Round(id: "r", gameType: "stableford", holeCount: 18, holeStart: 0,
                          course: viaTee.coreCourse(tee: S.id(102)), hcpAllowance: 1)
            #expect(rules.effectiveHandicap(for: player, in: a, roster: [player])
                    == rules.effectiveHandicap(for: player, in: b, roster: [player]))
        }
    }

    @Test func verdienITeeRaden() {
        #expect(TeeChoice.value(nil) == "Banens tall")
        #expect(TeeChoice.value(S.a6Tees[1]) == "Gul-Blå - Gul (herre)")
        #expect(TeeChoice.detail(S.a6Tees[0]) == "dame · CR 77,4 · slope 134 · par 72")
        #expect(TeeChoice.detail(S.tee(1, "X", .men, cr: 73, slope: 132, par: nil, sort: 1)) == "herre · CR 73 · slope 132")
    }
}

struct SlopeNoSearchTests {
    static let courses = [
        SlopeCourseRow(id: S.id(201), name: "A6 Golfklubb", city: "Jönköping", country: "SE"),
        SlopeCourseRow(id: S.id(202), name: "Ålesund Golfklubb", city: "Sula", country: "NO"),
        SlopeCourseRow(id: S.id(203), name: "Aas Gaard Golfpark", city: "Tjøme", country: "NO"),
        SlopeCourseRow(id: S.id(204), name: "Oslo Golfklubb", city: "Oslo", country: "NO"),
        SlopeCourseRow(id: S.id(205), name: "Royal Copenhagen Golf Club", city: "Klampenborg", country: "DK"),
        SlopeCourseRow(id: S.id(206), name: "Golfklubben Oslo", city: nil, country: nil),
    ]

    @Test func norskeBanerForstSaNorskAlfabetisk() {
        let sorted = SlopeCourseSearch.filter(Self.courses, query: "")
        // Norsk rekkefølge: «Aa» er «Å» og kommer sist, etter «Ål».
        #expect(sorted.map(\.name) == ["Oslo Golfklubb", "Ålesund Golfklubb", "Aas Gaard Golfpark",
                                       "A6 Golfklubb", "Golfklubben Oslo", "Royal Copenhagen Golf Club"])
    }

    @Test func sokPaNavnStedOgLand() {
        #expect(SlopeCourseSearch.filter(Self.courses, query: "oslo").map(\.name) == ["Oslo Golfklubb", "Golfklubben Oslo"])
        #expect(SlopeCourseSearch.filter(Self.courses, query: "jönköping").map(\.name) == ["A6 Golfklubb"])
        #expect(SlopeCourseSearch.filter(Self.courses, query: "sverige").map(\.name) == ["A6 Golfklubb"])
        #expect(SlopeCourseSearch.filter(Self.courses, query: "danmark golf").map(\.name) == ["Royal Copenhagen Golf Club"])
        #expect(SlopeCourseSearch.filter(Self.courses, query: "  SULA  ").map(\.name) == ["Ålesund Golfklubb"])
        #expect(SlopeCourseSearch.filter(Self.courses, query: "tromsø").isEmpty)
    }

    @Test func stedetPaNorsk() {
        #expect(SlopeCourseSearch.place(Self.courses[1]) == "Sula, Norge")
        #expect(SlopeCourseSearch.place(Self.courses[5]) == "")
        #expect(SlopeCourseSearch.countryName("IS") == "Island")
        #expect(SlopeCourseSearch.countryName("XX") == "XX")
    }
}

struct SlopeNoCourseDraftTests {
    @Test func slopeBaneFyllerNavnTeesOgRatingMenIkkeHullene() throws {
        var draft = CourseDraft()
        draft.prefill(from: SlopeNoSearchTests.courses[0], tees: S.a6Tees)
        #expect(draft.name == "A6 Golfklubb")
        #expect(draft.kind == .course)
        #expect(draft.courseRatingText == "73")
        #expect(draft.slopeText == "132")
        #expect(draft.tees?.map(\.name) == ["Gul-Blå - Hvit", "Gul-Blå - Gul", "Gul-Blå - Rød", "Gul-Blå - Gul"])
        #expect(draft.holeCount == 18)
        #expect(draft.holes.allSatisfy { $0.par == nil })
        // Par og indeks mangler fortsatt: banen lagres som ikke satt opp, med teene.
        let values = try #require(draft.validate().values)
        #expect(values.tees?.count == 4)
        #expect(values.holes.isEmpty)
    }

    @Test func niHullsbaneOgRatingUtenforSkjemaetsGrenser() {
        var draft = CourseDraft()
        draft.courseRatingText = "70"
        let nine = [S.tee(1, "Gul", .men, cr: 33.1, slope: 118, par: 33, sort: 1)]
        draft.prefill(from: SlopeNoSearchTests.courses[2], tees: nine)
        #expect(draft.holeCount == 9)
        // CR 33,1 er en 9-hullsrating; skjemaet godtar 50–90, så feltet står tomt (teen har tallet).
        #expect(draft.courseRatingText.isEmpty)
        #expect(draft.slopeText.isEmpty)
        #expect(draft.tees?.first?.courseRating == 33.1)
    }

    @Test func lagretBaneMedTeesGirTeeneISkjemaet() {
        let draft = CourseDraft(course: S.courseRow(), holes: S.holes, kind: .course, tees: S.a6Tees)
        #expect(draft.tees?.count == 4)
        #expect(CourseDraft(course: S.courseRow(), holes: S.holes, kind: .course).tees == nil)
    }

    @Test func teeneSendesMedNavnSomDatabasenVil() throws {
        let tee = TeeInput(name: "Hvit", gender: .men, courseRating: 73, slopeRating: 132, par: nil, sortOrder: 1)
        let json = try #require(String(data: JSONEncoder().encode(tee), encoding: .utf8))
        for key in ["\"name\":\"Hvit\"", "\"gender\":\"men\"", "\"course_rating\":73", "\"slope_rating\":132",
                    "\"par\":null", "\"sort_order\":1"] {
            #expect(json.contains(key), "\(key) mangler i \(json)")
        }
    }

    @Test func listaViserAntallTees() {
        #expect(S.item().summary.contains("4 tees"))
        #expect(!S.item(tees: []).summary.contains("tee"))
    }
}

struct SlopeNoRoundTests {
    @Test func nyBaneTomTeen() {
        var draft = RoundDraft.new(eventID: S.id(4), roundNo: 1, teeTime: nil, participants: [], source: .signups,
                                   rules: .golfgutu)
        draft.courseID = S.course
        draft.teeID = S.id(101)
        QuickStart.setCourse(S.course, on: &draft, courseHoles: 18)
        #expect(draft.teeID == S.id(101), "samme bane: teen står")
        QuickStart.setCourse(S.id(99), on: &draft, courseHoles: 18)
        #expect(draft.teeID == nil)

        var loose = LooseRoundDraft.new()
        loose.setCourse(S.course, courseHoles: 18)
        loose.teeID = S.id(101)
        loose.setCourse(S.id(99), courseHoles: 18)
        #expect(loose.teeID == nil)
    }

    @Test func forslagetFraForrigeRundeTarMedTeenNarDenFinnes() {
        var draft = RoundDraft.new(eventID: S.id(4), roundNo: 2, teeTime: nil, participants: [], source: .signups,
                                   rules: .golfgutu)
        QuickStart.applySuggestion(from: S.roundRow(teeID: S.id(105)), to: &draft, courses: [S.item()], rules: .golfgutu)
        #expect(draft.teeID == S.id(105))
        QuickStart.applySuggestion(from: S.roundRow(teeID: S.id(109)), to: &draft, courses: [S.item()], rules: .golfgutu)
        #expect(draft.teeID == nil, "teen er borte fra kilden")
    }

    @Test func lagretKladdHarTeen() {
        let draft = RoundDraft.saved(S.roundRow(teeID: S.id(102)), players: [], matches: [], participants: [],
                                     source: .signups)
        #expect(draft.teeID == S.id(102))
    }

    @Test func rundeRadenSenderTeenBareMedFlagget() throws {
        var draft = RoundDraft.new(eventID: S.id(4), roundNo: 1, teeTime: nil, participants: [], source: .signups,
                                   rules: .golfgutu)
        draft.courseID = S.course
        draft.teeID = S.id(102)
        func json(_ write: RoundWrite) throws -> String {
            try #require(String(data: JSONEncoder().encode(write), encoding: .utf8))
        }
        #expect(try !json(RoundWrite(draft: draft, clubID: S.club, course: nil, includeTee: false)).contains("tee_id"))
        #expect(try json(RoundWrite(draft: draft, clubID: S.club, course: nil, includeTee: true))
            .contains("\"tee_id\":\"\(S.id(102).uuidString)\""))
        draft.teeID = nil
        #expect(try json(RoundWrite(draft: draft, clubID: S.club, course: nil, includeTee: true)).contains("\"tee_id\":null"))
    }

    /// Med flagget på (08.10.2026) sendes teen. Den må høre til banen; en ukjent tee sendes ikke.
    @Test func losRundeSenderTeenSomHorerTilBanen() throws {
        var draft = LooseRoundDraft.new()
        let course = CourseListItem(course: CourseRow(id: S.course, clubID: nil, name: "A6", externalName: nil,
                                                      courseRating: nil, slopeRating: nil, inUse: true,
                                                      confirmedBy: nil, confirmedAt: nil),
                                    holes: S.holes, storedKind: .course, tees: S.a6Tees)
        draft.setCourse(course.id, courseHoles: 18)
        draft.teeID = S.id(101)
        let start = try #require(LooseRoundStart.make(draft, course: course, names: ["Meg"]))
        #expect(start.teeID == (SlopeNoFeature.isEnabled ? course.tee(S.id(101))?.id : nil))
        let json = try #require(String(data: JSONEncoder().encode(start), encoding: .utf8))
        #expect(json.contains("tee_id") == (start.teeID != nil))
        draft.teeID = UUID()
        let unknown = try #require(LooseRoundStart.make(draft, course: course, names: ["Meg"]))
        #expect(unknown.teeID == nil)
    }

    @Test func rundenRegnerMedTallaneFraStart() {
        let row = S.courseRow(cr: 72, slope: 113)
        let plain = RoundGame.makeCourse(row, holes: S.holes, round: S.roundRow())
        #expect(plain?.courseRating == 72)
        #expect(plain?.slopeRating == 113)
        let teed = RoundGame.makeCourse(row, holes: S.holes, round: S.roundRow(teeID: S.id(101), cr: 73, slope: 132))
        #expect(teed?.courseRating == 73)
        #expect(teed?.slopeRating == 132)
        #expect(teed?.holes == plain?.holes)
    }

    @Test func statistikkenRegnerMedRundensTall() {
        var input = StatsInput()
        input.courses = [StatsCourseRow(id: S.course, name: "A6", courseRating: 72, slopeRating: 113)]
        input.courseHoles = S.holes
        var round = StatsRoundRow(id: S.round, clubID: S.club, eventID: nil, courseID: S.course, name: nil, status: .locked,
                                  holeCount: 18, firstHole: 1, format: "stableford", handicapAllowance: 1,
                                  externalHandicap: false, startedAt: nil)
        #expect(input.makeCourse(S.course, round: round)?.courseRating == 72)
        round.courseRating = 73
        round.slopeRating = 132
        #expect(input.makeCourse(S.course, round: round)?.courseRating == 73)
        #expect(input.makeCourse(S.course, round: round)?.slopeRating == 132)
    }

    @Test func rundeRadenLeserTeeKolonnene() throws {
        let json = """
        {"id":"\(S.round.uuidString)","club_id":null,"event_id":null,"course_id":"\(S.course.uuidString)",
         "round_no":1,"name":null,"status":"active","hole_count":18,"first_hole":1,"tee_time":null,
         "format":"stableford","handicap_allowance":1,"external_handicap":false,"weight":1,"ld_enabled":true,
         "ld_hole_index":null,"kp_enabled":true,"kp_hole_index":null,"cut_rule":null,"cut_after":null,
         "par_confirmed_by":null,"par_confirmed_at":null,"started_at":null,"locked_at":null,
         "tee_id":"\(S.id(101).uuidString)","tee_name":"Gul-Blå - Hvit","course_rating":73.0,"slope_rating":132}
        """
        let row = try JSONDecoder().decode(RoundRow.self, from: Data(json.utf8))
        #expect(row.teeID == S.id(101))
        #expect(row.teeName == "Gul-Blå - Hvit")
        #expect(row.courseRating == 73)
        #expect(row.slopeRating == 132)
        #expect(RoundRow.columns.contains("tee_id") == SlopeNoFeature.isEnabled, "kolonnene hentes bare med flagget")
        #expect(RoundRow.teeColumns == "tee_id, tee_name, course_rating, slope_rating")
    }
}
