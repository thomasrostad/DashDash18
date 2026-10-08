import Foundation
import Supabase

/// Feil fra invitasjonen til en privat konkurranse (`competition_invite_preview` og
/// `claim_competition_invite`, sql/022 og 025) som norsk tekst.
///
/// DDB01 (sql/025): det er en blokkering mellom deg og eieren, så du kan ikke bli med med
/// koden. Meldingen sier ikke «blokkert» (sql/019: den blokkerte får ikke vite det).
/// Forhåndsvisningen svarer da som for en ukjent kode (P0002), så DDB01 kommer bare fra «Bli med».
/// Resten går til den felles oversettelsen i `DataError`.
nonisolated enum CompetitionInviteErrors {
    static let blockedSQLState = "DDB01"
    static let blockedMessage = "Du kan ikke bli med i denne turneringen."

    static func message(sqlState: String?, fallback: DataError) -> String {
        sqlState == blockedSQLState ? blockedMessage : fallback.message
    }

    static func message(for error: any Error) -> String {
        message(sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error))
    }
}
