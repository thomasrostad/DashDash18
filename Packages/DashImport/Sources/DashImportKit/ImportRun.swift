import Foundation

/// Det kommandolinjen gjør, samlet så det kan testes.
public enum ImportRun {
    /// Leser mappa og lager planen. Returnerer også sjekksummen av snapshot.json.
    public static func plan(snapshotDirectory: URL, options: ImportOptions = ImportOptions()) throws -> (plan: ImportPlan, checksum: String) {
        let (snapshot, raw) = try PWASnapshot.load(directory: snapshotDirectory)
        return (try Mapper.plan(snapshot, options: options), SHA1.hex(Array(raw)))
    }

    /// SQL-en for mappa.
    public static func sql(snapshotDirectory: URL, options: ImportOptions = ImportOptions()) throws -> (sql: String, plan: ImportPlan) {
        let (plan, checksum) = try plan(snapshotDirectory: snapshotDirectory, options: options)
        return (SQLWriter.write(plan, sourceChecksum: checksum), plan)
    }

    /// `true` når fila havner i et git-arbeidstre utenfor de ignorerte importmappene.
    public static func isRiskyOutput(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.contains("/import-out/") || path.contains("/import-snapshot/") { return false }
        var dir = url.standardizedFileURL.deletingLastPathComponent()
        while dir.path != "/" && !dir.path.isEmpty {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return true }
            dir = dir.deletingLastPathComponent()
        }
        return false
    }
}
