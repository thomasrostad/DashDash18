import Supabase
import SwiftUI

/// Det en skjerm inne i appen trenger for å lese og skrive data for den valgte klubben.
/// Settes i miljøet av `RootView`, så alle skjermer under fanene kan hente det med
/// `@Environment(\.clubContext)`.
struct ClubContext {
    let client: SupabaseClient
    let user: AuthUser
    let membership: Membership

    var clubID: UUID { membership.clubID }
    var memberID: UUID { membership.id }
    var isOrganizer: Bool { membership.isOrganizer }
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
        case "22023", "23514", "23503", "55000", "P0002": .invalid(message)
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
