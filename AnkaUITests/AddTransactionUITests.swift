//
//  AddTransactionUITests.swift
//  AnkaUITests
//
//  Verifies the current Add Transaction sheet (Phase 8 Mail-style layout):
//  bottom-bar "+" → sheet with description/amount fields, a category chip
//  rail, and a morphing Save button that's only enabled once both an amount
//  and a category are set.
//

import XCTest

final class AddTransactionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // Skip onboarding so the dashboard is immediately visible.
        app.launchArguments += ["-anka.hasCompletedOnboarding", "YES"]
        // Force the classic sheet (v1) entry layout regardless of what a
        // previous run left in this simulator's persisted UserDefaults.
        app.launchArguments += ["-transactionEntryLayout", "v1"]
        app.launch()
        return app
    }

    @MainActor
    func testAddTransactionLayout() throws {
        let app = launchApp()

        // Bottom-bar "+" opens the Add sheet.
        let addButton = app.buttons["Add transaction"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add transaction button should exist")
        addButton.tap()

        // Top bar: dismiss ("X") capsule present.
        XCTAssertTrue(app.buttons["Dismiss"].waitForExistence(timeout: 5), "Dismiss button should appear")

        // Description field auto-focuses with its placeholder visible.
        let descriptionField = app.textFields["Description"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5), "Description field should exist")

        // Amount placeholder shown when empty; Save disabled.
        XCTAssertTrue(app.staticTexts["Amount"].exists, "Amount placeholder should be visible")
        let saveButton = app.buttons["Save transaction"]
        XCTAssertTrue(saveButton.exists, "Save button should exist")
        XCTAssertFalse(saveButton.isEnabled, "Save should be disabled initially")

        // Enter an amount.
        descriptionField.tap()
        let amountField = app.textFields.element(boundBy: 1)
        amountField.tap()
        amountField.typeText("12345")
        XCTAssertTrue(app.staticTexts["12,345"].waitForExistence(timeout: 2),
                      "Amount should format as 12,345")
        XCTAssertFalse(saveButton.isEnabled, "Save should stay disabled without a category")

        // Pick a category from the horizontal chip rail.
        let groceriesChip = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Groceries")
        ).firstMatch
        XCTAssertTrue(groceriesChip.waitForExistence(timeout: 5), "Groceries chip should exist")
        groceriesChip.tap()

        // Selected category surfaces in the sparkle pill (rendered as
        // per-character labels by SparkleCategoryLabel, so check the first
        // letter rather than the full word); Save now enabled.
        XCTAssertTrue(app.staticTexts["G"].waitForExistence(timeout: 5),
                      "Selected category should show after picking")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled, "Save should be enabled once amount + category are set")

        // Capture the filled state for the record.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "AddTransaction-Filled"
        shot.lifetime = .keepAlways
        add(shot)

        // Save closes the sheet, returning to the dashboard.
        saveButton.tap()
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Should return to the dashboard after Save")
    }
}
