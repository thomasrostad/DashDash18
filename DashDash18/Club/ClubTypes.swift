import Foundation
import GolfgutuCore

/// Hva appen viser etter innlogging.
nonisolated enum ClubState: Equatable, Sendable {
    case loading
    /// Innlogget, men ikke med i noen klubb ennå.
    case noClub
    case pending(Membership)
    case active(Membership)
    case failed(ClubError)
}

/// Status på en rad i troppen (`club_members.status`).
nonisolated enum MemberStatus: String, Codable, Sendable {
    case active
    case pending
    case archived
}

/// Mitt medlemskap i én klubb, slik det leses fra `club_members` med klubben innebygd.
nonisolated struct Membership: Codable, Equatable, Identifiable, Sendable {
    struct ClubInfo: Codable, Equatable, Sendable {
        let name: String
        let joinCode: String?

        enum CodingKeys: String, CodingKey {
            case name
            case joinCode = "join_code"
        }
    }

    let id: UUID
    let clubID: UUID
    let displayName: String
    let status: MemberStatus
    let isOrganizer: Bool
    let isTreasurer: Bool
    let club: ClubInfo

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case displayName = "display_name"
        case status
        case isOrganizer = "is_organizer"
        case isTreasurer = "is_treasurer"
        case club = "clubs"
    }

    /// Kolonnene appen henter. Klubben kommer med via fremmednøkkelen.
    static let selectColumns = "id, club_id, display_name, status, is_organizer, is_treasurer, clubs(name, join_code)"

    var roleText: String {
        switch (isOrganizer, isTreasurer) {
        case (true, true): "Arrangør og kasserer"
        case (true, false): "Arrangør"
        case (false, true): "Kasserer"
        case (false, false): "Spiller"
        }
    }

    /// Hvilken klubb appen skal vise: den sist valgte hvis den fortsatt er aktiv,
    /// ellers første aktive, ellers første som venter. Arkiverte vises ikke.
    static func choose(from memberships: [Membership], remembered: UUID?) -> Membership? {
        let active = memberships.filter { $0.status == .active }
        if let remembered, let match = active.first(where: { $0.clubID == remembered }) {
            return match
        }
        return active.first ?? memberships.first { $0.status == .pending }
    }

    /// Hva appen viser for disse radene: klubben, venting eller klubbvalg.
    static func state(for memberships: [Membership], remembered: UUID?) -> ClubState {
        guard let chosen = choose(from: memberships, remembered: remembered) else { return .noClub }
        return chosen.status == .active ? .active(chosen) : .pending(chosen)
    }
}

/// Siste kjente medlemskap per innlogging, så appen starter uten nett (på banen, i kjelleren)
/// i stedet for å stoppe på «Fikk ikke hentet klubben». Slettes ved utlogging.
nonisolated struct MembershipCache {
    let defaults: UserDefaults
    private static let prefix = "medlemskap."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(userID: UUID) -> [Membership]? {
        guard let data = defaults.data(forKey: Self.key(userID)) else { return nil }
        return try? JSONDecoder().decode([Membership].self, from: data)
    }

    func save(_ memberships: [Membership], userID: UUID) {
        guard let data = try? JSONEncoder().encode(memberships) else { return }
        defaults.set(data, forKey: Self.key(userID))
    }

    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(_ userID: UUID) -> String { prefix + userID.uuidString.lowercased() }
}

/// Svaret fra `club_preview(kode)`: klubbnavn og ledige navn i troppen.
nonisolated struct ClubPreview: Decodable, Equatable, Sendable {
    struct OpenMember: Decodable, Equatable, Identifiable, Sendable {
        let id: UUID
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }

    let clubID: UUID
    let name: String
    let myStatus: MemberStatus?
    let openMembers: [OpenMember]

    /// De ledige navnene i norsk rekkefølge (databasen sorterer Æ, Ø og Å feil).
    var sortedOpenMembers: [OpenMember] {
        openMembers.sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
    }

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case name
        case myStatus = "my_status"
        case openMembers = "open_members"
    }
}

/// Svaret fra `join_club`.
nonisolated struct JoinResult: Decodable, Equatable, Sendable {
    let memberID: UUID
    let status: MemberStatus

    enum CodingKeys: String, CodingKey {
        case memberID = "member_id"
        case status
    }
}

