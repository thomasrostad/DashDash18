import Foundation
import GolfgutuCore

// Sosialt (gjennomføringsplanen steg 9, sql/050): reaksjoner på alt, kommentarer, «Følg tråden»,
// Hjem i sider (`feed_page`) og bildeoppfordringen. Rene typer og regler her; kallene står i
// `SocialService`. Uten 050 på serveren (ukjent funksjon eller tabell) faller appen tilbake til
// det faste reaksjonssettet i `activity_reactions` og den gamle feeden, uten kommentarer.

/// Slår sosialt (050) av i appen. Av: alt går som før steg 9.
nonisolated enum SocialFeature {
    /// På: 050 er kjørt på test 12.10.2026. Mangler 050 likevel (prod før kjøring), merker appen det
    /// på svaret (`PushSchema.isMissing`) og bruker den gamle veien.
    /// Kan slås av fra serveren: `ios_flags.social` (sql/068).
    static var isEnabled: Bool { !KillSwitch.isOff("social") }
}

/// Hva en reaksjon eller kommentar henger på (`reactions.target_kind`, `comments.target_kind`).
nonisolated enum SocialTargetKind: String, Codable, Sendable, Hashable {
    case activity
    case message
    case comment

    /// Bare hendelser og meldinger kan kommenteres (flate kommentarer).
    var canHaveComments: Bool { self != .comment }
}

/// Et mål for reaksjoner og kommentarer.
nonisolated struct SocialTarget: Hashable, Sendable, Identifiable {
    let kind: SocialTargetKind
    let id: UUID
    /// Klubben målet hører til. nil: en turnering uten klubb.
    var clubID: UUID?

    init(kind: SocialTargetKind, id: UUID, clubID: UUID?) {
        self.kind = kind
        self.id = id
        self.clubID = clubID
    }
}

// MARK: - Emoji

/// Én emoji, som `private.is_single_emoji` i 050: ett tegn (med hudfarge, ZWJ-sekvens, flagg eller
/// tast), høyst 16 kodepunkter. Tall og bokstaver alene er ikke emoji.
nonisolated enum EmojiCheck {
    static let maxScalars = 16

    static func isSingleEmoji(_ text: String) -> Bool {
        guard text.count == 1 else { return false }
        let scalars = Array(text.unicodeScalars)
        guard (1...maxScalars).contains(scalars.count), let first = scalars.first,
              first.properties.isEmoji else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Tegn som er tekst som standard (❤, ☺, 1, #) må ha emojivarianten eller være en tast.
        return scalars.count > 1 && scalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 }
    }

    /// Den siste emojien i det som er skrevet (emojitastaturet kan gi flere), eller nil.
    static func lastEmoji(in text: String) -> String? {
        text.reversed().map(String.init).first(where: isSingleEmoji)
    }
}

/// De fem faste først (beslutningen 11.10.2026), og et lite utvalg bak «+».
nonisolated enum ReactionPalette {
    static let quick: [String] = ActivityReaction.allCases.map(\.rawValue)
    static let more: [String] = [
        "👏", "🙌", "💪", "🎉", "🥳", "😅", "🤣", "😍", "😎", "🤔",
        "😬", "😱", "😢", "😡", "🙈", "🤝", "🙏", "👀", "💯", "🏆",
        "🥇", "🍺", "🍻", "☕", "🌧️", "☀️", "🌬️", "🏌️", "🎯", "🚀",
        "🐐", "🦅", "🐦", "💩", "🤡", "👎", "✅", "❌", "⚡", "💸",
    ]
}

// MARK: - Reaksjoner

/// En rad i `reactions` (sql/050): én per mål, person og emoji. Personen er medlemmet i klubben,
/// eller profilen uten klubb.
nonisolated struct ReactionRow: Codable, Equatable, Hashable, Sendable {
    let targetKind: SocialTargetKind
    let targetID: UUID
    var clubID: UUID?
    var memberID: UUID?
    var profileID: UUID?
    let emoji: String
    var createdAt: Date?

    init(targetKind: SocialTargetKind, targetID: UUID, clubID: UUID?, memberID: UUID?, profileID: UUID? = nil,
         emoji: String, createdAt: Date? = nil) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.clubID = clubID
        self.memberID = memberID
        self.profileID = profileID
        self.emoji = emoji
        self.createdAt = createdAt
    }

    /// Medlemmet eller profilen (`reactions.person_id`).
    var personID: UUID? { memberID ?? profileID }

    enum CodingKeys: String, CodingKey {
        case targetKind = "target_kind"
        case targetID = "target_id"
        case clubID = "club_id"
        case memberID = "member_id"
        case profileID = "profile_id"
        case emoji
        case createdAt = "created_at"
    }

    static let columns = "target_kind, target_id, club_id, member_id, profile_id, emoji, created_at"

    /// En rad fra den gamle tabellen (`activity_reactions`).
    init(legacy row: ActivityReactionRow) {
        self.init(targetKind: .activity, targetID: row.activityID, clubID: row.clubID, memberID: row.memberID,
                  emoji: row.emoji?.rawValue ?? "", createdAt: row.createdAt)
    }
}

