import Foundation
import Supabase

/// Det tråden trenger fra serveren. Egen protokoll, så sending og tilbakerulling kan testes
/// uten nett.
nonisolated protocol TradBackend: Sendable {
    func messages(eventID: UUID) async throws -> [ThreadMessageRow]
    func members(clubID: UUID) async throws -> [ClubMemberRow]
    /// Lagrer meldingen og gir raden tilbake slik serveren har den (med serverens tid).
    func insert(_ message: ThreadMessageInsert) async throws -> ThreadMessageRow
    /// Sletter meldingen. Gir false når ingen rad ble slettet (RLS sa nei, eller den var borte).
    func delete(messageID: UUID) async throws -> Bool
    func uploadImage(path: String, jpeg: Data) async throws
    func removeImages(paths: [String]) async throws
    /// Signerte lenker per sti. Stier som ikke kunne signeres, mangler i svaret.
    func signedURLs(paths: [String], expiresIn: Int) async throws -> [String: URL]
}

/// Tråden mot Supabase: tabellen `thread_messages` og bøtta `thread`.
nonisolated struct SupabaseTradBackend: TradBackend {
    let client: SupabaseClient

    private var bucket: StorageFileApi { client.storage.from(TradImagePath.bucket) }

    func messages(eventID: UUID) async throws -> [ThreadMessageRow] {
        try await client.from("thread_messages")
            .select(ThreadMessageRow.columns)
            .eq("event_id", value: eventID)
            .order("created_at")
            .execute().value
    }

    func members(clubID: UUID) async throws -> [ClubMemberRow] {
        try await client.from("club_members")
            .select(KveldQueries.memberColumns)
            .eq("club_id", value: clubID)
            .execute().value
    }

    func insert(_ message: ThreadMessageInsert) async throws -> ThreadMessageRow {
        try await client.from("thread_messages")
            .insert(message)
            .select(ThreadMessageRow.columns)
            .single()
            .execute().value
    }

    func delete(messageID: UUID) async throws -> Bool {
        let rows: [IDOnly] = try await client.from("thread_messages")
            .delete()
            .eq("id", value: messageID)
            .select("id")
            .execute().value
        return !rows.isEmpty
    }

    func uploadImage(path: String, jpeg: Data) async throws {
        _ = try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
    }

    func removeImages(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await bucket.remove(paths: paths)
    }

    func signedURLs(paths: [String], expiresIn: Int) async throws -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        let results: [SignedURLResult] = try await bucket.createSignedURLs(paths: paths, expiresIn: expiresIn)
        var urls: [String: URL] = [:]
        for result in results {
            if case .success(let path, let url) = result { urls[path] = url }
        }
        return urls
    }

    private struct IDOnly: Decodable { let id: UUID }
}

/// Hvor langt du har lest i hver tråd, lagret på telefonen (PWA: `gg_traad_sett`).
nonisolated protocol TradReadStoring: Sendable {
    func lastSeen(memberID: UUID, eventID: UUID) -> Date?
    func setLastSeen(_ date: Date, memberID: UUID, eventID: UUID)
}

/// `UserDefaults`, én nøkkel per medlemskap og kveld (to klubber på samme telefon holdes fra
/// hverandre).
nonisolated struct UserDefaultsTradReadStore: TradReadStoring, @unchecked Sendable {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ memberID: UUID, _ eventID: UUID) -> String {
        "trad.lastSeen.\(memberID.uuidString.lowercased()).\(eventID.uuidString.lowercased())"
    }

    func lastSeen(memberID: UUID, eventID: UUID) -> Date? {
        defaults.object(forKey: key(memberID, eventID)) as? Date
    }

    func setLastSeen(_ date: Date, memberID: UUID, eventID: UUID) {
        defaults.set(date, forKey: key(memberID, eventID))
    }
}

nonisolated extension TradSummary {
    /// Henter tråden for én kveld og lager kortet (for Kveld, når den kobles inn).
    static func load(backend: any TradBackend, clubID: UUID, eventID: UUID, viewer: UUID,
                     readStore: any TradReadStoring = UserDefaultsTradReadStore()) async throws -> TradSummary {
        async let messages = backend.messages(eventID: eventID)
        async let members = backend.members(clubID: clubID)
        let rows = try await messages
        let names = Dictionary(try await members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        return make(messages: rows, names: names, viewer: viewer,
                    lastSeen: readStore.lastSeen(memberID: viewer, eventID: eventID))
    }
}
