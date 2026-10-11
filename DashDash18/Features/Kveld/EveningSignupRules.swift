import Foundation

// Påmelding per kveld (gjennomføringsplanen steg 4, sql/045): tak, venteliste, frister, gjester,
// «sett» og logg. Serveren er vakta (triggerne og RPC-ene). Her er radene og det appen viser.
// Uten sql/045 finnes ikke kolonnene og tabellene: da hentes ingenting av dette, og alt er som før.

/// Arrangørens innstillinger for påmeldingen på en kveld (kolonnene fra sql/045 på `events`).
nonisolated struct EveningSettingsRow: Codable, Equatable, Sendable {
    let id: UUID
    /// nil: ingen grense.
    var maxPlayers: Int?
    /// nil: ingen frist.
    var signupDeadline: Date?
    var withdrawDeadline: Date?
    var allowGuests: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case maxPlayers = "max_players"
        case signupDeadline = "signup_deadline"
        case withdrawDeadline = "withdraw_deadline"
        case allowGuests = "allow_guests"
    }

    static let columns = "id, max_players, signup_deadline, withdraw_deadline, allow_guests"

    /// Slik en kveld er uten noe slått på.
    static func off(_ id: UUID) -> EveningSettingsRow {
        EveningSettingsRow(id: id, maxPlayers: nil, signupDeadline: nil, withdrawDeadline: nil, allowGuests: false)
    }
}

/// Det som skrives til `events` når arrangøren endrer innstillingene. Tomme felt sendes som null.
nonisolated struct EveningSettingsWrite: Encodable, Sendable {
    let maxPlayers: Int?
    let signupDeadline: Date?
    let withdrawDeadline: Date?
    let allowGuests: Bool

    enum CodingKeys: String, CodingKey {
        case maxPlayers = "max_players"
        case signupDeadline = "signup_deadline"
        case withdrawDeadline = "withdraw_deadline"
        case allowGuests = "allow_guests"
    }

    init(_ s: EveningSettingsRow) {
        maxPlayers = s.maxPlayers
        signupDeadline = s.signupDeadline
        withdrawDeadline = s.withdrawDeadline
        allowGuests = s.allowGuests
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxPlayers, forKey: .maxPlayers)
        try c.encode(signupDeadline, forKey: .signupDeadline)
        try c.encode(withdrawDeadline, forKey: .withdrawDeadline)
        try c.encode(allowGuests, forKey: .allowGuests)
    }
}

/// En gjest på kvelden (`event_guests`).
nonisolated struct EventGuestRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let eventID: UUID
    let clubID: UUID
    var name: String
    let invitedBy: UUID
    var waitlistedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case clubID = "club_id"
        case name
        case invitedBy = "invited_by"
        case waitlistedAt = "waitlisted_at"
    }

    static let columns = "id, event_id, club_id, name, invited_by, waitlisted_at"
}

/// «Sett» (`event_views`): medlemmet har åpnet kvelden.
nonisolated struct EventViewRow: Codable, Equatable, Sendable {
    let eventID: UUID
    let memberID: UUID

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
    }

    static let columns = "event_id, member_id"
}

/// En linje i `signup_log`.
nonisolated struct SignupLogRow: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let eventID: UUID
    let memberID: UUID?
    let guestName: String?
    let oldStatus: String
    let newStatus: String
    let changedAt: Date
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case memberID = "member_id"
        case guestName = "guest_name"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case changedAt = "changed_at"
        case note
    }

    static let columns = "id, event_id, member_id, guest_name, old_status, new_status, changed_at, note"
}

/// Svaret fra `evening_signup`.
nonisolated struct EveningSignupResult: Decodable, Equatable, Sendable {
    var status: SignupStatus?
    var waitlisted: Bool
    var place: Int?
    var late: Bool
    var comment: String?

    enum CodingKeys: String, CodingKey {
        case status, waitlisted, place, late, comment
    }

    init(status: SignupStatus?, waitlisted: Bool = false, place: Int? = nil, late: Bool = false, comment: String? = nil) {
        self.status = status
        self.waitlisted = waitlisted
        self.place = place
        self.late = late
        self.comment = comment
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status).flatMap(SignupStatus.init(rawValue:))
        waitlisted = try c.decodeIfPresent(Bool.self, forKey: .waitlisted) ?? false
        place = try c.decodeIfPresent(Int.self, forKey: .place)
        late = try c.decodeIfPresent(Bool.self, forKey: .late) ?? false
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
    }
}

// MARK: - Tekstene

