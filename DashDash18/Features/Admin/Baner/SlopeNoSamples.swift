#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Baner, tees og hull fra slope.no uten nett (`-DDDesignScreen slopesok`, `slopebane`, `teevalg`,
/// `losnytee`, `hurtigstarttee`, og fra fase 20b `slopevelg` og `slopeklubb`). Navn, steder, tees og hull
/// er ekte, fra slope.no-eksporten 08.10.2026. Skjermprøvene viser hullene (fase 20b) selv om
/// `SlopeNoFeature.usesHoles` står av.
enum SlopeNoSamples {
    static let losbyID = UUID()
    static let helsinkiID = UUID()

    /// Har banen hull hos slope.no? Som i eksporten: Finland, A6 og Royal Copenhagen har ingen.
    static let courses: [SlopeCourseRow] = [
        ("A6 Golfklubb", "Jönköping", "SE", false),
        ("Bærum Golfklubb", "Lommedalen", "NO", true),
        ("Golfklúbbur Reykjavíkur – Grafarholt", "Reykjavík", "IS", true),
        ("Helsingin Golfklubi", "Helsinki", "FI", false),
        ("Losby Golfklubb - Østmork 18-hull", "Lørenskog", "NO", true),
        ("Losby Golfklubb - Vestmork 9-hull", "Lørenskog", "NO", true),
        ("Miklagard Golfklubb Ullensaker", "Kløfta", "NO", true),
        ("Oslo Golfklubb", "Oslo", "NO", true),
        ("Royal Copenhagen Golf Club", "Klampenborg", "DK", false),
        ("Stavanger Golfklubb", "Stavanger", "NO", true),
        ("Trondheim Golfklubb", "Trondheim", "NO", true),
        ("Ålesund Golfklubb", "Skodje", "NO", true),
    ].map { name, city, country, holes in
        let id = name.hasPrefix("Losby Golfklubb - Østmork") ? losbyID : name.hasPrefix("Helsingin") ? helsinkiID : UUID()
        return SlopeCourseRow(id: id, name: name, city: city, country: country, hasHoles: holes)
    }

    /// Par og indeks på Losby Østmork (like på alle tees; banen spilles som 2 × 9 i 2026).
    static let losbyPars = [5, 5, 3, 4, 4, 3, 4, 3, 5, 5, 5, 3, 4, 4, 3, 4, 3, 5]
    static let losbyIndex = [3, 7, 17, 9, 1, 11, 13, 15, 5, 4, 8, 18, 10, 2, 12, 14, 16, 6]
    /// Lengdene per tee (navnet er meter fra tee på hull 1, i hundretall).
    static let losbyLengths: [String: [Int]] = [
        "64": [478, 483, 110, 378, 403, 175, 390, 162, 510],
        "59": [454, 452, 110, 352, 383, 152, 319, 139, 465],
        "54": [421, 422, 110, 352, 311, 136, 319, 124, 445],
        "48": [367, 395, 110, 315, 311, 121, 260, 101, 380],
        "35": [220, 315, 110, 208, 245, 121, 220, 101, 304],
    ]

    /// Teene på Losby Østmork (navn = meter fra tee, herre og dame). Med `holes` har de hullene fra
    /// slope.no (fase 20b).
    static func losbyTees(course: UUID = losbyID, holes: Bool = false) -> [CourseTeeRow] {
        let rows: [(String, TeeGender, Double, Int)] = [
            ("64", .men, 75.6, 146), ("59", .men, 73, 141), ("54", .men, 71.2, 138), ("48", .men, 68.2, 132),
            ("35", .men, 59, 112), ("64", .women, 81.6, 155), ("59", .women, 78.4, 152), ("54", .women, 76.2, 147),
            ("48", .women, 72.8, 139), ("35", .women, 62.6, 112),
        ]
        return rows.enumerated().map { i, t in
            let lengths = (losbyLengths[t.0] ?? []) + (losbyLengths[t.0] ?? [])
            return CourseTeeRow(courseID: course, name: t.0, gender: t.1, courseRating: t.2, slopeRating: t.3, par: 72,
                                sortOrder: i + 1,
                                holes: holes ? losbyPars.indices.map {
                                    CourseHoleRecord(courseID: course, holeNumber: $0 + 1, par: losbyPars[$0],
                                                     strokeIndex: losbyIndex[$0], lengthM: lengths[$0])
                                } : [])
        }
    }

    /// Teene på Helsingin Golfklubi (ingen hull hos slope.no: kopi og scorekort).
    static func helsinkiTees(course: UUID = helsinkiID) -> [CourseTeeRow] {
        let rows: [(String, TeeGender, Double, Int)] = [
            ("Gul", .men, 69.5, 127), ("Blå", .men, 68, 124), ("Rød", .men, 66.1, 121),
            ("Gul", .women, 75.9, 132), ("Blå", .women, 74, 128), ("Rød", .women, 71.8, 123),
        ]
        return rows.enumerated().map { i, t in
            CourseTeeRow(courseID: course, name: t.0, gender: t.1, courseRating: t.2, slopeRating: t.3, par: 71,
                         sortOrder: i + 1)
        }
    }

