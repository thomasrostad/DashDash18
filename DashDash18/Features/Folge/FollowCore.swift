import Foundation
import GolfgutuCore

// Følge andre spillere (steg 13, sql/054, docs/folge.md). Ren logikk uten nettverk og SwiftUI:
// statusen og knappen, listene fra `my_follows`, søketeksten, QR-lenken, sidene i «Følger» og
// tekstene i varslene.

// MARK: - Status og knappen

/// Min følgestatus mot en person (`search_people.my_status`, `follows.status`).
nonisolated enum FollowStatus: String, Codable, Sendable, Equatable {
    case none
    case pending
    case accepted

    /// Ukjent tekst fra serveren leses som `none`.
    init(server: String?) {
        self = server.flatMap(FollowStatus.init(rawValue:)) ?? .none
    }
}

/// Hvor en følging kom fra (`follows.source`).
nonisolated enum FollowSource: String, Codable, Sendable {
    case search
    case qr
    case round
    case link
    case suggestion
}

/// Knappen Følg / Venter / Følger, og hva et trykk gjør. Ren tilstandsmaskin.
nonisolated enum FollowButton {
    enum Action: Equatable, Sendable {
        /// `follow_request`.
        case request
        /// Trekk forespørselen (`follow_remove`).
        case cancel
        /// Slutt å følge (`follow_remove`), etter bekreftelse.
        case unfollow
    }

    /// `followsMe`: personen følger deg, så «Følg» blir «Følg tilbake».
    static func title(_ status: FollowStatus, followsMe: Bool = false) -> String {
        switch status {
        case .none: followsMe ? "Følg tilbake" : "Følg"
        case .pending: "Venter"
        case .accepted: "Følger"
        }
    }

    static func action(_ status: FollowStatus) -> Action {
        switch status {
        case .none: .request
        case .pending: .cancel
        case .accepted: .unfollow
        }
    }

    /// Statusen etter svaret fra serveren. `follow_request` svarer `pending` eller `accepted`;
    /// `follow_remove` svarer om noe ble fjernet (begge gir `none`).
    static func after(_ action: Action, answer: String?) -> FollowStatus {
        switch action {
        case .request: FollowStatus(server: answer) == .accepted ? .accepted : .pending
        case .cancel, .unfollow: .none
        }
    }
}

// MARK: - Listene (`my_follows`)

/// Én rad fra `my_follows()`.
nonisolated struct FollowRow: Codable, Equatable, Identifiable, Sendable {
    enum Direction: String, Codable, Sendable {
        /// Jeg følger (pending = jeg venter på svar).
        case following
        /// Følger meg (pending = forespørsel til meg).
        case follower
    }

    let profileID: UUID
    let displayName: String
    var avatarPath: String?
    let direction: Direction
    let status: FollowStatus
    var source: String?
    var createdAt: Date?
    var acceptedAt: Date?

    var id: String { direction.rawValue + profileID.uuidString }

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case direction, status, source
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
    }
}

/// Følger, følgere og forespørsler, slik Deg viser dem.
nonisolated struct FollowLists: Equatable, Sendable {
    /// Forespørsler til meg (øverst, med Godta og Avslå).
    let requests: [FollowRow]
    /// Godtatte følgere.
    let followers: [FollowRow]
    /// Dem jeg følger, og dem jeg venter på svar fra.
    let following: [FollowRow]

    init(_ rows: [FollowRow]) {
        func sorted(_ list: [FollowRow]) -> [FollowRow] {
            list.sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
        }
        requests = rows.filter { $0.direction == .follower && $0.status == .pending }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        followers = sorted(rows.filter { $0.direction == .follower && $0.status == .accepted })
        // Godtatte først, så de som venter.
        following = sorted(rows.filter { $0.direction == .following && $0.status == .accepted })
            + sorted(rows.filter { $0.direction == .following && $0.status == .pending })
    }

    static let empty = FollowLists([])

    /// Antallet jeg følger (godtatt).
    var followingCount: Int { following.filter { $0.status == .accepted }.count }
    var followerCount: Int { followers.count }

    /// Min status mot personen.
    func status(of profile: UUID) -> FollowStatus {
        following.first { $0.profileID == profile }?.status ?? .none
    }

    /// Følger personen meg (godtatt)?
    func followsMe(_ profile: UUID) -> Bool {
        followers.contains { $0.profileID == profile }
    }

    /// Status for «Følg tilbake»: personen følger meg, og jeg følger ikke tilbake ennå (`none`) eller
    /// venter på svar (`pending`). nil: de følger meg ikke, eller jeg følger dem alt.
    func followBackStatus(_ profile: UUID) -> FollowStatus? {
        guard followsMe(profile) else { return nil }
        let mine = status(of: profile)
        return mine == .accepted ? nil : mine
    }

    /// Dem jeg følger (godtatt), for «Ny runde» og turneringer.
    var followingIDs: Set<UUID> { Set(following.filter { $0.status == .accepted }.map(\.profileID)) }

    /// «Du følger 12 · 30 følgere».
    var countsText: String {
        "Du følger \(followingCount) · \(followerCount) " + (followerCount == 1 ? "følger" : "følgere")
    }
}

