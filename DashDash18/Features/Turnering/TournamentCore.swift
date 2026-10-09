import Foundation
import GolfgutuCore

/// Fase 23, turneringen som kjerne (docs/fase-22-turnering-som-kjerne.md): turneringsvelger på
/// arrangørsiden, påmelding med tak, vindu og venteliste, stab og startliste. Krever
/// `sql/032_turnering_kjerne_trinn2.sql`. Av til 032 er kjørt; med flagget av er appen som før.
/// `min_ios_build` (031) er ikke bak flagget (`MinimumBuild`).
nonisolated enum TournamentCoreFeature {
    /// På siden 09.10.2026: sql/032 er kjørt på test (kontrollen 10 av 10, paritet identisk).
    static let isEnabled = true

    /// Krever også konkurransene (017/022).
    static var isActive: Bool { isEnabled && CompetitionsFeature.isActive }
}

// MARK: - Turneringsvelger

/// En turnering i velgeren på arrangørsiden.
nonisolated struct TournamentOption: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let kind: CompetitionKind
    let status: SeasonStatus
    /// Sesongen den speiler. Da har den kvelder, og arrangørsiden viser tidslinja.
    let seasonID: UUID?
    let isMain: Bool
    let entry: CompetitionEntry

    init(_ row: CompetitionRow) {
        id = row.id
        name = row.name
        kind = row.kind
        status = row.status
        seasonID = row.seasonID
        isMain = row.isMain
        entry = row.entry
    }

    /// Har spilledager (kvelder) på arrangørsiden. De andre får spilledager i trinn 3.
    var hasEvenings: Bool { seasonID != nil }

    /// «Hovedturnering · Serie», «Cup · planlagt».
    var subtitle: String {
        var parts: [String] = []
        if isMain { parts.append("Hovedturnering") }
        parts.append(CompetitionText.kind(kind))
        if status == .planned { parts.append("planlagt") }
        return parts.joined(separator: " · ")
    }
}

/// Velgeren øverst på arrangørsiden: klubbens turneringer som ikke er ferdige, hovedturneringen
/// først. Med én turnering vises ingen velger (Golfgutu merker ingenting).
nonisolated enum TournamentPicker {
    static func options(_ competitions: [CompetitionRow], clubID: UUID) -> [TournamentOption] {
        func rank(_ c: CompetitionRow) -> Int {
            if c.isMain && c.status == .active { return 0 }
            if c.isMain { return 1 }
            return c.status == .active ? 2 : 3
        }
        return competitions
            .filter { $0.clubID == clubID && $0.kind != .game && $0.status != .finished }
            .sorted { a, b in
                rank(a) != rank(b) ? rank(a) < rank(b) : NorwegianSort.areInIncreasingOrder(a.name, b.name)
            }
            .map(TournamentOption.init)
    }

    static func showsPicker(_ options: [TournamentOption]) -> Bool { options.count > 1 }

    /// Den valgte når arrangørsiden åpnes: turneringen som speiler sesongen den ble åpnet med, ellers
    /// den første med kvelder (hovedturneringen). Uten noen med kvelder: ingen, så arrangørsiden
    /// viser kveldene og «Kom i gang» som før.
    static func initial(_ options: [TournamentOption], seasonID: UUID?) -> TournamentOption? {
        if let seasonID, let match = options.first(where: { $0.seasonID == seasonID }) { return match }
        return options.first(where: \.hasEvenings)
    }
}

// MARK: - Påmelding (sql/032)

