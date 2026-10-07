import Foundation
import GolfgutuCore

/// Er banen klar til å spilles, i klart språk? Samme regel som `baneErKlar`: 9 eller 18 hull
/// med gyldig par på hvert. Indeks, lengde og rating kreves ikke.
nonisolated enum CourseReadiness: Equatable, Sendable {
    case ready
    /// `missing` av `total` hull mangler gyldig par.
    case missingPar(missing: Int, total: Int)
    /// Ingen hull lagret (banen er ikke satt opp).
    case noHoles

    /// Fra parene i skjemaet eller på banen, i hullrekkefølge.
    init(pars: [Int?]) {
        guard !pars.isEmpty else {
            self = .noHoles
            return
        }
        let missing = pars.filter { !Course.isValidPar($0) }.count
        if missing == 0, CourseDraft.holeCounts.contains(pars.count) {
            self = .ready
        } else {
            self = .missingPar(missing: missing == 0 ? pars.count : missing, total: pars.count)
        }
    }

    var isReady: Bool { self == .ready }

    /// Merket i lista og skjemaet: «Klar», «Mangler par på 3 hull».
    var title: String {
        switch self {
        case .ready: "Klar"
        case .noHoles: "Mangler par"
        case .missingPar(let missing, let total) where missing == total: "Mangler par på alle hull"
        case .missingPar(let missing, _): missing == 1 ? "Mangler par på 1 hull" : "Mangler par på \(missing) hull"
        }
    }

    /// Forklaringen under: hva som kreves, og hva som er valgfritt.
    func detail(kind: CourseKind) -> String {
        switch self {
        case .ready:
            "Banen kan velges når en runde settes opp."
        case .noHoles, .missingPar:
            "Banen er klar når alle hullene har par. Les dem av \(kind.source). Indeks, lengde og rating er valgfritt."
        }
    }
}
