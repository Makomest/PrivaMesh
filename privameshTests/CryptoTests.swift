//
//  CryptoTests.swift
//  privameshTests
//
//  Unit tests for the Double Ratchet crypto layer.
//  All tests use the Swift Testing framework (#expect).
//

import Testing
import Foundation
import CryptoKit
@testable import privamesh

@Suite("MessagePadding")
struct MessagePaddingTests {

    @Test func roundTrip_shortMessage() throws {
        let plain = Data("hello".utf8)
        let padded = MessagePadding.pad(plain)
        #expect(padded.count == 32)
        let unpadded = try MessagePadding.unpad(padded)
        #expect(unpadded == plain)
    }

    @Test func roundTrip_exactBucketBoundary() throws {
        // 31 bytes → needs 32-byte bucket (31 + 1 marker = 32)
        let plain = Data(repeating: 0xAB, count: 31)
        let padded = MessagePadding.pad(plain)
        #expect(padded.count == 32)
        let unpadded = try MessagePadding.unpad(padded)
        #expect(unpadded == plain)
    }

    @Test func roundTrip_largeBucket() throws {
        let plain = Data(repeating: 0x42, count: 300)
        let padded = MessagePadding.pad(plain)
        #expect(padded.count == 512)
        let unpadded = try MessagePadding.unpad(padded)
        #expect(unpadded == plain)
    }

    @Test func corruptPadding_throws() {
        var bad = Data(repeating: 0x00, count: 32)
        bad[0] = 0xFF  // no 0x80 marker anywhere
        #expect(throws: CryptoError.invalidPadding) {
            try MessagePadding.unpad(bad)
        }
    }
}

@Suite("CryptoBox primitives")
struct CryptoBoxTests {

    @Test func ecdhSymmetry() throws {
        let aliceKey = Curve25519.KeyAgreement.PrivateKey()
        let bobKey   = Curve25519.KeyAgreement.PrivateKey()
        let ab = try CryptoBox.dh(privateKey: aliceKey, publicKey: bobKey.publicKey)
        let ba = try CryptoBox.dh(privateKey: bobKey,   publicKey: aliceKey.publicKey)
        #expect(ab == ba)
        #expect(ab.count == 32)
    }

    @Test func aesGcmRoundTrip() throws {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let plain = Data("PrivaMesh secret message 🔐".utf8)
        let aad   = Data("header".utf8)
        let ct = try CryptoBox.encrypt(plaintext: plain, key: key, associatedData: aad)
        let recovered = try CryptoBox.decrypt(combined: ct, key: key, associatedData: aad)
        #expect(recovered == plain)
    }

    @Test func aesGcmTamperedAad_throws() throws {
        let key   = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let plain = Data("test".utf8)
        let ct    = try CryptoBox.encrypt(plaintext: plain, key: key, associatedData: Data("aad".utf8))
        #expect(throws: CryptoError.decryptionFailed) {
            try CryptoBox.decrypt(combined: ct, key: key, associatedData: Data("tampered".utf8))
        }
    }

    @Test func hkdfDeterministic() {
        let ikm  = Data(repeating: 0x01, count: 32)
        let salt = Data(repeating: 0x02, count: 32)
        let info = Data("test".utf8)
        let r1 = CryptoBox.hkdf(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: 64)
        let r2 = CryptoBox.hkdf(inputKeyMaterial: ikm, salt: salt, info: info, outputByteCount: 64)
        #expect(r1 == r2)
        #expect(r1.count == 64)
    }
}

@Suite("X3DH shared secret")
struct X3DHTests {

    @Test func aliceAndBobDeriveIdenticalSecret() throws {
        let aliceIdentity   = CryptoIdentity.generate_unsafe() // generate without throws for tests
        let bobIdentity     = CryptoIdentity.generate_unsafe()
        let aliceEphemeral  = Curve25519.KeyAgreement.PrivateKey()

        let bobBundle = try bobIdentity.prekeyBundle()
        try bobBundle.verify()

        let skAlice = try X3DH.senderSharedSecret(
            myIdentityKey: try aliceIdentity.dhIdentityKey(),
            myEphemeralKey: aliceEphemeral,
            remoteBundle: bobBundle
        )

        let skBob = try X3DH.receiverSharedSecret(
            myIdentityKey: try bobIdentity.dhIdentityKey(),
            mySignedPrekey: try bobIdentity.signedPrekey(),
            senderIdentityKeyPublic: try aliceIdentity.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralKeyPublic: aliceEphemeral.publicKey.rawRepresentation
        )

        #expect(skAlice == skBob)
        #expect(skAlice.count == 32)
    }

    @Test func bundleSignatureVerification() throws {
        let identity = CryptoIdentity.generate_unsafe()
        let bundle   = try identity.prekeyBundle()
        try bundle.verify()  // should not throw
    }

