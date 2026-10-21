import Foundation
import Supabase

// Rapporter og blokker (App Store 1.2, brukerinnhold). Skjemaet er sql/019: `content_reports`,
// `user_blocks`, `report_content`, `block_user`, `my_blocks` og `resolve_report`.

/// Hva som rapporteres (`content_reports.kind`).
nonisolated enum ReportKind: String, Codable, Sendable {
    case message
    case image
    case member
    case profile
    /// En kommentar (sql/050).
    case comment
    /// En bane i det felles biblioteket som en annen har lagt inn (sql/066).
    case course
    /// En turnering i «Finn turneringer» (sql/066).
    case competition

    var title: String {
        switch self {
        case .message: "Rapporter meldingen"
        case .image: "Rapporter bildet"
        case .member: "Rapporter navnet"
        case .profile: "Rapporter profilen"
        case .comment: "Rapporter kommentaren"
        case .course: "Rapporter banen"
        case .competition: "Rapporter turneringen"
        }
    }

    /// Kort, i lista for arrangøren.
    var label: String {
        switch self {
        case .message: "Melding"
        case .image: "Bilde"
        case .member: "Navn i troppen"
        case .profile: "Profil"
        case .comment: "Kommentar"
        case .course: "Bane"
        case .competition: "Turnering"
        }
    }

    /// Ser en arrangør rapporten? Baner og offentlige turneringer har ingen arrangør over seg
    /// (klubbens arrangør står bak turneringen), så de går bare til oss (sql/066).
    var reachesOrganizer: Bool {
        switch self {
        case .course, .competition: false
        default: true
        }
    }

    /// Takken etter at rapporten er sendt.
    var sentText: String {
        reachesOrganizer
            ? "Takk. Rapporten er sendt til arrangøren og oss, og vi ser på den innen 24 timer."
            : "Takk. Rapporten er sendt til oss, og vi ser på den innen 24 timer."
    }
}

/// Grunnen (`content_reports.reason`), i den rekkefølgen den vises.
nonisolated enum ReportReason: String, CaseIterable, Codable, Identifiable, Sendable {
    case offensive
    case harassment
    case spam
    case inappropriateImage = "inappropriate_image"
    case impersonation
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .offensive: "Støtende eller hatefullt"
        case .harassment: "Trakassering eller mobbing"
        case .spam: "Spam eller reklame"
        case .inappropriateImage: "Upassende bilde"
        case .impersonation: "Utgir seg for å være en annen"
        case .other: "Noe annet"
        }
    }

    /// Grunnene som passer for typen innhold: bildegrunnen for bilder, navn og profiler, og
    /// «utgir seg for» bare for navn, profiler og turneringer (en turnering kan late som den er en
    /// annen klubbs).
    static func options(for kind: ReportKind) -> [ReportReason] {
        allCases.filter { reason in
            switch reason {
            case .inappropriateImage: kind == .image || kind == .member || kind == .profile
            case .impersonation: kind == .member || kind == .profile || kind == .competition
            default: true
            }
        }
    }
}

nonisolated enum ReportStatus: String, Codable, Sendable {
    case open
    case removed
    case dismissed

    var label: String {
        switch self {
        case .open: "Åpen"
        case .removed: "Fjernet"
        case .dismissed: "Avvist"
        }
    }
}

/// Én rapport slik arrangøren (eller den som rapporterte) ser den.
nonisolated struct ContentReportRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: ReportKind
    let targetID: UUID
    var clubID: UUID?
    var reason: ReportReason
    var note: String?
    var snapshot: String?
    var status: ReportStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, reason, note, snapshot, status
        case targetID = "target_id"
        case clubID = "club_id"
        case createdAt = "created_at"
    }

    static let columns = "id, kind, target_id, club_id, reason, note, snapshot, status, created_at"
}

