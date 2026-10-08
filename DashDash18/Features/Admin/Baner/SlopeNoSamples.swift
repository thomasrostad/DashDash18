#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Baner og tees fra slope.no uten nett (`-DDDesignScreen slopesok`, `slopebane`, `teevalg`, `losnytee`,
/// `hurtigstarttee`). Navn, steder og tees er ekte, fra slope.no-eksporten 08.10.2026.
enum SlopeNoSamples {
    static let losbyID = UUID()

    static let courses: [SlopeCourseRow] = [
        ("A6 Golfklubb", "Jönköping", "SE"),
        ("Bærum Golfklubb", "Lommedalen", "NO"),
        ("Golfklúbbur Reykjavíkur – Grafarholt", "Reykjavík", "IS"),
        ("Helsingin Golfklubi", "Helsinki", "FI"),
        ("Losby Golfklubb - Østmork 18-hull", "Lørenskog", "NO"),
        ("Losby Golfklubb - Vestmork 9-hull", "Lørenskog", "NO"),
        ("Miklagard Golfklubb Ullensaker", "Kløfta", "NO"),
        ("Oslo Golfklubb", "Oslo", "NO"),
        ("Royal Copenhagen Golf Club", "Klampenborg", "DK"),
        ("Stavanger Golfklubb", "Stavanger", "NO"),
        ("Trondheim Golfklubb", "Trondheim", "NO"),
        ("Ålesund Golfklubb", "Skodje", "NO"),
    ].map { name, city, country in
        SlopeCourseRow(id: name.hasPrefix("Losby Golfklubb - Østmork") ? losbyID : UUID(), name: name, city: city,
                       country: country)
    }

    /// Teene på Losby Østmork (navn = meter fra tee, herre og dame).
    static func losbyTees(course: UUID = losbyID) -> [CourseTeeRow] {
        let rows: [(String, TeeGender, Double, Int)] = [
            ("64", .men, 75.6, 146), ("59", .men, 73, 141), ("54", .men, 71.2, 138), ("48", .men, 68.2, 132),
            ("35", .men, 59, 112), ("64", .women, 81.6, 155), ("59", .women, 78.4, 152), ("54", .women, 76.2, 147),
            ("48", .women, 72.8, 139), ("35", .women, 62.6, 112),
        ]
        return rows.enumerated().map { i, t in
            CourseTeeRow(courseID: course, name: t.0, gender: t.1, courseRating: t.2, slopeRating: t.3, par: 72,
                         sortOrder: i + 1)
        }
    }

    static var catalog: SlopeCatalogModel {
        SlopeCatalogModel(preview: courses, tees: [losbyID: losbyTees()])
    }

    /// «Ny bane» etter at Losby Østmork er hentet fra slope.no: navn, tees og rating, hullene tomme.
    static var prefilledDraft: CourseDraft {
        var draft = CourseDraft()
        draft.prefill(from: courses.first { $0.id == losbyID }!, tees: losbyTees())
        return draft
    }

    /// Losby Østmork i det felles biblioteket, med hull og tees.
    static var losbyItem: CourseListItem {
        let base = SpillSamples.course("Losby Golfklubb - Østmork", kind: .course, pars: Course.defaultPar,
                                       createdBy: SpillSamples.me)
        return CourseListItem(course: base.course, holes: base.holes, storedKind: .course,
                              tees: losbyTees(course: base.id))
    }

    static var nyRunde: NyRundeModel {
        let course = losbyItem
        var draft = LooseRoundDraft.new()
        draft.courseID = course.id
        draft.teeID = TeeChoice.suggested(course.tees, previous: nil)?.id
        draft.friends = [SpillSamples.friends[0].id]
        draft.guests = [.init(name: "Per", handicapText: "18,4")]
        let library = CourseLibraryModel(previewShared: [course], client: SpillSamples.client, userID: SpillSamples.me)
        return NyRundeModel(preview: library, friends: SpillSamples.friends, me: SpillSamples.profile, draft: draft)
    }
}

struct SlopeNoSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    @State private var selectedTee: UUID? = SlopeNoSamples.losbyTees()[2].id
    private let tees = SlopeNoSamples.losbyTees()

    var body: some View {
        NavigationStack {
            switch screen {
            case .slopesok:
                SlopeCourseSearchView(model: SlopeNoSamples.catalog, onPick: { _, _ in })
            case .slopebane:
                CourseEditView(model: CourseLibraryModel(preview: [], slopeCatalog: SlopeNoSamples.catalog), item: nil,
                               initialDraft: SlopeNoSamples.prefilledDraft)
            case .teevalg:
                TeePickerView(tees: tees, selected: $selectedTee)
            case .hurtigstarttee:
                let model = RundeAdminModel.sample(withTees: true)
                RundeQuickStartView(model: model, draft: model.newDraft()!, onDone: { _ in })
            default:
                NyRundeView(model: SlopeNoSamples.nyRunde) { _ in }
            }
        }
        .tint(Color.ddForestInk)
    }
}
#endif
