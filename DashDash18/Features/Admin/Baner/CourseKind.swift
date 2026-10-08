import Foundation

/// Er `courses.kind` på plass i databasen? Kolonnen kommer med `sql/016_banetype.sql` (kjørt på test).
/// Med flagget av leser og skriver appen ikke kolonnen, typevalget vises ikke, og typen avledes
/// (se `CourseKind.resolve`).
nonisolated enum CourseKindFeature {
    static let isEnabled = true
}

/// Simulatorbane eller ekte bane. Rå-verdiene er de samme som i `courses.kind` (016).
nonisolated enum CourseKind: String, CaseIterable, Codable, Hashable, Sendable {
    case simulator
    case course

    /// Valget i skjemaet.
    var title: String {
        switch self {
        case .simulator: "Simulator"
        case .course: "Ekte bane"
        }
    }

    /// Overskriften i banelista.
    var groupTitle: String {
        switch self {
        case .simulator: "Simulatorbaner"
        case .course: "Ekte baner"
        }
    }

    /// Det tallene leses av og bekreftes mot.
    var source: String {
        switch self {
        case .simulator: "skjermen"
        case .course: "scorekortet"
        }
    }

    /// Typen for en bane. Lagret type vinner. Uten lagret type (før 016 er kjørt) kan den ikke
    /// avledes sikkert: navn i simulatoren betyr simulatorbane, men mange simulatorbaner har
    /// samme navn som hos oss og står uten. Alle regnes derfor som simulatorbaner, som er
    /// databasens standard i 016 og det klubben spiller i dag. Ekte baner finnes bare når typen er lagret.
    static func resolve(stored: CourseKind?) -> CourseKind {
        stored ?? .simulator
    }
}