/// Én emoji med antall (`feed_page.reactions`).
nonisolated struct ReactionCount: Codable, Equatable, Hashable, Sendable {
    let emoji: String
    var count: Int
}

/// Reaksjonene på ett mål: antall per emoji og dine egne. Rekkefølgen er serverens: flest først,
/// så den som kom først, så emojien.
nonisolated struct ReactionSummary: Equatable, Sendable {
    var counts: [ReactionCount] = []
    var mine: [String] = []

    init(counts: [ReactionCount] = [], mine: [String] = []) {
        self.counts = counts.filter { $0.count > 0 }
        self.mine = mine
    }

    /// Fra radene, som `feed_page` regner det.
    static func from(_ rows: [ReactionRow], me: Set<UUID>) -> ReactionSummary {
        var count: [String: Int] = [:]
        var first: [String: Date] = [:]
        for r in rows where !r.emoji.isEmpty {
            count[r.emoji, default: 0] += 1
            let t = r.createdAt ?? .distantFuture
            first[r.emoji] = min(first[r.emoji] ?? .distantFuture, t)
        }
        let order = count.keys.sorted { a, b in
            if count[a] != count[b] { return count[a]! > count[b]! }
            if first[a] != first[b] { return first[a]! < first[b]! }
            return a < b
        }
        let mine = rows.filter { r in r.personID.map(me.contains) ?? false }
            .sorted { ($0.createdAt ?? .distantFuture, $0.emoji) < ($1.createdAt ?? .distantFuture, $1.emoji) }
            .map(\.emoji)
        return ReactionSummary(counts: order.map { ReactionCount(emoji: $0, count: count[$0]!) }, mine: mine)
    }

    func has(_ emoji: String) -> Bool { mine.contains(emoji) }

    var total: Int { counts.reduce(0) { $0 + $1.count } }

    /// Etter et trykk: din reaksjon fjernes hvis du har den, ellers legges den til (sist, så
    /// brikkene ikke hopper).
    func toggled(_ emoji: String) -> ReactionSummary {
        var out = self
        if has(emoji) {
            out.mine.removeAll { $0 == emoji }
            if let i = out.counts.firstIndex(where: { $0.emoji == emoji }) {
                out.counts[i].count -= 1
                if out.counts[i].count <= 0 { out.counts.remove(at: i) }
            }
        } else {
            out.mine.append(emoji)
            if let i = out.counts.firstIndex(where: { $0.emoji == emoji }) {
                out.counts[i].count += 1
            } else {
                out.counts.append(ReactionCount(emoji: emoji, count: 1))
            }
        }
        return out
    }

    /// Brikkene. `names` gir hvem som reagerte når radene er kjent.
    func chips(names: [String: [String]] = [:]) -> [ReactionChip] {
        counts.map { ReactionChip(emoji: $0.emoji, count: $0.count, isMine: has($0.emoji), names: names[$0.emoji] ?? []) }
    }
}

