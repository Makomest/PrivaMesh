//
//  BlindTokenCrypto.swift
//  privamesh
//
//  Client half of the RSA blind-signature token protocol. Mirrors the relay's
//  relay/src/blindtokens.ts EXACTLY (same MGF1-SHA256 full-domain hash, same
//  domain-separation label, same blinding maths) so a token blinded here and
//  signed there verifies on both sides. See BlindTokenService for the flow and
//  RelayService for where a token is spent.
//
//  The blinding factor r is fresh per token and never leaves the device; it is
//  what makes issuance and spending unlinkable. The relay signs a value it cannot
//  read and later sees a token it cannot correlate to any issuance.
//

import Foundation
import CryptoKit

/// An RSA issuer public key (modulus + exponent), fetched from GET /pubkey.
struct BlindIssuerKey {
    let n: BigUInt
    let e: BigUInt
    let byteLen: Int   // modulus width in bytes

    /// Minimum issuer modulus: 2048-bit. Refuse a smaller (forgeable) key even if
    /// the relay serves one — mirrors the Worker's loadPublicKey guard.
    private static let minModulusBytes = 256

    init?(nB64u: String, eB64u: String) {
        guard let nb = Base64URL.decode(nB64u), let eb = Base64URL.decode(eB64u),
              nb.count >= Self.minModulusBytes, !eb.isEmpty else { return nil }
        let ee = BigUInt(bytes: [UInt8](eb))
        // Public exponent must be odd and >= 3 (e = 1 gives no security).
        guard ee.compare(BigUInt(3)) >= 0, !ee.mod(BigUInt(2)).isZero else { return nil }
        n = BigUInt(bytes: [UInt8](nb))
        e = ee
        byteLen = nb.count
    }
}

/// One unblinded, spendable token: a random nonce plus the issuer's RSA-FDH
/// signature over it. Presented at /send; the relay verifies s^e == FDH(nonce).
struct BlindToken: Codable, Equatable {
    let t: String      // nonce, base64url (32 random bytes)
    let sig: String    // unblinded signature, base64url (modulus width)
}

enum BlindTokenCrypto {
    private static let label = Array("PrivaMesh-blind-token-v1".utf8)

    /// MGF1-SHA256 expansion of `seed` to `len` bytes (PKCS#1 mask generation).
    private static func mgf1(_ seed: [UInt8], _ len: Int) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(len)
        var counter: UInt32 = 0
        while out.count < len {
            var block = seed
            block.append(UInt8((counter >> 24) & 0xff))
            block.append(UInt8((counter >> 16) & 0xff))
            block.append(UInt8((counter >> 8) & 0xff))
            block.append(UInt8(counter & 0xff))
            let digest = SHA256.hash(data: Data(block))
            out.append(contentsOf: digest)
            counter += 1
        }
        return Array(out.prefix(len))
    }

    /// Full-domain hash of a token nonce into Z_n (label-separated), as an integer.
    static func fdh(nonce: [UInt8], key: BlindIssuerKey) -> BigUInt {
        let seed = label + nonce
        let wide = mgf1(seed, key.byteLen)
        return BigUInt(bytes: wide).mod(key.n)
    }

    /// Blind a fresh nonce for signing. Returns the nonce, the blinded value to
    /// POST to /issue, and the secret blinding factor needed to unblind later.
    /// `randomBytes` is injectable for deterministic tests; production passes nil.
    static func blind(key: BlindIssuerKey,
                      nonce: [UInt8]? = nil,
                      r: BigUInt? = nil) -> (nonce: [UInt8], blindedB64u: String, r: BigUInt) {
        let theNonce = nonce ?? randomBytes(32)
        let m = fdh(nonce: theNonce, key: key)
        // Random r in [2, n), coprime to n (overwhelmingly likely for RSA n).
        var rr = r ?? BigUInt(bytes: randomBytes(key.byteLen)).mod(key.n)
        if rr.compare(BigUInt(2)) < 0 { rr = BigUInt(2) }
        // blinded = m * r^e mod n
        let blinded = m.mulMod(rr.powMod(key.e, key.n), key.n)
        let b64u = Base64URL.encode(Data(blinded.toBytes(count: key.byteLen)))
        return (theNonce, b64u, rr)
    }

    /// Unblind the relay's blind signature into a spendable token: s = s' * r^-1.
    /// Returns nil if r is not invertible (should never happen for RSA n).
    static func unblind(blindSigB64u: String, nonce: [UInt8], r: BigUInt,
                        key: BlindIssuerKey) -> BlindToken? {
        guard let sigData = Base64URL.decode(blindSigB64u) else { return nil }
        let blindSig = BigUInt(bytes: [UInt8](sigData))
        guard let rInv = r.inverseMod(key.n) else { return nil }
        let s = blindSig.mulMod(rInv, key.n)
        let token = BlindToken(t: Base64URL.encode(Data(nonce)),
                               sig: Base64URL.encode(Data(s.toBytes(count: key.byteLen))))
        // Self-check before we ever rely on it: s^e mod n must equal FDH(nonce).
        return verify(token, key: key) ? token : nil
    }

    /// Local verification, identical to the relay's /send check: s^e == FDH(t).
    static func verify(_ token: BlindToken, key: BlindIssuerKey) -> Bool {
        guard let sigData = Base64URL.decode(token.sig),
              let nonceData = Base64URL.decode(token.t) else { return false }
        let s = BigUInt(bytes: [UInt8](sigData))
        if s.compare(key.n) >= 0 || s.isZero { return false }
        let recovered = s.powMod(key.e, key.n)
        let expected = fdh(nonce: [UInt8](nonceData), key: key)
        return recovered == expected
    }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b
    }
}

/// base64url without padding, matching the relay's encoding on the wire.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        var s = data.base64EncodedString()
        s = s.replacingOccurrences(of: "+", with: "-")
             .replacingOccurrences(of: "/", with: "_")
        while s.hasSuffix("=") { s.removeLast() }
        return s
    }

    static func decode(_ s: String) -> Data? {
        var b64 = s.replacingOccurrences(of: "-", with: "+")
                   .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - (b64.count % 4)) % 4
        b64 += String(repeating: "=", count: pad)
        return Data(base64Encoded: b64)
    }
}
