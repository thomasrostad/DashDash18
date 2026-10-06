import Foundation

/// En rad fra `course_holes`.
public struct CourseHoleRow: Codable, Hashable, Sendable {
    public var courseId: String?
    public var holeNumber: Int
    public var par: Int?
    public var hcpIndex: Int?
    public var distanceMeters: Double?

    public init(courseId: String?, holeNumber: Int, par: Int?, hcpIndex: Int? = nil, distanceMeters: Double? = nil) {
        self.courseId = courseId
        self.holeNumber = holeNumber
        self.par = par
        self.hcpIndex = hcpIndex
        self.distanceMeters = distanceMeters
    }
}

extension Course {
    /// `DEFAULT_PAR`: standardbanen, par 72 over 18 hull.
    public static let defaultPar: [Int] = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    /// `PAR_LENGDE`: rimelig lengde i meter per par (grensene er inkludert).
    public static let parLengthRange: [Int: ClosedRange<Double>] = [
        3: 90...210,
        4: 230...440,
        5: 420...580,
    ]

    /// `parErEtTall`: par mellom 3 og 6.
    public static func isValidPar(_ par: Int?) -> Bool {
        guard let par else { return false }
        return par >= 3 && par <= 6
    }

    /// `lengdePasserParet`: passer lengden til paret? Uten lengde eller ukjent par: `true`.
    public static func lengthMatchesPar(par: Int?, meters: Double?) -> Bool {
        guard let meters, let par, let range = parLengthRange[par] else { return true }
        return range.contains(meters)
    }

    /// Et hull der lengden ikke passer paret (`hullMedRarLengde`). `number` er 1-basert.
    public struct OddLengthHole: Hashable, Sendable {
        public var number: Int
        public var par: Int?
        public var meters: Double?
    }

    /// `hullMedRarLengde` for banens hull.
    public static func holesWithOddLength(_ holes: [CourseHole]) -> [OddLengthHole] {
        oddLength(holes.map { ($0.par, $0.meters) })
    }

    /// `hullMedRarLengde` for hullene i en runde (`courseForRound`).
    public static func holesWithOddLength(_ holes: [PlayedHole]) -> [OddLengthHole] {
        oddLength(holes.map { ($0.par, $0.meters) })
    }

    private static func oddLength(_ holes: [(Int?, Double?)]) -> [OddLengthHole] {
        holes.enumerated().compactMap { i, h in
            lengthMatchesPar(par: h.0, meters: h.1) ? nil : OddLengthHole(number: i + 1, par: h.0, meters: h.1)
        }
    }

    /// `banehullFraRader`: rader fra `course_holes` gruppert per bane, sortert på hullnummer.
    /// En bane får `nil` med mindre den har 9 eller 18 sammenhengende hull fra 1.
    /// Rader uten bane-id hoppes over.
    public static func holesFromRows(_ rows: [CourseHoleRow]) -> [String: [CourseHole]?] {
        var perCourse: [String: [CourseHoleRow]] = [:]
        for row in rows {
            guard let id = row.courseId, !id.isEmpty else { continue }
            perCourse[id, default: []].append(row)
        }
        return perCourse.mapValues { rows in
            let sorted = rows.sorted { $0.holeNumber < $1.holeNumber }
            let whole = (sorted.count == 9 || sorted.count == 18)
                && sorted.enumerated().allSatisfy { i, r in r.holeNumber == i + 1 }
            guard whole else { return nil }
            return sorted.map { CourseHole(par: $0.par, si: $0.hcpIndex, meters: $0.distanceMeters) }
        }
    }

    /// `baneHarIndeks`: har hvert hull en stroke index over 0?
    public var hasStrokeIndex: Bool {
        guard let holes, !holes.isEmpty else { return false }
        return holes.allSatisfy { ($0.si ?? 0) > 0 }
    }

    /// `baneErKlar`: 9 eller 18 hull, og gyldig par på hvert av dem. Stroke index kreves ikke.
    public var isReady: Bool {
        guard let holes, holes.count == 9 || holes.count == 18 else { return false }
        return holes.allSatisfy { Course.isValidPar($0.par) }
    }
}

/// JS-sannhet for tall: 0 og `nil` er «falsy» og faller gjennom (`a || b`).
@inline(__always)
func truthy(_ x: Int?) -> Int? {
    guard let x, x != 0 else { return nil }
    return x
}

@inline(__always)
func truthy(_ x: Double?) -> Double? {
    guard let x, x != 0, !x.isNaN else { return nil }
    return x
}

extension Round {
    /// `antallHull`: 9 eller 18. Alt annet (også `nil`) er 18.
    public var numberOfHoles: Int {
        (holeCount == 9 || holeCount == 18) ? holeCount! : 18
    }

    /// `courseForRound`: hullene slik de spilles i denne runden.
    ///
    /// Par: rundens eget (hvis gyldig) → banens → `DEFAULT_PAR[i]` (merk: `i`, ikke `start + i`).
    /// Kortindeks: rundens egen → banens → `i + 1`, med JS-sannhet (0 faller gjennom).
    /// `strokeIndex` er rangen etter kortindeks, likhet avgjøres av lavest hullindeks.
    /// Start på banens hull 10 gjelder bare når runden er 9 hull, `holeStart == 9` og banen har 18 hull.
    public func courseHoles() -> [PlayedHole] {
        let count = numberOfHoles
        let fromCourse = course?.holes
        let start = (count == 9 && holeStart == 9 && fromCourse?.count == 18) ? 9 : 0

        var played: [PlayedHole] = []
        played.reserveCapacity(count)
        for i in 0..<count {
            let custom = holes?[i]
            let courseIndex = start + i
            let fromBane: CourseHole? = (fromCourse != nil && courseIndex < fromCourse!.count) ? fromCourse![courseIndex] : nil

            let par: Int
            if let p = custom?.par, Course.isValidPar(p) {
                par = p
            } else if let p = fromBane?.par, Course.isValidPar(p) {
                par = p
            } else {
                par = Course.defaultPar[i]
            }
            let cardIndex = truthy(custom?.strokeIndex) ?? truthy(fromBane?.si) ?? (i + 1)
            let meters = truthy(custom?.meters) ?? truthy(fromBane?.meters)
            played.append(PlayedHole(par: par, cardIndex: cardIndex, meters: meters, strokeIndex: 0))
        }

        let order = played.indices.sorted { a, b in
            played[a].cardIndex != played[b].cardIndex ? played[a].cardIndex < played[b].cardIndex : a < b
        }
        for (rank, i) in order.enumerated() {
            played[i].strokeIndex = rank + 1
        }
        return played
    }
}
