import Foundation

// Spilleren endrer sitt eget visningsnavn og sin handicapindeks under «Deg».
// Ren logikk: skjemaet, sjekken av det som skrives, hva som sendes, og sjekken
// av raden som kommer tilbake. Nettverket ligger i `DegProfileModel`.

/// Det som står i skjemaet, som tekst.
nonisolated struct DegProfileDraft: Equatable, Sendable {
    var name: String
    var handicap: String

    init(name: String, handicap: String) {
        self.name = name
        self.handicap = handicap
    }

    /// Skjemaet fylt ut fra egen rad i troppen.
    init(row: ClubMemberRow) {
        self.init(name: row.displayName, handicap: TroppInput.handicapText(row.handicapIndex))
    }

    /// Sjekker skjemaet som klubbskjemaene (`ClubInput`): navn 1–40 tegn etter
    /// trimming, handicap med komma eller punktum, «+» for plusshandicap, tomt = ikke oppgitt.
    func validate() -> Result<DegProfileChange, DegProfileError> {
        guard let name = ClubInput.normalizedName(name) else {
            return .failure(.invalid("Skriv inn et navn (høyst 40 tegn)."))
        }
        switch ClubInput.handicapIndex(handicap) {
        case .success(let index):
            return .success(DegProfileChange(name: name, handicapIndex: index))
        case .failure(let error):
            return .failure(.invalid(error.message))
        }
    }

    /// Om skjemaet er endret fra raden (det er bare da «Lagre» gir mening).
    /// Sammenligner verdiene, ikke teksten, så «18.4» og «18,4» er det samme.
    func hasChanges(from row: ClubMemberRow) -> Bool {
        switch validate() {
        case .success(let change): !change.matches(row)
        case .failure: self != DegProfileDraft(row: row)
        }
    }
}

/// Et gyldig navn og handicap, klart til å sendes.
nonisolated struct DegProfileChange: Equatable, Sendable {
    let name: String
    let handicapIndex: Double?

    /// Bare de to kolonnene spilleren selv har lov til å endre på egen rad.
    /// Kolonnevakten i databasen (`guard_club_members`) stopper rolle, seeding,
    /// status og innloggingskobling. Tomt handicap sendes som `null`.
    var patch: MemberPatch {
        MemberPatch(displayName: name, handicapIndex: .some(handicapIndex))
    }

    /// Om raden har akkurat disse verdiene. Handicap lagres med én desimal.
    func matches(_ row: ClubMemberRow) -> Bool {
        guard row.displayName == name else { return false }
        switch (row.handicapIndex, handicapIndex) {
        case (nil, nil): return true
        case let (stored?, wanted?): return abs(stored - wanted) < 0.05
        default: return false
        }
    }
}

/// Handicapet i toppen av Deg (PWA: `hcpTekst`, «hcp 12,4»). Plusshandicap med «+».
nonisolated enum DegHandicapText {
    static func short(_ index: Double?) -> String {
        guard let index else { return "hcp ikke oppgitt" }
        return "hcp " + TroppInput.handicapText(index)
    }
}

nonisolated enum DegProfile {
    /// Kolonnene spilleren kan skrive på egen rad uten å være arrangør.
    static let ownWritableColumns: Set<String> = ["display_name", "handicap_index", "avatar_path"]

    /// Sjekker raden(e) som kom tilbake. PostgREST sier ikke fra når RLS stopper en
    /// update; da kommer det bare null rader tilbake (SPEC 3.2).
    static func verify(
        returned rows: [ClubMemberRow],
        memberID: UUID,
        change: DegProfileChange
    ) -> Result<ClubMemberRow, DegProfileError> {
        guard rows.count == 1, let row = rows.first, row.id == memberID else {
            return .failure(.notSaved)
        }
        guard change.matches(row) else {
            return .failure(.mismatch)
        }
        return .success(row)
    }
}

/// Feil i «Deg»-skjemaet, med norsk tekst.
nonisolated enum DegProfileError: Error, Equatable {
    case invalid(String)
    case duplicateName
    case notSaved
    case mismatch
    case other(DataError)

    var message: String {
        switch self {
        case .invalid(let text): text
        case .duplicateName: "Det navnet finnes allerede i troppen."
        case .notSaved: "Endringen ble ikke lagret. Du har kanskje ikke tilgang lenger. Last inn på nytt."
        case .mismatch: "Serveren lagret noe annet enn du skrev. Last inn på nytt og sjekk."
        case .other(let error): error.message
        }
    }

    /// Oversetter SQLSTATE fra databasen (se `sql/README.md`, feilkoder).
    static func from(sqlState: String?, message: String) -> DegProfileError {
        switch sqlState {
        case "23505": .duplicateName
        case "23514": .invalid("Verdien er ikke gyldig.")
        default: .other(DataError.from(sqlState: sqlState, message: message))
        }
    }
}
