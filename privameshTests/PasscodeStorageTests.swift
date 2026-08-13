//
//  PasscodeStorageTests.swift
//  privameshTests
//
//  Regression for the "app asks me to create a passcode, then asks for the old one
//  after a restart" report.
//
//  Cause: the hash was stored as WhenUnlockedThisDeviceOnly, which is unreadable
//  until the device has been unlocked once per boot, and every read failure was
//  collapsed into nil — so a temporarily unreadable passcode looked like no
//  passcode at all, and the app offered to create one over it.
//

import Testing
import Foundation
import Security
@testable import privamesh

@Suite("Passcode storage", .serialized)
struct PasscodeStorageTests {

    private static let service = "com.privamesh.passcode"

    /// Read the protection class actually stored on the Keychain item.
    private func accessibleAttribute(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attrs = result as? [String: Any] else { return nil }
        return attrs[kSecAttrAccessible as String] as? String
    }

    /// The fix itself: the passcode must survive a launch that happens before the
    /// device has been unlocked in this boot.
    @Test func storedPasscodeUsesAfterFirstUnlock() throws {
        let manager = PasscodeManager()
        defer { manager.wipe() }

        try manager.setPasscode("123456", length: 6)

        #expect(accessibleAttribute(account: "passcodeHash") == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect(accessibleAttribute(account: "passcodeSalt") == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
    }

    /// A set passcode has to be reported as set, and verification must work.
    @Test func setThenVerify() throws {
        let manager = PasscodeManager()
        defer { manager.wipe() }

        try manager.setPasscode("4321", length: 4)

        #expect(manager.isPasscodeSet)
        #expect(manager.isPasscodeConfirmedAbsent == false)
        #expect(manager.verify("4321"))
        #expect(manager.verify("0000") == false)
    }

    /// Only a genuinely missing item may report "absent" — that flag is what gates
    /// showing the create-a-passcode screen.
    @Test func wipedPasscodeIsConfirmedAbsent() throws {
        let manager = PasscodeManager()
        try manager.setPasscode("111111", length: 6)
        manager.wipe()

        #expect(manager.isPasscodeSet == false)
        #expect(manager.isPasscodeConfirmedAbsent)
    }

    /// Migration rewrites a 1.0-era item without changing the passcode itself.
    @Test func migrationKeepsThePasscodeUsable() throws {
        let manager = PasscodeManager()
        defer { manager.wipe() }
        try manager.setPasscode("246810", length: 6)

        // Simulate an install from 1.0: same data, old protection class.
        for (account, data) in [("passcodeHash", readRaw("passcodeHash")),
                                ("passcodeSalt", readRaw("passcodeSalt"))] {
            let value = try #require(data)
            writeRaw(account: account, data: value, accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        }
        UserDefaults.standard.removeObject(forKey: "privamesh.passcode.protectionMigrated")
        #expect(accessibleAttribute(account: "passcodeHash") == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String))

        manager.migrateProtectionClassIfNeeded()

        #expect(accessibleAttribute(account: "passcodeHash") == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect(manager.verify("246810"), "the passcode must still unlock after migration")
    }

    // MARK: - Raw helpers

    private func readRaw(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func writeRaw(account: String, data: Data, accessible: CFString) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = accessible
        SecItemAdd(attrs as CFDictionary, nil)
    }
}
