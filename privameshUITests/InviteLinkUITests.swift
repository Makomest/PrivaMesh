//
//  InviteLinkUITests.swift
//  privameshUITests
//
//  An invite link has to land the recipient on a pre-filled add-contact screen.
//  The system "open in app?" prompt cannot be tapped from a script, so the test
//  feeds the same inbox through the DEBUG -inviteURL argument and asserts on what
//  the user actually sees afterwards.
//

import XCTest

final class InviteLinkUITests: XCTestCase {

    /// A real card payload: valid Solana address, nickname "Decart".
    private let payload = "NY7NCoJAFIXf5a5dJAWC0CrRkhZRoWm0mNFJr86MOo5SiO_eCLY7H-eHM8EIrm0ByXPF-h5cCJV3e_htlpZlXXVlZ8dnhwSUXNvtwbdHei_GXUadI3UisIAOMufM1Ng3FEms-alqMJHRkAYffpKbvcm0qnnjEppAYlZLIpaCxzKi9DKBjUEj_qZ58XyZSyPRRK3Asdcoi5WwvygmcBDgajWwef4B"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(with url: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-demoImport", "-inviteURL", url,
                                "-privamesh.onboardingDone", "YES",
                                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    /// The whole point: open a link, get the add-contact sheet without hunting for it.
    @MainActor
    func testInviteLinkOpensAddContactSheet() throws {
        let app = launch(with: "privamesh://add?c=\(payload)")

        // The sheet has a Cancel button in its navigation bar; its presence means
        // the invite was accepted and the screen came up on its own.
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 45),
                      "Invite link did not open the add-contact screen.")
    }

    /// A link that is not ours must be ignored, not open anything.
    @MainActor
    func testForeignLinkIsIgnored() throws {
        let app = launch(with: "https://example.com/i/whatever")

        // Main screen chrome instead of the sheet.
        XCTAssertTrue(app.buttons["New contact"].waitForExistence(timeout: 45),
                      "app did not reach the main screen")
        XCTAssertFalse(app.buttons["Cancel"].exists,
                       "An unrelated URL must not open the add-contact screen.")
    }
}
