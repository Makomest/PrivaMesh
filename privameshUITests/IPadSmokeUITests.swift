//
//  IPadSmokeUITests.swift
//  privameshUITests
//
//  App Review 2.1(a) follow-up audit: sweep the screens a reviewer touches and
//  assert that every primary control answers a tap — including taps away from the
//  label's glyphs, which is what breaks first on a wide (iPad) layout.
//
//  "Answers" means: navigates, opens, or explains why it can't. A control that
//  silently absorbs the touch is the bug that got the app rejected.
//

import XCTest

final class IPadSmokeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-privamesh.onboardingDone", "YES",
                                "-privamesh.installMarker", "NO",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchArguments += extraArgs
        app.launch()
        return app
    }

    private func tap(_ element: XCUIElement, dx: Double = 0.5,
                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), "element never appeared",
                      file: file, line: line)
        element.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
    }

    // MARK: - Account creation path

    /// Create-account onboarding: both gated steps must explain themselves rather
    /// than sit dead until the user guesses what is missing.
    @MainActor
    func testCreateAccountFlowExplainsGatedSteps() throws {
        let app = launch()

        tap(app.buttons["Create account"], dx: 0.9)

        // CreateWalletView -> generates the draft phrase.
        let generate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Create'")).firstMatch
        tap(generate, dx: 0.85)

        // Seed display: Continue before ticking the confirmation must answer.
        let cont = app.buttons["Continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 25), "seed phrase screen never appeared")
        XCTAssertTrue(cont.isEnabled, "Continue is disabled — taps are silently dropped.")
        tap(cont, dx: 0.12)
        let needsTick = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'confirm that you wrote'")).firstMatch
        XCTAssertTrue(needsTick.waitForExistence(timeout: 10),
                      "Continue without the confirmation toggle produced no response.")

        // Tick it (the switch itself sits at the trailing edge), then continue.
        tap(app.switches.firstMatch, dx: 0.95)
        tap(cont, dx: 0.12)

        // Confirm quiz: Confirm with nothing answered must answer too.
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 20),
                      "confirm-quiz screen never appeared. buttons=\(app.buttons.allElementsBoundByIndex.map(\.label)) "
                      + "switches=\(app.switches.allElementsBoundByIndex.map { "\($0.label)=\($0.value ?? "")" })")
        XCTAssertTrue(confirm.isEnabled, "Confirm is disabled — taps are silently dropped.")
        tap(confirm, dx: 0.12)
        let needsAnswers = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Answer all'")).firstMatch
        XCTAssertTrue(needsAnswers.waitForExistence(timeout: 10),
                      "Confirm with no answers selected produced no response.")
    }

    // MARK: - Main screen

    /// Chrome on the main screen: profile, quota pill, new-contact, and a chat row
    /// all have to open something on a tap away from centre.
    @MainActor
    func testMainScreenChromeOpens() throws {
        let app = launch(["-demoImport"])

        // New contact sheet.
        let newContact = app.buttons["New contact"]
        XCTAssertTrue(newContact.waitForExistence(timeout: 40), "main screen never appeared")
        tap(newContact, dx: 0.8)
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 15),
                      "New-contact button did not open the add-contact sheet.")
        tap(app.buttons["Cancel"])

        // Profile / settings.
        let profile = app.buttons["Profile and settings"]
        tap(profile, dx: 0.2)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15),
                      "Profile button did not open the profile screen.")

        // The app is dark-only: an appearance control here would promise a change
        // the orbit surface never makes (App Review 2.1(a), "Theme did not change").
        let appearance = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Theme' OR label CONTAINS[c] 'Appearance'")).firstMatch
        XCTAssertFalse(appearance.exists,
                       "An appearance/theme control is back in Profile, but the app ships dark-only.")
    }

    /// Add-contact sheet: the search button must react on an empty query instead
    /// of looking broken.
    @MainActor
    func testAddContactSearchAnswersEmptyQuery() throws {
        let app = launch(["-demoImport"])

        let newContact = app.buttons["New contact"]
        XCTAssertTrue(newContact.waitForExistence(timeout: 40), "main screen never appeared")
        tap(newContact, dx: 0.8)

        let search = app.buttons["Find"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "search button missing")
        XCTAssertTrue(search.isEnabled, "Search is disabled — taps are silently dropped.")
        tap(search, dx: 0.15)

        let complaint = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'Enter a handle'")).firstMatch
        XCTAssertTrue(complaint.waitForExistence(timeout: 10),
                      "Search on an empty query produced no response.")
    }
}
