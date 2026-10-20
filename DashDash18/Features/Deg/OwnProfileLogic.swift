import Foundation

// Din egen profil (`profiles`): navn, handicapindeks og NGF-medlemsnummer.
// Uten klubb er profilen det eneste stedet navnet og handicapet står, og det er det som brukes i
// løse runder, i søk og når du blir deltaker i en turnering (sql/059 `ensure_participant`).
// Med klubb står navn og handicap i medlemskapet (`DegProfileLogic`); da endres bare NGF-nummeret her.
// Ren logikk: skjemaet, sjekken, hva som sendes og sjekken av raden som kommer tilbake.
// Nettverket ligger i `OwnProfileModel`.

/// Egen profilrad, med kolonnene skjemaet trenger. `ngf_number` hentes bare for deg selv.
nonisolated struct OwnProfileRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String?
    var handicapIndex: Double?
    var ngfNumber: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case ngfNumber = "ngf_number"
    }

    static let columns = "id, display_name, handicap_index, ngf_number"
}

/// NGF-medlemsnummeret: sifre, eventuelt to grupper med bindestrek, som i databasen
/// (`profiles_ngf_number_check`: `^[0-9]{1,12}(-[0-9]{1,12})?$`). Mellomrom ignoreres. Tomt = ingen.
nonisolated enum NGFNumber {
    static func normalized(_ raw: String) -> Result<String?, OwnProfileError> {
        let text = String(raw.filter { !$0.isWhitespace })
        if text.isEmpty { return .success(nil) }
        guard text.wholeMatch(of: /[0-9]{1,12}(-[0-9]{1,12})?/) != nil else {
            return .failure(.invalid("NGF-nummeret er bare sifre, f.eks. 12345 eller 12-345."))
        }
        return .success(text)
    }
}

/// Hva skjemaet endrer: alt (uten klubb), eller bare NGF-nummeret (med klubb).
nonisolated enum OwnProfileScope: Equatable, Sendable {
    case full
    case ngfOnly
}

/// Det som står i skjemaet, som tekst.
nonisolated struct OwnProfileDraft: Equatable, Sendable {
    var name: String
    var handicap: String
    var ngf: String
    var scope: OwnProfileScope

    init(name: String, handicap: String, ngf: String, scope: OwnProfileScope = .full) {
        self.name = name
        self.handicap = handicap
        self.ngf = ngf
        self.scope = scope
    }

    init(row: OwnProfileRow, scope: OwnProfileScope = .full) {
        self.init(
            name: row.displayName ?? "",
            handicap: TroppInput.handicapText(row.handicapIndex),
            ngf: row.ngfNumber ?? "",
            scope: scope
        )
    }

    /// Samme regler som klubbskjemaene (`ClubInput`): navn 1–40 tegn etter trimming, handicap med
    /// komma eller punktum og «+» for plusshandicap. Tomt handicap og NGF-nummer = ikke oppgitt.
    func validate() -> Result<OwnProfileChange, OwnProfileError> {
        let ngfNumber: String?
        switch NGFNumber.normalized(ngf) {
        case .success(let number): ngfNumber = number
        case .failure(let error): return .failure(error)
        }
        guard scope == .full else {
            return .success(OwnProfileChange(nameAndHandicap: nil, ngfNumber: ngfNumber))
        }
        guard let name = ClubInput.normalizedName(name) else {
            return .failure(.invalid("Skriv inn et navn (høyst 40 tegn)."))
        }
        switch ClubInput.handicapIndex(handicap) {
        case .success(let index):
            return .success(OwnProfileChange(nameAndHandicap: .init(name: name, handicapIndex: index), ngfNumber: ngfNumber))
        case .failure(let error):
            return .failure(.invalid(error.message))
        }
    }

    /// Om skjemaet er endret fra raden. Sammenligner verdiene, så «18.4» og «18,4» er det samme.
    func hasChanges(from row: OwnProfileRow) -> Bool {
        switch validate() {
        case .success(let change): !change.matches(row)
        case .failure: self != OwnProfileDraft(row: row, scope: scope)
        }
    }
}