/// Svaret fra `competition_signup_status` og RPC-ene for påmelding.
nonisolated struct CompetitionSignupStatus: Decodable, Equatable, Sendable {
    enum State: String, Decodable, Sendable {
        case entered, offered, expired, waitlisted, withdrawn, none
    }

    let competitionID: UUID
    var state: State
    var waitlistPosition: Int?
    var offerExpiresAt: Date?
    var entrants: Int
    var maxEntrants: Int?
    var waitlist: Int
    var signupOpen: Bool
    var openToAnyone: Bool
    var waitlistEnabled: Bool
    var signupOpensAt: Date?
    var signupClosesAt: Date?

    enum CodingKeys: String, CodingKey {
        case competitionID = "competition_id"
        case state
        case waitlistPosition = "waitlist_position"
        case offerExpiresAt = "offer_expires_at"
        case entrants
        case maxEntrants = "max_entrants"
        case waitlist
        case signupOpen = "signup_open"
        case signupAudience = "signup_audience"
        case waitlistEnabled = "waitlist_enabled"
        case signupOpensAt = "signup_opens_at"
        case signupClosesAt = "signup_closes_at"
    }

    init(competitionID: UUID, state: State, waitlistPosition: Int? = nil, offerExpiresAt: Date? = nil,
         entrants: Int = 0, maxEntrants: Int? = nil, waitlist: Int = 0, signupOpen: Bool = true,
         openToAnyone: Bool = false, waitlistEnabled: Bool = false, signupOpensAt: Date? = nil,
         signupClosesAt: Date? = nil) {
        self.competitionID = competitionID
        self.state = state
        self.waitlistPosition = waitlistPosition
        self.offerExpiresAt = offerExpiresAt
        self.entrants = entrants
        self.maxEntrants = maxEntrants
        self.waitlist = waitlist
        self.signupOpen = signupOpen
        self.openToAnyone = openToAnyone
        self.waitlistEnabled = waitlistEnabled
        self.signupOpensAt = signupOpensAt
        self.signupClosesAt = signupClosesAt
    }

    /// Ukjent tilstand fra en nyere server blir «none», så knappen ikke forsvinner med en feil.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        competitionID = try c.decode(UUID.self, forKey: .competitionID)
        state = (try? c.decode(State.self, forKey: .state)) ?? .none
        waitlistPosition = try c.decodeIfPresent(Int.self, forKey: .waitlistPosition)
        offerExpiresAt = try c.decodeIfPresent(Date.self, forKey: .offerExpiresAt)
        entrants = try c.decodeIfPresent(Int.self, forKey: .entrants) ?? 0
        maxEntrants = try c.decodeIfPresent(Int.self, forKey: .maxEntrants)
        waitlist = try c.decodeIfPresent(Int.self, forKey: .waitlist) ?? 0
        signupOpen = try c.decodeIfPresent(Bool.self, forKey: .signupOpen) ?? false
        openToAnyone = (try c.decodeIfPresent(String.self, forKey: .signupAudience)) == "anyone"
        waitlistEnabled = try c.decodeIfPresent(Bool.self, forKey: .waitlistEnabled) ?? false
        signupOpensAt = try c.decodeIfPresent(Date.self, forKey: .signupOpensAt)
        signupClosesAt = try c.decodeIfPresent(Date.self, forKey: .signupClosesAt)
    }

    /// Full: taket er nådd, eller noen venter allerede (en ny påmelding havner da bak dem).
    var isFull: Bool {
        guard let maxEntrants else { return false }
        return entrants >= maxEntrants || waitlist > 0
    }
}

