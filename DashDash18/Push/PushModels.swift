import Foundation

// Push (fase 8, `sql/010_push.sql`): rene typer uten UIKit og nettverk, så de kan testes
// isolert. Tjenesten som snakker med iOS og Supabase ligger i `PushRegistrar`.

/// Bryteren for hele push-delen (`sql/010_push.sql` og `push-send`, docs/push-oppsett.md).
/// Når den er av, spør appen ikke om varseltillatelse, registrerer seg ikke hos APNs, kaller
/// ingen push-RPC-er og viser ikke innstillingene under Deg.
nonisolated enum PushFeature {
    static let isEnabled = true
}

// MARK: - Token og miljø

nonisolated enum PushToken {
    /// APNs-tokenet som heks med små bokstaver, slik `register_push_device` vil ha det.
    static func hex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(data.count * 2)
        for byte in data {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Samme sjekk som databasen (`^[0-9a-f]{64,200}$`).
    static func isValid(_ hex: String) -> Bool {
        (64...200).contains(hex.utf8.count) && hex.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Hvilken APNs-vert tokenet hører til. Bygg fra Xcode får sandbox-tokens; TestFlight og
/// App Store får production (styrt av `aps-environment` som Xcode setter ved signering).
nonisolated enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    static func forBuild(isDebug: Bool) -> PushEnvironment {
        isDebug ? .sandbox : .production
    }

    static var current: PushEnvironment {
        #if DEBUG
        forBuild(isDebug: true)
        #else
        forBuild(isDebug: false)
        #endif
    }
}

/// Parameterne til `register_push_device`.
nonisolated struct PushDeviceRegistration: Encodable, Equatable, Sendable {
    let deviceID: String
    let token: String
    let environment: PushEnvironment
    let bundleID: String?

    enum CodingKeys: String, CodingKey {
        case deviceID = "p_device_id"
        case token = "p_token"
        case environment = "p_environment"
        case bundleID = "p_bundle_id"
    }
}

// MARK: - Kategorier

/// Tråden: alle meldinger, bare når jeg nevnes (standard, som PWA-ens `prat_push`), eller av.
nonisolated enum ThreadPushMode: String, Codable, CaseIterable, Sendable {
    case all
    case mentions
    case off

    var title: String {
        switch self {
        case .all: "Alle meldinger"
        case .mentions: "Når jeg nevnes"
        case .off: "Av"
        }
    }
}

nonisolated enum PushCategories {
    /// Det spilleren kan slå av for seg selv. Samme liste som `push_player_categories()` i 010:
    /// alt unntatt «Melding til alle».
    static let playerToggleable: [ActivityCategory] = ActivityCategory.allCases.filter { $0 != .announcement }

    /// Det arrangøren kan slå av for klubben (`push_club_categories()`), uten tråden. «Melding til
    /// alle» og purring har ingen klubbryter (PWA: ALLTID).
    static let clubToggleable: [ActivityCategory] = ActivityCategory.allCases.filter {
        $0 != .announcement && $0 != .nudge
    }

    /// Nøkkelen for tråden i `clubs.push_disabled_categories`.
    static let threadKey = "thread"

    /// Det innstillingene under Deg (og arrangørens «Hva blir push») viser, i fast rekkefølge:
    /// de ROADMAP nevner først. Veddemål (`bet`) er med når veddemål er på (`BetsFeature`).
    static let shownToPlayer: [ActivityCategory] = shown(bets: BetsFeature.isEnabled)

    static func shown(bets: Bool) -> [ActivityCategory] {
        [.score, .lead, .round, .reminder, .nudge, .sidePrize, .tips]
            + (bets ? [.bet] : [])
            + [.signup, .social, .setup, .club]
    }

    /// Undertekst i innstillingene (PWA: `VARSEL_KATEGORIER.under`).
    static func subtitle(_ category: ActivityCategory) -> String {
        switch category {
        case .score: "Hole in one, eagle og albatross"
        case .lead: "Hvem leder underveis i runden"
        case .sidePrize: "Nærmest pinnen og longest drive"
        case .round: "Ny runde, runde låst eller slettet"
        case .setup: "Rettede scorer"
        case .bet: "Nye veddemål, utfordringer og oppgjør"
        case .signup: "Når noen melder seg på eller av"
        case .social: "Trekning av sosialkomiteen"
        case .club: "Nye spillere i klubben"
        case .tips: "Tippekongen etter kvelden"
        case .announcement: "Beskjeder fra arrangøren"
        case .nudge: "Når arrangøren mangler svaret ditt"
        case .reminder: "En uke før hver kveld"
        }
    }
}

// MARK: - Valg per spiller

/// En rad i `push_preferences`. Ingen rad = standard (alt på, tråden «når jeg nevnes»).
/// Lista er det som er AV, så en ny kategori er på til spilleren slår den av.
nonisolated struct PushPreferences: Codable, Equatable, Sendable {
    let memberID: UUID
    let clubID: UUID
    /// Rå id-er fra databasen. Ukjente (en nyere server) beholdes, så de ikke forsvinner ved lagring.
    var disabledCategories: [String]
    var threadMode: ThreadPushMode

    init(memberID: UUID, clubID: UUID, disabledCategories: [String] = [], threadMode: ThreadPushMode = .mentions) {
        self.memberID = memberID
        self.clubID = clubID
        self.disabledCategories = disabledCategories
        self.threadMode = threadMode
    }

    static func defaults(memberID: UUID, clubID: UUID) -> PushPreferences {
        PushPreferences(memberID: memberID, clubID: clubID)
    }

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case clubID = "club_id"
        case disabledCategories = "disabled_categories"
        case threadMode = "thread_mode"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        clubID = try c.decode(UUID.self, forKey: .clubID)
        disabledCategories = (try? c.decodeIfPresent([String].self, forKey: .disabledCategories)) ?? []
        // Ukjent valg leses som standard, som senderen gjør.
        threadMode = (try? c.decodeIfPresent(ThreadPushMode.self, forKey: .threadMode)) ?? .mentions
    }

    func isOn(_ category: ActivityCategory) -> Bool {
        category == .announcement || !disabledCategories.contains(category.rawValue)
    }

    /// Slår en kategori av eller på. «Melding til alle» kan ikke slås av.
    mutating func set(_ category: ActivityCategory, on: Bool) {
        guard category != .announcement else { return }
        disabledCategories.removeAll { $0 == category.rawValue }
        if !on { disabledCategories.append(category.rawValue) }
    }
}

/// Arrangørens «Hva blir push» (`clubs.push_disabled_categories`), lest for å vise hva som er
/// slått av for hele klubben.
nonisolated struct ClubPushSettings: Codable, Equatable, Sendable {
    var disabledCategories: [String]

    init(disabledCategories: [String] = []) {
        self.disabledCategories = disabledCategories
    }

    enum CodingKeys: String, CodingKey {
        case disabledCategories = "push_disabled_categories"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disabledCategories = (try? c.decodeIfPresent([String].self, forKey: .disabledCategories)) ?? []
    }

    func blocks(_ category: ActivityCategory) -> Bool {
        category != .announcement && category != .nudge && disabledCategories.contains(category.rawValue)
    }

    var blocksThread: Bool { disabledCategories.contains(PushCategories.threadKey) }
}

// MARK: - Push mens appen er åpen

/// Hva en push gjelder, lest fra `dd18` i pushen (`push-send`: `type`, `event_id`).
nonisolated struct PushTarget: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case activity
        case thread
    }

    let kind: Kind?
    let eventID: UUID?

    init(kind: Kind?, eventID: UUID?) {
        self.kind = kind
        self.eventID = eventID
    }

    /// Fra `userInfo`. Ukjent eller manglende innhold gir en tom `PushTarget`.
    init(userInfo: [AnyHashable: Any]) {
        let data = userInfo["dd18"] as? [String: Any] ?? [:]
        kind = (data["type"] as? String).flatMap(Kind.init(rawValue:))
        eventID = (data["event_id"] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// Om en push vises som banner når appen står åpen (iOS viser ingenting av seg selv da).
/// Tråden du ser på, varsles ikke: meldingen dukker opp i tråden.
nonisolated enum PushForeground {
    static func shouldShow(_ target: PushTarget, visibleThreadEventID: UUID?) -> Bool {
        guard target.kind == .thread, let event = target.eventID else { return true }
        return event != visibleThreadEventID
    }
}

/// Varseltillatelsen fra iOS, forenklet til det appen bryr seg om.
nonisolated enum PushPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}
