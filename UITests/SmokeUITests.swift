//
//  SmokeUITests.swift
//
//  Proves the app launches and renders on the CI simulators. Phase 12 grows
//  this into the fastlane snapshot capture (docs/11-SCREENSHOTS-SPEC.md).
//
//  WHY THIS TEST IS WRITTEN SO LOOSELY:
//  The first CI run failed here on iPad but passed on iPhone. The cause was the
//  test, not the app. On iPhone the tab bar is always on screen, so a "Today"
//  cell exists. On iPad in portrait, NavigationSplitView collapses the sidebar
//  behind a toggle, so "Today" appears only in the DETAIL pane as static text.
//
//  A smoke test's job is "did the app launch and draw something recognisable",
//  not "is this specific accessibility element of this specific type present".
//  Asserting on element *type* made it a layout test by accident, and a fragile
//  one. So it now accepts the label in any element type, on either layout.
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

        XCTAssertEqual(app.state, .runningForeground, "App is not in the foreground after launch.")

        // "Today" is the default tab. It renders as:
        //   iPhone  -> a tab bar button / cell
        //   iPad    -> a sidebar row AND a detail-pane title + label
        // Accept any of them.
        let candidates: [XCUIElement] = [
            app.staticTexts["Today"].firstMatch,
            app.buttons["Today"].firstMatch,
            app.cells["Today"].firstMatch,
            app.navigationBars["Today"].firstMatch,
            app.otherElements["Today"].firstMatch
        ]

        let deadline = Date().addingTimeInterval(30)
        var found = false
        while Date() < deadline && !found {
            found = candidates.contains { $0.exists }
            if !found { _ = candidates[0].waitForExistence(timeout: 2) }
        }

        if !found {
            // Dump the hierarchy so a future failure is diagnosable from the CI
            // log alone, rather than needing a local repro we cannot do.
            XCTFail("""
                Could not find a 'Today' element in any form.
                Element hierarchy follows:
                \(app.debugDescription)
                """)
        }
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
