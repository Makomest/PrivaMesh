//
//  SafetyNumber.swift
//  privamesh
//
//  Out-of-band verification that you are talking to the person you think you are.
//
//  The wallet signature on a prekey bundle proves the registry did not swap a key
//  underneath you. It cannot prove that the nickname you typed belongs to your
//  friend rather than to someone who picked a similar one. Only the two humans can
//  settle that, by comparing a number that both devices derive independently from
//  the keys actually in use.
//
//  Construction follows Signal's fingerprint design: each side is hashed into a
//  30-byte fingerprint, the two are sorted and concatenated, and the result is
//  read out as 60 decimal digits. Sorting is what makes both phones display the
//  same string without agreeing who is "first".
//
//  The iteration count is deliberate. A single hash would let an attacker who is
//  generating identities grind for one whose fingerprint shares a prefix with the
//  real one, betting that people compare the first few groups and stop. 5200
//  iterations makes that search expensive while staying instant on a phone.
//

import Foundation
import CryptoKit

enum SafetyNumber {
    /// Hash rounds per fingerprint. Same value Signal uses.
    private static let iterations = 5200
    /// Bytes kept from the digest, five per displayed group.
    private static let fingerprintBytes = 30
    /// Version byte, so a future change to this construction cannot be confused
    /// with the current one.
    private static let version: UInt8 = 1

    // MARK: - Public

    /// The 60-digit number both sides must see. Returns nil if either bundle is
    /// unreadable, which is the only honest answer: showing a number derived from
    /// a partial key would be worse than showing none.
    static func digits(myBundleBase64: String, myAddress: String,
                       theirBundleBase64: String, theirAddress: String) -> String? {
        guard let mine = try? PrekeyBundle.fromBase64(myBundleBase64),
              let theirs = try? PrekeyBundle.fromBase64(theirBundleBase64) else { return nil }
        return digits(myBundle: mine, myAddress: myAddress,
                      theirBundle: theirs, theirAddress: theirAddress)
    }

    /// The common case in the UI: our own bundle is in hand, theirs is the stored
    /// base64 blob from the contact.
    static func digits(myBundle: PrekeyBundle, myAddress: String,
                       theirBundleBase64: String, theirAddress: String) -> String? {
        guard let theirs = try? PrekeyBundle.fromBase64(theirBundleBase64) else { return nil }
        return digits(myBundle: myBundle, myAddress: myAddress,
                      theirBundle: theirs, theirAddress: theirAddress)
    }

    static func digits(myBundle: PrekeyBundle, myAddress: String,
                       theirBundle: PrekeyBundle, theirAddress: String) -> String? {
        guard let a = fingerprint(bundle: myBundle, address: myAddress),
              let b = fingerprint(bundle: theirBundle, address: theirAddress) else { return nil }
        // Sorted so both devices concatenate in the same order.
        let (first, second) = a.lexicographicallyPrecedes(b) ? (a, b) : (b, a)
        return encode(first) + encode(second)
    }

    /// "12345 67890 …" — grouped for reading aloud without losing your place.
    static func formatted(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 5).map { i in
            let start = digits.index(digits.startIndex, offsetBy: i)
            let end = digits.index(start, offsetBy: min(5, digits.count - i))
            return String(digits[start..<end])
        }.joined(separator: " ")
    }

    /// Payload for the QR that lets two phones compare without reading numbers out.
    static func qrPayload(_ digits: String) -> String { "privamesh-sn:\(digits)" }

    /// Digits back out of a scanned QR, or nil if it is not one of ours.
    static func digits(fromQR payload: String) -> String? {
        let prefix = "privamesh-sn:"
        guard payload.hasPrefix(prefix) else { return nil }
        let value = String(payload.dropFirst(prefix.count))
        guard value.count == 60, value.allSatisfy(\.isNumber) else { return nil }
        return value
    }

    // MARK: - Internals

    /// One side's 30 bytes: version, both long-lived public keys, and the Solana
    /// address. Every one of those is something an impersonator would have to
    /// match, so all of them go in.
    private static func fingerprint(bundle: PrekeyBundle, address: String) -> [UInt8]? {
        guard !address.isEmpty else { return nil }
        var input = Data([version])
        input += bundle.signingIdentityKey
        input += bundle.dhIdentityKey
        input += Data(address.utf8)

        var digest = Data(SHA512.hash(data: input))
        for _ in 1..<iterations {
            // Fold the identity back in each round: the chain then depends on the
            // key at every step, not just on the first digest.
            digest = Data(SHA512.hash(data: digest + input))
        }
        return Array(digest.prefix(fingerprintBytes))
    }

    /// Five bytes to five decimal digits, repeated: 30 bytes to 30 digits.
    private static func encode(_ bytes: [UInt8]) -> String {
        stride(from: 0, to: bytes.count, by: 5).map { i in
            let chunk = bytes[i..<min(i + 5, bytes.count)]
            let value = chunk.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return String(format: "%05llu", value % 100_000)
        }.joined()
    }
}
