import Foundation
import WidgetKit

// DELT FIL: må være medlem av både DashDash18 og DashDash18Widgets (se docs/widgets-oppsett.md).
// Bare Foundation og WidgetKit her, ingen typer fra appen.

/// App Group-en appen og widgetene deler. `group.` + appens bundle-id.
nonisolated enum AppGroup {
    static let identifier = "group.com.dashdash18.app"
}

/// Det widgetene viser: neste kveld og topp 3 på Tavla. Appen skriver, widgetene leser.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct NextEvening: Codable, Equatable, Sendable {
        /// `YYYY-MM-DD`.
        var eventDate: String
        /// «Torsdag 8. oktober».
        var dateText: String
        /// «17:00», eller nil når klokkeslett ikke er satt.
        var timeText: String?
        /// Start i Oslo-tid (dato + klokkeslett, ellers kl. 12), for nedtelling og når widgeten skal byttes.
        var startsAt: Date?
        /// Banen eller stedet.
        var venue: String?
    }

    struct Leader: Codable, Equatable, Sendable {
        var place: Int
        var name: String
        var points: Double
        /// Poengene slik Tavla viser dem (regelsettets avrunding): «14,5».
        var pointsText: String
        var isMe: Bool
    }

    var nextEvening: NextEvening?
    var seasonName: String?
    var top: [Leader] = []
    var updatedAt: Date = .distantPast

    static let empty = WidgetSnapshot()

    /// Samme innhold, uansett når det ble skrevet.
    func sameContent(as other: WidgetSnapshot) -> Bool {
        var a = self, b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }
}

/// Leser og skriver `WidgetSnapshot` som JSON i App Group-containeren. Finnes ikke containeren
/// (App Group ikke satt opp ennå), brukes appens egen Application Support, så appen virker likt.
nonisolated struct WidgetSnapshotStore: Sendable {
    static let fileName = "widget-snapshot.json"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// Containeren til App Group-en, eller reserven.
    static var shared: WidgetSnapshotStore {
        WidgetSnapshotStore(directory: containerDirectory(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)))
    }

    /// App Group-containeren når den finnes, ellers Application Support/WidgetSnapshot.
    static func containerDirectory(_ groupContainer: URL?) -> URL {
        groupContainer ?? URL.applicationSupportDirectory.appending(path: "WidgetSnapshot", directoryHint: .isDirectory)
    }

    var fileURL: URL { directory.appending(path: Self.fileName, directoryHint: .notDirectory) }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Det som er lagret, eller et tomt øyeblikksbilde når ingenting er lagret eller fila er ødelagt.
    func read() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    /// Endrer det lagrede og skriver det tilbake. Widgetene lastes på nytt bare når innholdet
    /// faktisk er endret (WidgetKit har et budsjett for omlastinger). Gir `true` når noe ble endret.
    @discardableResult
    func update(now: Date = .now, reloadWidgets: Bool = true, _ change: (inout WidgetSnapshot) -> Void) -> Bool {
        let before = read()
        var after = before
        change(&after)
        guard !after.sameContent(as: before) else { return false }
        after.updatedAt = now
        do {
            try write(after)
        } catch {
            return false
        }
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }
}
