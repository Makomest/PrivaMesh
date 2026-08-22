//
//  CertificatePinning.swift
//  privamesh
//
//  Pins the relay's TLS chain, so a mis-issued certificate from any of the ~150
//  CAs iOS trusts is not enough to sit between the app and the relay.
//
//  Message CONTENT does not need this: it is end-to-end encrypted before it goes
//  anywhere. What an attacker in the middle would get is metadata (which account
//  sends when) and the ability to tamper with quota and token responses. That is
//  worth closing.
//
//  Three deliberate choices, because naive pinning bricks apps:
//
//  1. We pin the ISSUER chain, never the leaf. Cloudflare rotates leaf certs on
//     its own schedule; pinning one guarantees an outage.
//  2. Several pins, including a root the host does not use today, so a CA change
//     does not take the app down with it.
//  3. The pin set EXPIRES. After `enforceUntil` the app falls back to normal
//     system validation. A build that stops being updated must degrade to "as
//     safe as everyone else", not to "cannot connect at all" — Apple recommends
//     the same for ATS pinning.
//
//  Only the relay is pinned. Solana RPC endpoints are user-configurable and Irys
//  is a third party; pinning those would break the moment either changes host.
//

import Foundation
import CryptoKit

enum CertificatePinning {
    /// SHA-256 of the SubjectPublicKeyInfo, base64 — the standard HPKP form.
    ///
    /// Taken from the live chain of privamesh-relay.privamesh.workers.dev
    /// (Google Trust Services WE1 → GTS Root R4) plus ISRG Root X1 as a spare in
    /// case the host moves to Let's Encrypt. Regenerate with:
    ///
    ///   openssl s_client -connect <host>:443 -servername <host> -showcerts </dev/null \
    ///     | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der \
    ///     | openssl dgst -sha256 -binary | base64
    static let pins: Set<String> = [
        "kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=",   // GTS WE1 (intermediate)
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=",   // GTS Root R4
        "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=",   // ISRG Root X1 (spare)
    ]

    /// Hosts we pin. Everything else validates normally.
    static let pinnedHosts: Set<String> = ["privamesh-relay.privamesh.workers.dev"]

    /// After this date the pins stop being enforced. Push it forward with each
    /// release; an abandoned build then keeps working on system trust alone.
    static let enforceUntil = Date(timeIntervalSince1970: 1_811_000_000)   // ~mid-2027

    static func shouldPin(host: String) -> Bool {
        pinnedHosts.contains(host.lowercased()) && Date() < enforceUntil
    }

    /// Whether this chain carries one of our pins. Evaluated over the whole chain,
    /// which is what makes leaf rotation a non-event.
    static func chainMatchesPin(_ trust: SecTrust) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return false }
        for cert in chain {
            guard let key = SecCertificateCopyKey(cert),
                  let data = SecKeyCopyExternalRepresentation(key, nil) as Data?,
                  let attrs = SecKeyCopyAttributes(key) as? [CFString: Any] else { continue }
            let spki = subjectPublicKeyInfo(rawKey: data, attributes: attrs)
            let digest = Data(SHA256.hash(data: spki)).base64EncodedString()
            if pins.contains(digest) { return true }
        }
        return false
    }

    /// SecKey gives the bare key; a pin is over the DER SubjectPublicKeyInfo, so
    /// the algorithm header has to be prepended before hashing.
    private static func subjectPublicKeyInfo(rawKey: Data, attributes: [CFString: Any]) -> Data {
        let type = attributes[kSecAttrKeyType] as? String
        let size = attributes[kSecAttrKeySizeInBits] as? Int ?? 0

        if type == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            switch size {
            case 256: return Data(ecP256Header) + rawKey
            case 384: return Data(ecP384Header) + rawKey
            default: return rawKey
            }
        }
        switch size {
        case 2048: return Data(rsa2048Header) + rawKey
        case 4096: return Data(rsa4096Header) + rawKey
        default:   return rawKey
        }
    }

    // DER prefixes for the key types a public CA actually issues.
    private static let rsa2048Header: [UInt8] = [
        0x30,0x82,0x01,0x22,0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,
        0x01,0x05,0x00,0x03,0x82,0x01,0x0f,0x00]
    private static let rsa4096Header: [UInt8] = [
        0x30,0x82,0x02,0x22,0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,
        0x01,0x05,0x00,0x03,0x82,0x02,0x0f,0x00]
    private static let ecP256Header: [UInt8] = [
        0x30,0x59,0x30,0x13,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,0x06,0x08,0x2a,
        0x86,0x48,0xce,0x3d,0x03,0x01,0x07,0x03,0x42,0x00]
    private static let ecP384Header: [UInt8] = [
        0x30,0x76,0x30,0x10,0x06,0x07,0x2a,0x86,0x48,0xce,0x3d,0x02,0x01,0x06,0x05,0x2b,
        0x81,0x04,0x00,0x22,0x03,0x62,0x00]
}

/// URLSession delegate that enforces the pins above.
final class PinningSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        guard CertificatePinning.shouldPin(host: host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // System validation FIRST: pinning replaces trusting every CA, not the
        // expiry, hostname and revocation checks.
        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        if CertificatePinning.chainMatchesPin(trust) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
