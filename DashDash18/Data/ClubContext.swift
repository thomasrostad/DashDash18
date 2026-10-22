import Supabase
import SwiftUI

/// Det en skjerm inne i appen trenger for å lese og skrive data for den valgte klubben.
/// Settes i miljøet av `RootView`, så alle skjermer under fanene kan hente det med
/// `@Environment(\.clubContext)`.
struct ClubContext {
    let client: SupabaseClient
    let user: AuthUser
    let membership: Membership
    /// Rollene i klubben (sql/044). nil når 044 ikke er kjørt eller rollene ikke er hentet ennå:
    /// da gjelder flaggene `is_organizer` og `is_treasurer`, som før.
    var roleAccess: ClubRoleAccess? = nil

    var clubID: UUID { membership.clubID }
    var memberID: UUID { membership.id }

    /// Rettighetene den innloggede har i klubben. Bare for å skjule; serveren er vakta.
    var rights: ClubRights {
        roleAccess?.rights ?? .legacy(isOrganizer: membership.isOrganizer, isTreasurer: membership.isTreasurer)
    }

    /// Minst én rettighet (som `is_club_organizer`). Flagget teller også, så ingen dagens arrangør
    /// mister noe mens rollene hentes.
    var isOrganizer: Bool { membership.isOrganizer || rights.hasAny }

    func can(_ right: ClubRight) -> Bool { rights.has(right) }
}

extension EnvironmentValues {
    @Entry var clubContext: ClubContext?
}

/// Felles oversetting av feil fra Supabase til norsk tekst, for alle skjermer.
nonisolated enum DataError: Error, Equatable {
    case notAllowed
    case duplicate
    case invalid(String)
    case offline
    /// Serveren svarer med 5xx, eller PostgREST når ikke databasen.
    case serverDown
    /// Tokenet er utløpt eller avvist (PostgREST PGRST3xx, «JWT …», HTTP 401).
    case sessionExpired
    /// Detaljen er bare for feilsøking. Den vises aldri.
    case unknown(String)

    var message: String {
        switch self {
        case .notAllowed: "Du har ikke tilgang til dette."
        case .duplicate: "Det finnes allerede."
        case .invalid(let text): text
        case .offline: "Ingen kontakt med serveren. Sjekk nettet og prøv igjen."
        case .serverDown: "Serveren svarer ikke akkurat nå. Prøv igjen om litt."
        case .sessionExpired: "Innloggingen har gått ut. Lukk og åpne appen, eller logg inn på nytt."
        case .unknown: "Det oppsto en ukjent feil."
        }
    }

    /// Brukes når databasen avviser noe med sin egen engelske tekst.
    static let rejectedText = "Serveren godtok ikke endringen. Sjekk det du fylte inn og prøv igjen."

    static func from(sqlState: String?, message: String) -> DataError {
        switch sqlState {
        case "42501": .notAllowed
        case "23505": .duplicate
        case "22023", "55000", "P0002": .invalid(message)
        // Våre egne `raise` har norsk tekst. Postgres sine egne (brutt sjekk, fremmednøkkel,
        // grense) er engelske og byttes ut.
        case "23514", "23503", "54000": .invalid(isPostgresDefault(message) ? rejectedText : message)
        // Fristen for påmelding eller avmelding er ute (sql/045).
        case "DDB02": .invalid(EveningSignupText.deadlinePassed)
        default: .unknown(message)
        }
    }

    static func from(_ error: any Error) -> DataError {
        if let error = error as? DataError { return error }
        if let postgrest = error as? PostgrestError {
            let code = postgrest.code ?? ""
            if code.hasPrefix("PGRST3") || postgrest.message.contains("JWT") { return .sessionExpired }
            if code.hasPrefix("PGRST0") { return .serverDown }
            return from(sqlState: postgrest.code, message: postgrest.message)
        }
        if let http = error as? HTTPError { return from(status: http.response.statusCode) }
        if case .httpError(let code, _) = error as? FunctionsError { return from(status: code) }
        if error is URLError { return .offline }
        return .unknown(error.localizedDescription)
    }

    /// Avbrutt av appen selv (skjermen lukket, ny henting startet). Skal ikke vises som feil.
    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private static func from(status: Int) -> DataError {
        switch status {
        case 401: .sessionExpired
        case 500...599: .serverDown
        default: .unknown("HTTP \(status)")
        }
    }

    /// Postgres sine standardmeldinger for 23514, 23503 og 54000 er engelske og starter likt.
    private static func isPostgresDefault(_ message: String) -> Bool {
        let text = message.lowercased()
        let prefixes = ["new row", "insert or update", "update or delete", "check constraint", "value for domain",
                        "stack depth", "index row", "row is too big", "value too long", "cannot ", "too many"]
        return text.isEmpty || text.contains("violates") || prefixes.contains { text.hasPrefix($0) }
    }
}
