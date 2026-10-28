import Foundation
import Testing
@testable import GolfgutuCore

/// `can_score` i databasen har en fast liste over formene der lagkamerater fører for hverandre
/// (sql/071 og 074), mens appen regner det ut av formene (`isTeamScorer`: mer enn én spiller per lag).
/// Kommer det en ny lagform uten at lista i SQL-en utvides, feiler denne, og serveren ville avvist
/// føringen appen tilbyr.
struct LagForerSQLTests {
    /// Repoets `sql/`, fra denne fila (Packages/GolfgutuCore/Tests/GolfgutuCoreTests).
    static let sqlDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("sql", isDirectory: true)

    /// Den nyeste fila som definerer `can_score`, og formlisten i lag-grenen der.
    static func latestTeamForms() throws -> (file: String, forms: Set<String>) {
        let files = try FileManager.default.contentsOfDirectory(atPath: sqlDirectory.path)
            .filter { $0.hasSuffix(".sql") }
            .sorted()
        for file in files.reversed() {
            let text = try String(contentsOf: sqlDirectory.appendingPathComponent(file), encoding: .utf8)
            guard text.contains("create or replace function public.can_score"),
                  let start = text.range(of: "if v_format in (") else { continue }
            let rest = text[start.upperBound...]
            guard let end = rest.firstIndex(of: ")") else { continue }
            let forms = rest[..<end].split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            }
            return (file, Set(forms))
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test func lagformeneIDatabasenErLagformeneIMotoren() throws {
        let (file, forms) = try Self.latestTeamForms()
        let teamForms = Set(CompetitionForm.catalog.filter { $0.teamSize > 1 }.map(\.id))
        #expect(forms == teamForms, "\(file): \(forms.sorted()) ≠ \(teamForms.sorted())")
    }
}
