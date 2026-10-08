import Foundation
import GolfgutuCore

// Hull per tee fra slope.no (fase 20b, sql/030_slope_hull.sql, bak `SlopeNoFeature.usesHoles`).
//
// slope.no har par, indeks og lengde per hull på rundt to av tre tees. Par og indeks kan variere mellom
// tees på samme bane (Valdres GK: par 73, 72 og 66), og lengden varierer alltid. Synken lagrer hullene per
// tee (`course_tee_holes`) og banens hull (`course_holes`) fra første herre-tee med hull. Med valgt tee
// gjelder teens hull når den har et helt sett, ellers banens. Ved start fryser databasen hullene i
// `round_holes` og teens par i `rounds.tee_par` (bare hentede baner), så en ny indeks hos kilden ikke
// endrer gamle runder. Ren logikk her, uten nettverk og SwiftUI.

/// Ett hull på en tee (`course_tee_holes`, sql/030). Bare kilden (synken) skriver dem.
nonisolated struct TeeHoleRow: Codable, Equatable, Sendable {
    let teeID: UUID
    var holeNumber: Int
    var par: Int
    var strokeIndex: Int?
    var lengthM: Int?

    enum CodingKeys: String, CodingKey {
        case teeID = "tee_id"
        case holeNumber = "hole_number"
        case par
        case strokeIndex = "stroke_index"
        case lengthM = "length_m"
    }

    static let columns = "tee_id, hole_number, par, stroke_index, length_m"
}

/// Teens hull: hvilke som gjelder, par og lengde.
nonisolated enum TeeHoles {
    /// Fester hullradene på teene sine, som banens hullrader (med banens id), sortert på nummer.
    static func attach(_ rows: [TeeHoleRow], to tees: [CourseTeeRow]) -> [CourseTeeRow] {
        guard !rows.isEmpty else { return tees }
        let byTee = Dictionary(grouping: rows, by: \.teeID)
        return tees.map { tee in
            var tee = tee
            tee.holes = (byTee[tee.id] ?? [])
                .map { CourseHoleRecord(courseID: tee.courseID, holeNumber: $0.holeNumber, par: $0.par,
                                        strokeIndex: $0.strokeIndex, lengthM: $0.lengthM) }
                .sorted { $0.holeNumber < $1.holeNumber }
            return tee
        }
    }

    /// Er hullene et helt sett: 9 eller 18 sammenhengende fra 1, med gyldig par på hvert
    /// (`banehullFraRader` og `baneErKlar`)?
    static func isComplete(_ holes: [CourseHoleRecord]) -> Bool {
        guard let first = holes.first else { return false }
        let id = first.courseID.uuidString
        let rows = holes.map {
            CourseHoleRow(courseId: id, holeNumber: $0.holeNumber, par: $0.par, hcpIndex: $0.strokeIndex,
                          distanceMeters: $0.lengthM.map(Double.init))
        }
        guard let played = Course.holesFromRows(rows)[id] ?? nil else { return false }
        return played.allSatisfy { Course.isValidPar($0.par) }
    }

    /// Har teen et helt sett egne hull?
    static func hasOwnHoles(_ tee: CourseTeeRow?) -> Bool {
        guard let tee else { return false }
        return isComplete(tee.holes)
    }

    /// Hullene runden spilles med: teens når teen har et helt sett egne, ellers banens. Uten tee, eller
    /// med en tee uten hull (simulatorbaner, egne baner, alt før sql/030), er svaret banens hull uendret.
    static func effective(course: [CourseHoleRecord], tee: CourseTeeRow?) -> [CourseHoleRecord] {
        guard let tee, hasOwnHoles(tee) else { return course }
        return tee.holes
    }

    /// Teens par regnet av hullene, når den har et helt sett.
    static func par(of tee: CourseTeeRow?) -> Int? {
        guard let tee, hasOwnHoles(tee) else { return nil }
        return tee.holes.reduce(0) { $0 + $1.par }
    }

    /// Banens par for banehandicapet i en runde: teens par slik den ble frosset ved start
    /// (`rounds.tee_par`, satt bare når teen har egne hull), ellers summen av banens hull som før.
    static func coursePar(holesPar: Int?, teePar: Int?) -> Int? {
        teePar ?? holesPar
    }

    /// Summen av lengdene, når alle hullene har lengde.
    static func totalLength(_ holes: [CourseHoleRecord]) -> Int? {
        guard !holes.isEmpty else { return nil }
        let lengths = holes.compactMap(\.lengthM)
        guard lengths.count == holes.count else { return nil }
        return lengths.reduce(0, +)
    }

    /// «6 040 m».
    static func lengthText(_ meters: Int) -> String {
        "\(meters.formatted(.number.locale(Locale(identifier: "nb_NO")))) m"
    }
}
