import XCTest

/// Råbilder til App Store (6,9 tommer). Kjøres på iPhone 17 Pro Max og hentes ut av `.xcresult`
/// med `docs/app-store/lag-skjermbilder.py`, som setter overskriften over bildet.
/// Skjermene er skjermprøvene (`-DDDesignScreen`) med oppdiktede data, så det trengs verken nett eller innlogging.
final class AppStoreScreenshotTests: XCTestCase {
    /// Rekkefølgen og navnene skriptet forventer (`01-kvelden` osv.).
    private static let screens = ["kvelden", "hullkort", "tavla", "sesong", "nyturnering", "feiring"]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.appearance = .light
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        for (index, screen) in Self.screens.enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-DDDesignScreen", screen]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "\(screen) startet ikke")
            // La innlasting og animasjoner (feiringen) bli ferdige før bildet.
            Thread.sleep(forTimeInterval: 2.5)

            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = String(format: "%02d-%@", index + 1, screen)
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
