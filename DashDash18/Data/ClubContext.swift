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
    case unknown(String)

    var message: String {
        switch self {
        case .notAllowed: "Du har ikke tilgang til dette."
        case .duplicate: "Det finnes allerede."
        case .invalid(let text): text
        case .offline: "Ingen kontakt med serveren. Sjekk nettet og prøv igjen."
        case .unknown(let detail): "Noe gikk galt: \(detail)"
        }
    }

    static func from(sqlState: String?, message: String) -> DataError {
        switch sqlState {
        case "42501": .notAllowed
        case "23505": .duplicate
        case "22023", "23514", "23503", "55000", "P0002", "54000": .invalid(message)
        // Fristen for påmelding eller avmelding er ute (sql/045).
        case "DDB02": .invalid(EveningSignupText.deadlinePassed)
        default: .unknown(message)
        }
    }

    static func from(_ error: any Error) -> DataError {
        if let error = error as? DataError { return error }
        if let postgrest = error as? PostgrestError {
            return from(sqlState: postgrest.code, message: postgrest.message)
        }
        if error is URLError { return .offline }
        return .unknown(error.localizedDescription)
    }
}
