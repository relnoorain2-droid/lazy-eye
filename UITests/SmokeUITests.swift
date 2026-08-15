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
            // The identifier the app sets on the tab itself. Preferred, because
            // it is ours: the four below depend on how the system happens to
            // render a tab bar in this iOS version, which is not something this
            // app controls or should be asserting.
            app.descendants(matching: .any)["tab.today"].firstMatch,
            app.staticTexts["Today"].firstMatch,
            app.buttons["Today"].firstMatch,
            app.cells["Today"].firstMatch,
            app.navigationBars["Today"].firstMatch,
            app.otherElements["Today"].firstMatch
        ]

        let deadline = Date().addingTimeInterval(30)
        var found = false
        var died = false
        while Date() < deadline && !found {
            // CHECK THE APP IS STILL ALIVE ON EVERY PASS.
            //
            // Without this the loop cheerfully polls a dead process for thirty
            // seconds and then reports "element not found", which sent three
            // CI runs chasing a layout problem that was really a termination.
            // "The thing I am looking at stopped existing" and "the thing I am
            // looking for is not there" deserve different messages.
            if app.state != .runningForeground { died = true; break }
            found = candidates.contains { $0.exists }
            if !found { _ = candidates[0].waitForExistence(timeout: 2) }
        }

        if died {
            XCTFail("The app terminated during launch. State: \(app.state.rawValue)")
            return
        }

        if !found {
            // ONE LINE, NOT A HIERARCHY DUMP.
            //
            // This used to print `app.debugDescription`. It is the right
            // instinct and it does not survive: xcbeautify keeps the first line
            // of a failure message and discards the rest, so three CI runs
            // reported "could not find a 'Today' element" and nothing else,
            // and each fix after that was a guess.
            //
            // `RootView` now publishes its own state as an accessibility
            // identifier, so the failure can state which screen was actually on
            // display and how many profiles the store had — on one line, which
            // is the only kind of diagnostic a formatted CI log reliably keeps.
            XCTFail("No 'Today' element. Root state: \(rootState(of: app))")
        }
    }

    /// Reads the identifier `RootView` publishes. Returns a description rather
    /// than an optional so the failure message is never empty.
    @MainActor
    private func rootState(of app: XCUIApplication) -> String {
        // Querying a dead app throws its own error and buries the real one.
        guard app.state == .runningForeground else {
            return "app is not running (state \(app.state.rawValue))"
        }
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'root:'"))
        guard matches.count > 0 else {
            return "no root identifier found — the app may not have drawn at all"
        }
        return (0..<matches.count)
            .map { matches.element(boundBy: $0).identifier }
            .joined(separator: ", ")
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