/// Rapportene som én sak per innhold: flere som rapporterer samme melding, vises én gang.
nonisolated struct ReportCase: Equatable, Identifiable, Sendable {
    let first: ContentReportRow
    let count: Int
    let reasons: [ReportReason]
    var id: UUID { first.id }

    /// Åpne saker, eldste først (Apple: følg opp innen 24 timer).
    static func open(_ rows: [ContentReportRow]) -> [ReportCase] {
        let open = rows.filter { $0.status == .open }
        // Tekst og bilde i samme melding er samme sak.
        func key(_ r: ContentReportRow) -> String {
            (r.kind == .image ? ReportKind.message.rawValue : r.kind.rawValue) + r.targetID.uuidString
        }
        var order: [String] = []
        var groups: [String: [ContentReportRow]] = [:]
        for row in open.sorted(by: { $0.createdAt < $1.createdAt }) {
            let k = key(row)
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(row)
        }
        return order.map { k in
            let rows = groups[k]!
            var reasons: [ReportReason] = []
            for r in rows where !reasons.contains(r.reason) { reasons.append(r.reason) }
            return ReportCase(first: rows[0], count: rows.count, reasons: reasons)
        }
    }

    /// Timer siden første rapport, for «Svar innen 24 timer».
    func hoursOpen(now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(first.createdAt) / 3600))
    }
}

