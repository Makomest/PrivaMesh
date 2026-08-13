//
//  PQXDHTests.swift
//  privameshTests
//
//  The post-quantum handshake was held back because it had never been exercised
//  end to end. These tests do that in-process: both sides of a real X-Wing
//  encapsulation, the root-secret binding, and the fallback path that a pre-iOS 26
//  device (or a contact who published no PQ prekey) takes.
//
//  CryptoKit ships X-Wing only from iOS 26, so the PQ tests are gated the same way
//  the product code is. `combine` and the fallback are testable everywhere.
//

import Testing
import Foundation
import CryptoKit
@testable import privamesh

@Suite("PQXDH")
struct PQXDHTests {

    // MARK: - Fallback (works on every supported system)

    /// No PQ secret means the root is the classical X3DH secret, byte for byte.
    /// This is what keeps PQ-capable and classical devices interoperable.
    @Test func combineWithoutPQ_returnsClassicalSecretUnchanged() {
        let classical = Data((0..<32).map { UInt8($0) })
        #expect(PQXDH.combine(classicalSecret: classical, pqSharedSecret: nil) == classical)
    }

    /// Mixing a PQ secret must actually change the root, and stay deterministic so
    /// both sides land on the same value.
    @Test func combineWithPQ_isDeterministicAndDiffers() {
        let classical = Data(repeating: 0xAB, count: 32)
        let pq        = Data(repeating: 0xCD, count: 32)

        let a = PQXDH.combine(classicalSecret: classical, pqSharedSecret: pq)
        let b = PQXDH.combine(classicalSecret: classical, pqSharedSecret: pq)

        #expect(a == b, "both parties must derive the same root")
        #expect(a != classical, "PQ secret has to affect the root")
        #expect(a.count == 32)
    }

    /// A different PQ secret must produce a different root — otherwise the KEM
    /// contributes nothing.
    @Test func combine_differentPQSecrets_giveDifferentRoots() {
        let classical = Data(repeating: 0x11, count: 32)
        let one = PQXDH.combine(classicalSecret: classical, pqSharedSecret: Data(repeating: 0x01, count: 32))
        let two = PQXDH.combine(classicalSecret: classical, pqSharedSecret: Data(repeating: 0x02, count: 32))
        #expect(one != two)
    }

    // MARK: - Real X-Wing handshake (iOS 26+)

    /// The actual two-party exchange: the responder publishes a prekey, the
    /// initiator encapsulates to it, and both recover the same secret.
    @available(iOS 26.0, *)
    @Test func encapsulateDecapsulate_bothSidesAgree() throws {
        let responder = try PQXDH.generate()

        let sent = try PQXDH.encapsulate(toEncapsulationKey: responder.encapsulationKey)
        let recovered = try PQXDH.decapsulate(ciphertext: sent.ciphertext, keypair: responder)

        #expect(sent.sharedSecret == recovered, "initiator and responder must agree")
        #expect(!sent.sharedSecret.isEmpty)
    }

    /// End to end: both parties bind the same classical secret with the KEM output
    /// and must arrive at an identical root key.
    @available(iOS 26.0, *)
    @Test func fullHandshake_producesIdenticalRootOnBothSides() throws {
        let classical = Data(repeating: 0x5A, count: 32)   // stands in for the X3DH secret
        let responder = try PQXDH.generate()

        let sent = try PQXDH.encapsulate(toEncapsulationKey: responder.encapsulationKey)
        let responderSecret = try PQXDH.decapsulate(ciphertext: sent.ciphertext, keypair: responder)

        let initiatorRoot = PQXDH.combine(classicalSecret: classical, pqSharedSecret: sent.sharedSecret)
        let responderRoot = PQXDH.combine(classicalSecret: classical, pqSharedSecret: responderSecret)

        #expect(initiatorRoot == responderRoot)
        #expect(initiatorRoot != classical, "the PQ secret must be mixed in")
    }

    /// Someone else's prekey must not recover the secret — the KEM is doing real work.
    @available(iOS 26.0, *)
    @Test func decapsulateWithWrongKey_doesNotRecoverSecret() throws {
        let responder = try PQXDH.generate()
        let stranger  = try PQXDH.generate()

        let sent = try PQXDH.encapsulate(toEncapsulationKey: responder.encapsulationKey)
        let wrong = try? PQXDH.decapsulate(ciphertext: sent.ciphertext, keypair: stranger)

        #expect(wrong != sent.sharedSecret, "a foreign key must never yield the session secret")
    }

    /// The prekey must survive Keychain storage: identity is restored from a seed,
    /// so a reinstalled device has to rebuild the exact same PQ keypair.
    @available(iOS 26.0, *)
    @Test func keypairFromSeed_restoresTheSamePrekey() throws {
        let original = try PQXDH.generate()
        let restored = try PQXDH.keypair(fromSeed: original.seed)

        #expect(restored.encapsulationKey == original.encapsulationKey)

        // And it still decapsulates traffic sent to the original public key.
        let sent = try PQXDH.encapsulate(toEncapsulationKey: original.encapsulationKey)
        #expect(try PQXDH.decapsulate(ciphertext: sent.ciphertext, keypair: restored) == sent.sharedSecret)
    }

    /// The messaging identity derives its PQ prekey deterministically from the
    /// recovery phrase, so re-entering the phrase on another device must reproduce
    /// the published prekey exactly.
    @available(iOS 26.0, *)
    @Test func identityFromSamePhrase_derivesTheSamePQPrekey() throws {
        let phrase = ["drum", "need", "person", "expire", "large", "wrist",
                      "struggle", "labor", "label", "ill", "improve", "cloud"]

        let first  = try CryptoIdentity.derive(fromSeedPhrase: phrase)
        let second = try CryptoIdentity.derive(fromSeedPhrase: phrase)

        #expect(first.pqPrekeySeed == second.pqPrekeySeed)
        #expect(first.pqKeypair()?.encapsulationKey == second.pqKeypair()?.encapsulationKey)
        #expect(first.pqKeypair() != nil, "a derived identity must carry a PQ prekey on iOS 26")
    }

    /// A PQ-capable device must advertise its prekey in the published bundle,
    /// otherwise senders never upgrade the handshake.
    @available(iOS 26.0, *)
    @Test func publishedBundle_carriesThePQPrekey() throws {
        let identity = try CryptoIdentity.generate()
        let bundle = try identity.prekeyBundle()

        #expect(bundle.pqPrekeyPublic != nil)
        #expect(bundle.pqPrekeyPublic == identity.pqKeypair()?.encapsulationKey)
        try bundle.verify()   // signatures must still check out with the PQ key present
    }
}
