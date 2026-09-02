//
//  SessionInitReplayTests.swift
//  privameshTests

//  Reported externally on 25 August 2026.

//  A session-opening envelope is self-contained on purpose: it carries the
//  sender's identity and ephemeral keys, so the recipient can derive the same
//  X3DH secret again and read it without any stored state. That also means it
//  decrypts every time it is seen.

//  Replay detection was the Solana transaction signature. Copying the same memo
//  into a new transaction produces a new signature, so an old opener came back
//  looking like a fresh message from a saved contact - with the original
//  identity key, so no key-change warning fired - and the reconstructed ratchet
//  was installed over the live session.


import Testing
import Foundation
import CryptoKit
@testable import privamesh

@Suite("Session-init replay")
struct SessionInitReplayTests {

    /// One opener, exactly as a sender would build it.
    private func opener(text: String = "meet me at seven") throws -> MessageEnvelope {
        let recipient = CryptoIdentity.generate_unsafe()
        let sender = CryptoIdentity.generate_unsafe()

        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let bundle = try recipient.prekeyBundle()
        let sharedSecret = try X3DH.senderSharedSecret(
            myIdentityKey: try sender.dhIdentityKey(),
            myEphemeralKey: ephemeral,
            remoteBundle: bundle
        )
        var ratchet = try DoubleRatchet.initSender(
            sharedSecret: sharedSecret,
            remoteSPKPublic: bundle.signedPrekeyPublic
        )
        let padded = try MessagePadding.pad(try ChatPayload.text(text).encode())
        let message = try ratchet.encrypt(plaintext: padded)

        return MessageEnvelope(
            kind: .sessionInit,
            senderIdentityPublic: try sender.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralPublic: ephemeral.publicKey.rawRepresentation,
            message: message
        )
    }

    /// The digest is over what the envelope decrypts to, so a copy cannot dodge it.
    @Test func aCopiedOpenerHasTheSameDigest() throws {
        let envelope = try opener()

        // A replay is the same bytes in a different transaction: the wire form is
        // identical, only the carrier changes.
        let copied = try MessageEnvelope.deserialize(envelope.serialize())

        #expect(Contact.sessionInitDigest(copied) == Contact.sessionInitDigest(envelope))
    }

    @Test func twoDifferentOpenersHaveDifferentDigests() throws {
        let first = try opener(text: "meet me at seven")
        let second = try opener(text: "meet me at seven")

        // Same text, different keys and ratchet state: two genuine openers must
        // never collide, or accepting one would block the other.
        #expect(Contact.sessionInitDigest(first) != Contact.sessionInitDigest(second))
    }

    /// The contact remembers what it has already accepted.
    @Test func anAcceptedOpenerIsRememberedAndRefused() throws {
        let envelope = try opener()
        let contact = Contact(id: "peer", displayName: "Peer", prekeyBundleBase64: "")

        let digest = Contact.sessionInitDigest(envelope)
        #expect(contact.hasConsumedSessionInit(digest) == false)

        contact.noteConsumedSessionInit(digest)
        #expect(contact.hasConsumedSessionInit(digest), "the replay would have been accepted again")

        // A different opener from the same contact still goes through: people do
        // re-initialise sessions, and refusing that would break the conversation.
        let another = try opener(text: "actually, eight")
        #expect(contact.hasConsumedSessionInit(Contact.sessionInitDigest(another)) == false)
    }

    /// The record is bounded, and forgets the oldest first.
    @Test func theListStaysSmall() throws {
        let contact = Contact(id: "peer", displayName: "Peer", prekeyBundleBase64: "")

        var digests: [Data] = []
        for index in 0..<(Contact.maxConsumedInits + 5) {
            let digest = Data(SHA256.hash(data: Data("opener-\(index)".utf8)))
            digests.append(digest)
            contact.noteConsumedSessionInit(digest)
        }

        let stored = try #require(contact.consumedInitDigests)
        #expect(stored.count == Contact.maxConsumedInits * 32)

        // The most recent are what a replay would most plausibly target.
        #expect(contact.hasConsumedSessionInit(digests.last!))
        #expect(contact.hasConsumedSessionInit(digests[digests.count - Contact.maxConsumedInits]))
        // And the oldest has fallen off, which is the trade this cap makes.
        #expect(contact.hasConsumedSessionInit(digests.first!) == false)
    }
}