    @Test func tamperedBundle_throws() throws {
        var identity = CryptoIdentity.generate_unsafe()
        let bundle = try identity.prekeyBundle()

        // Tamper with the SPK — signature will no longer match
        var tampered = bundle
        let badSPK = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        tampered = PrekeyBundle(
            dhIdentityKey: bundle.dhIdentityKey,
            signedPrekeyPublic: badSPK,
            signedPrekeySignature: bundle.signedPrekeySignature,
            oneTimePrekeyPublic: nil,
            signingIdentityKey: bundle.signingIdentityKey
        )
        #expect(throws: CryptoError.invalidSignature) {
            try tampered.verify()
        }
    }
}

@Suite("Double Ratchet")
struct DoubleRatchetTests {

    /// Set up a fully initialized Alice/Bob ratchet pair.
    private func makePair() throws -> (alice: DoubleRatchet, bob: DoubleRatchet) {
        let aliceIdentity  = CryptoIdentity.generate_unsafe()
        let bobIdentity    = CryptoIdentity.generate_unsafe()
        let aliceEphemeral = Curve25519.KeyAgreement.PrivateKey()
        let bobBundle      = try bobIdentity.prekeyBundle()

        let sk = try X3DH.senderSharedSecret(
            myIdentityKey: try aliceIdentity.dhIdentityKey(),
            myEphemeralKey: aliceEphemeral,
            remoteBundle: bobBundle
        )

        let alice = try DoubleRatchet.initSender(
            sharedSecret: sk,
            remoteSPKPublic: bobBundle.signedPrekeyPublic
        )
        let bob = DoubleRatchet.initReceiver(
            sharedSecret: sk,
            localSPK: try bobIdentity.signedPrekey()
        )
        return (alice, bob)
    }

    @Test func aliceSendsBobReceives() throws {
        var (alice, bob) = try makePair()
        let plain = MessagePadding.pad(Data("Hello Bob!".utf8))
        let msg = try alice.encrypt(plaintext: plain)
        let recovered = try bob.decrypt(message: msg)
        #expect(try MessagePadding.unpad(recovered) == Data("Hello Bob!".utf8))
    }

    @Test func bidirectionalExchange() throws {
        var (alice, bob) = try makePair()

        let m1 = try alice.encrypt(plaintext: MessagePadding.pad(Data("Hi Bob".utf8)))
        let d1 = try bob.decrypt(message: m1)
        #expect(try MessagePadding.unpad(d1) == Data("Hi Bob".utf8))

        let m2 = try bob.encrypt(plaintext: MessagePadding.pad(Data("Hey Alice".utf8)))
        let d2 = try alice.decrypt(message: m2)
        #expect(try MessagePadding.unpad(d2) == Data("Hey Alice".utf8))

        let m3 = try alice.encrypt(plaintext: MessagePadding.pad(Data("How are you?".utf8)))
        let d3 = try bob.decrypt(message: m3)
        #expect(try MessagePadding.unpad(d3) == Data("How are you?".utf8))
    }

    @Test func multipleMessagesInSequence() throws {
        var (alice, bob) = try makePair()
        let texts = ["msg1", "msg2", "msg3", "msg4", "msg5"]
        var encrypted: [EncryptedMessage] = []
        for t in texts {
            encrypted.append(try alice.encrypt(plaintext: MessagePadding.pad(Data(t.utf8))))
        }
        for (i, msg) in encrypted.enumerated() {
            let plain = try bob.decrypt(message: msg)
            #expect(try MessagePadding.unpad(plain) == Data(texts[i].utf8))
        }
    }

    @Test func outOfOrderDelivery() throws {
        var (alice, bob) = try makePair()

        let m0 = try alice.encrypt(plaintext: MessagePadding.pad(Data("msg0".utf8)))
        let m1 = try alice.encrypt(plaintext: MessagePadding.pad(Data("msg1".utf8)))
        let m2 = try alice.encrypt(plaintext: MessagePadding.pad(Data("msg2".utf8)))

        // Receive in order 2, 0, 1
        let d2 = try bob.decrypt(message: m2)
        let d0 = try bob.decrypt(message: m0)
        let d1 = try bob.decrypt(message: m1)

        #expect(try MessagePadding.unpad(d0) == Data("msg0".utf8))
        #expect(try MessagePadding.unpad(d1) == Data("msg1".utf8))
        #expect(try MessagePadding.unpad(d2) == Data("msg2".utf8))
    }

    @Test func serialization() throws {
        var (alice, _) = try makePair()
        let msg = try alice.encrypt(plaintext: MessagePadding.pad(Data("test".utf8)))
        let bytes = msg.serialized
        let recovered = try EncryptedMessage.deserialize(bytes)
        #expect(recovered.dhPublicKey == msg.dhPublicKey)
        #expect(recovered.previousCount == msg.previousCount)
        #expect(recovered.messageNumber == msg.messageNumber)
        #expect(recovered.ciphertext == msg.ciphertext)
    }
}

// MARK: - Unsafe generate helper for tests (avoids try in closures)

extension CryptoIdentity {
    static func generate_unsafe() -> CryptoIdentity {
        (try? CryptoIdentity.generate())!
    }
}