/// Rydding og sjekk av det brukeren skriver i klubbskjemaene.
nonisolated enum ClubInput {
    /// Store bokstaver, uten mellomrom og bindestrek. Samme format som `clubs.join_code`.
    static func normalizedJoinCode(_ raw: String) -> String? {
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.wholeMatch(of: /[A-Z0-9]{6,16}/) != nil else { return nil }
        return code
    }

    /// Et nytt navn som allerede står ledig i troppen: da skal spilleren trykke på det i stedet
    /// (PWA: `handleAddSelfAndJoin`). Sammenlignes som i databasen, `lower(btrim(navn))`.
    static func openNameConflict(_ name: String, openMembers: [ClubPreview.OpenMember]) -> ClubError? {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = openMembers.first(where: {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) else { return nil }
        return .invalidInput("«\(match.displayName)» står allerede i troppen. Trykk på navnet over i stedet.")
    }

    /// Når «Be om å bli med» stopper på et navn som er tatt (23505). Det vanlige er at det er
    /// ditt eget navn, tatt av en annen innlogging (PWA, 17.09: «leses som en app i ulage»).
    static func nameTakenByOtherLogin(_ name: String) -> ClubError {
        .invalidInput("«\(name)» er tatt av en annen innlogging. Er det deg, har du kanskje logget inn med en annen e-post før. Logg ut og prøv den, eller be arrangøren frigjøre navnet.")
    }

    /// Navn i troppen: 1–40 tegn etter trimming (som i skjemaet).
    static func normalizedName(_ raw: String, maxLength: Int = 40) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...maxLength).contains(name.count) else { return nil }
        return name
    }

    /// Handicapindeks som på scorekortet: komma eller punktum, «+» betyr plusshandicap
    /// (lagres negativt). Tomt felt = ikke oppgitt. Gyldig −10…54, én desimal.
    /// PWA-en tolket komma på samme måte (`parseHcp`), fordi norsk tastatur gir komma.
    /// Mellomrom (også hardt mellomrom fra innliming) ignoreres, så «+ 2,3» og «12 ,4» går.
    /// Bare vanlige desimaltall godtas (ikke «1e1» eller «0x1A», som `Double` ellers tolker).
    static func handicapIndex(_ raw: String) -> Result<Double?, ClubError> {
        var text = String(raw.filter { !$0.isWhitespace }).replacingOccurrences(of: ",", with: ".")
        if text.isEmpty { return .success(nil) }
        // Minus er tvetydig (noen skriver plusshandicap som minus). Be om «+» i stedet.
        if text.hasPrefix("-") || text.hasPrefix("\u{2212}") {
            return .failure(.invalidInput("Plusshandicap skrives med «+», f.eks. +2,3."))
        }
        var sign = 1.0
        if text.hasPrefix("+") {
            sign = -1
            text.removeFirst()
        }
        guard text.wholeMatch(of: /[0-9]+(\.[0-9]*)?|\.[0-9]+/) != nil,
              let value = Double(text), value.isFinite else {
            return .failure(.invalidInput("Handicap må være et tall, f.eks. 18,4."))
        }
        let index = (sign * value * 10).rounded() / 10
        guard (-10...54).contains(index) else {
            return .failure(.invalidInput("Handicap må være mellom +10 og 54."))
        }
        return .success(index == 0 ? 0 : index)
    }
}

/// Feil i klubbflyten, med norsk tekst.
nonisolated enum ClubError: Error, Equatable {
    case notFound
    case nameTaken
    case duplicateName
    case invalidInput(String)
    case notAllowed
    case offline
    case unknown(String)

    var message: String {
        switch self {
        case .notFound: "Fant ingen klubb med den koden. Sjekk at den er skrevet riktig."
        case .nameTaken: "Navnet er tatt av noen andre i mellomtiden. Velg et annet."
        case .duplicateName: "Det navnet finnes allerede i troppen."
        case .invalidInput(let text): text
        case .notAllowed: "Du har ikke tilgang til dette."
        case .offline: "Ingen kontakt med serveren. Sjekk nettet og prøv igjen."
        case .unknown(let detail): "Noe gikk galt: \(detail)"
        }
    }

    /// Oversetter SQLSTATE fra databasen (se `sql/README.md`, feilkoder).
    static func from(sqlState: String?, message: String) -> ClubError {
        switch sqlState {
        case "P0002": .notFound
        case "55000": .nameTaken
        case "23505": .duplicateName
        case "22023", "23514": .invalidInput(message)
        case "42501": .notAllowed
        default: .unknown(message)
        }
    }
}
