//
//  MessagingIdentityManager.swift
//  privamesh
//
//  Manages the per-device CryptoIdentity (X25519 DH + Ed25519 signing keys)
//  that are separate from the Solana wallet key.
//  Persisted in Keychain as JSON data.
//

import Foundation

@Observable
final class MessagingIdentityManager {
    /// Legacy single device-wide key (pre per-account identities).
    private static let legacyKey = "privamesh.messaging.identity"
    /// One account adopts the legacy identity on upgrade so existing sessions
    /// keep working; the rest get fresh keys. Flag records which address took it.
    private static let migratedFlag = "privamesh.messaging.legacyMigratedTo"

    /// Active account address; nil falls back to the legacy key (pre-bind / background warm-up).
    private(set) var address: String?
    private(set) var identity: CryptoIdentity?

    init() {
        identity = load()
    }

    private func keychainKey(for address: String?) -> String {
        guard let address, !address.isEmpty else { return Self.legacyKey }
        return "privamesh.messaging.identity.\(address)"
    }

    /// Point the manager at an account. Migrates the legacy identity into the
    /// first account that binds after upgrade (the one that owned those
    /// sessions), then loads this account's own identity.
    func bind(to address: String) {
        migrateLegacyIfNeeded(to: address)
        self.address = address
        identity = load()
    }

    /// Returns the existing identity or creates and persists a new one.
    func getOrCreate() throws -> CryptoIdentity {
        if let existing = identity { return existing }
        let new = try CryptoIdentity.generate()
        try save(new)
        identity = new
        return new
    }

    func prekeyBundle() throws -> PrekeyBundle {
        try getOrCreate().prekeyBundle()
    }

    // MARK: - Keychain helpers

    private func migrateLegacyIfNeeded(to address: String) {
        guard UserDefaults.standard.string(forKey: Self.migratedFlag) == nil,
              let legacy = KeychainStorage.load(key: Self.legacyKey) else { return }
        // Adopt legacy only if this account has no identity yet.
        let key = keychainKey(for: address)
        if KeychainStorage.load(key: key) == nil {
            KeychainStorage.save(key: key, data: legacy)
        }
        KeychainStorage.delete(key: Self.legacyKey)
        UserDefaults.standard.set(address, forKey: Self.migratedFlag)
    }

    /// Derive & persist `address`'s messaging identity from its seed phrase so
    /// the identity is recoverable by re-entering the phrase (no server, no extra
    /// backup). No-op if an identity already exists for `address` — never clobbers
    /// live keys or existing Double Ratchet sessions. Called whenever an account's
    /// seed is (re)stored.
    func provision(address: String, seedPhrase words: [String]) {
        guard !address.isEmpty, !words.isEmpty else { return }
        let key = keychainKey(for: address)
        guard KeychainStorage.load(key: key) == nil else { return }
        guard let derived = try? CryptoIdentity.derive(fromSeedPhrase: words),
              let data = try? JSONEncoder().encode(derived) else { return }
        KeychainStorage.save(key: key, data: data)
        if address == self.address { identity = derived }   // adopt if currently bound
    }

    private func save(_ id: CryptoIdentity) throws {
        let data = try JSONEncoder().encode(id)
        KeychainStorage.save(key: keychainKey(for: address), data: data)
    }

    private func load() -> CryptoIdentity? {
        guard let data = KeychainStorage.load(key: keychainKey(for: address)) else { return nil }
        return try? JSONDecoder().decode(CryptoIdentity.self, from: data)
    }

    /// Wipe the currently bound identity (and any legacy remnant).
    func wipe() {
        KeychainStorage.delete(key: keychainKey(for: address))
        KeychainStorage.delete(key: Self.legacyKey)
        identity = nil
    }

    /// Full reset: wipe every account's identity. Pass all known account
    /// addresses (capture before AccountManager.removeAll()).
    func wipeAll(addresses: [String]) {
        for addr in addresses { KeychainStorage.delete(key: keychainKey(for: addr)) }
        KeychainStorage.delete(key: Self.legacyKey)
        UserDefaults.standard.removeObject(forKey: Self.migratedFlag)
        address = nil
        identity = nil
    }
}