nonisolated enum EveningSignupText {
    /// SQLSTATE DDB02 fra triggerne og RPC-ene.
    static let deadlinePassed = "Fristen er ute. Kontakt arrangøren."

    /// «På venteliste (nr. 2)».
    static func waitlist(place: Int?) -> String {
        place.map { "På venteliste (nr. \($0))" } ?? "På venteliste"
    }

    /// Feilen under svarknappene. Fristen står alene; resten får «Klarte ikke å lagre svaret.» foran.
    static func answerError(_ error: DataError) -> String {
        if case .invalid(let text) = error, text == deadlinePassed { return text }
        return "Klarte ikke å lagre svaret. \(error.message)"
    }

    /// «14 av 16 plasser», «16 av 16 plasser · 2 på venteliste». nil uten tak.
    static func capacity(coming: Int, max: Int?, waitlist: Int) -> String? {
        guard let max else { return nil }
        var text = "\(coming) av \(max) plasser"
        if waitlist > 0 { text += " · \(waitlist) på venteliste" }
        return text
    }

    /// «Påmeldingsfrist torsdag 8. oktober kl. 12:00».
    static func deadline(_ title: String, _ date: Date) -> String {
        "\(title) \(EveningDates.longText(EveningDates.dateString(from: date))) kl. \(EveningDates.timeString(from: date).prefix(5))"
    }

    /// En linje i loggen: «Anders: Kommer ikke → Kommer», med merknaden etter.
    static func logLine(_ row: SignupLogRow, name: (UUID) -> String?) -> String {
        let who: String
        if let guest = row.guestName {
            who = "\(guest) (gjest av \(row.memberID.flatMap(name) ?? "et medlem"))"
        } else {
            who = row.memberID.flatMap(name) ?? "Tidligere medlem"
        }
        var text = "\(who): \(state(row.oldStatus)) → \(state(row.newStatus))"
        if let note = row.note.flatMap(noteText) { text += " (\(note))" }
        return text
    }

    static func state(_ raw: String) -> String {
        switch raw {
        case "yes": SignupStatus.yes.title
        case "maybe": SignupStatus.maybe.title
        case "no": SignupStatus.no.title
        case "waitlist": "Venteliste"
        default: "Ikke svart"
        }
    }

    static func noteText(_ raw: String) -> String? {
        switch raw {
        case "organizer": "endret av arrangøren"
        case "late": "etter fristen"
        case "promoted": "fikk plass"
        case "system": "automatisk"
        default: nil
        }
    }
}

// MARK: - Fristene

nonisolated enum SignupDeadline {
    /// Stopper fristen dette svaret? Som triggeren: ny «kommer» etter påmeldingsfristen, og
    /// avmelding fra bekreftet «kommer» etter avmeldingsfristen. Arrangøren kan alltid.
    static func blocks(_ settings: EveningSettingsRow?, current: SignupRow?, new: SignupStatus?,
                       now: Date, isOrganizer: Bool) -> Bool {
        guard let settings, !isOrganizer else { return false }
        let wasYes = current?.status == .yes
        if new == .yes, !wasYes, let deadline = settings.signupDeadline, now > deadline { return true }
        if current?.isConfirmed == true, new != .yes, let deadline = settings.withdrawDeadline, now > deadline {
            return true
        }
        return false
    }

    /// Gjest: påmeldingsfristen gjelder for å legge til, avmeldingsfristen for å fjerne en bekreftet.
    static func blocksGuest(_ settings: EveningSettingsRow?, adding: Bool, waitlisted: Bool,
                            now: Date, isOrganizer: Bool) -> Bool {
        guard let settings, !isOrganizer else { return false }
        if adding { return settings.signupDeadline.map { now > $0 } ?? false }
        return !waitlisted && (settings.withdrawDeadline.map { now > $0 } ?? false)
    }
}

// MARK: - Gjester

nonisolated enum GuestInput {
    static let nameMax = 60
    /// Høyst så mange gjester per medlem og kveld (arrangøren har ingen slik grense).
    static let perMember = 3

    /// Mellomrom slås sammen og trimmes. Tomt eller for langt gir en feil.
    static func clean(_ raw: String) -> Result<String, DataError> {
        let name = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if name.isEmpty { return .failure(.invalid("Skriv navnet på gjesten.")) }
        if name.count > nameMax { return .failure(.invalid("Navnet kan være høyst \(nameMax) tegn.")) }
        return .success(name)
    }
}

// MARK: - Arrangørens innstillinger

/// Skjemaet for tak, frister og gjester på en kveld. Alt er av som standard (Thomas 11.10.2026).
nonisolated struct EveningRulesDraft: Equatable, Sendable {
    var hasMax = false
    var maxPlayers = 12
    var hasSignupDeadline = false
    var signupDeadline = Date.now
    var hasWithdrawDeadline = false
    var withdrawDeadline = Date.now
    var allowGuests = false

    static let maxRange = 1...500

    init() {}

    /// Fra innstillingene som ligger lagret. `eventDate` er kvelden kl. 12 (`EveningDates.date`); en
    /// frist som ikke er satt, foreslås til kl. 12 dagen før.
    init(_ settings: EveningSettingsRow?, eventDate: Date) {
        let suggested = EveningDates.osloCalendar.date(byAdding: .day, value: -1, to: eventDate) ?? eventDate
        hasMax = settings?.maxPlayers != nil
        maxPlayers = settings?.maxPlayers ?? 12
        hasSignupDeadline = settings?.signupDeadline != nil
        signupDeadline = settings?.signupDeadline ?? suggested
        hasWithdrawDeadline = settings?.withdrawDeadline != nil
        withdrawDeadline = settings?.withdrawDeadline ?? suggested
        allowGuests = settings?.allowGuests ?? false
    }

    /// Det som lagres. Det som er slått av, blir null.
    func settings(id: UUID) -> EveningSettingsRow {
        EveningSettingsRow(id: id,
                           maxPlayers: hasMax ? min(max(maxPlayers, Self.maxRange.lowerBound), Self.maxRange.upperBound) : nil,
                           signupDeadline: hasSignupDeadline ? signupDeadline : nil,
                           withdrawDeadline: hasWithdrawDeadline ? withdrawDeadline : nil,
                           allowGuests: allowGuests)
    }
}