// MARK: - Søk

/// Søketeksten i «Finn spillere»: minst 3 tegn og høyst 40 (`search_people`).
nonisolated enum PeopleSearchQuery: Equatable, Sendable {
    case empty
    case tooShort
    case tooLong
    case ready(String)

    static let minLength = 3
    static let maxLength = 40
    /// Venting før kallet, så hvert tastetrykk ikke blir et søk (60 i timen).
    static let debounce: Duration = .milliseconds(400)

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = trimmed.count
        if count == 0 { self = .empty }
        else if count < Self.minLength { self = .tooShort }
        else if count > Self.maxLength { self = .tooLong }
        else { self = .ready(trimmed) }
    }

    /// Teksten under feltet, eller nil når søket kan gå.
    var hint: String? {
        switch self {
        case .empty, .tooShort: "Skriv minst tre bokstaver."
        case .tooLong: "Høyst 40 tegn."
        case .ready: nil
        }
    }
}

/// Én rad fra `search_people`.
nonisolated struct PersonSearchRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    var avatarPath: String?
    var clubName: String?
    var myStatus: FollowStatus
    var followsMe: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case clubName = "club_name"
        case myStatus = "my_status"
        case followsMe = "follows_me"
    }

    init(id: UUID, displayName: String, avatarPath: String? = nil, clubName: String? = nil,
         myStatus: FollowStatus = .none, followsMe: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.clubName = clubName
        self.myStatus = myStatus
        self.followsMe = followsMe
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Spiller"
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        myStatus = FollowStatus(server: try c.decodeIfPresent(String.self, forKey: .myStatus))
        followsMe = try c.decodeIfPresent(Bool.self, forKey: .followsMe) ?? false
    }

    /// Linja under navnet: klubben og «Følger deg».
    var subtitle: String? {
        let parts = [clubName?.trimmingCharacters(in: .whitespaces), followsMe ? "Følger deg" : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - QR-koden og lenken

/// Følgekoden (`follow_code`): 8 tegn fra 32 uten I, O, 0 og 1. QR-koden er lenken
/// `https://dashdash18.com/folg/<KODE>`; appen godtar også `dashdash://folg/<KODE>` og koden alene.
nonisolated struct FollowLink: Equatable, Hashable, Identifiable, Sendable {
    static let host = "folg"
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 8

    let code: String
    var id: String { code }

    /// Koden renset (store bokstaver, uten mellomrom og bindestrek), eller nil når den ikke kan være en kode.
    init?(code raw: String) {
        let cleaned = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == Self.length, cleaned.allSatisfy(Self.alphabet.contains) else { return nil }
        code = cleaned
    }

    /// Fra en lenke (`https://dashdash18.com/folg/KODE`, `dashdash://folg/KODE`).
    init?(url: URL) {
        let parts: [String]
        switch url.scheme?.lowercased() {
        case "https", "http":
            guard let host = url.host()?.lowercased(), UniversalLink.hosts.contains(host) else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        case InviteCode.scheme:
            guard url.host()?.lowercased() == Self.host else { return nil }
            parts = [Self.host] + url.pathComponents.filter { $0 != "/" }
        default:
            return nil
        }
        guard parts.count == 2, parts[0].lowercased() == Self.host else { return nil }
        self.init(code: parts[1])
    }

    /// Det en skanner leser: en lenke, eller koden alene.
    init?(scanned text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            self.init(url: url)
        } else {
            self.init(code: trimmed)
        }
    }

    /// Lenken i QR-koden.
    var url: URL { UniversalLink.url(path: Self.host, code: code) }

    /// «ABCD-EFGH», lettere å lese opp.
    var display: String { String(code.prefix(4)) + "-" + String(code.suffix(4)) }
}

/// Svaret fra `follow_by_code`.
nonisolated struct FollowByCodeResult: Codable, Equatable, Sendable {
    var profileID: UUID?
    var displayName: String?
    var avatarPath: String?
    var status: String
    var already: Bool?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case status, already
    }

    var isNotFound: Bool { status == "not_found" || profileID == nil }

    /// Teksten etter skanningen.
    var message: String {
        if isNotFound { return "Fant ikke koden." }
        let name = followTrimmed(displayName) ?? "personen"
        return already == true ? "Du følger allerede \(name)." : "Du følger nå \(name)."
    }
}