/// Hva påmeldingskortet på turneringssiden viser.
nonisolated enum SignupCard {
    enum Action: Equatable, Sendable {
        case join, joinWaitlist, leave, leaveWaitlist, accept, decline

        var title: String {
            switch self {
            case .join: "Meld meg på"
            case .joinWaitlist: "Sett meg på ventelista"
            case .leave: "Meld meg av"
            case .leaveWaitlist: "Gå ut av ventelista"
            case .accept: "Ta plassen"
            case .decline: "Avslå"
            }
        }
    }

    enum Tone: Equatable, Sendable {
        case neutral, good, urgent, closed
    }

    struct Presentation: Equatable, Sendable {
        var headline: String
        var detail: String?
        var capacity: String
        var primary: Action?
        var secondary: Action?
        var tone: Tone
    }

    static func presentation(_ s: CompetitionSignupStatus, now: Date = .now, timeZone: TimeZone = .current) -> Presentation {
        let capacity = capacityText(s)
        switch s.state {
        case .entered:
            return Presentation(headline: "Du er påmeldt", detail: nil, capacity: capacity,
                                primary: nil, secondary: .leave, tone: .good)
        case .offered:
            let deadline = s.offerExpiresAt.map { "Svar innen \(dateText($0, timeZone: timeZone)), ellers går plassen videre." }
            return Presentation(headline: "Du har fått plass", detail: deadline, capacity: capacity,
                                primary: .accept, secondary: .decline, tone: .urgent)
        case .waitlisted:
            let place = s.waitlistPosition.map { "Du står som nr. \($0) på ventelista" } ?? "Du står på ventelista"
            return Presentation(headline: place,
                                detail: "Blir en plass ledig, får du tilbud om den her, med en frist for å svare.",
                                capacity: capacity, primary: nil, secondary: .leaveWaitlist, tone: .neutral)
        case .expired:
            var p = open(s, now: now, timeZone: timeZone, capacity: capacity)
            p.headline = "Tilbudet gikk ut"
            p.detail = "Plassen gikk videre til den neste på ventelista."
                + (p.primary == nil ? "" : " Du kan melde deg på igjen.")
            return p
        case .withdrawn, .none:
            return open(s, now: now, timeZone: timeZone, capacity: capacity)
        }
    }

    /// Ikke med: åpen, stengt, ikke åpnet ennå eller full.
    private static func open(_ s: CompetitionSignupStatus, now: Date, timeZone: TimeZone, capacity: String) -> Presentation {
        func closed(_ headline: String, _ detail: String? = nil) -> Presentation {
            Presentation(headline: headline, detail: detail, capacity: capacity, primary: nil, secondary: nil, tone: .closed)
        }
        guard s.signupOpen else { return closed("Påmeldingen er stengt") }
        if let opens = s.signupOpensAt, now < opens {
            return closed("Påmeldingen åpner \(dateText(opens, timeZone: timeZone))")
        }
        if let closes = s.signupClosesAt, now > closes { return closed("Påmeldingen er stengt") }
        let deadline = s.signupClosesAt.map { "Påmeldingen stenger \(dateText($0, timeZone: timeZone))." }
        if s.isFull {
            guard s.waitlistEnabled else { return closed("Turneringen er full") }
            return Presentation(headline: "Turneringen er full",
                                detail: "Du kan stå på ventelista og få tilbud om en plass som blir ledig.",
                                capacity: capacity, primary: .joinWaitlist, secondary: nil, tone: .neutral)
        }
        let headline: String
        if let max = s.maxEntrants {
            let free = max - s.entrants
            headline = free == 1 ? "1 ledig plass" : "\(free) ledige plasser"
        } else {
            headline = "Påmeldingen er åpen"
        }
        return Presentation(headline: headline, detail: deadline, capacity: capacity,
                            primary: .join, secondary: nil, tone: .neutral)
    }

    /// «12 av 16 plasser · 3 på venteliste», «5 påmeldte».
    static func capacityText(_ s: CompetitionSignupStatus) -> String {
        var text: String
        if let max = s.maxEntrants {
            text = "\(s.entrants) av \(max) plasser"
        } else {
            text = s.entrants == 1 ? "1 påmeldt" : "\(s.entrants) påmeldte"
        }
        if s.waitlist > 0 { text += " · \(s.waitlist) på venteliste" }
        return text
    }

    /// «fredag 10. oktober kl. 18:30».
    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.timeZone = timeZone
        f.dateFormat = "EEEE d. MMMM 'kl.' HH:mm"
        return f.string(from: date)
    }
}

/// Påmeldingsfeltene på turneringen (sql/031), hentet bare når flagget er på.
nonisolated struct CompetitionSignupSettings: Decodable, Equatable, Sendable {
    var signupOpen: Bool
    var signupAudience: String
    var listed: Bool
    var maxEntrants: Int?
    var waitlistEnabled: Bool
    var signupOpensAt: Date?
    var signupClosesAt: Date?

    enum CodingKeys: String, CodingKey {
        case signupOpen = "signup_open"
        case signupAudience = "signup_audience"
        case listed
        case maxEntrants = "max_entrants"
        case waitlistEnabled = "waitlist_enabled"
        case signupOpensAt = "signup_opens_at"
        case signupClosesAt = "signup_closes_at"
    }

    static let columns = "signup_open, signup_audience, listed, max_entrants, waitlist_enabled, signup_opens_at, signup_closes_at"

    static let closed = CompetitionSignupSettings(signupOpen: false, signupAudience: "members", listed: false,
                                                  maxEntrants: nil, waitlistEnabled: false,
                                                  signupOpensAt: nil, signupClosesAt: nil)
}

