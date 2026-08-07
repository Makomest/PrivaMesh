//
//  PQXDH.swift
//  privamesh
//
//  Post-quantum augmentation of the X3DH handshake (Signal's PQXDH design). A
//  classical X25519 X3DH is fine against today's adversary, but a "harvest now,
//  decrypt later" attacker who records traffic and breaks ECDH with a future
//  quantum computer recovers the session. Mixing a post-quantum KEM secret into
//  the root key blocks that: the attacker must ALSO break ML-KEM.
//
//  Uses CryptoKit's XWingMLKEM768X25519 — a hybrid KEM (X25519 + ML-KEM-768) that
//  is IND-CCA2 secure as long as EITHER component holds, so switching to it never
//  weakens the classical guarantee. No third-party dependency.
//
//  TRANSPORT NOTE: the X-Wing ciphertext is ~1120 bytes and the encapsulation key
//  ~1216 bytes — both larger than a single Solana memo tx (1232-byte cap) can
//  carry once signatures/accounts/blockhash are counted. So on the wire the PQ
//  prekey ships via QR and the session-init ciphertext ships off-chain (Irys, the
//  same channel photos use) with a pointer in the memo. This file is only the
//  crypto core; the wire delivery is wired separately. When a contact has no PQ
//  prekey (QR not exchanged, or an older build), the handshake falls back to the
//  classical X3DH secret unchanged.
//

import Foundation
import CryptoKit

enum PQXDH {
    /// Master switch for the post-quantum handshake. OFF for now: the PQ path is
    /// wired end-to-end but not yet two-device integration-tested, so this release
    /// stays classical-only (identical to pre-PQXDH). Flipping this to true — after
    /// device testing — turns it on with NO migration: the PQ prekey seed is already
    /// derived deterministically from the phrase, so bundles just start carrying the
    /// PQ key. While false, the published bundle is byte-identical to the old format
    /// (so wallet signatures and older builds stay compatible) and every send is
    /// classical.
    static let enabled = false

    /// One party's post-quantum prekey. The private half stays on device; the
    /// public half (`encapsulationKey`) is published in the prekey bundle.
    struct Keypair {
        let privateKey: XWingMLKEM768X25519.PrivateKey
        var publicKey: XWingMLKEM768X25519.PublicKey { privateKey.publicKey }
        /// Wire form of the public key (goes in the bundle).
        var encapsulationKey: Data { privateKey.publicKey.rawRepresentation }
        /// Deterministic seed form of the private key, for Keychain storage.
        var seed: Data { privateKey.seedRepresentation }
    }

    /// Fresh PQ prekey.
    static func generate() throws -> Keypair {
        Keypair(privateKey: try XWingMLKEM768X25519.PrivateKey.generate())
    }

    /// Restore a PQ prekey from its stored seed.
    static func keypair(fromSeed seed: Data) throws -> Keypair {
        Keypair(privateKey: try XWingMLKEM768X25519.PrivateKey(seedRepresentation: seed, publicKey: nil))
    }

    /// INITIATOR: encapsulate to the responder's published PQ prekey. Returns the
    /// ciphertext (to send off-chain) and the PQ shared secret (to mix in).
    static func encapsulate(toEncapsulationKey keyData: Data) throws -> (ciphertext: Data, sharedSecret: Data) {
        let pub = try XWingMLKEM768X25519.PublicKey(rawRepresentation: keyData)
        let result = try pub.encapsulate()
        return (result.encapsulated, dataOf(result.sharedSecret))
    }

    /// RESPONDER: decapsulate the initiator's ciphertext with the local PQ prekey,
    /// recovering the same PQ shared secret.
    static func decapsulate(ciphertext: Data, keypair: Keypair) throws -> Data {
        dataOf(try keypair.privateKey.decapsulate(ciphertext))
    }

    /// Bind the classical X3DH secret and the PQ shared secret into ONE root
    /// secret. Order-fixed and domain-separated so both parties derive the same
    /// value. If `pqSharedSecret` is nil (no PQ prekey / fallback), returns the
    /// classical secret unchanged — identical to the pre-PQ behaviour.
    static func combine(classicalSecret: Data, pqSharedSecret: Data?) -> Data {
        guard let pq = pqSharedSecret else { return classicalSecret }
        return CryptoBox.hkdf(
            inputKeyMaterial: classicalSecret + pq,
            salt: Data("PrivaMesh-PQXDH-v1".utf8),
            info: Data("root".utf8),
            outputByteCount: 32)
    }

    private static func dataOf(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}