// MARK: - Feil

/// De norske feilene fra 054 (`54000` er grensen, `P0002` fant ikke personen). `FollowService`
/// gir feilkoden fra Postgres.
nonisolated enum FollowError {
    static let rateLimited = "Prøv igjen om litt. Du har nådd grensen for nå."

    static func message(_ error: DataError, code: String?) -> String {
        switch code {
        case "54000": rateLimited
        case "P0002": "Fant ikke personen."
        default: error.message
        }
    }
}

// MARK: - «Følger»-fanen (`following_feed_page`)

/// Ett kort i «Følger»: en ferdig runde fra en du følger, eller din egen.
nonisolated struct FollowingCard: Codable, Equatable, Identifiable, Sendable {
    struct Hole: Codable, Equatable, Sendable {
        let hole: Int
        var par: Int?
        var strokeIndex: Int?
        var strokes: Int?
    }

    struct Reaction: Codable, Equatable, Sendable {
        let emoji: String
        let count: Int
    }

    /// Hendelsen (`activity.id`): målet for reaksjoner og kommentarer.
    let id: UUID
    var roundID: UUID?
    let createdAt: Date
    let profileID: UUID
    var displayName: String?
    var avatarPath: String?
    var isMine: Bool
    /// `YYYY-MM-DD`.
    var playedOn: String?
    var courseName: String?
    var holeCount: Int?
    var strokes: Int?
    var holesPlayed: Int?
    var toPar: Int?
    var holes: [Hole]
    var reactions: [Reaction]
    var myReactions: [String]
    var commentCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case createdAt = "created_at"
        case profileID = "profile_id"
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case isMine = "is_mine"
        case playedOn = "played_on"
        case courseName = "course_name"
        case holeCount = "hole_count"
        case strokes
        case holesPlayed = "holes_played"
        case toPar = "to_par"
        case holes, reactions
        case myReactions = "my_reactions"
        case commentCount = "comment_count"
    }

    init(id: UUID, createdAt: Date, profileID: UUID, displayName: String?, isMine: Bool = false,
         playedOn: String? = nil, courseName: String? = nil, holeCount: Int? = nil, strokes: Int? = nil,
         holesPlayed: Int? = nil, toPar: Int? = nil, holes: [Hole] = [], reactions: [Reaction] = [],
         myReactions: [String] = [], commentCount: Int = 0) {
        self.id = id
        self.createdAt = createdAt
        self.profileID = profileID
        self.displayName = displayName
        self.isMine = isMine
        self.playedOn = playedOn
        self.courseName = courseName
        self.holeCount = holeCount
        self.strokes = strokes
        self.holesPlayed = holesPlayed
        self.toPar = toPar
        self.holes = holes
        self.reactions = reactions
        self.myReactions = myReactions
        self.commentCount = commentCount
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roundID = try c.decodeIfPresent(UUID.self, forKey: .roundID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        isMine = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
        playedOn = try c.decodeIfPresent(String.self, forKey: .playedOn)
        courseName = try c.decodeIfPresent(String.self, forKey: .courseName)
        holeCount = try c.decodeIfPresent(Int.self, forKey: .holeCount)
        strokes = try c.decodeIfPresent(Int.self, forKey: .strokes)
        holesPlayed = try c.decodeIfPresent(Int.self, forKey: .holesPlayed)
        toPar = try c.decodeIfPresent(Int.self, forKey: .toPar)
        holes = (try? c.decodeIfPresent([Hole].self, forKey: .holes)) ?? []
        reactions = (try? c.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
        myReactions = (try? c.decodeIfPresent([String].self, forKey: .myReactions)) ?? []
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }

    var name: String { LooseRoundInfo.name(displayName) }

    /// «+3», «E» eller «-2» (til par for hullene som er spilt).
    var toParText: String? {
        guard let toPar else { return nil }
        if toPar == 0 { return "E" }
        return toPar > 0 ? "+\(toPar)" : "\(toPar)"
    }

    /// «Bjaavann · 9 hull» med datoen først når den finnes.
    var subtitle: String {
        var parts: [String] = []
        if let playedOn { parts.append(EveningDates.longText(playedOn)) }
        if let courseName, !courseName.isEmpty { parts.append(courseName) }
        if let holesPlayed, let holeCount, holesPlayed < holeCount {
            parts.append("\(holesPlayed) av \(holeCount) hull")
        } else if let holeCount {
            parts.append("\(holeCount) hull")
        }
        return parts.joined(separator: " · ")
    }

    /// Brikkene under kortet (reaksjonene med antall, mine merket).
    var chips: [ReactionChip] {
        reactions.map { ReactionChip(emoji: $0.emoji, count: $0.count, isMine: myReactions.contains($0.emoji)) }
    }

    /// Kortet etter at jeg har slått en reaksjon av eller på (vises med en gang).
    func toggling(_ emoji: String) -> FollowingCard {
        var copy = self
        if let i = copy.myReactions.firstIndex(of: emoji) {
            copy.myReactions.remove(at: i)
            if let r = copy.reactions.firstIndex(where: { $0.emoji == emoji }) {
                let left = copy.reactions[r].count - 1
                if left > 0 { copy.reactions[r] = Reaction(emoji: emoji, count: left) } else { copy.reactions.remove(at: r) }
            }
        } else {
            copy.myReactions.append(emoji)
            if let r = copy.reactions.firstIndex(where: { $0.emoji == emoji }) {
                copy.reactions[r] = Reaction(emoji: emoji, count: copy.reactions[r].count + 1)
            } else {
                copy.reactions.append(Reaction(emoji: emoji, count: 1))
            }
        }
        return copy
    }
}

/// Sidene i «Følger»: nyeste først, neste side fra den eldste (created_at, id).
nonisolated struct FollowingFeedPages: Equatable, Sendable {
    static let pageSize = 30

    private(set) var cards: [FollowingCard] = []
    private(set) var hasMore = false

    /// Der neste side starter.
    var cursor: FeedCursor? {
        cards.last.map { FeedCursor(createdAt: $0.createdAt, id: $0.id) }
    }

    /// Første side (erstatter alt).
    mutating func reset(_ page: [FollowingCard], limit: Int = pageSize) {
        cards = Self.ordered(page)
        hasMore = page.count >= limit
    }

    /// Neste side, uten dubletter.
    mutating func append(_ page: [FollowingCard], limit: Int = pageSize) {
        let known = Set(cards.map(\.id))
        cards = Self.ordered(cards + page.filter { !known.contains($0.id) })
        hasMore = page.count >= limit
    }

    mutating func replace(_ card: FollowingCard) {
        if let i = cards.firstIndex(where: { $0.id == card.id }) { cards[i] = card }
    }

    mutating func setCommentCount(_ count: Int, on id: UUID) {
        if let i = cards.firstIndex(where: { $0.id == id }) { cards[i].commentCount = count }
    }

    static func ordered(_ cards: [FollowingCard]) -> [FollowingCard] {
        cards.sorted { a, b in
            a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.uuidString > b.id.uuidString
        }
    }
}

// MARK: - Varslene (personlige linjer)

/// En personlig linje i `activity` (uten klubb og turnering, sql/054): følging og kommentarer på
/// et kort i «Følger». `round_finished` vises bare i «Følger», aldri som varsel.
nonisolated struct PersonalActivity: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: String
    var actorProfileID: UUID?
    var recipients: [UUID]?
    var data: PersonalActivityData
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, recipients, data
        case actorProfileID = "actor_profile_id"
        case createdAt = "created_at"
    }

    init(id: UUID, kind: String, actorProfileID: UUID?, recipients: [UUID]? = nil,
         data: PersonalActivityData = PersonalActivityData(), createdAt: Date) {
        self.id = id
        self.kind = kind
        self.actorProfileID = actorProfileID
        self.recipients = recipients
        self.data = data
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        actorProfileID = try c.decodeIfPresent(UUID.self, forKey: .actorProfileID)
        recipients = try c.decodeIfPresent([UUID].self, forKey: .recipients)
        data = (try? c.decodeIfPresent(PersonalActivityData.self, forKey: .data)) ?? PersonalActivityData()
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    /// Kindene som vises som varsel.
    static let notificationKinds = ["follow_requested", "follow_accepted", "followed", "comment_added", "mentioned"]
    static let columns = "id, kind, actor_profile_id, recipients, data, created_at"

    var isFollowRequest: Bool { kind == "follow_requested" }

    /// Kortet en kommentar gjelder (`activity`).
    var cardID: UUID? {
        guard kind == "comment_added" || kind == "mentioned", data.targetKind == "activity" else { return nil }
        return data.targetID
    }
}