/// Én blokkering (`my_blocks()`).
nonisolated struct BlockedUser: Codable, Equatable, Identifiable, Sendable {
    let blockedID: UUID
    let displayName: String
    var createdAt: Date?

    var id: UUID { blockedID }

    enum CodingKeys: String, CodingKey {
        case blockedID = "blocked_id"
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

/// Hva som skjules i tråden med en gang (før serveren har svart, og for den som rapporterte).
nonisolated struct ModerationFilter: Equatable, Sendable {
    /// Innlogginger du har blokkert.
    var blockedUsers: Set<UUID> = []
    /// Meldinger du har rapportert. De skjules for deg til arrangøren har sett på dem.
    var reportedMessages: Set<UUID> = []

    /// Skal meldingen vises? `userForMember` er troppen (medlem → innlogging).
    func shows(messageID: UUID, memberID: UUID, userForMember: [UUID: UUID]) -> Bool {
        if reportedMessages.contains(messageID) { return false }
        if let user = userForMember[memberID], blockedUsers.contains(user) { return false }
        return true
    }
}

/// Hvem som kan blokkeres. `block_user` trenger en innlogging bak navnet: et klubbnavn uten
/// innlogging (lagt inn av arrangøren, eller kontoen er slettet) kan rapporteres, men ikke blokkeres.
nonisolated enum BlockRules {
    /// Medlemmet i tråden. `userForMember` er troppen (medlem → innlogging).
    static func canBlock(memberID: UUID, userForMember: [UUID: UUID]) -> Bool {
        userForMember[memberID] != nil
    }

    /// Forfatteren av en kommentar: et medlem med innlogging, eller en profil (alltid en innlogging).
    /// `membersWithLogin` nil: troppen er ikke kjent, og medlemmet antas å ha innlogging (den som
    /// kommenterer, er logget inn).
    static func canBlock(memberID: UUID?, profileID: UUID?, membersWithLogin: Set<UUID>?) -> Bool {
        if let memberID { return membersWithLogin?.contains(memberID) ?? true }
        return profileID != nil
    }
}

/// Det du har rapportert og som ikke er avvist (`my_hidden_content`, sql/066). Skjules for deg i
/// banebiblioteket og i «Finn turneringer», slik rapporterte meldinger skjules i tråden.
nonisolated struct HiddenContent: Equatable, Sendable {
    var courses: Set<UUID> = []
    var competitions: Set<UUID> = []

    struct Row: Decodable, Equatable, Sendable {
        let kind: String
        let targetID: UUID

        enum CodingKeys: String, CodingKey {
            case kind
            case targetID = "target_id"
        }
    }

    init(courses: Set<UUID> = [], competitions: Set<UUID> = []) {
        self.courses = courses
        self.competitions = competitions
    }

    /// Radene fra serveren. Ukjente typer hoppes over.
    init(rows: [Row]) {
        for row in rows {
            switch ReportKind(rawValue: row.kind) {
            case .course: courses.insert(row.targetID)
            case .competition: competitions.insert(row.targetID)
            default: break
            }
        }
    }

    /// Legger til det som nettopp er rapportert, så det forsvinner med en gang.
    mutating func insert(_ kind: ReportKind, _ id: UUID) {
        switch kind {
        case .course: courses.insert(id)
        case .competition: competitions.insert(id)
        default: break
        }
    }

    /// Begge settene sammen.
    func merging(_ other: HiddenContent) -> HiddenContent {
        HiddenContent(courses: courses.union(other.courses), competitions: competitions.union(other.competitions))
    }
}

/// Kallene mot Supabase.
nonisolated struct ModerationService: Sendable {
    let client: SupabaseClient

    func report(kind: ReportKind, targetID: UUID, reason: ReportReason, note: String?) async throws -> UUID {
        struct Params: Encodable {
            let p_kind: String
            let p_target_id: UUID
            let p_reason: String
            let p_note: String?
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await client.rpc("report_content", params: Params(
            p_kind: kind.rawValue, p_target_id: targetID, p_reason: reason.rawValue,
            p_note: trimmed?.isEmpty == false ? trimmed : nil
        )).execute().value
    }

    /// Blokker innloggingen bak et klubbmedlem (tråden) eller en profil. Gir innloggingen tilbake.
    func block(memberID: UUID? = nil, profileID: UUID? = nil) async throws -> UUID {
        struct Params: Encodable {
            let p_profile_id: UUID?
            let p_member_id: UUID?
        }
        return try await client.rpc("block_user", params: Params(p_profile_id: profileID, p_member_id: memberID))
            .execute().value
    }

    func unblock(_ userID: UUID) async throws {
        try await client.from("user_blocks").delete().eq("blocked_id", value: userID).execute()
    }

    /// Baner og turneringer du har rapportert (sql/066). Tomt når `PublicContentReportFeature` er av.
    func hiddenContent() async throws -> HiddenContent {
        guard PublicContentReportFeature.isEnabled else { return HiddenContent() }
        struct Params: Encodable { let p_kinds: [String] }
        let rows: [HiddenContent.Row] = try await client.rpc("my_hidden_content", params: Params(
            p_kinds: [ReportKind.course.rawValue, ReportKind.competition.rawValue]
        )).execute().value
        return HiddenContent(rows: rows)
    }

    func myBlocks() async throws -> [BlockedUser] {
        try await client.rpc("my_blocks").execute().value
    }

    func clubReports(clubID: UUID) async throws -> [ContentReportRow] {
        try await client.from("content_reports")
            .select(ContentReportRow.columns)
            .eq("club_id", value: clubID)
            .order("created_at")
            .execute().value
    }

    struct Resolution: Decodable, Sendable {
        let status: ReportStatus
        let imagePath: String?

        enum CodingKeys: String, CodingKey {
            case status
            case imagePath = "image_path"
        }
    }

    /// Fjern innholdet eller avvis. Et bilde som fjernes, slettes også fra Storage.
    func resolve(_ reportID: UUID, remove: Bool) async throws -> Resolution {
        struct Params: Encodable {
            let p_report_id: UUID
            let p_action: String
        }
        let result: Resolution = try await client.rpc("resolve_report", params: Params(
            p_report_id: reportID, p_action: remove ? "remove" : "dismiss"
        )).execute().value
        if let path = result.imagePath {
            _ = try? await client.storage.from(TradImagePath.bucket).remove(paths: [path])
        }
        return result
    }

    func acceptTerms(version: String = LegalLinks.termsVersion) async throws {
        struct Params: Encodable { let p_version: String }
        try await client.rpc("accept_terms", params: Params(p_version: version)).execute()
    }
}
