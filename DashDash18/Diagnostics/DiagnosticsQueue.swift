import Foundation

/// Radene som ikke er sendt ennå: en liten JSON-fil i Application Support, høyst `limit` rader.
/// Kommer det flere, kastes de eldste. Fila slettes ved bytte mellom test og prod
/// (`EnvironmentSwitchGuard.removeLocalStores()`).
actor DiagnosticsQueue {
    nonisolated static let limit = 50
    nonisolated static let defaultFileURL = URL.applicationSupportDirectory.appending(path: "Feilrapporter.json")

    let fileURL: URL
    private let limit: Int

    init(fileURL: URL = DiagnosticsQueue.defaultFileURL, limit: Int = DiagnosticsQueue.limit) {
        self.fileURL = fileURL
        self.limit = limit
    }

    /// Alle rader i køen, eldste først. En fil som mangler eller ikke kan leses, gir tom kø.
    func load() -> [DiagnosticRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([DiagnosticRecord].self, from: data)) ?? []
    }

    func append(_ records: [DiagnosticRecord]) {
        guard !records.isEmpty else { return }
        save(Self.appending(records, to: load(), limit: limit))
    }

    /// Fjerner radene som serveren har tatt imot.
    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        save(load().filter { !ids.contains($0.id) })
    }

    private func save(_ records: [DiagnosticRecord]) {
        do {
            if records.isEmpty {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(records).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Feilrapportene er ikke viktigere enn appen: går lagringen ikke, mistes de.
        }
    }

    /// Nye rader bak de gamle. Blir det flere enn `limit`, kastes de eldste. Samme id to ganger
    /// legges ikke inn på nytt.
    nonisolated static func appending(_ new: [DiagnosticRecord], to existing: [DiagnosticRecord],
                                      limit: Int) -> [DiagnosticRecord] {
        let known = Set(existing.map(\.id))
        let combined = existing + new.filter { !known.contains($0.id) }
        return Array(combined.suffix(max(limit, 0)))
    }
}