nonisolated struct PersonalActivityData: Codable, Equatable, Sendable {
    var actorName: String?
    var source: String?
    var targetKind: String?
    var targetID: UUID?
    var preview: String?
    var authorName: String?

    init(actorName: String? = nil, source: String? = nil, targetKind: String? = nil, targetID: UUID? = nil,
         preview: String? = nil, authorName: String? = nil) {
        self.actorName = actorName
        self.source = source
        self.targetKind = targetKind
        self.targetID = targetID
        self.preview = preview
        self.authorName = authorName
    }

    enum CodingKeys: String, CodingKey {
        case actorName = "actor_name"
        case source
        case targetKind = "target_kind"
        case targetID = "target_id"
        case preview
        case authorName = "author_name"
    }
}

nonisolated enum PersonalActivityText {
    /// Teksten i Varsler. Samme ord som push-send (`activityDisplay`). nil: vises ikke som varsel.
    static func display(_ row: PersonalActivity) -> ActivityDisplay? {
        let actor = followTrimmed(row.data.actorName) ?? "Noen"
        let author = followTrimmed(row.data.authorName) ?? actor
        let quote = SocialComment.quoted(row.data.preview).map { ": " + $0 } ?? ""
        switch row.kind {
        case "follow_requested":
            return ActivityDisplay(symbol: "person.badge.plus", emoji: "👋", text: "\(actor) vil følge deg")
        case "follow_accepted":
            return ActivityDisplay(symbol: "person.crop.circle.badge.checkmark", emoji: "✅",
                                   text: "\(actor) godtok forespørselen din")
        case "followed":
            return ActivityDisplay(symbol: "person.badge.plus", emoji: "👋", text: "\(actor) følger deg nå")
        case "comment_added":
            return ActivityDisplay(symbol: "bubble.left.fill", emoji: "💬", text: "\(author) kommenterte runden" + quote)
        case "mentioned":
            return ActivityDisplay(symbol: "at", emoji: "💬", text: "\(author) nevnte deg" + quote)
        default:
            return nil
        }
    }

    /// Personen som kan få «Følg tilbake» i varselet: «X vil følge deg» når du har godtatt, og
    /// «X følger deg nå». nil: forespørselen venter fortsatt, eller du følger dem alt.
    static func followBack(_ row: PersonalActivity, lists: FollowLists) -> UUID? {
        guard row.kind == "follow_requested" || row.kind == "followed", let actor = row.actorProfileID,
              lists.followBackStatus(actor) != nil else { return nil }
        return actor
    }

    /// Linjene som vises (nyeste først), uten mine egne og uten `round_finished`.
    static func notifications(_ rows: [PersonalActivity], me: UUID) -> [PersonalActivity] {
        rows.filter { row in
            row.actorProfileID != me && display(row) != nil && (row.recipients?.contains(me) ?? false)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    /// Uleste: nyere enn sist sett.
    static func unreadCount(_ rows: [PersonalActivity], me: UUID, lastSeen: Date?) -> Int {
        notifications(rows, me: me).filter { row in lastSeen.map { row.createdAt > $0 } ?? true }.count
    }
}

// MARK: - «Ny runde» og turneringer

nonisolated enum FollowOrdering {
    /// Dem jeg følger først, så resten; norsk navnerekkefølge innen hver del.
    static func followedFirst(_ rows: [ProfileRow], following: Set<UUID>) -> [ProfileRow] {
        let name = { (row: ProfileRow) in row.displayName ?? "" }
        let sorted = rows.sorted { NorwegianSort.areInIncreasingOrder(name($0), name($1)) }
        return sorted.filter { following.contains($0.id) } + sorted.filter { !following.contains($0.id) }
    }
}

/// Teksten uten mellomrom rundt, eller nil når den er tom.
nonisolated func followTrimmed(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}