    /// Losby Østmork slik den spilles direkte (fase 20b): hentet bane med banens hull (fra 64 herre) og
    /// teene med egne hull.
    static func losbySourceItem(id: UUID = losbyID) -> CourseListItem {
        let row = CourseRow(id: id, clubID: nil, name: "Losby Golfklubb - Østmork 18-hull", externalName: nil,
                            courseRating: 75.6, slopeRating: 146, inUse: true, confirmedBy: nil, confirmedAt: nil)
        let tees = losbyTees(course: id, holes: true)
        return CourseListItem(course: row, holes: tees[0].holes, storedKind: .course, tees: tees, isFromSource: true)
    }

    /// Søket med hullene i bruk (fase 20b).
    static var catalog: SlopeCatalogModel {
        SlopeCatalogModel(preview: courses, tees: [losbyID: losbyTees(holes: true), helsinkiID: helsinkiTees()],
                          items: [losbySourceItem()], usesHoles: true)
    }

    /// «Ny bane» etter at Helsingin Golfklubi (uten hull) er hentet fra slope.no: navn, tees og rating,
    /// hullene tomme.
    static var prefilledDraft: CourseDraft {
        var draft = CourseDraft()
        draft.prefill(from: courses.first { $0.id == helsinkiID }!, tees: helsinkiTees())
        return draft
    }

    /// Losby Østmork hentet fra slope.no, valgt i en løs runde, med tee 54 herre.
    static var nyRunde: NyRundeModel {
        let course = losbySourceItem()
        var draft = LooseRoundDraft.new()
        draft.courseID = course.id
        draft.teeID = course.tees.first { $0.name == "54" && $0.gender == .men }?.id
        draft.friends = [SpillSamples.friends[0].id]
        draft.guests = [.init(name: "Per", handicapText: "18,4")]
        let library = CourseLibraryModel(previewShared: [course], client: SpillSamples.client, userID: SpillSamples.me)
        return NyRundeModel(preview: library, friends: SpillSamples.friends, me: SpillSamples.profile, draft: draft)
    }

    /// Bane-velgeren i løse runder med «Fra slope.no».
    static var pickerLibrary: CourseLibraryModel {
        CourseLibraryModel(previewShared: SpillSamples.courses, client: SpillSamples.client, userID: SpillSamples.me,
                           slopeCatalog: catalog)
    }
}

struct SlopeNoSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    private static let tees = SlopeNoSamples.losbyTees(holes: true)
    @State private var selectedTee: UUID? = Self.tees[2].id
    @State private var clubDraft: RoundDraft?

    var body: some View {
        NavigationStack {
            switch screen {
            case .slopesok:
                SlopeCourseSearchView(model: SlopeNoSamples.catalog, onPick: { _, _ in })
            case .slopebane:
                CourseEditView(model: CourseLibraryModel(preview: [], slopeCatalog: SlopeNoSamples.catalog), item: nil,
                               initialDraft: SlopeNoSamples.prefilledDraft)
            case .teevalg:
                TeePickerView(tees: Self.tees, selected: $selectedTee)
            case .hurtigstarttee:
                let (model, draft) = SlopeNoSamples.clubSetup()
                RundeQuickStartView(model: model, draft: draft, onDone: { _ in })
            case .slopevelg:
                CoursePickerView(model: SlopeNoSamples.pickerLibrary, selected: nil) { _ in }
            case .slopeklubb:
                SlopeClubCourseSample()
            default:
                NyRundeView(model: SlopeNoSamples.nyRunde) { _ in }
            }
        }
        .tint(Color.ddForestInk)
    }
}

extension SlopeNoSamples {
    /// Klubbens runde-oppsett med Losby Østmork valgt fra slope.no og tee 54 herre (fase 20b).
    static func clubSetup() -> (RundeAdminModel, RoundDraft) {
        let model = RundeAdminModel.sample(withTees: true, slopeCatalog: catalog)
        let item = losbySourceItem()
        model.adopt(item)
        var draft = model.newDraft()!
        RoundConfirm.selectCourse(item, on: &draft, rules: model.rules)
        draft.teeID = item.tees.first { $0.name == "54" && $0.gender == .men }?.id
        return (model, draft)
    }
}

/// Bane-valget i klubbens runde-oppsett med «Fra slope.no» (`slopeklubb`).
private struct SlopeClubCourseSample: View {
    @State private var model: RundeAdminModel
    @State private var draft: RoundDraft

    init() {
        let (model, draft) = SlopeNoSamples.clubSetup()
        _model = State(initialValue: model)
        _draft = State(initialValue: draft)
    }

    var body: some View {
        RundeCourseStep(model: model, draft: $draft, showsVenue: false)
            .navigationTitle("Bane")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
