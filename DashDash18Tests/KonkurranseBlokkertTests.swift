import Foundation
import Supabase
import Testing
@testable import DashDash18

/// sql/025: den som har en blokkering mot eieren, kan ikke bli med i konkurransen med koden.
/// «Bli med» svarer DDB01, og appen viser en norsk melding som ikke sier «blokkert».
struct KonkurranseBlokkertTests {
    @Test func blockedClaimGivesNorwegianMessage() {
        let error = PostgrestError(code: "DDB01", message: "Du kan ikke bli med i denne konkurransen")
        #expect(CompetitionInviteErrors.message(for: error) == "Du kan ikke bli med i denne konkurransen.")
        #expect(!CompetitionInviteErrors.message(for: error).lowercased().contains("blokk"))
        #expect(!CompetitionInviteErrors.message(for: error).hasPrefix("Noe gikk galt"))
    }

    @Test func blockedBySqlState() {
        #expect(CompetitionInviteErrors.message(sqlState: "DDB01", fallback: .unknown("x"))
                == CompetitionInviteErrors.blockedMessage)
    }

    /// Forhåndsvisningen svarer som for en ukjent kode (P0002), og de andre feilene fra 022 går
    /// gjennom den felles oversettelsen som før.
    @Test func otherErrorsUseDataError() {
        let unknownCode = PostgrestError(code: "P0002", message: "Fant ingen konkurranse med den koden. Den kan ha gått ut.")
        #expect(CompetitionInviteErrors.message(for: unknownCode) == "Fant ingen konkurranse med den koden. Den kan ha gått ut.")
        let finished = PostgrestError(code: "55000", message: "Konkurransen er ferdig")
        #expect(CompetitionInviteErrors.message(for: finished) == "Konkurransen er ferdig")
        #expect(CompetitionInviteErrors.message(for: PostgrestError(code: "42501", message: "x")) == DataError.notAllowed.message)
        #expect(CompetitionInviteErrors.message(for: URLError(.notConnectedToInternet)) == DataError.offline.message)
        #expect(CompetitionInviteErrors.message(sqlState: nil, fallback: .offline) == DataError.offline.message)
    }
}
