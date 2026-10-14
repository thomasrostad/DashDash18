import Foundation
import Testing
@testable import DashDash18

/// «Del regningen» (V14): beløpet per person, live under totalfeltet.
struct RegningPerPersonTests {
    @Test func gaarOppIOere() {
        let total = NOK(parsing: "1250")!
        #expect(BillSplitSummary.perPerson(total: total, count: 4) == "312,50 kr hver (4 personer)")
        #expect(BillSplitSummary.perPerson(total: total, count: 1) == "1\u{00A0}250 kr hver (1 person)")
        #expect(BillSplitSummary.perPerson(total: NOK(parsing: "600")!, count: 3) == "200 kr hver (3 personer)")
    }

    @Test func gaarIkkeOppGirSpenn() {
        #expect(BillSplitSummary.perPerson(total: NOK(parsing: "1000")!, count: 3) == "333,33–333,34 kr hver (3 personer)")
    }

    @Test func ingenAaDeleMed() {
        #expect(BillSplitSummary.perPerson(total: NOK(parsing: "100")!, count: 0) == nil)
    }

    @Test func feltetFaarTusenskille() {
        #expect(BillSplitSummary.fieldText(NOK(parsing: "1250")!) == "1\u{00A0}250")
        #expect(BillSplitSummary.fieldText(NOK(parsing: "249,5")!) == "249,50")
        // Tilbake til samme beløp.
        #expect(NOK(parsing: BillSplitSummary.fieldText(NOK(parsing: "12500")!)) == NOK(parsing: "12500"))
    }
}
