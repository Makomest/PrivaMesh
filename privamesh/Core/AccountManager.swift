//
//  AccountManager.swift
//  privamesh
//
//  Multi-account manager. Each account is an INDEPENDENT wallet with its own
//  seed phrase (stored in Keychain, keyed by public key). You can create a new
//  one or import an existing one by seed phrase. The active account drives the
//  whole app (balance, nickname, market, chats) — switching copies its seed
//  into the "current" Keychain slot so signing/derivation use it.
//

import Foundation
import SolanaSwift

struct WalletAccount: Codable, Identifiable, Equatable {
    let publicKeyBase58: String
    var name: String

    var id: String { publicKeyBase58 }

    /// Localized display name: auto-default ("Аккаунт N"/"Account N") follows the
    /// app language; a user-chosen name is shown as-is.
    var displayName: String {
        let parts = name.split(separator: " ")
        if parts.count == 2, (parts[0] == "Аккаунт" || parts[0] == "Account"), let n = Int(parts[1]) {
            return String(localized: "Аккаунт \(n)")
        }
        return name
    }

    var shortKey: String {
        guard publicKeyBase58.count > 12 else { return publicKeyBase58 }
        return publicKeyBase58.prefix(6) + "…" + publicKeyBase58.suffix(6)
    }
}

@Observable
final class AccountManager {
    static let maxAccounts = 3

    private static let storageKey = "privamesh.accounts.v2"
    private static let activeKey  = "privamesh.activeAccountPubkey"

    private(set) var accounts: [WalletAccount] = []
    private(set) var activePublicKey: String = ""

    var activeAccount: WalletAccount? { accounts.first { $0.id == activePublicKey } }

    init() { load() }

    // MARK: - Per-account seed storage (Keychain)

    private func seedKey(_ pub: String) -> String { "privamesh.seed.\(pub)" }

    func seedPhrase(for publicKey: String) -> [String]? {
        guard let data = KeychainStorage.load(key: seedKey(publicKey),
                                              context: SeedLock.context(),
                                              prompt: "Доступ к аккаунту"),
              let s = String(data: data, encoding: .utf8) else { return nil }
        let words = s.split(separator: " ").map(String.init)
        return words.isEmpty ? nil : words
    }

    private func storeSeed(_ phrase: [String], for publicKey: String) {
        KeychainStorage.save(key: seedKey(publicKey),
                             data: Data(phrase.joined(separator: " ").utf8),
                             requireBiometry: SeedLock.isEnabled)
    }

    /// Re-store every account's seed backup with the current lock setting.
    /// Reads each seed once (reuse-windowed prompt) and rewrites it.
    func reapplySeedProtection() {
        for a in accounts {
            guard let phrase = seedPhrase(for: a.id) else { continue }
            storeSeed(phrase, for: a.id)
        }
    }

    // MARK: - Add accounts

    /// Import an existing account from its seed phrase (12/24 words).
    @discardableResult
    func importAccount(phrase: [String], name: String? = nil) async throws -> WalletAccount {
        let cleaned = phrase.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let keypair = try await KeyPair(phrase: cleaned, network: .mainnetBeta, derivablePath: .default)
        let pub = keypair.publicKey.base58EncodedString

        if let existing = accounts.first(where: { $0.id == pub }) { return existing }
        storeSeed(cleaned, for: pub)
        let account = WalletAccount(publicKeyBase58: pub, name: name ?? "Аккаунт \(accounts.count + 1)")
        accounts.append(account)
        save()
        return account
    }

    /// Create a brand-new account (fresh seed phrase).
    @discardableResult
    func createAccount(name: String? = nil) async throws -> (account: WalletAccount, phrase: [String]) {
        let phrase = Mnemonic(strength: 128).phrase
        let account = try await importAccount(phrase: phrase, name: name)
        return (account, phrase)
    }

    /// Ensure the wallet's current account (`publicKey`) is registered AND active.
    /// Called on launch with the address in WalletManager's seed slot. Must handle
    /// onboarding-restore: after a reset + import of a DIFFERENT seed, the new
    /// account has to become active even if a stale record lingered — the old
    /// `guard accounts.isEmpty` bailed and left the previous account selected.
    func ensurePrimary(phrase: [String], publicKey: String, name: String = "Аккаунт 1") {
        guard !publicKey.isEmpty else { return }
        if !accounts.contains(where: { $0.id == publicKey }) {
            storeSeed(phrase, for: publicKey)
            let n = accounts.isEmpty ? name : "Аккаунт \(accounts.count + 1)"
            accounts.append(WalletAccount(publicKeyBase58: publicKey, name: n))
            save()
        }
        if activePublicKey != publicKey { setActive(publicKey) }
    }

    // MARK: - Active / rename / remove

    func setActive(_ publicKey: String) {
        guard accounts.contains(where: { $0.id == publicKey }) else { return }
        activePublicKey = publicKey
        UserDefaults.standard.set(publicKey, forKey: Self.activeKey)
    }

    func rename(_ publicKey: String, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == publicKey }) else { return }
        accounts[i].name = name
        save()
    }

    /// Remove an account. Returns the account that is now active (or nil if none
    /// left) — the CALLER must re-activate it via `WalletManager.activate` so the
    /// Keychain seed slot + bound services follow, else the wallet stays on the
    /// just-removed account (same class of bug as the old `ensurePrimary`).
    @discardableResult
    func remove(_ publicKey: String) -> WalletAccount? {
        let removedActive = (activePublicKey == publicKey)
        accounts.removeAll { $0.id == publicKey }
        KeychainStorage.delete(key: seedKey(publicKey))
        if removedActive { activePublicKey = accounts.first?.id ?? "" }
        save()
        UserDefaults.standard.set(activePublicKey, forKey: Self.activeKey)
        return removedActive ? activeAccount : nil
    }

    func removeAll() {
        for a in accounts { KeychainStorage.delete(key: seedKey(a.id)) }
        accounts = []
        activePublicKey = ""
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.activeKey)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([WalletAccount].self, from: data) {
            accounts = saved
        }
        activePublicKey = UserDefaults.standard.string(forKey: Self.activeKey) ?? accounts.first?.id ?? ""
    }
}
