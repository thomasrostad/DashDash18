//
//  DashDash18UITests.swift
//  DashDash18UITests
//
//  Created by Thomas Rostad on 06/10/2026.
//

import XCTest

final class DashDash18UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testFanene() throws {
        let app = XCUIApplication()
        app.launch()

        for fane in ["Kveld", "Tavla", "Deg"] {
            XCTAssertTrue(app.tabBars.buttons[fane].waitForExistence(timeout: 5), "Mangler fanen \(fane)")
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
