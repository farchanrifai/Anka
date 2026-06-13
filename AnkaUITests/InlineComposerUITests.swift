//
//  InlineComposerUITests.swift
//  AnkaUITests
//
//  Covers Phase 8.5's V3 inline composer: opening it hides the bottom
//  Filter/Search/Add bar (Messages-style), and the bar must reliably come
//  back — both when the composer is dismissed by tapping outside it and
//  when it's dismissed by sending a transaction. Regression coverage for
//  the "tab bar randomly disappears" bug.
//

import XCTest

final class InlineComposerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Skip onboarding so the dashboard is immediately visible, and force
        // the V3 inline composer regardless of what a previous run left in
        // this simulator's persisted UserDefaults.
        app.launchArguments += ["-anka.hasCompletedOnboarding", "YES"]
        app.launchArguments += ["-transactionEntryLayout", "v3"]
        app.launch()
        return app
    }

    /// Open → tap outside to dismiss → bottom bar must reappear.
    @MainActor
    func testBottomBarReappearsAfterDismissingComposerByTappingOutside() throws {
        let app = launchApp()

        let filterButton = app.buttons["Filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5), "Bottom bar (Filter) should be visible on launch")

        // Open the inline composer.
        let addButton = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        // The Messages-style composer hides the Filter/Search/Add bar.
        XCTAssertTrue(
            waitForNonExistence(filterButton, timeout: 5),
            "Filter button should be hidden while the inline composer is open"
        )

        // Tap the tap-catcher overlay in the empty navigation-bar area (top
        // left, away from the Stats/Settings buttons and the keyboard, which
        // covers the lower half of the screen) to dismiss the composer.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).tap()

        // The bottom bar must come back.
        XCTAssertTrue(
            filterButton.waitForExistence(timeout: 5),
            "Filter button should reappear after dismissing the composer"
        )
    }

    /// Open, type a valid entry, send → composer closes → bottom bar reappears.
    @MainActor
    func testBottomBarReappearsAfterSendingFromComposer() throws {
        let app = launchApp()

        let filterButton = app.buttons["Filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))

        let addButton = app.buttons["Add transaction"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(waitForNonExistence(filterButton, timeout: 5),
                      "Filter button should be hidden while the inline composer is open")

        // Type something the parser can resolve to an amount + category.
        let textField = app.textFields["5k for coffee"]
        XCTAssertTrue(textField.waitForExistence(timeout: 5), "Composer text field should exist")
        textField.tap()
        textField.typeText("20k coffee")

        // Wait for the debounced parse + send button to become enabled, then send.
        // The toolbar "+" is removed from the hierarchy entirely while the
        // composer is open (its bottom bar is hidden), so the composer's own
        // send button is the only "Add transaction" element at this point.
        let sendButton = app.buttons["Add transaction"]
        // First-launch category prediction can take a moment to warm up, so
        // give the debounced parse + predictor more headroom than usual. Poll
        // rather than use XCTNSPredicateExpectation, since the send button is
        // recreated (new glass shape) as the parse result settles.
        XCTAssertTrue(
            waitForCondition(timeout: 15) { sendButton.exists && sendButton.isEnabled },
            "Send button should become enabled once the parser resolves an amount + category"
        )
        sendButton.tap()

        // After save, the composer closes (default preference) and the bar returns.
        XCTAssertTrue(
            filterButton.waitForExistence(timeout: 5),
            "Filter button should reappear after sending from the composer"
        )
    }

    // MARK: - Helpers

    /// `waitForExistence` has no built-in opposite — poll until the element
    /// stops existing or the timeout elapses.
    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }

    /// Polls `condition` until it returns true or the timeout elapses.
    private func waitForCondition(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
