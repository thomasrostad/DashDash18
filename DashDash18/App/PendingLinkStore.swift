import Foundation

/// Invitasjonslenken som venter på innloggingen (en løs runde, en konkurranse eller en følgelenke),
/// husket på telefonen. En ny bruker henter koden i Mail, og iOS kan lukke appen imens; uten dette
/// var lenken glemt når appen startet igjen. Glemmes når den er brukt, eller etter et døgn
/// (som klubbinvitasjonen, `PendingClubInviteStore`). Lenken lagres som den kom, og tolkes på nytt.
nonisolated struct PendingLinkStore {
    static let appLinkKey = "ventende-lenke"
    static let followKey = "ventende-folgelenke"
    static let maxAge: TimeInterval = 24 * 3600

    let key: String
    var defaults: UserDefaults = .standard

    private struct Saved: Codable {
        let url: URL
        let savedAt: Date
    }

    func save(_ url: URL, now: Date = .now) {
        guard let data = try? JSONEncoder().encode(Saved(url: url, savedAt: now)) else { return }
        defaults.set(data, forKey: key)
    }

    func load(now: Date = .now) -> URL? {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        guard now.timeIntervalSince(saved.savedAt) < Self.maxAge else {
            clear()
            return nil
        }
        return saved.url
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

nonisolated extension PendingLinkStore {
    /// Runde- og konkurranselenken (`AppLink`).
    static var appLinks: PendingLinkStore { PendingLinkStore(key: appLinkKey) }
    /// Følgelenken (`FollowLink`, sql/054).
    static var follows: PendingLinkStore { PendingLinkStore(key: followKey) }
}