/// Det arrangøren fyller inn under «Påmelding».
nonisolated struct SignupSettingsDraft: Equatable, Sendable {
    var isOpen: Bool
    var openToAnyone: Bool
    var listed: Bool
    var hasCap: Bool
    var maxEntrants: Int
    var waitlistEnabled: Bool
    var hasOpensAt: Bool
    var opensAt: Date
    var hasClosesAt: Bool
    var closesAt: Date
    /// Hele troppen er med (klubbserien): ingen påmelding.
    let isWholeClub: Bool
    let hasClub: Bool

    /// Standardtaket når arrangøren slår på «Begrens antall».
    static let defaultCap = 16

    init(_ s: CompetitionSignupSettings, entry: CompetitionEntry, hasClub: Bool, now: Date = .now) {
        isOpen = s.signupOpen
        openToAnyone = s.signupAudience == "anyone"
        listed = s.listed
        hasCap = s.maxEntrants != nil
        maxEntrants = s.maxEntrants ?? Self.defaultCap
        waitlistEnabled = s.waitlistEnabled
        hasOpensAt = s.signupOpensAt != nil
        opensAt = s.signupOpensAt ?? now
        hasClosesAt = s.signupClosesAt != nil
        closesAt = s.signupClosesAt ?? now.addingTimeInterval(7 * 24 * 3600)
        isWholeClub = entry == .club
        self.hasClub = hasClub
    }

    /// Samme sjekker som `set_competition_signup` (sql/032), med norsk tekst.
    func issues() -> [String] {
        var out: [String] = []
        if isWholeClub {
            out.append("Hele troppen er med i denne turneringen, så den har ingen påmelding.")
            return out
        }
        if hasCap && !(2...5000).contains(maxEntrants) { out.append("Taket må være mellom 2 og 5000.") }
        if waitlistEnabled && !hasCap { out.append("Venteliste krever et tak på antall påmeldte.") }
        if hasOpensAt && hasClosesAt && closesAt < opensAt { out.append("Påmeldingen må stenge etter at den åpner.") }
        if listed && openToAnyone && !hasClub { out.append("Bare en klubb eller et senter har en offentlig liste.") }
        return out
    }

    /// Parametrene til `set_competition_signup`. Den offentlige lista gjelder bare åpne turneringer,
    /// og venteliste bare med tak.
    func params(competitionID: UUID) -> SetSignupParams {
        SetSignupParams(p_competition_id: competitionID, p_signup_open: isOpen,
                        p_audience: openToAnyone ? "anyone" : "members",
                        p_listed: openToAnyone && listed,
                        p_max_entrants: hasCap ? maxEntrants : nil,
                        p_waitlist_enabled: hasCap && waitlistEnabled,
                        p_opens_at: hasOpensAt ? opensAt : nil,
                        p_closes_at: hasClosesAt ? closesAt : nil)
    }
}

nonisolated struct SetSignupParams: Encodable, Equatable, Sendable {
    let p_competition_id: UUID
    let p_signup_open: Bool
    let p_audience: String
    let p_listed: Bool
    let p_max_entrants: Int?
    let p_waitlist_enabled: Bool
    let p_opens_at: Date?
    let p_closes_at: Date?

    // Tomme verdier sendes som null (RPC-en har ingen standardverdier).
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_competition_id, forKey: .p_competition_id)
        try c.encode(p_signup_open, forKey: .p_signup_open)
        try c.encode(p_audience, forKey: .p_audience)
        try c.encode(p_listed, forKey: .p_listed)
        try c.encode(p_max_entrants, forKey: .p_max_entrants)
        try c.encode(p_waitlist_enabled, forKey: .p_waitlist_enabled)
        try c.encode(p_opens_at, forKey: .p_opens_at)
        try c.encode(p_closes_at, forKey: .p_closes_at)
    }

    enum CodingKeys: String, CodingKey {
        case p_competition_id, p_signup_open, p_audience, p_listed, p_max_entrants, p_waitlist_enabled,
             p_opens_at, p_closes_at
    }
}

