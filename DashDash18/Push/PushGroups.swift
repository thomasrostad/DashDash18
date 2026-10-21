import Foundation
import GolfgutuCore

// Varselgruppene (steg 5, sql/046): fire grupper over kategoriene, demping av én kveld og
// e-post til dem uten push. Rene typer, så de kan testes isolert. Lesing og skriving ligger i
// `PushSettingsStore` og `PushEventMuteStore`.

/// De fire gruppene (`push_groups()` i 046). Gruppe av = alle kategoriene i gruppen av.
nonisolated enum PushGroup: String, Codable, CaseIterable, Sendable {
    case game
    case social
    case evening
    case organizer

    /// «Spillet», «Sosialt», «Kvelden» (eller «Spilledagen»), «Arrangør».
    func title(term: DayTerm = .evening) -> String {
        switch self {
        case .game: "Spillet"
        case .social: "Sosialt"
        case .evening: DayTerm.capitalized(term.the)
        case .organizer: "Arrangør"
        }
    }

    func subtitle(term: DayTerm = .evening) -> String {
        switch self {
        case .game: "Scorer, ledelsen, sidepremier og runder"
        case .social: "Sosialkomiteen, klubben og tråden"
        case .evening: "Påmelding, påminnelser og når \(term.the) er i gang"
        case .organizer: PendingMembersFeature.isEnabled
            ? "Når noen melder seg av eller vil bli med i klubben" : "Når noen melder seg av"
        }
    }

    /// Bare for dem med minst én rettighet i klubben.
    var isOrganizerOnly: Bool { self == .organizer }

    /// Gruppen for en kategori og kind, som `public.push_group(kategori, kind)`: kind går foran.
    /// Ukjent kategori gir nil. `thread` er tråden.
    static func of(category: String, kind: String? = nil) -> PushGroup? {
        switch kind {
        case "signup_dropped", "member_pending": return .organizer
        case "evening_started": return .evening
        default: break
        }
        switch category {
        case "score", "lead", "side_prize", "round", "bet", "tips": return .game
        case "social", "club", "thread": return .social
        case "signup", "reminder", "nudge", "setup", "announcement": return .evening
        default: return nil
        }
    }

    /// De gruppene innstillingene viser: Arrangør bare med en rettighet.
    static func shown(isOrganizer: Bool) -> [PushGroup] {
        allCases.filter { !$0.isOrganizerOnly || isOrganizer }
    }
}

/// En rad fra `push_group_map()`: hver kjent kind med kategori og gruppe.
nonisolated struct PushGroupMapRow: Decodable, Equatable, Sendable {
    let groupKey: String?
    let category: String
    let kind: String

    init(groupKey: String?, category: String, kind: String) {
        self.groupKey = groupKey
        self.category = category
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case groupKey = "group_key"
        case category
        case kind
    }
}

/// Hva som hører til hvilken gruppe. Fra serveren (`push_group_map()`), eller den lokale kopien
/// når kallet feiler.
nonisolated struct PushGroupMap: Equatable, Sendable {
    let rows: [PushGroupMapRow]

    /// Samme tabell som `push_group_map()` i 046, med `member_pending` (067) når flagget er på.
    static let local = PushGroupMap(rows: (localPairs + (PendingMembersFeature.isEnabled ? pendingPairs : [])).map {
        PushGroupMapRow(groupKey: PushGroup.of(category: $0.0, kind: $0.1)?.rawValue, category: $0.0, kind: $0.1)
    })

    private static let localPairs: [(String, String)] = [
        ("round", "round_started"), ("round", "round_locked"), ("round", "round_deleted"),
        ("round", "table_changed"), ("round", "evening_started"),
        ("score", "big_score"), ("lead", "lead_changed"), ("side_prize", "side_prize"),
        ("setup", "score_corrected"),
        ("signup", "signup"), ("signup", "waitlist_promoted"), ("signup", "signup_dropped"),
        ("nudge", "nudge"), ("reminder", "reminder"), ("announcement", "announcement"),
        ("social", "committee_drawn"), ("club", "member_joined"), ("tips", "tips_king"),
        ("bet", "bet_created"), ("bet", "bet_challenge"), ("bet", "bet_resolved"),
        ("thread", "thread_message"),
    ]

    /// sql/067: noen vil bli med i klubben (Arrangør).
    private static let pendingPairs: [(String, String)] = [("club", "member_pending")]

    /// Gruppen kategorien hører til: den flest av kategoriens kinds står i. Likt (eller ingen
    /// rader): som `push_group(kategori)`. `round` er Spillet selv om «kvelden er i gang» er Kvelden.
    func mainGroup(of category: String) -> PushGroup? {
        let groups = rows.filter { $0.category == category }.compactMap { $0.groupKey.flatMap(PushGroup.init) }
        let counts = Dictionary(groups.map { ($0, 1) }, uniquingKeysWith: +)
        let fallback = PushGroup.of(category: category)
        guard let best = counts.values.max() else { return fallback }
        let top = counts.filter { $0.value == best }.map(\.key)
        if top.count == 1 { return top[0] }
        return fallback.flatMap { top.contains($0) ? $0 : nil } ?? top.sorted { $0.rawValue < $1.rawValue }.first
    }

    /// Kategoriene under gruppen, i rekkefølgen innstillingene viser dem.
    func categories(in group: PushGroup, shown: [ActivityCategory]) -> [ActivityCategory] {
        shown.filter { mainGroup(of: $0.rawValue) == group }
    }

    /// Hendelser som hører til gruppen selv om kategorien står et annet sted
    /// (`evening_started` under Kvelden, `signup_dropped` under Arrangør).
    func extraKinds(in group: PushGroup) -> [String] {
        rows.filter { row in
            row.groupKey == group.rawValue && mainGroup(of: row.category) != group
        }.map(\.kind)
    }

    /// Navnet på en slik hendelse i innstillingene. nil for kinds appen ikke kjenner.
    static func kindTitle(_ kind: String, term: DayTerm = .evening) -> String? {
        switch kind {
        case "evening_started": "\(DayTerm.capitalized(term.the)) er i gang"
        case "signup_dropped": "Avmeldinger fra «kommer»"
        case "member_pending": "Nye som vil bli med i klubben"
        default: nil
        }
    }
}

