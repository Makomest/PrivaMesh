//
//  RelayService.swift
//  privamesh
//
//  Client for the sponsoring relay. Messaging fees are paid by an app-operated
//  treasury wallet, never by the user. The client builds a message transaction
//  whose fee payer is the treasury, partial-signs it with the sender's key, and
//  POSTs it to the relay together with the user's Apple IAP receipt (JWS). The
//  relay verifies the receipt + remaining quota, adds the treasury signature and
//  submits the transaction to Solana, returning the signature.
//
//  The relay is the AUTHORITATIVE quota gate (MessageQuotaService is only the
//  on-device UX mirror). Without server-side verification the treasury could be
//  drained by a tampered client, so the relay must never co-sign without a valid,
//  unspent receipt.
//

import Foundation
import CryptoKit
import SolanaSwift

/// Deployment configuration for the sponsoring relay. Fill these in after
/// creating the treasury wallet and deploying the Worker (see /relay).
enum RelayConfig {
    /// Base URL of the relay (e.g. "https://relay.privamesh.workers.dev").
    static let baseURL = "https://privamesh-relay.privamesh.workers.dev"
    /// Base58 public key of the treasury wallet that pays network fees.
    static let treasuryPubkey = "ci28yZMzZ8Xo4DgkHXU8MgBzPMkXhVixEWsgEQm8ix8"

    static var isConfigured: Bool { !baseURL.isEmpty && !treasuryPubkey.isEmpty }
}

@Observable
final class RelayService {
    enum RelayError: LocalizedError {
        case notConfigured
        case quotaExceeded
        case http(Int, String)
        case badResponse
        /// This device has the anonymous path and the relay would not let it be
        /// used. The message is not sent: the alternative is to re-send it with
        /// the Apple receipt attached, which is the linkage the token exists to
        /// prevent.
        case anonymityUnavailable

        var errorDescription: String? {
            switch self {
            case .notConfigured: return String(localized: "Сервис доставки не настроен.")
            case .quotaExceeded: return String(localized: "Лимит сообщений исчерпан. Оформите подписку или купите пакет.")
            case .http(let code, let msg):
                return String(localized: "Ошибка доставки (\(code)). \(msg)")
            case .badResponse: return String(localized: "Некорректный ответ сервиса доставки.")
            case .anonymityUnavailable:
                return String(localized: "Анонимная отправка сейчас недоступна. Сообщение не отправлено — иначе оно ушло бы вместе с чеком Apple.")
            }
        }
    }

    /// Supplies the Apple IAP receipt (JWS) proving the user's entitlement.
    /// Wired to SubscriptionManager by the app root.
    var receiptProvider: () async -> String? = { nil }

    /// Supplies the active account's public key so quota is keyed PER ACCOUNT.
    /// This stops the relay from linking a device's separate accounts to one
    /// token. Wired to AccountManager by the app root.
    var activeAccountProvider: () -> String = { "" }

    /// Anonymous blind-token hooks (see BlindTokenService), wired at the app root.
    /// When a token is available, a message is sent with it INSTEAD of the Apple
    /// receipt + account token, so nothing identifying reaches the relay. Both are
    /// no-ops by default, which keeps the legacy receipt path working unchanged.
    var takeBlindToken: () async -> BlindToken? = { nil }
    var returnBlindToken: (BlindToken) async -> Void = { _ in }

    /// True when this device should be able to spend a token: it has been served
    /// the relay's issuer key, and StoreKit says the subscription that pays for
    /// tokens is active. Such a device does not fall back to the identifying path
    /// — see `sendMessage`.

    /// Entitlement is read from StoreKit rather than from the relay's answer to
    /// /issue on purpose. The relay only mints tokens for an active subscription,
    /// so "no subscription" is a legitimate reason to have none — and letting the
    /// relay assert it would hand back the lever this guard takes away.

    /// Wired at the app root; false by default, which is the state of a device
    /// that has never seen a key.
    var anonymityExpected: () -> Bool = { false }

    /// Refill the token pool. Called when the pool has run dry on a device that
    /// has the anonymous path, so an empty pool costs a refill rather than the
    /// sender's anonymity. Wired to BlindTokenService.ensureStock at the app root.
    var replenishBlindTokens: () async -> Void = { }

