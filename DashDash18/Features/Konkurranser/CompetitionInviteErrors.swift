import Foundation
import Supabase

/// Feil fra invitasjonen til en privat konkurranse (`competition_invite_preview` og
/// `claim_competition_invite`, sql/022 og 025) som norsk tekst.
///
/// DDB01 (sql/025): det er en blokkering mellom deg og eieren, så du kan ikke bli med med
/// koden. Meldingen sier ikke «blokkert» (sql/019: den blokkerte får ikke vite det).
/// Forhåndsvisningen svarer da som for en ukjent kode (P0002), så DDB01 kommer bare fra «Bli med».
/// Klubbturneringer (sql/060) gir to nye 55000-feil når du tar et ledig navn: navnet er tatt (noen
/// kom før deg), eller du har en ventende eller arkivert rad i klubben fra før.
/// Resten går til den felles oversettelsen i `DataError`.
nonisolated enum CompetitionInviteErrors {
    static let blockedSQLState = "DDB01"
    static let blockedMessage = "Du kan ikke bli med i denne turneringen."
    static let nameTakenMessage = "Noen har tatt det navnet, eller det finnes ikke lenger. Velg et annet, eller meld deg på som ny."
    static let existingRowMessage = "Du har allerede en rad i klubben (kanskje venter den på godkjenning, eller er arkivert). Spør arrangøren."

    static func message(sqlState: String?, fallback: DataError) -> String {
        sqlState == blockedSQLState ? blockedMessage : fallback.message
    }

    static func message(for error: any Error) -> String {
        let postgrest = error as? PostgrestError
        if postgrest?.code == "55000", let text = postgrest?.message {
            if text.hasPrefix("Navnet er tatt") { return nameTakenMessage }
            if text.hasPrefix("Du har allerede en rad i klubben") { return existingRowMessage }
        }
        return message(sqlState: postgrest?.code, fallback: DataError.from(error))
    }

    /// Navnet du valgte er tatt: lista over ledige navn må hentes på nytt.
    static func isNameTaken(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return postgrest.code == "55000" && postgrest.message.hasPrefix("Navnet er tatt")
    }
}
