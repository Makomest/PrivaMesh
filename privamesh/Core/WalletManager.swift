//
//  WalletManager.swift
//  privamesh
//

import Foundation
import SolanaSwift

@Observable
final class WalletManager {
    enum State: Equatable {
        case noWallet
        case draft(phrase: [String], publicKeyBase58: String)
        case ready(publicKeyBase58: String)
    }

    private(set) var state: State = .noWallet

    /// In-memory derived keypair so signing doesn't re-read (and re-prompt for)
    /// the Keychain seed on every transaction. Keyed by the active pubkey;
    /// cleared on switch/wipe.
    private var cachedKeyPair: KeyPair?
    private var cachedFor: String?

    private func clearCache() {
        cachedKeyPair = nil
        cachedFor = nil
        SeedLock.invalidate()
    }

    init() {
        if let publicKey = (try? KeychainStorage.read(.publicKey)) ?? nil {
            state = .ready(publicKeyBase58: publicKey)
            // One-time migration: re-store so an older install upgrades the
            // public-key item from WhenUnlocked to AfterFirstUnlock accessibility
            // (fixes the random "logged out at launch" when the device was locked).
            try? KeychainStorage.save(publicKey, for: .publicKey)
        }
    }

    /// Re-read the active wallet from Keychain. Called after switching accounts
    /// (which copies the selected account's seed/pubkey into the current slot).
    func reloadFromKeychain() {
        if let publicKey = (try? KeychainStorage.read(.publicKey)) ?? nil {
            state = .ready(publicKeyBase58: publicKey)
        } else {
            state = .noWallet
        }
    }

    /// Make `account` the current wallet: copy its seed + pubkey into the
    /// current Keychain slot so currentKeyPair()/signing use it.
    func activate(account: WalletAccount, seedPhrase: [String]) {
        clearCache()
        try? KeychainStorage.save(seedPhrase.joined(separator: " "), for: .seedPhrase,
                                  requireBiometry: SeedLock.isEnabled)
        try? KeychainStorage.save(account.publicKeyBase58, for: .publicKey)
        state = .ready(publicKeyBase58: account.publicKeyBase58)
    }

    /// Generate a new 12-word mnemonic and derive Solana keypair.
    /// Keeps it in `draft` state until user confirms.
    func generateDraft() async throws {
        let mnemonic = Mnemonic(strength: 128)
        let phrase = mnemonic.phrase

        let keypair = try await KeyPair(
            phrase: phrase,
            network: .mainnetBeta,
            derivablePath: .default
        )

        let publicKeyBase58 = keypair.publicKey.base58EncodedString

        await MainActor.run {
            self.state = .draft(phrase: phrase, publicKeyBase58: publicKeyBase58)
        }
    }

    /// Persist the draft wallet to Keychain. Call after user confirmed seed phrase.
    func confirmDraft() throws {
        guard case let .draft(phrase, publicKeyBase58) = state else { return }

        try KeychainStorage.save(phrase.joined(separator: " "), for: .seedPhrase,
                                 requireBiometry: SeedLock.isEnabled)
        try KeychainStorage.save(publicKeyBase58, for: .publicKey)

        state = .ready(publicKeyBase58: publicKeyBase58)
    }

    /// Import existing wallet from 12 or 24 words.
    func importWallet(phrase: [String]) async throws {
        let keypair = try await KeyPair(
            phrase: phrase,
            network: .mainnetBeta,
            derivablePath: .default
        )

        let publicKeyBase58 = keypair.publicKey.base58EncodedString

        try KeychainStorage.save(phrase.joined(separator: " "), for: .seedPhrase,
                                 requireBiometry: SeedLock.isEnabled)
        try KeychainStorage.save(publicKeyBase58, for: .publicKey)

        await MainActor.run {
            clearCache()   // drop any previous account's cached keypair
            self.state = .ready(publicKeyBase58: publicKeyBase58)
        }
    }

    func discardDraft() {
        state = .noWallet
    }

    /// Re-store the active seed slot with the current `SeedLock` setting.
    /// Call after toggling the lock (alongside AccountManager.reapplySeedProtection()).
    func reapplySeedProtection() {
        guard case .ready = state,
              let phrase = try? revealSeedPhrase(), !phrase.isEmpty else { return }
        cachedKeyPair = nil; cachedFor = nil
        try? KeychainStorage.save(phrase.joined(separator: " "), for: .seedPhrase,
                                  requireBiometry: SeedLock.isEnabled)
    }

    func wipe() {
        clearCache()
        KeychainStorage.wipeAll()
        state = .noWallet
    }

    /// Read the seed phrase from Keychain. When the seed lock is on this prompts
    /// Face ID / passcode (reuse-windowed). Caller may also gate at the app level.
    func revealSeedPhrase() throws -> [String] {
        guard let raw = try KeychainStorage.read(
            .seedPhrase, context: SeedLock.context(),
            prompt: "Доступ к seed-фразе") else { return [] }
        return raw.split(separator: " ").map(String.init)
    }

    /// Re-derive the Solana KeyPair from the stored seed phrase. The result
    /// contains the private key — DO NOT store outside short-lived scopes.
    /// Caller is responsible for biometry/passcode confirmation before calling.
    func currentKeyPair() async throws -> KeyPair {
        // Reuse the cached keypair for the active account so signing never
        // re-reads the seed (and never re-prompts) per transaction.
        if case let .ready(pub) = state, let cached = cachedKeyPair, cachedFor == pub {
            return cached
        }
        let phrase = try revealSeedPhrase()
        guard !phrase.isEmpty else {
            throw NSError(
                domain: "WalletManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No seed phrase stored"]
            )
        }
        let keyPair = try await KeyPair(
            phrase: phrase,
            network: .mainnetBeta,
            derivablePath: .default
        )
        cachedKeyPair = keyPair
        cachedFor = keyPair.publicKey.base58EncodedString
        return keyPair
    }
}
