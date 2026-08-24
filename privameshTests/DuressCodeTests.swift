//
//  DuressCodeTests.swift
//  privameshTests
//
//  The second passcode: the one that means "destroy this account".
//
//  What has to hold is not that it works, but that it is indistinguishable from
//  an ordinary unlock to whoever is watching the screen — and that it cannot be
//  set, changed or used as a shortcut by that same person.
//
//  Nested inside PasscodeStorageTests on purpose. Both suites write to the same
//  Keychain items, and `.serialized` only orders a suite against itself: run as
//  siblings they interleave and delete each other's passcode mid-test.
//

import Testing
import Foundation
@testable import privamesh

extension PasscodeStorageTests {

@Suite("Duress code", .serialized)
struct DuressCodeTests {

    /// Every test starts from nothing stored, since the Keychain outlives a run.
    private func fresh() -> PasscodeManager {
        let manager = PasscodeManager()
        manager.wipe()
        return manager
    }

    @Test func oneCodeUnlocksTheOtherWipes() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        #expect(manager.check("1234") == .correct)
        #expect(manager.check("9999") == .duress)
        #expect(manager.check("5555") == .incorrect)
    }

    /// Without the real passcode this setting is a way to destroy someone's
    /// account rather than protect it.
    @Test func settingItRequiresTheRealPasscode() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)

        #expect(manager.setDuressPasscode("9999", currentPasscode: "0000") == false)
        #expect(manager.isDuressSet == false)

        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))
        #expect(manager.isDuressSet)
    }

    /// A code that both unlocks and wipes resolves as "unlock", which would leave
    /// someone believing they have a way out that does nothing.
    @Test func itCannotEqualThePasscode() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("1234", currentPasscode: "1234") == false)
        #expect(manager.isDuressSet == false)
    }

    @Test func removingItRequiresTheRealPasscodeToo() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        #expect(manager.removeDuressPasscode(currentPasscode: "0000") == false)
        #expect(manager.isDuressSet)

        #expect(manager.removeDuressPasscode(currentPasscode: "1234"))
        #expect(manager.isDuressSet == false)
        // With nothing stored, that code is simply wrong again.
        #expect(manager.check("9999") == .incorrect)
    }

    @Test func wipeRemovesBothCodes() throws {
        let manager = fresh()

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        manager.wipe()

        #expect(manager.isPasscodeSet == false)
        #expect(manager.isDuressSet == false)
    }

    /// Wrong guesses get slower, and the wait applies to every code.
    ///
    /// If the duress code skipped the cooldown it would be a shortcut past the
    /// throttle, usable by whoever is holding the phone.
    @Test func theCooldownAppliesToEveryCode() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        // Five free attempts, then a cooldown starts.
        for _ in 0..<6 { _ = manager.check("0000") }
        #expect(manager.lockoutRemaining > 0)

        #expect(manager.check("9999") == .lockedOut)
        #expect(manager.check("1234") == .lockedOut)
    }

    /// The duress path must not leave a cooldown behind: an app that looks freshly
    /// installed but refuses passcodes for four minutes is not convincing.
    @Test func theDuressCodeClearsTheThrottle() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        // Stay inside the free attempts so no cooldown is running yet.
        for _ in 0..<3 { _ = manager.check("0000") }
        #expect(manager.check("9999") == .duress)
        #expect(manager.lockoutRemaining == 0)

        // And the counter is genuinely back to zero: the next wrong guesses get
        // the full set of free attempts again.
        for _ in 0..<4 { _ = manager.check("0000") }
        #expect(manager.lockoutRemaining == 0)
    }

    /// Timing. Both hashes are always derived, so no answer is measurably faster
    /// than another. Loose bounds on purpose: this catches a missing derivation,
    /// not a laboratory-grade side channel.
    @Test func allAnswersCostAboutTheSame() throws {
        let manager = fresh()
        defer { manager.wipe() }

        try manager.setPasscode("1234", length: 4)
        #expect(manager.setDuressPasscode("9999", currentPasscode: "1234"))

        func time(_ code: String) -> TimeInterval {
            _ = manager.check(code)   // warm up
            let started = Date()
            for _ in 0..<5 { _ = manager.check(code) }
            return Date().timeIntervalSince(started)
        }

        let correct = time("1234")
        let duress = time("9999")

        let slowest = max(correct, duress)
        let fastest = min(correct, duress)
        #expect(slowest < fastest * 3)
    }
}

}
