//
//  SelfMemoCollisionTests.swift
//  privameshTests

//  Reported externally.

//  Two different things start with the same byte. A Saved Messages note is
//  [0x02][AES-GCM...], and MessageEnvelope.Kind.sessionInitPQ is also 0x02. Both
//  arrive on the account's real address: the note because we sent it to
//  ourselves, the opener because the first message of a conversation has no
//  stealth chain to use yet.

//  The dispatcher routed on that byte before parsing, so every post-quantum
//  opener went to the self handler, failed to authenticate under the self key,
//  and was dropped by a silent catch. Adding a contact by QR or invite link
//  between two PQ-capable devices produced no message request, no contact and no
//  error - the sender saw "sent" and the recipient saw nothing.

//  The byte cannot decide. The key can: only a memo we sealed ourselves opens
//  under the self key.

import Testing
import Foundation
import CryptoKit
@testable import privamesh

@Suite("Self-memo / PQ-opener collision")
struct SelfMemoCollisionTests {

    /// A self memo exactly as MessageSender.buildSelfMemo writes it.
    private func selfMemo(_ text: String, identity: CryptoIdentity) throws -> Data {
        let key      = try MessageSender.deriveSelfKey(identity: identity)
        let padded   = try MessagePadding.pad(try ChatPayload.text(text).encode())
        var envelope = Data([0x02])
        envelope.append(try CryptoBox.encrypt(plaintext: padded, key: key))
        return envelope
    }

    /// A PQ opener as the sender builds it: classical X3DH plus a KEM secret
    /// mixed in, the ciphertext itself referenced off-chain. The reference is a
    /// stand-in here — routing is decided before anything is fetched.
    private func pqOpener(
        text: String = "hi from the qr scan",
        to recipient: CryptoIdentity,
        ref: String = "irys-tx-id-placeholder",
        pqSharedSecret: Data = Data(repeating: 0x5A, count: 32)
    ) throws -> MessageEnvelope {
        let sender    = CryptoIdentity.generate_unsafe()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let classical = try X3DH.senderSharedSecret(
            myIdentityKey:  try sender.dhIdentityKey(),
            myEphemeralKey: ephemeral,
            remoteBundle:   try recipient.prekeyBundle()
        )
        let sk = PQXDH.combine(classicalSecret: classical, pqSharedSecret: pqSharedSecret)
        var ratchet = try DoubleRatchet.initSender(
            sharedSecret:    sk,
            remoteSPKPublic: try recipient.prekeyBundle().signedPrekeyPublic
        )
        let padded  = try MessagePadding.pad(try ChatPayload.text(text).encode())
        let message = try ratchet.encrypt(plaintext: padded)

        return MessageEnvelope(
            kind: .sessionInitPQ,
            senderIdentityPublic:  try sender.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralPublic: ephemeral.publicKey.rawRepresentation,
            pqCiphertextRef: ref,
            message: message
        )
    }

    /// The collision itself: the two kinds are indistinguishable by first byte.
    @Test func bothKindsStartWithTheSameByte() throws {
        let me = CryptoIdentity.generate_unsafe()

        #expect(try selfMemo("note to self", identity: me)[0] == 0x02)
        #expect(try pqOpener(to: me).serialize()[0] == 0x02)
        #expect(MessageEnvelope.Kind.sessionInitPQ.rawValue == 0x02)
    }

    /// The regression. The opener must not be consumed by the self handler —
    /// that is exactly how it used to disappear.
    @Test func aPQOpenerIsNotMistakenForASelfMemo() throws {
        let me  = CryptoIdentity.generate_unsafe()
        let key = try MessageSender.deriveSelfKey(identity: me)

        let opener = try pqOpener(to: me).serialize()

        #expect(PollingService.decryptSelfMemo(data: opener, key: key) == nil,
                "a session opener must fall through to the envelope parser")
    }

    /// Having fallen through, it has to parse as what it is.
    @Test func aPQOpenerParsesAsAPQSessionInit() throws {
        let me = CryptoIdentity.generate_unsafe()

        let parsed = try MessageEnvelope.deserialize(
            try pqOpener(to: me, ref: "abcDEF123").serialize()
        )

        #expect(parsed.kind == .sessionInitPQ)
        #expect(parsed.pqCiphertextRef == "abcDEF123")
        #expect(parsed.senderIdentityPublic?.count == 32)
        #expect(parsed.senderEphemeralPublic?.count == 32)
    }

    /// End to end: with the KEM secret recovered, the opener the dispatcher used
    /// to drop decrypts to the message the sender typed.
    @Test func aPQOpenerDecryptsOnceItReachesItsHandler() throws {
        let me  = CryptoIdentity.generate_unsafe()
        let pq  = Data(repeating: 0x5A, count: 32)

        let envelope = try MessageEnvelope.deserialize(
            try pqOpener(text: "meet me at seven", to: me, pqSharedSecret: pq).serialize()
        )
        let result = PollingService.decryptSessionInit(
            envelope: envelope, myIdentity: me, pqSharedSecret: pq
        )

        #expect(result?.payload.body == "meet me at seven")
    }

    /// Saved Messages keeps working — the fix must not cost the self path.
    @Test func aSelfMemoStillOpens() throws {
        let me  = CryptoIdentity.generate_unsafe()
        let key = try MessageSender.deriveSelfKey(identity: me)

        let payload = PollingService.decryptSelfMemo(
            data: try selfMemo("buy milk", identity: me), key: key
        )

        #expect(payload?.body == "buy milk")
    }

    /// And someone else's note to themselves is still none of our business.
    @Test func anotherIdentitysSelfMemoIsNotOurs() throws {
        let me     = CryptoIdentity.generate_unsafe()
        let others = try selfMemo("their own note", identity: CryptoIdentity.generate_unsafe())

        #expect(PollingService.decryptSelfMemo(
            data: others, key: try MessageSender.deriveSelfKey(identity: me)) == nil)
    }

    /// Short and malformed 0x02 memos fall through rather than crash the parser.
    @Test func truncatedMemosAreRejectedWithoutConsuming() throws {
        let key = try MessageSender.deriveSelfKey(identity: CryptoIdentity.generate_unsafe())

        #expect(PollingService.decryptSelfMemo(data: Data([0x02]), key: key) == nil)
        #expect(PollingService.decryptSelfMemo(
            data: Data([0x02] + Array(repeating: UInt8(0), count: 20)), key: key) == nil)
        #expect(PollingService.decryptSelfMemo(data: Data(), key: key) == nil)
    }
}