/// En linje på ventelista (`competition_waitlist_entries`), for arrangøren.
nonisolated struct WaitlistEntryRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let position: Int
    let displayName: String
    let offeredAt: Date?
    let offerExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case position = "waitlist_position"
        case displayName = "display_name"
        case offeredAt = "offered_at"
        case offerExpiresAt = "offer_expires_at"
    }

    /// «Tilbudt plass, frist fredag 10. oktober kl. 18:30».
    func status(now: Date = .now, timeZone: TimeZone = .current) -> String? {
        guard offeredAt != nil, let offerExpiresAt else { return nil }
        if offerExpiresAt <= now { return "Tilbudet har gått ut" }
        return "Tilbudt plass, frist \(SignupCard.dateText(offerExpiresAt, timeZone: timeZone))"
    }
}

// MARK: - Stab (sql/031, rettighetene i 032)

nonisolated enum StaffRole: String, Codable, CaseIterable, Sendable {
    case organizer
    case scorer

    var title: String {
        switch self {
        case .organizer: "Arrangør"
        case .scorer: "Funksjonær"
        }
    }

    var help: String {
        switch self {
        case .organizer: "Styrer turneringen: påmelding, stab, runder og startliste. Fører for alle."
        case .scorer: "Fører for gruppene hen er satt på i startlista, mens runden pågår."
        }
    }
}

nonisolated struct CompetitionStaffRow: Codable, Equatable, Identifiable, Sendable {
    let competitionID: UUID
    let profileID: UUID
    var role: StaffRole
    var id: UUID { profileID }

    enum CodingKeys: String, CodingKey {
        case competitionID = "competition_id"
        case profileID = "profile_id"
        case role
    }

    static let columns = "competition_id, profile_id, role"
}

nonisolated enum StaffList {
    /// Arrangørene først, så funksjonærene, hver etter navn.
    static func sorted(_ staff: [CompetitionStaffRow], name: (UUID) -> String) -> [CompetitionStaffRow] {
        staff.sorted { a, b in
            if a.role != b.role { return a.role == .organizer }
            return NorwegianSort.areInIncreasingOrder(name(a.profileID), name(b.profileID))
        }
    }

    /// Hvem som kan legges til: folk med innlogging som ikke er i staben, etter navn.
    static func candidates(_ people: [(profileID: UUID, name: String)], staff: [CompetitionStaffRow])
        -> [(profileID: UUID, name: String)] {
        let taken = Set(staff.map(\.profileID))
        var seen = Set<UUID>()
        return people
            .filter { !taken.contains($0.profileID) && seen.insert($0.profileID).inserted }
            .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
    }
}

// MARK: - Startliste (sql/031 round_start_groups, lagres med save_start_list i 032)

/// En gruppe i startlista slik den er lagret.
nonisolated struct RoundStartGroupRow: Codable, Equatable, Sendable {
    let roundID: UUID
    var groupNo: Int
    /// «18:10:00».
    var startsAt: String?
    var startHole: Int?
    var resourceLabel: String?
    var scorerID: UUID?

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case groupNo = "group_no"
        case startsAt = "starts_at"
        case startHole = "start_hole"
        case resourceLabel = "resource_label"
        case scorerID = "scorer_id"
    }

    static let columns = "round_id, group_no, starts_at, start_hole, resource_label, scorer_id"
}

/// En gruppe i startlista mens arrangøren endrer den. Spillerne er båsfordelingen fra
/// runde-oppsettet (`round_players.bay_no`).
nonisolated struct StartGroupDraft: Equatable, Identifiable, Sendable {
    var groupNo: Int
    /// «18:10», eller tom.
    var startsAt: String?
    var startHole: Int?
    var resourceLabel: String
    var scorerID: UUID?
    var memberIDs: [UUID]

    var id: Int { groupNo }
}

nonisolated struct SaveStartListParams: Encodable, Equatable, Sendable {
    struct Group: Encodable, Equatable, Sendable {
        let group_no: Int
        let starts_at: String?
        let start_hole: Int?
        let resource_label: String?
        let scorer_id: UUID?

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(group_no, forKey: .group_no)
            try c.encode(starts_at, forKey: .starts_at)
            try c.encode(start_hole, forKey: .start_hole)
            try c.encode(resource_label, forKey: .resource_label)
            try c.encode(scorer_id, forKey: .scorer_id)
        }

        enum CodingKeys: String, CodingKey { case group_no, starts_at, start_hole, resource_label, scorer_id }
    }

    let p_round_id: UUID
    let p_wave_no: Int
    let p_groups: [Group]
}

