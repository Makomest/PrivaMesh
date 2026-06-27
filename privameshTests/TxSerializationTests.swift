//
//  TxSerializationTests.swift
//  privameshTests
//
//  Regression test for the "unable to decode tx.Message / failed to fill whole
//  buffer" RPC failures. Root cause: SolanaSwift's PublicKey(string:) only
//  checks the string length (>= 32 chars), NOT that Base58.decode yields 32
//  bytes. An invalid-base58 recipient (e.g. a base64 DH-key id from a QR
//  contact) produces an empty key that silently drops 32 bytes from the
//  serialized transaction, so the network rejects it.
//

import Testing
import Foundation
import CryptoKit
import SolanaSwift
@testable import privamesh

@Suite("Stealth addresses")
struct StealthAddressTests {

    @Test func bothSidesDeriveSameRootAndAddresses() throws {
        // Bob publishes a prekey bundle; Alice sends to him via X3DH.
        let bob   = try CryptoIdentity.generate()
        let alice = try CryptoIdentity.generate()
        let bundle = try bob.prekeyBundle()
        let ek = Curve25519.KeyAgreement.PrivateKey()

        let skSender = try X3DH.senderSharedSecret(
            myIdentityKey: alice.dhIdentityKey(), myEphemeralKey: ek, remoteBundle: bundle)
        let skReceiver = try X3DH.receiverSharedSecret(
            myIdentityKey: bob.dhIdentityKey(), mySignedPrekey: bob.signedPrekey(),
            senderIdentityKeyPublic: alice.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralKeyPublic: ek.publicKey.rawRepresentation)
        #expect(skSender == skReceiver)

        // Same stealth root on both sides.
        let rootA = StealthAddress.root(fromSharedSecret: skSender)
        let rootB = StealthAddress.root(fromSharedSecret: skReceiver)
        #expect(rootA == rootB)

        // Same one-time address for the same chain/index on both sides.
        let a0 = StealthAddress.address(root: rootA, label: StealthAddress.initiatorToResponder, index: 0)
        let b0 = StealthAddress.address(root: rootB, label: StealthAddress.initiatorToResponder, index: 0)
        #expect(a0 != nil)
        #expect(a0 == b0)
        // Valid 32-byte Solana address.
        #expect((try? PublicKey(string: a0!))?.bytes.count == 32)

        // Unlinkable: different index and different chain → different addresses.
        let a1 = StealthAddress.address(root: rootA, label: StealthAddress.initiatorToResponder, index: 1)
        let r0 = StealthAddress.address(root: rootA, label: StealthAddress.responderToInitiator, index: 0)
        #expect(a0 != a1)
        #expect(a0 != r0)
    }
}

@Suite("Tx serialization")
struct TxSerializationTests {

    @Test func invalidBase58Recipient_yieldsEmptyKey_andShortTx() async throws {
        // base64 of a 32-byte key: length >= 32 (so PublicKey(string:) won't
        // throw) but contains '+', '/', '=' which aren't base58.
        let badId = "Ab+/cd0OIl1234567890ABCDEFGHIJKLMNOP=="
        let recipient = try PublicKey(string: badId)

        // The smoking gun: construction succeeds, but the key is empty.
        #expect(recipient.bytes.count != PublicKey.numberOfBytes)
        #expect(recipient.data.isEmpty)

        let keypair = try await KeyPair(network: .mainnetBeta)
        let memoProgram = try PublicKey(string: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")
        let transferIx = SystemProgram.transferInstruction(from: keypair.publicKey, to: recipient, lamports: 1)
        let memoIx = TransactionInstruction(
            keys: [AccountMeta(publicKey: keypair.publicKey, isSigner: true, isWritable: false)],
            programId: memoProgram, data: Array(String(repeating: "A", count: 136).utf8))
        var tx = Transaction(instructions: [transferIx, memoIx],
                             recentBlockhash: "BdA9gRatFvvwszr9uU5fznkHoMVQE8tf6ZFi8Mp6xdKs",
                             feePayer: keypair.publicKey)
        try tx.sign(signers: [keypair])
        let data = try tx.serialize()

        // A valid recipient yields 388 bytes; the empty key drops 32 → 356.
        #expect(data.count == 356)
    }

    @Test func contactCard_roundTripsAndValidatesAddress() async throws {
        let address = try await KeyPair(network: .mainnetBeta).publicKey.base58EncodedString
        let card = ContactCard(address: address, bundle: "YnVuZGxlLWJhc2U2NA==")

        // Round-trips through the QR payload.
        let decoded = ContactCard.fromQRPayload(card.qrPayload)
        #expect(decoded?.address == address)
        #expect(decoded?.bundle == card.bundle)
        #expect(decoded?.hasValidAddress == true)

        // A base64 DH-key id (the old broken value) is rejected.
        let bad = ContactCard(address: "Ab+/cd0OIl1234567890ABCDEFGHIJKLMNOP==", bundle: "x")
        #expect(bad.hasValidAddress == false)

        // A legacy bundle-only QR (raw PrekeyBundle base64, not a ContactCard)
        // is not parseable as a card.
        #expect(ContactCard.fromQRPayload("not-a-contact-card") == nil)
    }

    @Test func validRecipient_yieldsWellFormedTx() async throws {
        let keypair = try await KeyPair(network: .mainnetBeta)
        let recipient = try await KeyPair(network: .mainnetBeta).publicKey
        #expect(recipient.bytes.count == PublicKey.numberOfBytes)

        let memoProgram = try PublicKey(string: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")
        let transferIx = SystemProgram.transferInstruction(from: keypair.publicKey, to: recipient, lamports: 1)
        let memoIx = TransactionInstruction(
            keys: [AccountMeta(publicKey: keypair.publicKey, isSigner: true, isWritable: false)],
            programId: memoProgram, data: Array(String(repeating: "A", count: 136).utf8))
        var tx = Transaction(instructions: [transferIx, memoIx],
                             recentBlockhash: "BdA9gRatFvvwszr9uU5fznkHoMVQE8tf6ZFi8Mp6xdKs",
                             feePayer: keypair.publicKey)
        try tx.sign(signers: [keypair])
        let data = try tx.serialize()

        // 65 (sig) + 3 (header) + 1 + 4*32 (accounts) + 32 (blockhash)
        // + 1 + 17 (transfer ix) + 141 (memo ix, 2-byte len + 136 data) = 388
        #expect(data.count == 388)
    }
}
