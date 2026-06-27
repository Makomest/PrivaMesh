//
//  StealthAddress.swift
//  privamesh
//
//  Per-conversation one-time rendezvous addresses (recipient unlinkability).
//
//  After X3DH both peers share the initial secret SK. From it we derive a
//  stable `stealthRoot = HKDF(SK, "privamesh-stealth-v1")`. Both peers can then
//  deterministically derive a *sequence* of one-time Solana addresses for each
//  direction:
//
//      address(root, label, n) = ed25519_pubkey( HKDF(root, salt=label, info=n) )
//
//  The initiator sends message #n on the "i2r" chain; the responder polls the
//  same chain. Outsiders see messages landing on unrelated random addresses —
//  the recipient's real wallet never appears, and consecutive messages are not
//  linkable to each other or to the recipient.
//
//  NOTE (phase 1): this file provides the derivation primitive + shared root.
//  Delivery + polling windows are wired in later phases.
//

import Foundation
import CryptoKit
import SolanaSwift

enum StealthAddress {
    /// Direction labels for the two per-conversation chains.
    static let initiatorToResponder = "i2r"   // messages from the session initiator
    static let responderToInitiator = "r2i"   // messages from the responder

    static let rootInfo = Data("privamesh-stealth-v1".utf8)

    /// Derive the stable stealth root shared by both peers from the X3DH secret.
    static func root(fromSharedSecret sk: Data) -> Data {
        CryptoBox.hkdf(
            inputKeyMaterial: sk,
            salt: Data(count: 32),
            info: rootInfo,
            outputByteCount: 32
        )
    }

    /// The one-time Solana address (base58) for `label` chain at `index`.
    static func address(root: Data, label: String, index: Int) -> String? {
        let seed = CryptoBox.hkdf(
            inputKeyMaterial: root,
            salt: Data(label.utf8),
            info: indexInfo(index),
            outputByteCount: 32
        )
        guard let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { return nil }
        // ed25519 public key (32 bytes) == a valid Solana address.
        return (try? PublicKey(data: signing.publicKey.rawRepresentation))?.base58EncodedString
    }

    private static func indexInfo(_ index: Int) -> Data {
        let v = UInt32(truncatingIfNeeded: index).bigEndian
        return withUnsafeBytes(of: v) { Data($0) }
    }
}
