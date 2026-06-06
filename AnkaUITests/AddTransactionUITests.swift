//
//  AddTransactionUITests.swift
//  AnkaUITests
//
//  Phase 2 (Spendy-adapted layout) verification.
//

import XCTest

final class AddTransactionUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddTransactionLayout() throws {
        let app = XCUIApplication()
        app.launch()

        // Open the Add sheet (detached "Add" tab button).
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Add tab button should exist")
        addButton.tap()

        // Top bar: Cancel capsule present.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5), "Cancel button should appear")

        // Currency prefix + zero amount by default.
        XCTAssertTrue(app.staticTexts["IDR"].exists, "Currency prefix IDR should be visible")
        XCTAssertTrue(app.staticTexts["0"].exists, "Amount should default to 0")

        // Note field placeholder.
        XCTAssertTrue(app.textFields["Add note"].exists, "Note field with 'Add note' placeholder should exist")

        // Category slot shows placeholder; Save disabled.
        XCTAssertTrue(app.buttons["Category"].exists, "Category slot should show 'Category' initially")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should be disabled initially")

        // Enter 12345 via numpad → thousands separator "12,345".
        for digit in ["1", "2", "3", "4", "5"] {
            app.buttons[digit].tap()
        }
        XCTAssertTrue(app.staticTexts["12,345"].waitForExistence(timeout: 2),
                      "Amount should format as 12,345")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save should stay disabled without a category")

        // Pick a category via the picker sheet (segmented Expenses/Income + list).
        app.buttons["Category"].tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5),
                      "Category picker sheet should open")
        XCTAssertTrue(app.buttons["Expenses"].exists, "Picker should have an Expenses tab")
        XCTAssertTrue(app.buttons["Income"].exists, "Picker should have an Income tab")

        let foodRow = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Food & Dining")
        ).firstMatch
        XCTAssertTrue(foodRow.waitForExistence(timeout: 2), "Food & Dining row should exist")

        // Capture the picker sheet (segmented tabs + list) for the record.
        let pickerShot = XCTAttachment(screenshot: app.screenshot())
        pickerShot.name = "CategoryPicker-Sheet"
        pickerShot.lifetime = .keepAlways
        add(pickerShot)

        foodRow.tap()

        // Selected category surfaces in the slot; Save now enabled.
        XCTAssertTrue(app.staticTexts["Food & Dining"].waitForExistence(timeout: 5),
                      "Selected category should show after picking")
        XCTAssertTrue(app.buttons["Save"].isEnabled, "Save should be enabled once amount + category set")

        // Capture the filled state for the record.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "AddTransaction-Filled"
        shot.lifetime = .keepAlways
        add(shot)

        // Save closes the sheet.
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5),
                      "Should return to Today after Save")
    }
}