/// Gruppene og e-postvalget i `push_preferences` (046). Lista er det som er AV.
nonisolated struct PushGroupSettings: Codable, Equatable, Sendable {
    /// Rå nøkler fra databasen. Ukjente beholdes, så de ikke forsvinner ved lagring.
    var disabledGroups: [String]
    /// «E-post når du ikke har varsler på». På som standard.
    var emailFallback: Bool

    init(disabledGroups: [String] = [], emailFallback: Bool = true) {
        self.disabledGroups = disabledGroups
        self.emailFallback = emailFallback
    }

    static let defaults = PushGroupSettings()

    static let columns = "disabled_groups, email_fallback"

    enum CodingKeys: String, CodingKey {
        case disabledGroups = "disabled_groups"
        case emailFallback = "email_fallback"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disabledGroups = (try? c.decodeIfPresent([String].self, forKey: .disabledGroups)) ?? []
        emailFallback = (try? c.decodeIfPresent(Bool.self, forKey: .emailFallback)) ?? true
    }

    func isOn(_ group: PushGroup) -> Bool { !disabledGroups.contains(group.rawValue) }

    mutating func set(_ group: PushGroup, on: Bool) {
        disabledGroups.removeAll { $0 == group.rawValue }
        if !on { disabledGroups.append(group.rawValue) }
        disabledGroups = Self.normalized(disabledGroups)
    }

    /// Som `push_set_groups`: bare kjente grupper, uten like, sortert.
    static func normalized(_ groups: [String]) -> [String] {
        Array(Set(groups.filter { PushGroup(rawValue: $0) != nil })).sorted()
    }

    /// Lik etter lagring? (Serveren sorterer og fjerner like.)
    func matches(_ other: PushGroupSettings) -> Bool {
        Self.normalized(disabledGroups) == Self.normalized(other.disabledGroups) && emailFallback == other.emailFallback
    }

    /// Parameterne til `push_set_groups`.
    var rpcParams: SetGroupsParams {
        SetGroupsParams(groups: Self.normalized(disabledGroups), email: emailFallback)
    }

    nonisolated struct SetGroupsParams: Encodable, Equatable, Sendable {
        let groups: [String]
        let email: Bool?

        enum CodingKeys: String, CodingKey {
            case groups = "p_disabled_groups"
            case email = "p_email_fallback"
        }
    }
}

/// Når en tabell, kolonne eller funksjon fra 046 mangler (ikke kjørt): da skjules det nye.
nonisolated enum PushSchema {
    /// Kodene fra `EveningSignupService.isMissing`, pluss PGRST205 (ukjent tabell i PostgREST).
    static func isMissing(code: String?) -> Bool {
        EveningSignupService.isMissing(code: code) || code == "PGRST205"
    }
}

/// «Demp denne kvelden» (`push_event_mutes`, `push_mute_event`).
nonisolated enum PushEventMuteText {
    static func title(term: DayTerm = .evening) -> String { "Demp denne \(term.the)" }

    static func subtitle(term: DayTerm = .evening) -> String {
        "Ingen push om \(term.the). Meldinger til alle kommer fortsatt."
    }
}
