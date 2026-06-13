//
//  AnkaUITestsLaunchTests.swift
//  AnkaUITests
//
//  Created by Farchan on 6/6/2026.
//

import XCTest

final class AnkaUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-anka.hasCompletedOnboarding", "YES"]
        app.launch()

        // Dashboard should be reachable on a clean launch (onboarding skipped).
        XCTAssertTrue(app.buttons["Add transaction"].waitForExistence(timeout: 5),
                      "Dashboard should appear with the Add transaction button")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
