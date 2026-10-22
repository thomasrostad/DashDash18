import Foundation
import Observation
import Supabase

/// Kommentarene under en hendelse eller en melding (sql/050): flat liste, @-omtale, endre og slette
/// egne, moderator sletter, rapporter, reaksjoner på hver kommentar og «Følg tråden».
@Observable
final class CommentsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let target: SocialTarget
    /// Du i klubben (medlemmet), eller profilen uten klubb.
    let me: UUID
    let isModerator: Bool
    /// Du skrev det som kommenteres (får varsel uten å følge).
    let isTargetAuthor: Bool

    private(set) var state: LoadState = .loading
    private(set) var comments: [CommentRow] = []
    private(set) var reactions: [ReactionRow] = []
    private(set) var following = false
    private(set) var isSending = false
    var draft = ""
    /// Kommentaren som endres. nil: ny kommentar.
    private(set) var editing: CommentRow?
    var errorMessage: String?
    /// Rapportert av deg: skjules til moderatoren har sett på dem.
    private(set) var hidden: Set<UUID> = []

    let directory: MentionDirectory
    private let names: [UUID: String]
    /// Medlemmene i klubben som har innlogging, eller nil når troppen ikke er kjent (`BlockRules`).
    private let membersWithLogin: Set<UUID>?
    private let client: SupabaseClient?
    /// Antall kommentarer har endret seg (feeden og tråden viser det).
    var onCountChange: ((Int) -> Void)?
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []

    init(target: SocialTarget, me: UUID, isModerator: Bool, isTargetAuthor: Bool, people: [TradPerson],
         names: [UUID: String], membersWithLogin: Set<UUID>? = nil, client: SupabaseClient?) {
        self.target = target
        self.me = me
        self.isModerator = isModerator
        self.isTargetAuthor = isTargetAuthor
        directory = MentionDirectory(people: people)
        self.names = names
        self.membersWithLogin = membersWithLogin
        self.client = client
        following = ThreadFollow.isFollowing(row: nil, isTargetAuthor: isTargetAuthor)
    }

    /// Skjermprøve og tester: faste rader, ingen nettverk.
    convenience init(preview comments: [CommentRow], target: SocialTarget, me: UUID, isModerator: Bool = false,
                     people: [TradPerson], membersWithLogin: Set<UUID>? = nil) {
        self.init(target: target, me: me, isModerator: isModerator, isTargetAuthor: false, people: people,
                  names: Dictionary(people.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }),
                  membersWithLogin: membersWithLogin, client: nil)
        self.comments = comments
        state = .loaded
    }

    var items: [CommentItem] {
        CommentList.items(comments, me: [me], isModerator: isModerator, hidden: hidden, name: { names[$0] })
    }

    func name(_ id: UUID) -> String? { names[id] }

    /// Kan forfatteren blokkeres fra rapportarket? Bare når det finnes en innlogging bak navnet.
    func canBlock(_ comment: CommentRow) -> Bool {
        BlockRules.canBlock(memberID: comment.memberID, profileID: comment.profileID, membersWithLogin: membersWithLogin)
    }

    func chips(for comment: UUID) -> [ReactionChip] {
        ReactionRows.chips(for: .comment, id: comment, in: reactions, me: [me], name: { names[$0] })
    }

    var suggestions: [MentionDirectory.Suggestion] { directory.suggestions(for: draft, viewer: me) }

    var canSend: Bool {
        guard !isSending else { return false }
        if case .ready = CommentDraft.check(draft) { return true }
        return false
    }

    var remainingCharacters: Int? {
        let left = CommentDraft.maxLength - draft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        return left < 100 ? left : nil
    }

    private var service: SocialService? { client.map(SocialService.init) }

    // MARK: Henting

    func load() async {
        guard let service else { state = .loaded; return }
        do {
            async let rows = service.comments(on: target)
            async let follow = service.following(target)
            let fresh = try await rows
            comments = fresh
            following = ThreadFollow.isFollowing(row: try? await follow, isTargetAuthor: isTargetAuthor)
            reactions = (try? await service.reactions(.comment, ids: fresh.map(\.id))) ?? reactions
            state = .loaded
            onCountChange?(CommentList.count(comments))
            await startRealtime()
        } catch {
            guard !DataError.isCancellation(error) else { return }
            if state == .loaded { return }
            state = .failed(DataError.from(error).message)
        }
    }

    // MARK: Skriving

    func insertMention(_ handle: String) {
        draft = MentionDirectory.inserting(handle, into: draft)
    }

    func startEditing(_ comment: CommentRow) {
        editing = comment
        draft = comment.body
    }

    func cancelEditing() {
        editing = nil
        draft = ""
    }

    func send() async {
        guard !isSending else { return }
        let text: String
        switch CommentDraft.check(draft) {
        case .empty: return
        case .tooLong:
            errorMessage = "Kommentaren kan ha høyst \(CommentDraft.maxLength) tegn."
            return
        case .ready(let trimmed): text = trimmed
        }
        guard let service else { return }
        let mentions = directory.mentions(in: text, sender: me)
        let editing = editing
        isSending = true
        defer { isSending = false }
        do {
            let saved: CommentRow
            if let editing {
                saved = try await service.editComment(editing.id, body: text, mentions: mentions)
            } else {
                saved = try await service.addComment(on: target, body: text, mentions: mentions)
                following = true
            }
            comments = CommentList.upserting(saved, into: comments)
            self.editing = nil
            draft = ""
            onCountChange?(CommentList.count(comments))
        } catch {
            errorMessage = "Klarte ikke å lagre kommentaren: " + DataError.from(error).message
        }
    }

    func delete(_ comment: CommentRow) async {
        guard let service else { return }
        do {
            _ = try await service.deleteComment(comment.id)
            await load()
        } catch {
            errorMessage = "Klarte ikke å slette: " + DataError.from(error).message
        }
    }

    func toggleFollow() async {
        guard let service else { following.toggle(); return }
        let wanted = !following
        following = wanted
        do {
            try await service.follow(target, wanted)
        } catch {
            following = !wanted
            errorMessage = "Klarte ikke å lagre valget: " + DataError.from(error).message
        }
    }

    // MARK: Reaksjoner på kommentarene

    func toggle(_ emoji: String, on comment: UUID) async {
        let commentTarget = SocialTarget(kind: .comment, id: comment, clubID: target.clubID)
        let had = reactions.contains { $0.targetID == comment && $0.personID == me && $0.emoji == emoji }
        let before = reactions
        reactions = ReactionRows.toggled(emoji, on: commentTarget, person: me, isMember: target.clubID != nil,
                                         in: reactions)
        guard let service else { return }
        do {
            try await service.react(emoji, on: commentTarget, !had)
        } catch {
            reactions = before
            errorMessage = "Klarte ikke å lagre reaksjonen: " + DataError.from(error).message
        }
    }

    func who(_ comment: UUID) async throws -> [ReactionWhoGroup] {
        if let service {
            reactions = reactions.filter { $0.targetID != comment }
                + (try await service.reactions(.comment, ids: [comment]))
        }
        return ReactionWho.groups(reactions.filter { $0.targetID == comment }, name: { names[$0] })
    }

    // MARK: Rapporter

    func report(_ comment: CommentRow, reason: ReportReason, note: String, block: Bool) async throws {
        guard let client else { throw DataError.offline }
        let moderation = ModerationService(client: client)
        _ = try await moderation.report(kind: .comment, targetID: comment.id, reason: reason, note: note)
        hidden.insert(comment.id)
        if block, canBlock(comment) {
            _ = try await moderation.block(memberID: comment.memberID, profileID: comment.memberID == nil ? comment.profileID : nil)
        }
        onCountChange?(CommentList.count(comments.filter { !hidden.contains($0.id) }))
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard let client, channel == nil else { return }
        let channel = client.channel("kommentarer-\(target.id.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "comments",
                                             filter: .eq("target_id", value: target.id))
        self.channel = channel
        listenTasks = [
            Task { [weak self] in
                for await _ in changes { await self?.load() }
            },
            Task { try? await channel.subscribeWithError() },
        ]
    }

    func stopRealtime() async {
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel, let client { await client.removeChannel(channel) }
        channel = nil
    }
}
