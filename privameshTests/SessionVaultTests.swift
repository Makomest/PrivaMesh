//
//  SessionVaultTests.swift
//  privameshTests
//
//  The ratchet state is the conversation. These cover that it is sealed on the
//  way into the database, that it comes back out intact, and that stores written
//  before this existed keep working — a migration that drops sessions would break
//  every open chat.
//

import Testing
import Foundation
@testable import privamesh

@Suite("Session vault", .serialized)
struct SessionVaultTests {

    private let sample = Data(#"{"rootKey":"abc","sendCount":3}"#.utf8)

    @Test func sealedPayloadIsNotThePlaintext() {
        let sealed = SessionVault.seal(sample)
        #expect(sealed != sample)
        #expect(SessionVault.isSealed(sealed))
        // The JSON must not survive anywhere in the blob.
        #expect(sealed.range(of: Data("rootKey".utf8)) == nil)
    }

    @Test func sealThenOpenRoundTrips() {
        let opened = SessionVault.open(SessionVault.seal(sample))
        #expect(opened == sample)
    }

    /// Rows written before encryption existed are bare JSON and must still open,
    /// otherwise upgrading the app would silently break every conversation.
    @Test func legacyPlainJSONStillOpens() {
        #expect(SessionVault.isSealed(sample) == false)
        #expect(SessionVault.open(sample) == sample)
    }

    /// Two seals of the same state must differ: AES-GCM uses a fresh nonce, and
    /// identical ciphertexts would leak that a session did not advance.
    @Test func sealingIsNonDeterministic() {
        #expect(SessionVault.seal(sample) != SessionVault.seal(sample))
    }

    /// A tampered blob must fail closed rather than return garbage that would be
    /// decoded as a ratchet.
    @Test func tamperedPayloadDoesNotOpen() {
        var sealed = SessionVault.seal(sample)
        #expect(sealed.count > 20)
        sealed[sealed.count - 1] ^= 0xFF          // flip a bit in the tag
        #expect(SessionVault.open(sealed) == nil)
    }

    @Test func emptyInputIsHandled() {
        #expect(SessionVault.open(Data()) == nil)
    }

    // MARK: - Through a Contact

    @MainActor
    @Test func contactStoresRatchetSealed() throws {
        let (alice, _) = try makeRatchetPair()
        let contact = Contact(id: "addr", displayName: "Emma", prekeyBundleBase64: "")

        contact.setRatchet(alice)

        let stored = try #require(contact.sessionData)
        #expect(SessionVault.isSealed(stored), "a session row must never be written in the clear")
        #expect(contact.ratchet != nil, "and it must read back")
    }

    @MainActor
    @Test func clearingRatchetEmptiesTheRow() throws {
        let (alice, _) = try makeRatchetPair()
        let contact = Contact(id: "addr", displayName: "Emma", prekeyBundleBase64: "")
        contact.setRatchet(alice)
        contact.setRatchet(nil)
        #expect(contact.sessionData == nil)
        #expect(contact.ratchet == nil)
    }

    /// A restored session must still decrypt what the other side sends, which is
    /// the only thing that actually proves the round trip preserved the state.
    @MainActor
    @Test func restoredRatchetStillDecrypts() throws {
        let (alice, bob) = try makeRatchetPair()
        let contact = Contact(id: "addr", displayName: "Emma", prekeyBundleBase64: "")
        contact.setRatchet(bob)

        var sender = alice
        let message = try sender.encrypt(plaintext: Data("hello".utf8))

        var restored = try #require(contact.ratchet)
        let plain = try restored.decrypt(message: message)
        #expect(plain == Data("hello".utf8))
    }

    /// Same session pair the crypto tests use.
    private func makeRatchetPair() throws -> (DoubleRatchet, DoubleRatchet) {
        let shared = Data(repeating: 0x42, count: 32)
        let bobSPK = Curve25519.KeyAgreement.PrivateKey()
        let alice = try DoubleRatchet.initSender(sharedSecret: shared,
                                                 remoteSPKPublic: bobSPK.publicKey.rawRepresentation)
        let bob = DoubleRatchet.initReceiver(sharedSecret: shared, localSPK: bobSPK)
        return (alice, bob)
    }
}

import CryptoKit