nonisolated enum ReactionRows {
    /// Radene etter et trykk fra `person` på målet (vises med en gang, rulles tilbake ved feil).
    static func toggled(_ emoji: String, on target: SocialTarget, person: UUID, isMember: Bool,
                        in rows: [ReactionRow], now: Date = .now) -> [ReactionRow] {
        let hit: (ReactionRow) -> Bool = {
            $0.targetKind == target.kind && $0.targetID == target.id && $0.personID == person && $0.emoji == emoji
        }
        if rows.contains(where: hit) { return rows.filter { !hit($0) } }
        return rows + [ReactionRow(targetKind: target.kind, targetID: target.id, clubID: target.clubID,
                                   memberID: isMember ? person : nil, profileID: isMember ? nil : person,
                                   emoji: emoji, createdAt: now)]
    }

    /// Oppsummeringen for ett mål.
    static func summary(for target: SocialTargetKind, id: UUID, in rows: [ReactionRow], me: Set<UUID>) -> ReactionSummary {
        ReactionSummary.from(rows.filter { $0.targetKind == target && $0.targetID == id }, me: me)
    }

    /// Brikkene for ett mål, med navnene.
    static func chips(for target: SocialTargetKind, id: UUID, in rows: [ReactionRow], me: Set<UUID>,
                      name: (UUID) -> String?) -> [ReactionChip] {
        let mine = rows.filter { $0.targetKind == target && $0.targetID == id }
        let summary = ReactionSummary.from(mine, me: me)
        let groups = ReactionWho.groups(mine, name: name)
        let names = Dictionary(groups.map { ($0.emoji, $0.names) }, uniquingKeysWith: { a, _ in a })
        return summary.chips(names: names)
    }
}

/// «Hvem har reagert»: navnene per emoji, i brikkenes rekkefølge. Blokkerte er allerede borte (RLS).
nonisolated struct ReactionWhoGroup: Equatable, Identifiable, Sendable {
    let emoji: String
    let names: [String]
    var id: String { emoji }
}

nonisolated enum ReactionWho {
    static func groups(_ rows: [ReactionRow], name: (UUID) -> String?) -> [ReactionWhoGroup] {
        let summary = ReactionSummary.from(rows, me: [])
        return summary.counts.map { c in
            let names = rows.filter { $0.emoji == c.emoji }
                .map { r in r.personID.flatMap(name) ?? "Noen" }
                .sorted(by: NorwegianSort.areInIncreasingOrder)
            return ReactionWhoGroup(emoji: c.emoji, names: names)
        }
    }

    /// Fra brikkene når navnene alt er kjent (den gamle veien).
    static func groups(_ chips: [ReactionChip]) -> [ReactionWhoGroup] {
        chips.filter { !$0.names.isEmpty }.map { ReactionWhoGroup(emoji: $0.emoji, names: $0.names) }
    }
}

// MARK: - Kommentarer

/// En rad i `comments` (sql/050). Slettede står med `deletedAt` og tom tekst.
nonisolated struct CommentRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var clubID: UUID?
    var competitionID: UUID?
    let targetKind: SocialTargetKind
    let targetID: UUID
    var memberID: UUID?
    var profileID: UUID?
    var body: String
    var mentions: [UUID]
    let createdAt: Date
    var editedAt: Date?
    var deletedAt: Date?

    init(id: UUID, clubID: UUID?, targetKind: SocialTargetKind, targetID: UUID, memberID: UUID?,
         profileID: UUID? = nil, body: String, mentions: [UUID] = [], createdAt: Date, editedAt: Date? = nil,
         deletedAt: Date? = nil, competitionID: UUID? = nil) {
        self.id = id
        self.clubID = clubID
        self.competitionID = competitionID
        self.targetKind = targetKind
        self.targetID = targetID
        self.memberID = memberID
        self.profileID = profileID
        self.body = body
        self.mentions = mentions
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.deletedAt = deletedAt
    }

    /// Den som skrev: medlemmet, eller profilen uten klubb.
    var authorID: UUID? { memberID ?? profileID }
    var isDeleted: Bool { deletedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case competitionID = "competition_id"
        case targetKind = "target_kind"
        case targetID = "target_id"
        case memberID = "member_id"
        case profileID = "profile_id"
        case body, mentions
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clubID = try c.decodeIfPresent(UUID.self, forKey: .clubID)
        competitionID = try c.decodeIfPresent(UUID.self, forKey: .competitionID)
        targetKind = try c.decode(SocialTargetKind.self, forKey: .targetKind)
        targetID = try c.decode(UUID.self, forKey: .targetID)
        memberID = try c.decodeIfPresent(UUID.self, forKey: .memberID)
        profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        mentions = (try? c.decodeIfPresent([UUID].self, forKey: .mentions)) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    static let columns = "id, club_id, competition_id, target_kind, target_id, member_id, profile_id, body, mentions, created_at, edited_at, deleted_at"
}

