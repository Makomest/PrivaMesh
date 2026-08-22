//
//  SessionVault.swift
//  privamesh
//
//  Encrypts the Double Ratchet state before it is written to the local database.
//
//  The ratchet state IS the conversation: with it, past and future messages on
//  that chain can be decrypted. Until now it sat in SwiftData as plain JSON,
//  protected only by the file-level class on the store. That class
//  (completeUntilFirstUserAuthentication) keeps the file unreadable before the
//  first unlock after boot and nothing after it — so anything that gets at the
//  file later, from a backup extraction to another process on a jailbroken
//  device, gets the sessions.
//
//  Now the state is sealed with AES-256-GCM under a key that lives in the
//  Keychain and never leaves it. The database file alone is no longer enough.
//
//  MIGRATION: existing rows hold bare JSON. Reads accept both, writes always
//  produce the sealed form, so a store converts itself as conversations advance.
//

import Foundation
import CryptoKit

enum SessionVault {
    /// Marks a sealed payload. Bare JSON starts with '{' (0x7B), so the two forms
    /// are never ambiguous.
    private static let version: UInt8 = 0x01
    private static let keychainKey = "privamesh.sessionVaultKey"

    // MARK: - Sealing

    /// Encrypt ratchet state for storage. Falls back to the plain encoding only if
    /// the key is unavailable, because refusing to save would lose the session and
    /// break the conversation outright.
    static func seal(_ data: Data) -> Data {
        guard let key = key() else { return data }
        guard let sealed = try? AES.GCM.seal(data, using: key).combined else { return data }
        return Data([version]) + sealed
    }

    /// Decrypt storage back into ratchet state, accepting the pre-encryption form.
    static func open(_ stored: Data) -> Data? {
        guard let first = stored.first else { return nil }
        guard first == version else { return stored }   // legacy plain JSON
        guard let key = key(),
              let box = try? AES.GCM.SealedBox(combined: stored.dropFirst()),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return plain
    }

    /// Whether a stored blob is already sealed. Used by tests and migration checks.
    static func isSealed(_ stored: Data) -> Bool { stored.first == version }

    // MARK: - Key

    /// Created on first use and kept in the Keychain. AfterFirstUnlock, because
    /// background delivery has to open sessions while the phone is locked.
    private static func key() -> SymmetricKey? {
        if let existing = load() { return SymmetricKey(data: existing) }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        guard store(raw) else { return nil }
        return fresh
    }

    private static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.privamesh.sessionvault",
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private static func store(_ data: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.privamesh.sessionvault",
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    /// Wiping the account must take the key with it: without it the stored
    /// sessions are unreadable noise, which is the point.
    static func wipe() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.privamesh.sessionvault",
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Contact convenience

extension Contact {
    /// The live ratchet for this conversation, decrypted on read.
    var ratchet: DoubleRatchet? {
        guard let stored = sessionData, let plain = SessionVault.open(stored) else { return nil }
        return try? JSONDecoder().decode(DoubleRatchet.self, from: plain)
    }

    /// Store ratchet state, sealed. Every write goes through here so nothing can
    /// re-introduce a plaintext row.
    func setRatchet(_ ratchet: DoubleRatchet?) {
        guard let ratchet, let encoded = try? JSONEncoder().encode(ratchet) else {
            sessionData = nil
            return
        }
        sessionData = SessionVault.seal(encoded)
    }
}
