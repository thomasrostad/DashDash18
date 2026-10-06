import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private typealias F = ForingFixture

/// Hvem som får bekrefte parene: samme regel som `confirm_round_par` (sql/007_foring.sql).
/// markor-test.js-oppsettet: Anders og Erik er markører, Gunnar arrangør uten å være markør.
struct ForingParTests {
    static func game(_ status: RoundStatus = .active) -> RoundGame {
        RoundGame(F.snapshot(F.markorPlayers(), round: F.round(status: status, parConfirmed: false)))
    }

    @Test func markorenKanBekrefte() {
        #expect(Self.game().canConfirmPar(F.viewer(F.anders)))
        #expect(Self.game().canConfirmPar(F.viewer(F.erik)))
    }

    @Test func vanligSpillerKanIkke() {
        #expect(!Self.game().canConfirmPar(F.viewer(F.bjorn)))
    }

    @Test func arrangorenAlltid() {
        #expect(Self.game().canConfirmPar(F.viewer(F.gunnar)))
        #expect(Self.game(.draft).canConfirmPar(F.viewer(F.gunnar)))
    }

    @Test func markorenBareMensRundenGaar() {
        #expect(!Self.game(.draft).canConfirmPar(F.viewer(F.anders)))
        #expect(!Self.game(.locked).canConfirmPar(F.viewer(F.anders)))
    }

    @Test func utenBaaserIngenMarkor() {
        let g = RoundGame(F.snapshot(F.markorPlayers(bays: false), round: F.round(parConfirmed: false)))
        #expect(!g.canConfirmPar(F.viewer(F.anders)))
    }

    @Test func feilmeldingene() {
        #expect(ParConfirmation.error(.notAllowed).message == "Bare arrangøren eller en markør kan bekrefte parene.")
        #expect(ParConfirmation.error(DataError.from(sqlState: "55000", message: "Runden er ikke i gang")).message
                == "Runden er ikke i gang")
    }
}