    /// Opaque token unique to the ACTIVE account. DERIVED from the account's SEED
    /// (a secret only the owner holds) as `HKDF(seed, info: pubkey)`, persisted in
    /// the Keychain by `provisionToken`. Two properties matter:
    ///   • STABLE — the same seed yields the same token, so a reinstall/restore
    ///     recovers the account's server-side balance instead of looking new.
    ///   • UNFORGEABLE — it is NOT derived from the public key, so a third party
    ///     who knows a victim's on-chain address (and can read the app binary)
    ///     still cannot compute the victim's token and grief/spend their quota.
    /// Anonymity holds: distinct seeds → unrelated tokens; the relay sees only the
    /// digest, never the pubkey, so it can't correlate a device's accounts.
    private static let tokenKey = "privamesh.relay.accountToken"   // legacy pre-account fallback
    private static let legacyTokenSalt = "privamesh.relay.token.v1"
    private func tokenKeychainKey(_ pub: String) -> String { "privamesh.relay.token.\(pub)" }

    var accountToken: String {
        let acct = activeAccountProvider()
        // Pre-account (onboarding warm-up): keep the legacy random device token.
        guard !acct.isEmpty else {
            let d = UserDefaults.standard
            if let t = d.string(forKey: Self.tokenKey) { return t }
            let t = UUID().uuidString
            d.set(t, forKey: Self.tokenKey)
            return t
        }
        // Seed-derived token (provisioned when the seed was stored).
        if let data = KeychainStorage.load(key: tokenKeychainKey(acct)),
           let s = String(data: data, encoding: .utf8), !s.isEmpty { return s }
        // Transitional fallback for accounts provisioned before seed-derived
        // tokens existed. Deterministic but derived from the public key, so it is
        // replaced by the seed-derived token on the next seed (re)store.
        let digest = SHA256.hash(data: Data("\(acct).\(Self.legacyTokenSalt)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Derive & persist this account's relay token from its seed phrase. No-op if
    /// one already exists. Called whenever an account's seed is (re)stored, so the
    /// token is recoverable by re-entering the phrase yet never exposed by the
    /// public key alone. See `accountToken`.
    func provisionToken(address: String, seedPhrase words: [String]) {
        guard !address.isEmpty, !words.isEmpty else { return }
        let key = tokenKeychainKey(address)
        guard KeychainStorage.load(key: key) == nil else { return }
        let normalized = words.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        let digest = CryptoBox.hkdf(inputKeyMaterial: Data(normalized.utf8),
                                    salt: Data("PrivaMesh-relay-token-v1".utf8),
                                    info: Data(address.utf8), outputByteCount: 32)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        KeychainStorage.save(key: key, data: Data(hex.utf8))
    }

    var isConfigured: Bool { RelayConfig.isConfigured }

    // MARK: - Send

    /// Build a sponsored message tx, submit it via the relay, return the on-chain
    /// signature. Throws `notConfigured` when the relay/treasury are unset (the
    /// caller should fall back or block).
    /// - Parameter allowAnonymousToken: when true (the default, for ordinary
    ///   messages) an anonymous blind token is spent if one is stocked, so the
    ///   relay learns nothing about the sender. Discovery publishes pass false —
    ///   they need the account path for authoritative nickname ownership.
    func sendMessage(
        to recipientAddress: String,
        memoBase64: String,
        endpointURL: String,
        computeUnitLimit: UInt32? = nil,
        allowAnonymousToken: Bool = true
    ) async throws -> String {
        guard RelayConfig.isConfigured,
              let treasury = try? PublicKey(string: RelayConfig.treasuryPubkey),
              treasury.bytes.count == PublicKey.numberOfBytes else {
            throw RelayError.notConfigured
        }
        let txBase64 = try await MemoTransactionBuilder.buildSponsoredMessageBase64(
            to: recipientAddress, memoBase64: memoBase64,
            treasury: treasury, endpointURL: endpointURL, computeUnitLimit: computeUnitLimit)

        // Preferred path: spend an anonymous token.

        // The fall-back to the receipt path is NOT unconditional. It used to be,
        // and that handed the relay the switch: answer `enabled: false` at
        // /pubkey, or simply reject every token at /send, and every client
        // quietly re-sent the same message with the Apple receipt attached —
        // exactly the purchase-to-send link the blind signatures exist to break,
        // obtained without touching the signatures. Reported externally.

        // So a device that has the anonymous path keeps it: an empty pool costs a
        // refill, and a relay that refuses the token costs the send. A device that
        // has never been served an issuer key has no anonymity to lose and still
        // takes the receipt path, which is what keeps free-tier and
        // never-configured-relay installs working.
        if allowAnonymousToken {
            var token = await takeBlindToken()
            if token == nil, anonymityExpected() {
                await replenishBlindTokens()
                token = await takeBlindToken()
            }
            if let token {
                do {
                    return try await post(txBase64: txBase64, jws: nil, token: token)
                } catch {
                    // Still unspent — the relay only burns it on submit success.
                    await returnBlindToken(token)
                    // Report what went wrong; do not re-send the same message with
                    // the receipt attached.
                    if !Self.mayUseReceiptPath(allowAnonymousToken: true,
                                               anonymityExpected: anonymityExpected()) { throw error }
                }
            } else if !Self.mayUseReceiptPath(allowAnonymousToken: true,
                                              anonymityExpected: anonymityExpected()) {
                throw RelayError.anonymityUnavailable
            }
        }

        let jws = await receiptProvider()
        return try await post(txBase64: txBase64, jws: jws, token: nil)
    }

    /// Mint an NFT nickname with the fee + account rent sponsored by the treasury.
    /// Verified subscribers get a limited number of sponsored mints (enforced by
    /// the relay). Returns the mint address on success.
    func sponsorMint(designId: String, keypair: KeyPair, rpc: SolanaRPCService) async throws -> String {
        guard RelayConfig.isConfigured,
              let treasury = try? PublicKey(string: RelayConfig.treasuryPubkey),
              treasury.bytes.count == PublicKey.numberOfBytes else {
            throw RelayError.notConfigured
        }
        let built = try await OnChainNFT.buildSponsoredMint(
            designId: designId, keypair: keypair, treasury: treasury, rpc: rpc)
        let jws = await receiptProvider()

        guard let url = URL(string: RelayConfig.baseURL + "/mint") else { throw RelayError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "tx": built.tx, "jws": jws ?? "", "account": accountToken,
        ])
        let (data, resp) = try await PrivateNetwork.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw RelayError.badResponse }
        if http.statusCode == 402 { throw RelayError.quotaExceeded }   // out of mint allowance
        guard (200..<300).contains(http.statusCode) else {
            throw RelayError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return built.mint
    }

    /// Forward a consumable-pack receipt to the relay so it credits the
    /// authoritative server-side message balance. Idempotent on the relay.
    func creditPack(jws: String) async {
        guard RelayConfig.isConfigured, !jws.isEmpty,
              let url = URL(string: RelayConfig.baseURL + "/credit") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["jws": jws, "account": accountToken])
        _ = try? await PrivateNetwork.shared.data(for: req)
    }

    // MARK: - Transport

    /// Whether this send may fall back to the identifying path: the Apple receipt
    /// plus the per-account token.

    /// Two cases may. A discovery publish (`allowAnonymousToken: false`) claims a
    /// public nickname and needs the account path for ownership — it is
    /// identifying by construction and the relay rejects it on the token path. And
    /// a device with no token to expect — it has never been served an issuer key,
    /// or it is on the free tier, which the relay meters per account precisely
    /// because it mints no tokens for it — has no anonymity to preserve here;
    /// refusing would only mean it could not send at all.

    /// Everything else may not, which is the fix: whether a send carries the
    /// receipt is no longer something the relay can decide by withholding tokens.
    static func mayUseReceiptPath(allowAnonymousToken: Bool, anonymityExpected: Bool) -> Bool {
        !allowAnonymousToken || !anonymityExpected
    }

    /// The body a /send carries, as a pure function so the property that matters
    /// can be asserted in a test: the token path carries NO receipt and NO account
    /// token, and the two are never sent together. `account` is an autoclosure
    /// because reading it provisions a device token on first use — the token path
    /// must not cause that.
    static func sendBody(txBase64: String, jws: String?, token: BlindToken?,
                         account: @autoclosure () -> String) -> [String: Any] {
        var body: [String: Any] = ["tx": txBase64]
        if let token {
            body["token"] = ["t": token.t, "sig": token.sig]
        } else {
            body["jws"] = jws ?? ""
            body["account"] = account()
        }
        return body
    }

    private func post(txBase64: String, jws: String?, token: BlindToken?) async throws -> String {
        guard let url = URL(string: RelayConfig.baseURL + "/send") else {
            throw RelayError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(
            withJSONObject: Self.sendBody(txBase64: txBase64, jws: jws, token: token,
                                          account: accountToken))

        let (data, resp) = try await PrivateNetwork.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw RelayError.badResponse }
        if http.statusCode == 402 { throw RelayError.quotaExceeded }   // out of quota
        guard (200..<300).contains(http.statusCode) else {
            throw RelayError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sig = obj["signature"] as? String, !sig.isEmpty else {
            throw RelayError.badResponse
        }
        return sig
    }
}
