#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Banelista og «Ny bane» med oppdiktede baner, uten nett (`-DDDesignScreen baner` og `nybane`).
enum BanerSamples {
    static let club = UUID()

    static func item(_ name: String, external: String? = nil, pars: [Int], confirmed: Bool = false,
                     inUse: Bool = true) -> CourseListItem {
        let id = UUID()
        let course = CourseRow(id: id, clubID: club, name: name, externalName: external, courseRating: nil,
                               slopeRating: nil, inUse: inUse, confirmedBy: nil,
                               confirmedAt: confirmed ? Date.now.addingTimeInterval(-3 * 86_400) : nil)
        let holes = pars.enumerated().map { i, par in
            CourseHoleRecord(courseID: id, holeNumber: i + 1, par: par, strokeIndex: nil, lengthM: nil)
        }
        return CourseListItem(course: course, holes: holes)
    }

    static var items: [CourseListItem] {
        [
            item("Adare Manor", pars: Course.defaultPar, confirmed: true),
            item("Pebble Beach Golf Links", external: "Pebble Beach Links", pars: Course.defaultPar),
            item("Lofoten Links", pars: []),
            item("Miklagard Golf", pars: Array(Course.defaultPar.prefix(9)), inUse: false),
        ]
    }

    static var model: CourseLibraryModel { CourseLibraryModel(preview: items) }
}

struct BanerSampleScreen: View {
    let newCourse: Bool
    @State private var model = BanerSamples.model

    var body: some View {
        NavigationStack {
            if newCourse {
                CourseEditView(model: model, item: nil)
            } else {
                CourseListView(model: model, isOrganizer: true)
                    .navigationTitle("Banene")
                    .ddNavigationChrome()
            }
        }
    }
}
#endif
