//
//  GasWalletService.swift
//  privamesh
//
//  Optional "fee wallet" — a separate, throwaway keypair that pays the fee and
//  signs message transactions instead of the main wallet. With it on, the main
//  wallet NEVER appears on-chain for messages: the fee payer (= the only visible
//  sender) is this gas wallet. Combined with stealth addresses, neither the
//  sender's nor the recipient's real wallet is exposed by a message.
//
//  PRIVACY NOTE: for real sender anonymity the user must fund this wallet from
//  an UNLINKABLE source (exchange withdrawal, a different wallet). Funding it
//  from the main wallet re-links them on-chain.
//
//  It's a hot wallet by design (signs frequently, incl. cover traffic), so it is
//  intentionally NOT behind the biometric seed lock and its keypair is cached.
//

import Foundation
import SolanaSwift

@Observable
final class GasWalletService {
    // PER-ACCOUNT keys (suffixed with the wallet address). A shared gas wallet
    // would pay fees for every account → same on-chain fee payer links the
    // otherwise-unlinkable accounts. Each account now has its own gas wallet.
    private static let seedKeyBase    = "privamesh.gaswallet.seed"
    private static let pubkeyKeyBase  = "privamesh.gaswallet.pubkey"
    private static let enabledKeyBase = "privamesh.gaswallet.enabled"
    private static let migratedFlag   = "privamesh.gaswallet.migratedV2"

    private var walletKey = ""
    private func seedKey()    -> String { walletKey.isEmpty ? Self.seedKeyBase    : "\(Self.seedKeyBase).\(walletKey)" }
    private func pubkeyKey()  -> String { walletKey.isEmpty ? Self.pubkeyKeyBase  : "\(Self.pubkeyKeyBase).\(walletKey)" }
    private func enabledKey() -> String { walletKey.isEmpty ? Self.enabledKeyBase : "\(Self.enabledKeyBase).\(walletKey)" }

    /// Gas wallet public address (nil if none created) for the BOUND account.
    private(set) var address: String?

    private var cached: KeyPair?

    init() {}

    /// Bind to the active account — switches the gas-wallet namespace + reloads.
    func bind(to wallet: String) {
        guard !wallet.isEmpty, walletKey != wallet else { return }
        walletKey = wallet
        cached = nil
        migrateGlobalIfNeeded()
        address = UserDefaults.standard.string(forKey: pubkeyKey())
    }

    /// One-time: move the legacy single global gas wallet onto the first account
    /// bound after the upgrade, so existing users keep their funded gas wallet.
    private func migrateGlobalIfNeeded() {
        let d = UserDefaults.standard
        guard d.string(forKey: Self.migratedFlag) == nil else { return }
        d.set(walletKey, forKey: Self.migratedFlag)      // claim migration for this account
        guard d.string(forKey: pubkeyKey()) == nil,      // account has no gas wallet yet
              let globalPub = d.string(forKey: Self.pubkeyKeyBase) else { return }
        if let seed = KeychainStorage.load(key: Self.seedKeyBase) {
            KeychainStorage.save(key: seedKey(), data: seed)
        }
        d.set(globalPub, forKey: pubkeyKey())
        d.set(d.bool(forKey: Self.enabledKeyBase), forKey: enabledKey())
        // Remove the old global copy so accounts no longer share it.
        KeychainStorage.delete(key: Self.seedKeyBase)
        d.removeObject(forKey: Self.pubkeyKeyBase)
        d.removeObject(forKey: Self.enabledKeyBase)
    }

    /// User wants to route message fees through the gas wallet.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey()) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey()) }
    }

    var exists: Bool { address != nil }
    /// True only when a gas wallet exists AND routing is enabled.
    var isActive: Bool { isEnabled && address != nil }

    // MARK: - Create / import / remove

    /// Generate a fresh gas wallet. Returns the seed phrase so the user can back
    /// it up (and re-fund elsewhere).
    @discardableResult
    func create() async throws -> [String] {
        let phrase = Mnemonic(strength: 128).phrase
        try await store(phrase: phrase)
        return phrase
    }

    func importSeed(_ phrase: [String]) async throws {
        let cleaned = phrase.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try await store(phrase: cleaned)
    }

    private func store(phrase: [String]) async throws {
        let keypair = try await KeyPair(phrase: phrase, network: .mainnetBeta, derivablePath: .default)
        let pub = keypair.publicKey.base58EncodedString
        KeychainStorage.save(key: seedKey(), data: Data(phrase.joined(separator: " ").utf8))
        UserDefaults.standard.set(pub, forKey: pubkeyKey())
        cached = keypair
        address = pub
        isEnabled = true
    }

    func remove() {
        KeychainStorage.delete(key: seedKey())
        UserDefaults.standard.removeObject(forKey: pubkeyKey())
        UserDefaults.standard.removeObject(forKey: enabledKey())
        cached = nil
        address = nil
    }

    func revealSeed() -> [String] {
        guard let data = KeychainStorage.load(key: seedKey()),
              let s = String(data: data, encoding: .utf8) else { return [] }
        return s.split(separator: " ").map(String.init)
    }

    // MARK: - Signing

    /// Derive (and cache) the gas wallet keypair.
    func keyPair() async throws -> KeyPair {
        if let cached { return cached }
        let phrase = revealSeed()
        guard !phrase.isEmpty else {
            throw NSError(domain: "GasWalletService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Газовый баланс не создан"])
        }
        let kp = try await KeyPair(phrase: phrase, network: .mainnetBeta, derivablePath: .default)
        cached = kp
        return kp
    }

    /// The keypair that should pay+sign a message tx: the gas wallet when active,
    /// otherwise the provided fallback (main wallet).
    func feePayer(fallback: KeyPair) async -> KeyPair {
        guard isActive, let kp = try? await keyPair() else { return fallback }
        return kp
    }

    /// Lamports needed to afford the next message fee (base 5000 + priority +
    /// the 1-lamport marker, with a little headroom). Block only when truly short.
    static let minFundingLamports: UInt64 = 8_000

    /// True when routing through the gas wallet but it can't cover a fee → the
    /// caller should tell the user to top it up instead of letting the tx fail.
    func needsTopUp(rpc: SolanaRPCService) async -> Bool {
        guard isActive, let addr = address else { return false }
        let bal = (try? await rpc.client.getBalance(account: addr, commitment: "confirmed")) ?? 0
        return bal < Self.minFundingLamports
    }
}