/// Utkastet til en kommentar: 1–1000 tegn etter trimming (`comment_add`).
nonisolated enum CommentDraft {
    static let maxLength = 1000

    enum Check: Equatable {
        case empty
        case tooLong
        case ready(String)
    }

    static func check(_ text: String) -> Check {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.unicodeScalars.count > maxLength { return .tooLong }
        return .ready(trimmed)
    }
}

/// En kommentar slik lista viser den.
nonisolated struct CommentItem: Equatable, Identifiable, Sendable {
    let comment: CommentRow
    let author: String
    /// Teksten, eller «Kommentaren er slettet».
    let text: String
    let isMine: Bool
    let isEdited: Bool
    let canEdit: Bool
    let canDelete: Bool
    let canReport: Bool
    var id: UUID { comment.id }
    var isDeleted: Bool { comment.isDeleted }
}

nonisolated enum CommentList {
    static let deletedText = "Kommentaren er slettet"

    /// Eldste først. Det du har rapportert, skjules for deg (som tråden). Slettede står med
    /// «Kommentaren er slettet», så samtalen henger sammen.
    static func items(_ rows: [CommentRow], me: Set<UUID>, isModerator: Bool, hidden: Set<UUID> = [],
                      name: (UUID) -> String?) -> [CommentItem] {
        rows.filter { !hidden.contains($0.id) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            .map { row in
                let mine = row.authorID.map(me.contains) ?? false
                let live = !row.isDeleted
                return CommentItem(comment: row,
                                   author: row.authorID.flatMap(name) ?? "Noen",
                                   text: live ? row.body : deletedText,
                                   isMine: mine,
                                   isEdited: live && row.editedAt != nil,
                                   canEdit: live && mine,
                                   canDelete: live && (mine || isModerator),
                                   canReport: live && !mine)
            }
    }

    /// Antallet som teller (`feed_page.comment_count`): uten slettede.
    static func count(_ rows: [CommentRow]) -> Int { rows.filter { !$0.isDeleted }.count }

    /// Antall per mål, uten slettede.
    static func counts(_ rows: [CommentRow]) -> [UUID: Int] {
        rows.filter { !$0.isDeleted }.reduce(into: [:]) { $0[$1.targetID, default: 0] += 1 }
    }

    /// Raden etter en endring fra serveren (eller Realtime): byttes ut, eller legges til.
    static func upserting(_ row: CommentRow, into rows: [CommentRow]) -> [CommentRow] {
        var out = rows.filter { $0.id != row.id }
        out.append(row)
        return out
    }
}

/// «Følg tråden»: raden i `thread_follows`, ellers standarden (forfatteren av målet får varsel).
nonisolated enum ThreadFollow {
    static func isFollowing(row: Bool?, isTargetAuthor: Bool) -> Bool {
        row ?? isTargetAuthor
    }
}

/// Feltene i `activity.data` for `comment_added` og `mentioned` (sql/050).
nonisolated struct SocialComment: Equatable, Sendable {
    var targetKind: String?
    var targetID: UUID?
    var commentID: UUID?
    var preview: String?
    var authorName: String?
    var authorProfile: UUID?

    init(targetKind: String? = nil, targetID: UUID? = nil, commentID: UUID? = nil, preview: String? = nil,
         authorName: String? = nil, authorProfile: UUID? = nil) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.commentID = commentID
        self.preview = preview
        self.authorName = authorName
        self.authorProfile = authorProfile
    }

    init(_ d: ActivityData) {
        self.init(targetKind: d.targetKind, targetID: d.targetID, commentID: d.commentID, preview: d.preview,
                  authorName: d.authorName, authorProfile: d.authorProfile)
    }

    var data: ActivityData {
        var d = ActivityData()
        d.targetKind = targetKind
        d.targetID = targetID
        d.commentID = commentID
        d.preview = preview
        d.authorName = authorName
        d.authorProfile = authorProfile
        return d
    }

    /// Målet kommentaren står på, når det er kjent.
    func target(clubID: UUID?) -> SocialTarget? {
        guard let kind = targetKind.flatMap(SocialTargetKind.init), let targetID else { return nil }
        return SocialTarget(kind: kind, id: targetID, clubID: clubID)
    }

    static let previewLength = 80

    /// «Hei, kommer du?» i sitattegn, kortet og på én linje, eller nil når den er tom.
    static func quoted(_ preview: String?) -> String? {
        guard let preview else { return nil }
        let clean = preview.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        let short = clean.count > previewLength ? String(clean.prefix(previewLength - 1)) + "…" : clean
        return "«" + short + "»"
    }
}

