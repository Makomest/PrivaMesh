//
//  BlindTokenService.swift
//  privamesh

//  Maintains a device-local pool of anonymous, unlinkable message tokens (RSA
//  blind signatures — see BlindTokenCrypto). The pool is refilled by proving the
//  Apple subscription ONCE to the relay's /issue endpoint; from then on each
//  message spends a token that the relay cannot link back to the purchase or to
//  any other message. This replaces sending the Apple receipt on every /send.

//  Tokens are anonymous by construction, so the pool is device-global (NOT keyed
//  per account) and is kept in the Keychain. Losing the pool costs nothing but a
//  re-issue; it is never a secret that identifies the user.

//  Wired to SubscriptionManager (for the receipt) and RelayService (which spends
//  tokens) at the app root. When the relay has no issuer key configured, the
//  service stays disabled and the app falls back to the legacy receipt path.


import CryptoKit
import Foundation

@Observable
final class BlindTokenService {
    /// Supplies the Apple IAP receipt (JWS) proving entitlement, used only at
    /// issuance time. Wired to SubscriptionManager by the app root.
    var jwsProvider: () async -> String? = { nil }

    /// True once a usable issuer public key has been fetched.
    private(set) var enabled = false

    /// True when this device has ever committed to an issuer key — that is, the
    /// relay has served a working one at least once on this install.

    /// This outlives `enabled` and the pool on purpose. `enabled` is about the
    /// last /pubkey answer; a relay can make that answer `false`, or reject every
    /// token at /send, at any moment. Neither may turn a device that was
    /// anonymous back into an identified one, which is what RelayService's
    /// unconditional fall-back to the Apple receipt used to do. Reported
    /// externally. The pin is the durable record of "this device has the
    /// anonymous path", so it is what the fall-back is gated on.
    var anonymityEstablished: Bool { enabled || Self.hasIssuerPin }

    private static var hasIssuerPin: Bool {
        KeychainStorage.load(key: issuerPinKey) != nil
    }
    /// Number of spendable tokens currently stocked (for UX/diagnostics).
    private(set) var stock = 0

    private var issuer: BlindIssuerKey?

    // Refill policy. batchSize must not exceed the relay's ISSUE_BATCH_MAX.
    private let targetPool = 40
    private let refillThreshold = 8
    private let batchSize = 32

    private static let poolKey = "privamesh.relay.blindTokens.v1"

    /// Where the issuer key this device has committed to is remembered.
    private static let issuerPinKey = "privamesh.relay.issuerPin.v1"

    /// Issuer keys this build accepts, as SHA-256 over the raw modulus and
    /// exponent bytes. Empty means none is baked in yet.

    /// A pin belongs here once the relay has a stable issuer key. Until then the
    /// device pins the first key it is given - see `refreshIssuerKey`.
    private static let pinnedIssuerDigests: Set<String> = []

    private var refilling = false

    init() { stock = loadPool().count }

    // MARK: pubkey

    /// Fetch and cache the issuer public key. Idempotent; safe to call on launch.

    /// The key is pinned, because the relay choosing it per client is a way to
    /// undo the whole point of blind tokens. A key served to one device and no
    /// other is a tag: the blinded values and the returned signatures are encoded
    /// at that modulus width, so recognising the width later maps an anonymous
    /// send back to the exact purchase that issued it - no cookie, no account
    /// field, no shared connection. Reported externally,
    /// which is the issuance-consistency problem in RFC 9576 section 6.2.

    /// Two levels, in order. A digest baked into the build wins, and nothing else
    /// is accepted. With none baked in, the device pins the first key it sees and
    /// refuses any later change: an operator then gets one attempt, on first
    /// contact, instead of one per issuance.

    /// What this still does not give is consistency ACROSS devices - proving that
    /// everyone was handed the same key needs a commitment in the build or a
    /// transparency log. That limit is worth stating rather than implying.
    func refreshIssuerKey() async {
        guard RelayConfig.isConfigured,
              let url = URL(string: RelayConfig.baseURL + "/pubkey") else { return }
        do {
            let (data, resp) = try await PrivateNetwork.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["enabled"] as? Bool == true,
                  let n = obj["n"] as? String, let e = obj["e"] as? String,
                  let key = BlindIssuerKey(nB64u: n, eB64u: e),
                  Self.accept(issuerDigest: Self.issuerDigest(nB64u: n, eB64u: e)) else {
                enabled = false
                return
            }
            issuer = key
            enabled = true
        } catch {
            enabled = false
        }
    }

