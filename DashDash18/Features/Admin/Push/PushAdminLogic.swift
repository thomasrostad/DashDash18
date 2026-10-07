import Foundation
import GolfgutuCore

// Arrangørens push-skjermer (fase 8, `sql/010_push.sql`): «Hva blir push» for hele klubben
// og «Hvem har push». Ren logikk uten SwiftUI og nettverk, så alt kan testes isolert.

// MARK: - Hva blir push

/// En bryter i «Hva blir push». `key` er id-en i `clubs.push_disabled_categories`
/// (samme som `activity.category`, pluss `thread`).
nonisolated struct ClubPushToggle: Equatable, Identifiable, Sendable {
    let key: String
    let title: String
    let subtitle: String

    var id: String { key }
}

nonisolated enum ClubPushPlan {
    /// Bryterne arrangøren ser, i samme rekkefølge som spillerens innstillinger, pluss tråden.
    /// Bare kategorier fra `push_club_categories()`, så purring og «Melding til alle» er ute.
    /// Veddemål (`bet`) venter til fase 10, som hos spilleren.
    static let toggles: [ClubPushToggle] =
        PushCategories.shownToPlayer
            .filter { PushCategories.clubToggleable.contains($0) }
            .map { ClubPushToggle(key: $0.rawValue, title: $0.title, subtitle: PushCategories.subtitle($0)) }
        + [ClubPushToggle(key: PushCategories.threadKey, title: "Kveldens tråd", subtitle: "Meldinger i tråden, også når noen nevnes")]

    /// Kategoriene som alltid går som push og ikke kan slås av for klubben (PWA: ALLTID).
    static let locked: [ActivityCategory] = ActivityCategory.allCases.filter {
        !PushCategories.clubToggleable.contains($0)
    }

    static let lockedReason = "Går alltid som push. Arrangøren sender dem selv."

    static let footer = "Linja står alltid i Varsler i appen. Det er bare pushen til telefonen som stoppes. "
        + "Hver spiller kan i tillegg slå av det de ikke vil ha under Deg → Varsler."

    static func isOn(_ key: String, disabled: [String]) -> Bool {
        !disabled.contains(key)
    }

    /// Ny liste etter at én bryter er endret. Ukjente id-er (en nyere server) beholdes,
    /// og ingen id står to ganger.
    static func setting(_ key: String, on: Bool, in disabled: [String]) -> [String] {
        var next = disabled.filter { $0 != key }
        if !on { next.append(key) }
        return next
    }

    /// Databasen ga tilbake det vi skrev (rekkefølgen spiller ingen rolle).
    static func matches(_ saved: [String], _ sent: [String]) -> Bool {
        Set(saved) == Set(sent)
    }
}

/// Raden fra `clubs` som «Hva blir push» leser og skriver.
nonisolated struct ClubPushRow: Codable, Equatable, Sendable {
    var disabledCategories: [String]

    enum CodingKeys: String, CodingKey {
        case disabledCategories = "push_disabled_categories"
    }
}

// MARK: - Hvem har push

/// En rad fra `push_status(p_club_id)`: aktive medlemmer, aldri tokens.
nonisolated struct PushStatusRow: Decodable, Equatable, Sendable {
    let memberID: UUID
    let hasLogin: Bool
    let devices: Int
    let lastSeenAt: Date?

    init(memberID: UUID, hasLogin: Bool, devices: Int, lastSeenAt: Date?) {
        self.memberID = memberID
        self.hasLogin = hasLogin
        self.devices = devices
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case hasLogin = "has_login"
        case devices
        case lastSeenAt = "last_seen_at"
    }
}

/// Navnet på et medlem, fra `club_members`.
nonisolated struct PushMemberName: Decodable, Equatable, Sendable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

nonisolated enum PushStatusState: Equatable, Sendable {
    /// Minst én telefon er registrert.
    case on(devices: Int, lastSeenAt: Date?)
    /// Har logget inn, men ingen telefon har slått på push.
    case off
    /// Ledig navn uten innlogging.
    case noLogin
}

nonisolated struct PushStatusEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let state: PushStatusState

    /// «1 telefon» / «2 telefoner».
    var devicesText: String? {
        guard case .on(let devices, _) = state else { return nil }
        return devices == 1 ? "1 telefon" : "\(devices) telefoner"
    }
}

/// «Hvem har push» delt i tre lister, hver sortert norsk på navn.
nonisolated struct PushStatusSections: Equatable, Sendable {
    var on: [PushStatusEntry] = []
    var off: [PushStatusEntry] = []
    var noLogin: [PushStatusEntry] = []

    var total: Int { on.count + off.count + noLogin.count }

    /// Tekst over lista, f.eks. «5 av 9 har push».
    var summary: String { "\(on.count) av \(total) har push" }

    /// Slår sammen `push_status` med navnene. Mangler navnet (RLS eller en rad som kom
    /// mellom to spørringer), vises «Ukjent spiller».
    init(status: [PushStatusRow], names: [PushMemberName]) {
        let byID = Dictionary(names.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let entries = status.map { row in
            PushStatusEntry(
                id: row.memberID,
                name: byID[row.memberID] ?? "Ukjent spiller",
                state: Self.state(for: row)
            )
        }
        .sorted { a, b in
            let byName = NorwegianSort.compare(a.name, b.name)
            return byName == .orderedSame ? a.id.uuidString < b.id.uuidString : byName == .orderedAscending
        }
        for entry in entries {
            switch entry.state {
            case .on: on.append(entry)
            case .off: off.append(entry)
            case .noLogin: noLogin.append(entry)
            }
        }
    }

    static func state(for row: PushStatusRow) -> PushStatusState {
        if row.devices > 0 { return .on(devices: row.devices, lastSeenAt: row.lastSeenAt) }
        return row.hasLogin ? .off : .noLogin
    }
}
