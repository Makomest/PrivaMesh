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

        var errorDescription: String? {
            switch self {
            case .notConfigured: return String(localized: "Сервис доставки не настроен.")
            case .quotaExceeded: return String(localized: "Лимит сообщений исчерпан. Оформите подписку или купите пакет.")
            case .http(let code, let msg):
                return String(localized: "Ошибка доставки (\(code)). \(msg)")
            case .badResponse: return String(localized: "Некорректный ответ сервиса доставки.")
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

    /// Opaque token unique to the ACTIVE account (not the device). DERIVED from
    /// the account pubkey — `SHA256(pubkey + salt)` — so it is STABLE across app
    /// reinstall/device: the same seed yields the same token, and the relay
    /// restores that account's server-side balance instead of treating a fresh
    /// install as a brand-new zero-balance user.
    ///
    /// Anonymity is preserved: two accounts have two pubkeys → two unrelated
    /// hashes, and the relay never sees the pubkey (only the digest), so it
    /// cannot correlate a device's separate accounts. Pubkeys are already public
    /// on-chain, so deriving from one leaks nothing new.
    private static let tokenKey = "privamesh.relay.accountToken"   // legacy pre-account fallback
    private static let tokenSalt = "privamesh.relay.token.v1"
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
        let digest = SHA256.hash(data: Data("\(acct).\(Self.tokenSalt)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var isConfigured: Bool { RelayConfig.isConfigured }

    // MARK: - Send

    /// Build a sponsored message tx, submit it via the relay, return the on-chain
    /// signature. Throws `notConfigured` when the relay/treasury are unset (the
    /// caller should fall back or block).
    func sendMessage(
        to recipientAddress: String,
        memoBase64: String,
        endpointURL: String,
        computeUnitLimit: UInt32? = nil
    ) async throws -> String {
        guard RelayConfig.isConfigured,
              let treasury = try? PublicKey(string: RelayConfig.treasuryPubkey),
              treasury.bytes.count == PublicKey.numberOfBytes else {
            throw RelayError.notConfigured
        }
        let txBase64 = try await MemoTransactionBuilder.buildSponsoredMessageBase64(
            to: recipientAddress, memoBase64: memoBase64,
            treasury: treasury, endpointURL: endpointURL, computeUnitLimit: computeUnitLimit)
        let jws = await receiptProvider()
        return try await post(txBase64: txBase64, jws: jws)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Transport

    private func post(txBase64: String, jws: String?) async throws -> String {
        guard let url = URL(string: RelayConfig.baseURL + "/send") else {
            throw RelayError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let body: [String: Any] = [
            "tx": txBase64,
            "jws": jws ?? "",
            "account": accountToken,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
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
