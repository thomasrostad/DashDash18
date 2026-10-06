import XCTest

final class DashDash18UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// En fersk installasjon har ingen økt, så appen skal starte på innloggingen.
    @MainActor
    func testStarterPaaInnlogging() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Logg inn"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["deg@epost.no"].exists)
        XCTAssertTrue(app.buttons["Send kode"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Apple'")).firstMatch.exists)
    }

    @MainActor
    func testUgyldigEpostGirMelding() throws {
        let app = XCUIApplication()
        app.launch()

        let felt = app.textFields["deg@epost.no"]
        XCTAssertTrue(felt.waitForExistence(timeout: 10))
        felt.tap()
        felt.typeText("ikke-en-epost")
        app.buttons["Send kode"].tap()

        XCTAssertTrue(app.staticTexts["Det ser ikke ut som en e-postadresse."].waitForExistence(timeout: 5))
    }
}