/// Gyldige verdier, klare til å sendes.
nonisolated struct OwnProfileChange: Equatable, Sendable {
    nonisolated struct NameAndHandicap: Equatable, Sendable {
        let name: String
        let handicapIndex: Double?
    }

    /// nil når bare NGF-nummeret endres (med klubb).
    let nameAndHandicap: NameAndHandicap?
    let ngfNumber: String?

    var patch: OwnProfilePatch {
        OwnProfilePatch(nameAndHandicap: nameAndHandicap, ngfNumber: ngfNumber)
    }

    /// Om raden har akkurat disse verdiene. Handicap lagres med én desimal.
    func matches(_ row: OwnProfileRow) -> Bool {
        guard row.ngfNumber == ngfNumber else { return false }
        guard let nameAndHandicap else { return true }
        guard row.displayName == nameAndHandicap.name else { return false }
        switch (row.handicapIndex, nameAndHandicap.handicapIndex) {
        case (nil, nil): return true
        case let (stored?, wanted?): return abs(stored - wanted) < 0.05
        default: return false
        }
    }
}

/// Kolonnene som sendes. Tomt handicap og NGF-nummer sendes som `null`.
nonisolated struct OwnProfilePatch: Encodable, Equatable, Sendable {
    let nameAndHandicap: OwnProfileChange.NameAndHandicap?
    let ngfNumber: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handicapIndex = "handicap_index"
        case ngfNumber = "ngf_number"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let nameAndHandicap {
            try c.encode(nameAndHandicap.name, forKey: .displayName)
            if let index = nameAndHandicap.handicapIndex {
                try c.encode(index, forKey: .handicapIndex)
            } else {
                try c.encodeNil(forKey: .handicapIndex)
            }
        }
        if let ngfNumber { try c.encode(ngfNumber, forKey: .ngfNumber) } else { try c.encodeNil(forKey: .ngfNumber) }
    }
}

nonisolated enum OwnProfile {
    /// Navnet mangler: da heter du «Spiller» for de andre og kan ikke finnes i søk.
    static func needsName(_ displayName: String?) -> Bool {
        (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sjekker raden(e) som kom tilbake. Stopper RLS en update, kommer det null rader (SPEC 3.2).
    static func verify(
        returned rows: [OwnProfileRow],
        userID: UUID,
        change: OwnProfileChange
    ) -> Result<OwnProfileRow, OwnProfileError> {
        guard rows.count == 1, let row = rows.first, row.id == userID else {
            return .failure(.notSaved)
        }
        guard change.matches(row) else { return .failure(.mismatch) }
        return .success(row)
    }
}

/// Navnet Apple gir ved første innlogging (bare da). Lagres som profilnavn når profilen ikke har
/// et navn fra før, så et navn brukeren har satt selv, aldri overskrives.
nonisolated enum AppleName {
    /// «Fornavn Etternavn», eller bare fornavnet når hele blir for langt (høyst 40 tegn, som i databasen).
    static func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let parts = [components.givenName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let full = ClubInput.normalizedName(parts.joined(separator: " ")) { return full }
        return components.givenName.flatMap { ClubInput.normalizedName($0) }
    }

    /// Navnet som skal lagres, eller nil når profilen alt har et navn (eller Apple ikke ga noe).
    static func nameToSave(apple: String?, existing: String?) -> String? {
        guard let apple, OwnProfile.needsName(existing) else { return nil }
        return apple
    }
}

/// Feil i profilskjemaet, med norsk tekst.
nonisolated enum OwnProfileError: Error, Equatable {
    case invalid(String)
    case ngfTaken
    case notSaved
    case mismatch
    case other(DataError)

    var message: String {
        switch self {
        case .invalid(let text): text
        case .ngfTaken: "Det NGF-nummeret er registrert på en annen bruker."
        case .notSaved: "Endringen ble ikke lagret. Last inn på nytt og prøv igjen."
        case .mismatch: "Serveren lagret noe annet enn du skrev. Last inn på nytt og sjekk."
        case .other(let error): error.message
        }
    }

    /// Oversetter SQLSTATE. Det eneste unike på profilen du kan skrive, er NGF-nummeret (`profiles_unique_ngf`).
    static func from(sqlState: String?, message: String) -> OwnProfileError {
        switch sqlState {
        case "23505": .ngfTaken
        case "23514": .invalid("Verdien er ikke gyldig.")
        default: .other(DataError.from(sqlState: sqlState, message: message))
        }
    }
}