nonisolated enum StartList {
    /// Gruppene fra båsfordelingen, med det som er lagret. Grupper som er lagret, men ikke har
    /// spillere lenger, står med tom spillerliste (arrangøren kan slette dem). En runde uten
    /// båser eller flighter har ingen grupper.
    static func groups(players: [RoundPlayerRow], saved: [RoundStartGroupRow], venue: String?) -> [StartGroupDraft] {
        let byGroup = Dictionary(grouping: players.filter { $0.bayNo != nil }, by: { $0.bayNo! })
        let savedByNo = Dictionary(saved.map { ($0.groupNo, $0) }, uniquingKeysWith: { first, _ in first })
        let numbers = Set(byGroup.keys).union(savedByNo.keys).sorted()
        return numbers.map { no in
            let s = savedByNo[no]
            return StartGroupDraft(groupNo: no,
                                   startsAt: s?.startsAt.map(timeText),
                                   startHole: s?.startHole,
                                   resourceLabel: s?.resourceLabel ?? defaultLabel(no, venue: venue),
                                   scorerID: s?.scorerID,
                                   memberIDs: (byGroup[no] ?? []).map(\.memberID))
        }
    }

    /// «Bås 3» i simulatoren, tom på ekte bane (flight uten ressurs).
    static func defaultLabel(_ groupNo: Int, venue: String?) -> String {
        venue == "course" ? "" : "Bås \(groupNo)"
    }

    /// Tee-tider med fast mellomrom fra første gruppe («18:00», 10 min → 18:00, 18:10, …).
    static func fillTimes(_ groups: [StartGroupDraft], first: String, intervalMinutes: Int) -> [StartGroupDraft] {
        guard let start = minutes(first) else { return groups }
        return groups.enumerated().map { i, g in
            var g = g
            g.startsAt = clock(start + i * max(intervalMinutes, 0))
            return g
        }
    }

    /// Kanonstart: alle starter samtidig, gruppe nr. i på hull i (rundt, når det er flere grupper
    /// enn hull). Tiden fra første gruppe brukes for alle.
    static func shotgun(_ groups: [StartGroupDraft], holeCount: Int) -> [StartGroupDraft] {
        guard holeCount > 0 else { return groups }
        let time = groups.first?.startsAt
        return groups.enumerated().map { i, g in
            var g = g
            g.startHole = i % holeCount + 1
            if time != nil { g.startsAt = time }
            return g
        }
    }

    /// Samme sjekker som `save_start_list` (sql/032), med norsk tekst.
    static func issues(_ groups: [StartGroupDraft], wave: Int, holeCount: Int, staffIDs: Set<UUID>) -> [String] {
        var out: [String] = []
        if !(1...20).contains(wave) { out.append("Puljen må være mellom 1 og 20.") }
        if groups.count > 99 { out.append("Høyst 99 grupper.") }
        let numbers = groups.map(\.groupNo)
        if Set(numbers).count != numbers.count { out.append("To grupper har samme nummer.") }
        if numbers.contains(where: { !(1...99).contains($0) }) { out.append("Gruppenummeret må være mellom 1 og 99.") }
        if groups.contains(where: { g in g.startHole.map { !(1...max(holeCount, 1)).contains($0) } ?? false }) {
            out.append("Starthullet må være mellom 1 og \(holeCount).")
        }
        if groups.contains(where: { g in g.startsAt.map { minutes($0) == nil } ?? false }) {
            out.append("Starttiden må være på formen TT:MM.")
        }
        if groups.contains(where: { g in g.scorerID.map { !staffIDs.contains($0) } ?? false }) {
            out.append("En funksjonær er ikke lenger i staben.")
        }
        if groups.contains(where: { $0.resourceLabel.trimmingCharacters(in: .whitespaces).count > 40 }) {
            out.append("Bås eller tee kan ha høyst 40 tegn.")
        }
        return out
    }

    static func params(roundID: UUID, wave: Int, groups: [StartGroupDraft]) -> SaveStartListParams {
        SaveStartListParams(p_round_id: roundID, p_wave_no: wave, p_groups: groups.map { g in
            let label = g.resourceLabel.trimmingCharacters(in: .whitespaces)
            return .init(group_no: g.groupNo, starts_at: g.startsAt, start_hole: g.startHole,
                         resource_label: label.isEmpty ? nil : label, scorer_id: g.scorerID)
        })
    }

    /// Min gruppe i runden: gruppenummeret (båsen), det som er lagret, og de andre i gruppa.
    struct MyGroup: Equatable, Sendable {
        let groupNo: Int
        let saved: RoundStartGroupRow?
        let mates: [UUID]
    }

    static func myGroup(memberID: UUID, players: [RoundPlayerRow], saved: [RoundStartGroupRow]) -> MyGroup? {
        guard let me = players.first(where: { $0.memberID == memberID }), let no = me.bayNo else { return nil }
        let mates = players.filter { $0.bayNo == no && $0.memberID != memberID }.map(\.memberID)
        return MyGroup(groupNo: no, saved: saved.first { $0.groupNo == no }, mates: mates)
    }

    /// «Bås 3 · 18:10 · starter på hull 10 · pulje 2». Hull 1 og pulje 1 nevnes ikke.
    static func summary(groupNo: Int, saved: RoundStartGroupRow?, wave: Int = 1, venue: String?) -> String {
        var parts: [String] = []
        let label = saved?.resourceLabel?.trimmingCharacters(in: .whitespaces)
        if let label, !label.isEmpty {
            parts.append(label)
        } else {
            parts.append(venue == "course" ? "Flight \(groupNo)" : "Bås \(groupNo)")
        }
        if let time = saved?.startsAt { parts.append(timeText(time)) }
        if let hole = saved?.startHole, hole != 1 { parts.append("starter på hull \(hole)") }
        if wave > 1 { parts.append("pulje \(wave)") }
        return parts.joined(separator: " · ")
    }

    /// «med Anders, Bjørn og Cato», eller nil når du er alene i gruppa.
    static func matesText(_ names: [String]) -> String? {
        guard let last = names.last else { return nil }
        if names.count == 1 { return "med \(last)" }
        return "med " + names.dropLast().joined(separator: ", ") + " og " + last
    }

    /// «Anders, Bjørn» for gruppa i startlista.
    static func namesText(_ names: [String]) -> String {
        names.isEmpty ? "Ingen spillere" : names.joined(separator: ", ")
    }

    /// «18:10:00» → «18:10».
    static func timeText(_ time: String) -> String {
        String(time.prefix(5))
    }

    /// «18:10» → 1090 minutter, eller nil.
    static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 1090 → «18:10» (rundt midnatt).
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

// MARK: - Minste appbygg (sql/031 app_config.min_ios_build)

/// «Oppdater appen»: databasen kan stenge ute gamle bygg før trinn 4 (sql/034). Ikke bak flagget.
/// En feil ved lesing sperrer aldri appen.
nonisolated enum MinimumBuild {
    /// Bygget som kjører (`CFBundleVersion`), som heltall.
    static func currentBuild(_ info: [String: Any]? = Bundle.main.infoDictionary) -> Int? {
        guard let text = info?["CFBundleVersion"] as? String else { return nil }
        return Int(text.trimmingCharacters(in: .whitespaces))
    }

    /// Er bygget for gammelt? Bare når begge er kjent og kravet er over 0.
    static func isOutdated(current: Int?, required: Int?) -> Bool {
        guard let current, let required, required > 0 else { return false }
        return current < required
    }
}

/// `app_config.value` for `min_ios_build`: `{"build": 42}`. Tåler tall som tekst, og alt annet
/// gir «ukjent» (ingen sperre).
nonisolated struct MinimumBuildValue: Decodable, Equatable, Sendable {
    let build: Int?

    init(build: Int?) { self.build = build }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decode(Int.self, forKey: .build) {
            build = n
        } else if let s = try? c.decode(String.self, forKey: .build) {
            build = Int(s)
        } else {
            build = nil
        }
    }

    enum CodingKeys: String, CodingKey { case build }
}

nonisolated struct AppConfigMinBuildRow: Decodable, Sendable {
    let value: MinimumBuildValue?
}