/// Bildeoppfordringen (`photo_prompt`).
nonisolated enum PhotoPrompt {
    static let title = "Ta et bilde av gjengen"
    static let line = "Del det i tråden, så har alle det."
    static let action = "Ta bilde"
}

// MARK: - Hjem i sider (`feed_page`)

/// Hvor neste side starter: nøkkelen (created_at, id) for den eldste linja på forrige side.
nonisolated struct FeedCursor: Equatable, Sendable {
    let createdAt: Date
    let id: UUID

    init(createdAt: Date, id: UUID) {
        self.createdAt = createdAt
        self.id = id
    }

    init?(last rows: [ActivityRow]) {
        guard let last = FeedPaging.sorted(rows).last else { return nil }
        self.init(createdAt: last.createdAt, id: last.id)
    }

    /// Tiden som sendes som `p_before_ts`, med mikrosekunder. En `Date` kan ligge en brøkdel under
    /// databasens tid, så den rundes opp til neste mikrosekund: da kommer heller den siste linja
    /// én gang til (og fjernes som duplikat) enn at en linje i samme øyeblikk hoppes over.
    var timestamp: String {
        let micros = (createdAt.timeIntervalSince1970 * 1_000_000).rounded(.down) + 1
        let seconds = (micros / 1_000_000).rounded(.down)
        let fraction = Int(micros - seconds * 1_000_000)
        let date = Date(timeIntervalSince1970: seconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, fraction)
    }
}

nonisolated enum FeedPaging {
    /// Linjer per side. `feed_page` tar 1–100.
    static let pageSize = 40

    /// Nyest først, som `feed_page` (created_at, så id).
    static func isNewer(_ a: ActivityRow, _ b: ActivityRow) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.uuidString > b.id.uuidString
    }

    static func sorted(_ rows: [ActivityRow]) -> [ActivityRow] { rows.sorted(by: isNewer) }

    /// Neste side lagt til: uten duplikater, nyest først.
    static func appending(_ page: [ActivityRow], to rows: [ActivityRow]) -> [ActivityRow] {
        let known = Set(rows.map(\.id))
        return sorted(rows + page.filter { !known.contains($0.id) })
    }

    /// Første side hentet på nytt (Realtime, dra ned): den erstatter det den dekker, og eldre sider
    /// som alt er hentet, blir stående. Er første side hele feeden, er det bare den.
    static func refreshed(first page: [ActivityRow], limit: Int, existing: [ActivityRow]) -> [ActivityRow] {
        let fresh = sorted(page)
        guard fresh.count >= limit, let oldest = fresh.last else { return fresh }
        let ids = Set(fresh.map(\.id))
        let older = existing.filter { !ids.contains($0.id) && isNewer(oldest, $0) }
        return sorted(fresh + older)
    }

    /// Er det mer å hente etter en side med `count` linjer?
    static func hasMore(pageCount count: Int, limit: Int) -> Bool { count >= limit }
}

/// En linje fra `feed_page`: hendelsen, reaksjonene, dine og antall kommentarer.
nonisolated struct FeedPageRow: Decodable, Sendable {
    let activity: ActivityRow
    let reactions: [ReactionCount]
    let myReactions: [String]
    let commentCount: Int

    enum CodingKeys: String, CodingKey {
        case reactions
        case myReactions = "my_reactions"
        case commentCount = "comment_count"
    }

    init(activity: ActivityRow, reactions: [ReactionCount] = [], myReactions: [String] = [], commentCount: Int = 0) {
        self.activity = activity
        self.reactions = reactions
        self.myReactions = myReactions
        self.commentCount = commentCount
    }

    init(from decoder: any Decoder) throws {
        activity = try ActivityRow(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reactions = (try? c.decodeIfPresent([ReactionCount].self, forKey: .reactions)) ?? []
        myReactions = (try? c.decodeIfPresent([String].self, forKey: .myReactions)) ?? []
        commentCount = (try? c.decodeIfPresent(Int.self, forKey: .commentCount)) ?? 0
    }

    var social: ActivitySocial {
        ActivitySocial(summary: ReactionSummary(counts: reactions, mine: myReactions), commentCount: commentCount)
    }
}

/// Reaksjonene og kommentarene på én hendelse i feeden (050).
nonisolated struct ActivitySocial: Equatable, Sendable {
    var summary: ReactionSummary
    var commentCount: Int
}