    /// SHA-256 over the key as served, so two spellings of one key are one pin.
    private static func issuerDigest(nB64u: String, eB64u: String) -> String {
        var input = Data()
        input.append(contentsOf: Array(nB64u.utf8))
        input.append(0x00)
        input.append(contentsOf: Array(eB64u.utf8))
        return Data(SHA256.hash(data: input)).base64EncodedString()
    }

    /// True when this device may use the key behind [digest].
    private static func accept(issuerDigest digest: String) -> Bool {
        if !pinnedIssuerDigests.isEmpty {
            return pinnedIssuerDigests.contains(digest)
        }

        guard let stored = KeychainStorage.load(key: issuerPinKey),
              let known = String(data: stored, encoding: .utf8) else {
            // First contact: commit to this key. A device that has never seen one
            // has nothing to compare against, and refusing outright would turn a
            // fresh install into a broken one.
            KeychainStorage.save(key: issuerPinKey, data: Data(digest.utf8))
            return true
        }
        // A changed key is refused rather than adopted. Rotation therefore needs a
        // build that carries the new pin - which is the point: an operator must
        // not be able to rotate one device onto a key of its own.
        return known == digest
    }

    // MARK: pool storage

    private func loadPool() -> [BlindToken] {
        guard let data = KeychainStorage.load(key: Self.poolKey),
              let tokens = try? JSONDecoder().decode([BlindToken].self, from: data) else { return [] }
        return tokens
    }

    private func savePool(_ tokens: [BlindToken]) {
        stock = tokens.count
        if let data = try? JSONEncoder().encode(tokens) {
            KeychainStorage.save(key: Self.poolKey, data: data)
        }
    }

    /// Pop one token to spend, or nil if the pool is empty. Persists the removal
    /// so a token is never handed out twice across launches.
    func takeToken() -> BlindToken? {
        var pool = loadPool()
        guard !pool.isEmpty else { return nil }
        let t = pool.removeFirst()
        savePool(pool)
        return t
    }

    /// Return a token to the pool — used when a send failed before the relay
    /// could burn it, so the paid token is not lost.
    func returnToken(_ token: BlindToken) {
        var pool = loadPool()
        guard let issuer, BlindTokenCrypto.verify(token, key: issuer) else { return }
        pool.append(token)
        savePool(pool)
    }

    // MARK: refill

    /// Blind a batch, prove entitlement once at /issue, unblind the results into
    /// the pool. No-op when disabled, already well-stocked, or already refilling.
    func ensureStock() async {
        if issuer == nil { await refreshIssuerKey() }
        guard enabled, let issuer, !refilling else { return }
        var pool = loadPool()
        if pool.count >= refillThreshold { stock = pool.count; return }

        refilling = true
        defer { refilling = false }

        let need = min(targetPool - pool.count, batchSize)
        guard need > 0 else { return }

        // Blind `need` fresh nonces; keep the (nonce, r) secrets to unblind.
        var nonces: [[UInt8]] = []
        var rs: [BigUInt] = []
        var blindeds: [String] = []
        for _ in 0..<need {
            let (nonce, blindedB64u, r) = BlindTokenCrypto.blind(key: issuer)
            nonces.append(nonce); rs.append(r); blindeds.append(blindedB64u)
        }

        guard let url = URL(string: RelayConfig.baseURL + "/issue") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let jws = await jwsProvider()
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "jws": jws ?? "", "blinded": blindeds,
        ])

        guard let (data, resp) = try? await PrivateNetwork.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sigs = obj["sigs"] as? [String] else {
            // 402 (no subscription) or any error → stay on the legacy path silently.
            return
        }

        // Unblind each returned signature with its matching secret. The relay may
        // return FEWER than requested (monthly budget) — unblind only what came
        // back, pairing by index.
        for (i, sig) in sigs.enumerated() where i < nonces.count {
            if let token = BlindTokenCrypto.unblind(blindSigB64u: sig, nonce: nonces[i], r: rs[i], key: issuer) {
                pool.append(token)
            }
        }
        savePool(pool)
    }
}
