//
//  SafetyNumberUITests.swift
//  privameshUITests
//
//  Walks the path a user actually takes to verify someone: open a chat, tap the
//  contact in the header, then Verify contact. The number itself is covered by
//  unit tests; this checks the screen is reachable and shows what it should.
//

import XCTest

final class SafetyNumberUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchIntoChat() -> XCUIApplication {
        let app = XCUIApplication()
        // -chatShot seeds one conversation and opens it, which is exactly the
        // starting point this test needs.
        app.launchArguments += ["-demoImport", "-chatShot", "a",
                                "-privamesh.onboardingDone", "YES",
                                "-privamesh.installMarker", "NO",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testVerifyScreenIsReachableAndShowsANumber() throws {
        let app = launchIntoChat()

        // The chat opens on its own; the header carries the contact's name. It is
        // a Button wrapping a Text, so the text is what the query finds.
        let header = app.buttons["contactHeaderButton"]
        XCTAssertTrue(header.waitForExistence(timeout: 45), "chat never opened")
        header.tap()

        let verify = app.buttons["verifyContactRow"]
        if !verify.waitForExistence(timeout: 10) {
            app.scrollViews.firstMatch.swipeUp()   // safety card sits below the fold
        }
        XCTAssertTrue(verify.waitForExistence(timeout: 10),
                      "Verify contact is missing from the contact profile")
        verify.tap()

        // 60 digits, shown in groups of five.
        let number = app.staticTexts["safetyNumberDigits"]
        XCTAssertTrue(number.waitForExistence(timeout: 15), "the safety number is not displayed")
        let digits = number.label.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(digits.count, 60, "expected 60 digits, got: \(number.label)")
        XCTAssertTrue(digits.allSatisfy { $0.isNumber })

        // And the way to compare it without reading it aloud.
        XCTAssertTrue(app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Scan their code'")).firstMatch.exists,
            "no way to scan the other side's code")

        // Marking verified is a manual switch, never automatic.
        XCTAssertTrue(app.switches.firstMatch.exists, "the verified toggle is missing")
    }
}
