import Foundation
import Supabase

/// Kallene for sosialt (sql/050): `react`, `comment_add`/`_edit`/`_delete`, `follow_thread`,
/// `feed_page`, og lesing av `reactions`, `comments` og `thread_follows` (RLS skjuler blokkerte).
nonisolated struct SocialService: Sendable {
    let client: SupabaseClient

    /// Id-er per `in`-filter, så adressen holder seg kort.
    static let chunkSize = 50

    /// Mangler 050 på serveren (ukjent funksjon, tabell eller kolonne)?
    static func isMissing(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return PushSchema.isMissing(code: postgrest.code)
    }

    // MARK: Hjem

    private struct FeedParams: Encodable {
        let p_club_ids: [UUID]?
        let p_before_ts: String?
        let p_before_id: UUID?
        let p_limit: Int
    }

    /// Én side av feeden, nyeste først. `before` nil: første side.
    func feedPage(clubIDs: [UUID]?, before: FeedCursor?, limit: Int = FeedPaging.pageSize) async throws -> [FeedPageRow] {
        try await client.rpc("feed_page", params: FeedParams(p_club_ids: clubIDs, p_before_ts: before?.timestamp,
                                                             p_before_id: before?.id, p_limit: limit))
            .execute().value
    }

    // MARK: Reaksjoner

    private struct ReactParams: Encodable {
        let p_kind: String
        let p_id: UUID
        let p_emoji: String
        let p_on: Bool
    }

    /// Setter (`on`) eller fjerner din reaksjon. Fantes den, eller var den borte, er målet nådd.
    func react(_ emoji: String, on target: SocialTarget, _ on: Bool) async throws {
        _ = try await client.rpc("react", params: ReactParams(p_kind: target.kind.rawValue, p_id: target.id,
                                                              p_emoji: emoji, p_on: on))
            .execute()
    }

    /// Reaksjonene på målene, uten dem du er blokkert mot.
    func reactions(_ kind: SocialTargetKind, ids: [UUID]) async throws -> [ReactionRow] {
        try await chunked(ids) { chunk in
            try await client.from("reactions")
                .select(ReactionRow.columns)
                .eq("target_kind", value: kind.rawValue)
                .in("target_id", values: chunk)
                .execute().value
        }
    }

    // MARK: Kommentarer

    func comments(on target: SocialTarget) async throws -> [CommentRow] {
        try await client.from("comments")
            .select(CommentRow.columns)
            .eq("target_kind", value: target.kind.rawValue)
            .eq("target_id", value: target.id)
            .order("created_at")
            .limit(500)
            .execute().value
    }

    /// Antall kommentarer per mål (uten slettede).
    func commentCounts(_ kind: SocialTargetKind, ids: [UUID]) async throws -> [UUID: Int] {
        struct Row: Decodable {
            let targetID: UUID
            enum CodingKeys: String, CodingKey { case targetID = "target_id" }
        }
        let rows: [Row] = try await chunked(ids) { chunk in
            try await client.from("comments")
                .select("target_id")
                .eq("target_kind", value: kind.rawValue)
                .in("target_id", values: chunk)
                .is("deleted_at", value: nil)
                .execute().value
        }
        return rows.reduce(into: [:]) { $0[$1.targetID, default: 0] += 1 }
    }

    private struct AddParams: Encodable {
        let p_kind: String
        let p_id: UUID
        let p_body: String
        let p_mentions: [UUID]
        let p_follow: Bool
    }

    func addComment(on target: SocialTarget, body: String, mentions: [UUID], follow: Bool = true) async throws -> CommentRow {
        try await client.rpc("comment_add", params: AddParams(p_kind: target.kind.rawValue, p_id: target.id,
                                                              p_body: body, p_mentions: mentions, p_follow: follow))
            .execute().value
    }

    private struct EditParams: Encodable {
        let p_id: UUID
        let p_body: String
        let p_mentions: [UUID]
    }

    func editComment(_ id: UUID, body: String, mentions: [UUID]) async throws -> CommentRow {
        try await client.rpc("comment_edit", params: EditParams(p_id: id, p_body: body, p_mentions: mentions))
            .execute().value
    }

    private struct IDParams: Encodable { let p_id: UUID }

    /// Myk sletting. Gir om noe ble slettet.
    func deleteComment(_ id: UUID) async throws -> Bool {
        try await client.rpc("comment_delete", params: IDParams(p_id: id)).execute().value
    }

    // MARK: Følg tråden

    private struct FollowParams: Encodable {
        let p_kind: String
        let p_id: UUID
        let p_on: Bool
    }

    func follow(_ target: SocialTarget, _ on: Bool) async throws {
        _ = try await client.rpc("follow_thread", params: FollowParams(p_kind: target.kind.rawValue, p_id: target.id,
                                                                       p_on: on))
            .execute()
    }

    /// Ditt valg for tråden, eller nil når du ikke har valgt (RLS: bare dine rader).
    func following(_ target: SocialTarget) async throws -> Bool? {
        struct Row: Decodable { let following: Bool }
        let rows: [Row] = try await client.from("thread_follows")
            .select("following")
            .eq("target_kind", value: target.kind.rawValue)
            .eq("target_id", value: target.id)
            .execute().value
        return rows.first?.following
    }

    private func chunked<T: Sendable>(_ ids: [UUID], _ query: @Sendable ([String]) async throws -> [T]) async throws -> [T] {
        var out: [T] = []
        for start in stride(from: 0, to: ids.count, by: Self.chunkSize) {
            out += try await query(ids[start..<min(start + Self.chunkSize, ids.count)].map(\.uuidString))
        }
        return out
    }
}
