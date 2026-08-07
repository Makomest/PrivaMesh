//
//  WelcomeButtonsUITests.swift
//  privameshUITests
//
//  Regression for App Review 2.1(a) (iPad Air 11-inch, iPadOS 26.5.2):
//  "Sign in to account button was not responsive."
//
//  Two causes, both covered here:
//   1. The sign-in button was `.disabled` until all 12 fields were non-empty, so
//      an incomplete form swallowed every tap with no explanation.
//   2. The welcome screen's outlined button has no fill; without an explicit
//      content shape SwiftUI hit-tests the glyphs only, so taps beside the text
//      fall through on a wide layout.
//

import XCTest

final class WelcomeButtonsUITests: XCTestCase {

    private let demoPhrase = "drum need person expire large wrist struggle labor label ill improve cloud"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchAtWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        // Skip the explainer carousel (UserDefaults override) and pin English so
        // the assertions match the reviewer's locale.
        // `installMarker = NO` makes the app treat this launch as a fresh install
        // and purge the Keychain wallet/passcode, so tests don't inherit an
        // account imported by an earlier test.
        app.launchArguments += ["-privamesh.onboardingDone", "YES",
                                "-privamesh.installMarker", "NO",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// Tap `element` at a normalized point inside its own frame.
    private func tap(_ element: XCUIElement, dx: Double,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "element never appeared", file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    private func openRestoreScreen(_ app: XCUIApplication,
                                   file: StaticString = #filePath, line: UInt = #line) {
        // Off-centre on purpose: the outlined pill must be tappable across its
        // whole width, not only on the text.
        tap(app.buttons["Restore from recovery phrase"], dx: 0.06, file: file, line: line)
        XCTAssertTrue(app.buttons["Sign in to account"].waitForExistence(timeout: 15),
                      "Outlined welcome button ignored an off-centre tap.", file: file, line: line)
    }

    /// The reported bug: tapping sign-in with an incomplete form must react.
    @MainActor
    func testSignInButtonAnswersOnIncompleteForm() throws {
        let app = launchAtWelcome()
        openRestoreScreen(app)

        let signIn = app.buttons["Sign in to account"]
        XCTAssertTrue(signIn.isEnabled, "Sign-in button is disabled — taps are silently dropped.")
        tap(signIn, dx: 0.1)

        let complaint = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Enter all 12 words'")).firstMatch
        XCTAssertTrue(complaint.waitForExistence(timeout: 10),
                      "Tapping sign-in on an empty form produced no visible response.")
    }

    /// Full path the reviewer follows: paste the phrase, sign in, land in the app.
    @MainActor
    func testRestoreDemoAccountEndToEnd() throws {
        let app = launchAtWelcome()
        openRestoreScreen(app)

        // Type the phrase the way a reviewer does: one word per field.
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15))
        for (i, word) in demoPhrase.split(separator: " ").enumerated() {
            let field = app.textFields.element(boundBy: i)
            XCTAssertTrue(field.waitForExistence(timeout: 10), "field \(i + 1) missing")
            field.tap()
            field.typeText(String(word))
        }

        tap(app.buttons["Sign in to account"], dx: 0.1)

        // Leaving the restore screen proves the phrase was accepted and imported.
        let left = app.buttons["Sign in to account"].waitForNonExistence(timeout: 30)
        let fields = app.textFields.allElementsBoundByIndex.map { "\($0.value ?? "")" }
        XCTAssertTrue(left, "Sign-in with a valid phrase did not advance past the restore screen. "
                      + "fields=\(fields) errors=\(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }
}
