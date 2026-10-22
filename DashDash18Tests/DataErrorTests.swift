import Foundation
import Supabase
import Testing
@testable import DashDash18

/// Felles feiltekst: brukeren skal aldri se rå engelsk fra serveren eller Apple.
struct DataErrorTests {
    private func http(_ status: Int) -> HTTPError {
        let url = URL(string: "https://example.supabase.co/rest/v1/x")!
        return HTTPError(data: Data("<html>Bad Gateway</html>".utf8),
                         response: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    @Test func ukjentFeilGirFastSetningUtenDetalj() {
        #expect(DataError.unknown("Status Code: 418 Body: teapot").message == DataError.unknown("").message)
        #expect(!DataError.unknown("teapot").message.contains("teapot"))
        struct Rar: Error {}
        let mapped = DataError.from(Rar())
        #expect(mapped.message == DataError.unknown("").message)
    }

    @Test func serverfeilGirEgenTekst() {
        #expect(DataError.from(http(500)) == .serverDown)
        #expect(DataError.from(http(503)) == .serverDown)
        #expect(DataError.from(FunctionsError.httpError(code: 502, data: Data())) == .serverDown)
        // PGRST0xx: PostgREST får ikke kontakt med databasen.
        #expect(DataError.from(PostgrestError(code: "PGRST001", message: "Database client error")) == .serverDown)
        #expect(!DataError.serverDown.message.contains("Status"))
        #expect(DataError.from(http(404)) != .serverDown)
    }

    @Test func utloptInnloggingGirEgenTekst() {
        #expect(DataError.from(PostgrestError(code: "PGRST301", message: "JWT expired")) == .sessionExpired)
        #expect(DataError.from(PostgrestError(code: "PGRST303", message: "JWT claims check failed")) == .sessionExpired)
        #expect(DataError.from(PostgrestError(code: nil, message: "JWT expired")) == .sessionExpired)
        #expect(DataError.from(http(401)) == .sessionExpired)
    }

    @Test func egenRaiseSendesVidere() {
        #expect(DataError.from(sqlState: "23514", message: "Delene (100 øre) er ikke lik regningen (200 øre)")
                == .invalid("Delene (100 øre) er ikke lik regningen (200 øre)"))
        #expect(DataError.from(sqlState: "23503", message: "Spilleren er ikke med i klubben")
                == .invalid("Spilleren er ikke med i klubben"))
        #expect(DataError.from(sqlState: "54000", message: "Grensen er nådd: høyst 50 i staben")
                == .invalid("Grensen er nådd: høyst 50 i staben"))
    }

    @Test func postgresSineStandardmeldingerByttesUt() {
        let generic = DataError.invalid(DataError.rejectedText)
        #expect(DataError.from(sqlState: "23514",
                               message: #"new row for relation "bets" violates check constraint "bets_amount_check""#) == generic)
        #expect(DataError.from(sqlState: "23503",
                               message: #"insert or update on table "follows" violates foreign key constraint "follows_fk""#) == generic)
        #expect(DataError.from(sqlState: "23503",
                               message: #"update or delete on table "members" violates foreign key constraint "x" on table "y""#) == generic)
        #expect(DataError.from(sqlState: "54000", message: "stack depth limit exceeded") == generic)
        #expect(DataError.from(sqlState: "23514", message: "") == generic)
    }

    @Test func avbruddErIkkeFeil() {
        #expect(DataError.isCancellation(CancellationError()))
        #expect(DataError.isCancellation(URLError(.cancelled)))
        #expect(!DataError.isCancellation(URLError(.notConnectedToInternet)))
        #expect(!DataError.isCancellation(DataError.offline))
    }

    @Test func ingenDobleInnledninger() {
        for error in [DataError.unknown("x"), .serverDown, .sessionExpired, .offline] {
            #expect(!error.message.contains(":"))
            #expect(error.message.hasSuffix("."))
        }
    }

    @Test func klubbOgKjopSkjulerRaDetalj() {
        #expect(!ClubError.unknown("The operation couldn’t be completed").message.contains("operation"))
        #expect(!PurchaseError.unknown("SKErrorDomain 2").message.contains("SKError"))
    }
}
