import Foundation
import GolfgutuCore

/// Én bane i banelista, med hullene og det som regnes fra dem.
nonisolated struct CourseListItem: Equatable, Identifiable, Sendable {
    var course: CourseRow
    /// Sortert på hullnummer.
    var holes: [CourseHoleRecord]
    /// `courses.kind` når den leses (sql/016, `CourseKindFeature`), ellers nil.
    var storedKind: CourseKind?

    init(course: CourseRow, holes: [CourseHoleRecord], storedKind: CourseKind? = nil) {
        self.course = course
        self.holes = holes.sorted { $0.holeNumber < $1.holeNumber }
        self.storedKind = storedKind
    }

    /// Simulatorbane eller ekte bane.
    var kind: CourseKind { CourseKind.resolve(stored: storedKind) }

    /// «Klar» eller hva som mangler.
    var readiness: CourseReadiness {
        isReady ? .ready : CourseReadiness(pars: coreCourse.holes?.map(\.par) ?? [])
    }

    var id: UUID { course.id }

    /// GolfgutuCore-banen. Hullene tas med bare når de er 9 eller 18 sammenhengende fra 1
    /// (`banehullFraRader`), ellers er banen ikke satt opp.
    var coreCourse: Course {
        let rows = holes.map {
            CourseHoleRow(courseId: course.id.uuidString, holeNumber: $0.holeNumber, par: $0.par,
                          hcpIndex: $0.strokeIndex, distanceMeters: $0.lengthM.map(Double.init))
        }
        let coreHoles = Course.holesFromRows(rows)[course.id.uuidString] ?? nil
        return Course(
            id: course.id.uuidString,
            name: course.name,
            par: coreHoles.flatMap { CourseMath.par($0.map(\.par)) },
            courseRating: course.courseRating,
            slopeRating: course.slopeRating.map(Double.init),
            holes: coreHoles
        )
    }

    /// `baneErKlar`.
    var isReady: Bool { coreCourse.isReady }

    /// Banens par regnet fra hullene, når banen er satt opp.
    var par: Int? { isReady ? coreCourse.par : nil }

    var holeCount: Int { holes.count }

    var hasStrokeIndex: Bool { coreCourse.hasStrokeIndex }

    var isConfirmed: Bool { course.confirmedAt != nil }

    /// «18 hull · par 72 · CR 72 · slope 113», eller hva som mangler.
    var summary: String {
        guard isReady, let par else { return "Ikke satt opp. Skriv inn parene fra skjermen." }
        var parts = ["\(holeCount) hull", "par \(par)"]
        if let rating = course.courseRating { parts.append("CR \(CourseInput.decimalText(rating))") }
        if let slope = course.slopeRating { parts.append("slope \(slope)") }
        parts.append(hasStrokeIndex ? "med indeks" : "uten indeks")
        return parts.joined(separator: " · ")
    }

    /// Navnet i simulatoren når det er et annet enn vårt (PWA-ens `trackmanLinje`).
    var differentExternalName: String? {
        guard let external = course.externalName, !external.isEmpty,
              GolfgutuCourseSet.nameKey(external) != GolfgutuCourseSet.nameKey(course.name) else { return nil }
        return external
    }

    /// Banelista: i bruk først, så norsk alfabetisk (Æ, Ø, Å sist).
    static func sorted(_ items: [CourseListItem]) -> [CourseListItem] {
        items.sorted { a, b in
            if a.course.inUse != b.course.inUse { return a.course.inUse }
            return NorwegianSort.areInIncreasingOrder(a.course.name, b.course.name)
        }
    }

    /// Setter sammen baner og hull fra to spørringer (og typene, når de leses).
    static func make(courses: [CourseRow], holes: [CourseHoleRecord],
                     kinds: [UUID: CourseKind] = [:]) -> [CourseListItem] {
        let grouped = Dictionary(grouping: holes, by: \.courseID)
        return sorted(courses.map { CourseListItem(course: $0, holes: grouped[$0.id] ?? [], storedKind: kinds[$0.id]) })
    }

    /// Banelista delt i simulatorbaner og ekte baner, i den rekkefølgen. Tomme grupper utelates.
    static func grouped(_ items: [CourseListItem]) -> [(kind: CourseKind, items: [CourseListItem])] {
        CourseKind.allCases.compactMap { kind in
            let rows = items.filter { $0.kind == kind }
            return rows.isEmpty ? nil : (kind, rows)
        }
    }
}
