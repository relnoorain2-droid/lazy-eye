//
//  SmokeUITests.swift
//
//  Phase 1: proves the app launches and the tab shell exists on the CI
//  simulator. Phase 12 grows this file into the fastlane snapshot capture
//  (docs/11-SCREENSHOTS-SPEC.md section 3).
//

import XCTest

final class SmokeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesAndShowsNavigation() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-seed-demo-data"]
        app.launch()

        // The seed flag skips onboarding, so a tab or sidebar item must exist.
        let today = app.buttons["Today"].firstMatch
        let todayCell = app.cells["Today"].firstMatch

        XCTAssertTrue(
            today.waitForExistence(timeout: 10) || todayCell.waitForExistence(timeout: 10),
            "Expected a Today tab (compact) or sidebar row (regular) after launch."
        )
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
