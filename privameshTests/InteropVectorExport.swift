//
//  InteropVectorExport.swift
//  privameshTests
//
//  Phase 0 of the Android port: dump the wire formats this app already uses to
//  JSON, so the Kotlin implementation can assert against them instead of against
//  itself. Everything here is *observed*, never re-specified — the numbers come
//  out of the shipping types (CryptoIdentity, PrekeyBundle, DoubleRatchet,
//  StealthAddress, ContactCard, PQXDH), so a vector can only be wrong if the app
//  is wrong.
//
//  Two exceptions where the app is deliberately random and a vector cannot be:
//  the X3DH ephemeral key and the sender's first ratchet key. Both are derived
//  here from a fixed label instead, and the private bytes are exported, so the
//  Android side loads the same keys rather than guessing them. The hand-built
//  sender ratchet is then proved correct by having a *real* receiver ratchet
//  (DoubleRatchet.initReceiver, untouched) decrypt the exported envelope before
//  anything is written.
//
//  Run:  xcodebuild test -scheme privamesh -destination 'platform=iOS Simulator,name=iPhone 17' \
//          -only-testing:privameshTests/InteropVectorExport
//  Output goes to $VECTOR_OUT (see SIMCTL_CHILD_VECTOR_OUT) or /tmp/privamesh-vectors.
//

import Testing
import Foundation
import CryptoKit
import SolanaSwift
import TweetNacl
@testable import privamesh

// MARK: - Fixtures

private enum Fixture {
    /// The phrase named in the port plan. Its keys are what Android must reproduce.
    static let alicePhrase = ["drum", "need", "person", "expire", "large", "wrist",
                              "struggle", "labor", "label", "ill", "improve", "cloud"]
    /// A second fixed identity, so the X3DH vector has two known ends.
    static let bobPhrase = ["ridge", "coral", "sunset", "matrix", "gospel", "orbit",
                            "lantern", "puzzle", "velvet", "harbor", "nectar", "quiver"]

    /// A real base58 Solana address, reused from InviteLinkTests.
    static let walletAddress = "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V"

    /// A Solana keypair from a fixed 32-byte seed. The app draws these at random
    /// (the per-message ephemeral signer); the vector needs one that both platforms
    /// can rebuild, and Ed25519 seed → keypair is defined, so this is the same
    /// keypair on either side.
    static func fixedSolanaKeypair(_ label: String) throws -> KeyPair {
        let seed = CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data(label.utf8),
            outputByteCount: 32)
        let nacl = try NaclSign.KeyPair.keyPair(fromSeed: seed)
        return try KeyPair(secretKey: nacl.secretKey)
    }

    static func fixedSeedHex(_ label: String) -> String {
        CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data(label.utf8),
            outputByteCount: 32
        ).map { String(format: "%02x", $0) }.joined()
    }

    /// A blockhash never changes the assembly logic, only the bytes, so the vector
    /// pins one instead of fetching. Same value SolanaSwift's own tests use.
    static let blockhash = "BdA9gRatFvvwszr9uU5fznkHoMVQE8tf6ZFi8Mp6xdKs"

    /// A real one-time address off the same session the other vectors use, because a
    /// message is never addressed to a wallet.
    static var stealthRecipient: String {
        get throws {
            let alice = try CryptoIdentity.derive(fromSeedPhrase: alicePhrase)
            let bob = try CryptoIdentity.derive(fromSeedPhrase: bobPhrase)
            let secret = try X3DH.senderSharedSecret(
                myIdentityKey: alice.dhIdentityKey(),
                myEphemeralKey: fixedKey("aliceEphemeral"),
                remoteBundle: bob.prekeyBundle())
            let root = StealthAddress.root(fromSharedSecret: secret)
            guard let address = StealthAddress.address(
                root: root, label: StealthAddress.initiatorToResponder, index: 0)
            else { throw CryptoError.invalidData }
            return address
        }
    }

    /// Stands in for an envelope: fixed bytes of a realistic size, since the memo's
    /// content is opaque to transaction assembly but its LENGTH is not.
    static var memoBase64: String {
        CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data("memoPayload".utf8),
            outputByteCount: 105
        ).base64EncodedString()
    }

    /// Deterministic stand-in for a key the app generates randomly. Not a protocol
    /// construct — only a way to make a vector reproducible on both platforms.
    static func fixedKey(_ label: String) -> Curve25519.KeyAgreement.PrivateKey {
        let raw = CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data(label.utf8),
            outputByteCount: 32)
        return try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

private enum VectorWriter {
    /// Host directory the Android repo reads. The simulator can be pointed at the
    /// repo directly via SIMCTL_CHILD_VECTOR_OUT; /tmp is the fallback because it
    /// is never subject to a privacy prompt.
    static var directory: URL {
        let path = ProcessInfo.processInfo.environment["VECTOR_OUT"] ?? "/tmp/privamesh-vectors"
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func write(_ object: [String: Any], to name: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        print("[vectors] wrote \(url.path) (\(data.count) bytes)")
    }
}

// MARK: - Export

@Suite("Interop vector export")
struct InteropVectorExport {

    // MARK: 1. Identity + published bundle

    @Test func exportIdentityAndBundle() throws {
        let identity = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        let bundle   = try identity.prekeyBundle()
        try bundle.verify()

        let dhIK  = try identity.dhIdentityKey()
        let spk   = try identity.signedPrekey()
        let sigIK = try Curve25519.Signing.PrivateKey(rawRepresentation: identity.signingKeyData)

        var out: [String: Any] = [
            // Measured, not assumed: two encodes of one identity in this same export
            // run carry different signature bytes (compare with contact_card.json).
            "note": "HKDF-SHA256, salt PrivaMesh-msg-identity-v1, one info label per key. The KEYS "
                  + "are reproducible; the signature is NOT — CryptoKit's Ed25519 signer is hedged, "
                  + "so a re-derived bundle differs byte-wise every time. Verify signatures, never "
                  + "compare them. (The comment in PrekeyBundle.swift claiming byte-stability is wrong.)",
            "phrase": Fixture.alicePhrase.joined(separator: " "),
            "salt": "PrivaMesh-msg-identity-v1",
            "private": [
                "dhIdentityKey": identity.dhIdentityKeyData.hex,
                "signingKey": identity.signingKeyData.hex,
                "signedPrekey": identity.signedPrekeyData.hex,
                "pqPrekeySeed": identity.pqPrekeySeed?.hex ?? NSNull(),
            ],
            "public": [
                "dhIdentityKey": dhIK.publicKey.rawRepresentation.hex,
                "signingIdentityKey": sigIK.publicKey.rawRepresentation.hex,
                "signedPrekeyPublic": spk.publicKey.rawRepresentation.hex,
                "signedPrekeySignature": identity.signedPrekeySignature.hex,
            ],
            "prekeyBundleBase64": bundle.base64Encoded,
            "prekeyBundleDiscoveryPackedHex": bundle.discoveryPacked.hex,
        ]

        // The PQ prekey rides in the QR bundle only, and only from iOS 26. Exported
        // separately so a classical-only Android build can still use everything else.
        if #available(iOS 26.0, *), let pq = bundle.pqPrekeyPublic {
            out["pqPrekeyPublicHex"] = pq.hex
            out["pqPrekeyPublicByteCount"] = pq.count
        }

        try VectorWriter.write(out, to: "identity.json")
    }

    // MARK: 2. X3DH + stealth addresses

    @Test func exportX3DHAndStealthAddresses() throws {
        let alice = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        let bob   = try CryptoIdentity.derive(fromSeedPhrase: Fixture.bobPhrase)
        let bobBundle = try bob.prekeyBundle()
        let ephemeral = Fixture.fixedKey("aliceEphemeral")

        let skSender = try X3DH.senderSharedSecret(
            myIdentityKey: try alice.dhIdentityKey(),
            myEphemeralKey: ephemeral,
            remoteBundle: bobBundle)

        // Both ends must land on the same secret, or the vector is meaningless.
        let skReceiver = try X3DH.receiverSharedSecret(
            myIdentityKey: try bob.dhIdentityKey(),
            mySignedPrekey: try bob.signedPrekey(),
            senderIdentityKeyPublic: try alice.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralKeyPublic: ephemeral.publicKey.rawRepresentation)
        #expect(skSender == skReceiver)

        let root = StealthAddress.root(fromSharedSecret: skSender)
        func chain(_ label: String) -> [String] {
            (0..<3).compactMap { StealthAddress.address(root: root, label: label, index: $0) }
        }
        let i2r = chain(StealthAddress.initiatorToResponder)
        let r2i = chain(StealthAddress.responderToInitiator)
        #expect(i2r.count == 3 && r2i.count == 3)
        #expect(Set(i2r).isDisjoint(with: Set(r2i)), "the two directions must not collide")

        try VectorWriter.write([
            "note": "Classical X3DH only. DH order: DH(IK_A,SPK_B) ‖ DH(EK_A,IK_B) ‖ DH(EK_A,SPK_B), "
                  + "then HKDF salt=32 zero bytes, info=PrivaMesh-X3DH-v1. No one-time prekey in this vector.",
            "alicePhrase": Fixture.alicePhrase.joined(separator: " "),
            "bobPhrase": Fixture.bobPhrase.joined(separator: " "),
            "aliceEphemeralPrivateHex": ephemeral.rawRepresentation.hex,
            "aliceEphemeralPublicHex": ephemeral.publicKey.rawRepresentation.hex,
            "bobPrekeyBundleBase64": bobBundle.base64Encoded,
            "sharedSecretHex": skSender.hex,
            "stealth": [
                "rootInfo": "privamesh-stealth-v1",
                "rootHex": root.hex,
                "indexEncoding": "UInt32 big-endian as HKDF info; salt is the ASCII label",
                "i2r": i2r,
                "r2i": r2i,
            ],
        ], to: "x3dh_stealth.json")
    }

    // MARK: 3. Padding buckets

    @Test func exportPaddingBuckets() throws {
        // One input per bucket boundary, plus the clamp at maxPlaintextBytes.
        let inputs: [(String, Data)] = [
            ("empty", Data()),
            ("5 bytes", Data("hello".utf8)),
            ("31 bytes — fills bucket 32 exactly", Data(repeating: 0xAB, count: 31)),
            ("32 bytes — one over, spills to 64", Data(repeating: 0xAB, count: 32)),
            ("63 bytes", Data(repeating: 0xCD, count: 63)),
            ("127 bytes", Data(repeating: 0x11, count: 127)),
            ("255 bytes", Data(repeating: 0x22, count: 255)),
            ("300 bytes", Data(repeating: 0x42, count: 300)),
            ("460 bytes — maxPlaintextBytes", Data(repeating: 0x33, count: 460)),
            ("600 bytes — clamped to 460", Data(repeating: 0x44, count: 600)),
        ]
        let cases: [[String: Any]] = try inputs.map { label, plain in
            let padded = MessagePadding.pad(plain)
            #expect(MessagePadding.buckets.contains(padded.count))
            let expected = plain.count > MessagePadding.maxPlaintextBytes
                ? Data(plain.prefix(MessagePadding.maxPlaintextBytes)) : plain
            let unpadded = try MessagePadding.unpad(padded)
            #expect(unpadded == expected)
            return [
                "label": label,
                "plaintextHex": plain.hex,
                "paddedHex": padded.hex,
                "paddedLength": padded.count,
                "unpaddedHex": expected.hex,
            ]
        }

        try VectorWriter.write([
            "note": "ISO/IEC 7816-4: append 0x80 then 0x00 to the next bucket. Input longer than "
                  + "maxPlaintextBytes is truncated first, so unpad != original for the clamped case.",
            "buckets": MessagePadding.buckets,
            "maxPlaintextBytes": MessagePadding.maxPlaintextBytes,
            "cases": cases,
        ], to: "padding.json")
    }

    // MARK: 4. Session-init envelope (the memo payload)

    @Test func exportSessionInitEnvelope() throws {
        let alice = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        let bob   = try CryptoIdentity.derive(fromSeedPhrase: Fixture.bobPhrase)
        let bobBundle = try bob.prekeyBundle()
        let ephemeral = Fixture.fixedKey("aliceEphemeral")
        let ratchetKey = Fixture.fixedKey("aliceFirstRatchet")

        let sk = try X3DH.senderSharedSecret(
            myIdentityKey: try alice.dhIdentityKey(),
            myEphemeralKey: ephemeral,
            remoteBundle: bobBundle)

        // DoubleRatchet.initSender generates its ratchet key at random, so the state
        // is rebuilt here with a fixed one. Same KDF_RK the implementation uses; the
        // round-trip below is what proves it.
        let dhOut = try CryptoBox.dh(privateKey: ratchetKey,
                                     publicKey: try Curve25519.KeyAgreement.PublicKey(
                                        rawRepresentation: bobBundle.signedPrekeyPublic))
        let rkOut = CryptoBox.hkdf(inputKeyMaterial: dhOut, salt: sk,
                                   info: Data("PrivaMesh-DR-RK".utf8), outputByteCount: 64)
        var sender = DoubleRatchet(
            dhSending: RatchetKeyPair(privateKey: ratchetKey),
            dhRemote: bobBundle.signedPrekeyPublic,
            rootKey: Data(rkOut[..<32]),
            sendingChainKey: Data(rkOut[32...]),
            receivingChainKey: nil,
            sendCount: 0, receiveCount: 0, previousSendCount: 0,
            skippedKeys: [:])

        let initialStateJSON = try JSONEncoder().encode(sender)

        let text = "Hello from iOS 👋"
        let padded = MessagePadding.pad(Data(text.utf8))
        let encrypted = try sender.encrypt(plaintext: padded)
        let envelope = MessageEnvelope(
            kind: .sessionInit,
            senderIdentityPublic: try alice.dhIdentityKey().publicKey.rawRepresentation,
            senderEphemeralPublic: ephemeral.publicKey.rawRepresentation,
            message: encrypted)
        let memo = envelope.base64

        // Proof the hand-built sender state is a real one: an untouched receiver
        // ratchet, built the way the app builds it, decrypts what we just exported.
        var receiver = DoubleRatchet.initReceiver(sharedSecret: sk, localSPK: try bob.signedPrekey())
        let parsed = try MessageEnvelope.fromBase64(memo)
        let recovered = try MessagePadding.unpad(try receiver.decrypt(message: parsed.message))
        #expect(recovered == Data(text.utf8))

        // A second message on the same chain, so Android also exercises the chain step.
        let text2 = "second message on the same chain"
        let encrypted2 = try sender.encrypt(plaintext: MessagePadding.pad(Data(text2.utf8)))
        let memo2 = MessageEnvelope(kind: .regular, senderIdentityPublic: nil,
                                    senderEphemeralPublic: nil, message: encrypted2).base64
        let recovered2 = try MessagePadding.unpad(
            try receiver.decrypt(message: try MessageEnvelope.fromBase64(memo2).message))
        #expect(recovered2 == Data(text2.utf8))

        try VectorWriter.write([
            "note": "AES-GCM nonces are random, so these bytes cannot be regenerated — the Android "
                  + "test must DECRYPT them. Header (32B DH pub ‖ 4B prevCount BE ‖ 4B msgNum BE) is the AAD.",
            "sharedSecretHex": sk.hex,
            "senderRatchetPrivateHex": ratchetKey.rawRepresentation.hex,
            "senderRatchetPublicHex": ratchetKey.publicKey.rawRepresentation.hex,
            "senderInitialStateJSON": String(data: initialStateJSON, encoding: .utf8) ?? "",
            "rootKeyHex": Data(rkOut[..<32]).hex,
            "sendingChainKeyHex": Data(rkOut[32...]).hex,
            "bobPrekeyBundleBase64": bobBundle.base64Encoded,
            "bobSignedPrekeyPrivateHex": bob.signedPrekeyData.hex,
            "messages": [
                [
                    "kind": "sessionInit (0x01)",
                    "plaintext": text,
                    "paddedHex": padded.hex,
                    "envelopeBase64": memo,
                    "envelopeHex": envelope.serialize().hex,
                    "encryptedMessageHex": encrypted.serialized.hex,
                ],
                [
                    "kind": "regular (0x00)",
                    "plaintext": text2,
                    "envelopeBase64": memo2,
                ],
            ],
        ], to: "envelope.json")
    }

    // MARK: 5. Contact card + invite link

    @Test func exportContactCardAndInviteLink() throws {
        let identity = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        // The published card carries the classical bundle; the PQ prekey is dropped
        // so the vector is identical on every machine that runs this export.
        let full = try identity.prekeyBundle()
        let bundle = PrekeyBundle(
            dhIdentityKey: full.dhIdentityKey,
            signedPrekeyPublic: full.signedPrekeyPublic,
            signedPrekeySignature: full.signedPrekeySignature,
            oneTimePrekeyPublic: nil,
            signingIdentityKey: full.signingIdentityKey)

        let card = ContactCard(address: Fixture.walletAddress, bundle: bundle.base64Encoded)
        #expect(card.hasValidAddress)

        let qr = card.qrPayload
        let webURL = try #require(InviteLink.url(for: card))
        let appURL = try #require(InviteLink.appURL(for: card))

        // Round-trip through the parsers the app actually ships.
        let fromQR = try #require(ContactCard.fromQRPayload(qr))
        #expect(fromQR.bundle == card.bundle && fromQR.address == card.address)
        #expect(InviteLink.card(from: webURL)?.bundle == card.bundle)
        #expect(InviteLink.card(from: appURL)?.bundle == card.bundle)

        let cardJSON = try JSONEncoder().encode(card)

        try VectorWriter.write([
            // Verified against the emitted bytes, not against the docs: Apple's
            // .zlib emits RAW DEFLATE — no 0x78 header, no Adler-32 trailer. Inflater(true)
            // on Android, not the default. Getting this wrong makes every QR unreadable.
            "note": "qrPayload is base64(raw DEFLATE of the card JSON) — Apple's NSData .zlib "
                  + "algorithm is headerless DEFLATE (RFC 1951), NOT RFC 1950 zlib. Use "
                  + "java.util.zip.Inflater(nowrap = true) / Deflater(level, nowrap = true). The "
                  + "Android reader must also accept plain base64(JSON): older QRs used it and "
                  + "fromQRPayload still falls back to it.",
            "cardJSON": String(data: cardJSON, encoding: .utf8) ?? "",
            "address": Fixture.walletAddress,
            "bundleBase64": bundle.base64Encoded,
            "qrPayload": qr,
            "qrPayloadPlainBase64JSON": cardJSON.base64EncodedString(),
            "inviteLinkWeb": webURL.absoluteString,
            "inviteLinkApp": appURL.absoluteString,
            "base64urlRule": "+ → -, / → _, = stripped; padding restored on the way back",
        ], to: "contact_card.json")
    }

    // MARK: 6. Post-quantum (iOS 26+ only)

    @available(iOS 26.0, *)
    @Test func exportPQVectors() throws {
        let identity = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        let seed = try #require(identity.pqPrekeySeed)
        let keypair = try #require(identity.pqKeypair())

        // Encapsulation is randomized: the ciphertext is recorded and Android must
        // decapsulate it to the same secret. That is the blocking interop test —
        // if BouncyCastle's X-Wing byte layout differs, it fails here and Android
        // ships classical-only (PORT-PLAN §5.1).
        let sent = try PQXDH.encapsulate(toEncapsulationKey: keypair.encapsulationKey)
        let roundTrip = try PQXDH.decapsulate(ciphertext: sent.ciphertext, keypair: keypair)
        #expect(roundTrip == sent.sharedSecret)

        let classical = Data(repeating: 0x5A, count: 32)
        let combined = PQXDH.combine(classicalSecret: classical, pqSharedSecret: sent.sharedSecret)

        try VectorWriter.write([
            "note": "CryptoKit XWingMLKEM768X25519. seedRepresentation → keypair must be reproducible "
                  + "byte for byte, and decapsulating the recorded ciphertext must yield sharedSecretHex.",
            "source": "CryptoKit on \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "seedHex": seed.hex,
            "encapsulationKeyHex": keypair.encapsulationKey.hex,
            "encapsulationKeyByteCount": keypair.encapsulationKey.count,
            "ciphertextHex": sent.ciphertext.hex,
            "ciphertextByteCount": sent.ciphertext.count,
            "sharedSecretHex": sent.sharedSecret.hex,
            "combine": [
                "note": "HKDF(ikm = classical ‖ pq, salt = PrivaMesh-PQXDH-v1, info = root, 32 bytes). "
                      + "With no PQ secret the classical secret passes through unchanged.",
                "classicalSecretHex": classical.hex,
                "combinedRootHex": combined.hex,
                "fallbackRootHex": PQXDH.combine(classicalSecret: classical, pqSharedSecret: nil).hex,
            ],
        ], to: "pq_xwing.json")
    }

    // MARK: 7. Solana transactions

    /// The transaction bytes are the other half of interoperability: the crypto can
    /// be perfect and the message still never lands, because Solana rejects a
    /// mis-assembled transaction. SolanaSwift decides account ordering, the compact-u16
    /// lengths and the empty-signature placeholders; this records what it produced so
    /// the Kotlin builder can be compared byte for byte instead of "looking right".
    ///
    /// The instruction list mirrors `MemoTransactionBuilder.buildSponsoredMessageBase64`
    /// with two substitutions the vector needs: a fixed ephemeral signer instead of a
    /// random one, and a fixed blockhash instead of a fetched one.
    @Test func exportTransactionVectors() throws {
        let ephemeral = try Fixture.fixedSolanaKeypair("ephemeralSigner")
        let treasury = try PublicKey(string: RelayConfig.treasuryPubkey)
        let recipient = try PublicKey(string: try Fixture.stealthRecipient)
        let memoBase64 = Fixture.memoBase64
        let memoProgram = try PublicKey(string: MemoTransactionBuilder.memoProgramId)
        let computeBudget = try PublicKey(string: MemoTransactionBuilder.computeBudgetProgramId)

        func computeBudgetInstruction(_ discriminator: UInt8, _ value: [UInt8]) -> TransactionInstruction {
            TransactionInstruction(keys: [], programId: computeBudget, data: [discriminator] + value)
        }
        func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func le64(_ v: UInt64) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }

        let priceIx = computeBudgetInstruction(3, le64(MemoTransactionBuilder.computeUnitPriceMicroLamports))
        let limitIx = computeBudgetInstruction(2, le32(600_000))

        func memoInstruction(signer: PublicKey) -> TransactionInstruction {
            TransactionInstruction(
                keys: [AccountMeta(publicKey: signer, isSigner: true, isWritable: false)],
                programId: memoProgram,
                data: Array(memoBase64.utf8))
        }
        func transferInstruction(from: PublicKey) -> TransactionInstruction {
            SystemProgram.transferInstruction(
                from: from, to: recipient,
                lamports: MemoTransactionBuilder.lamportsPerMessage)
        }

        /// One case: build, sign the way the app signs, and record every layer the
        /// Kotlin side has to reproduce (accounts, header, message, final bytes).
        func record(
            _ name: String,
            instructions: [TransactionInstruction],
            feePayer: PublicKey,
            signers: [KeyPair],
            requiredAllSignatures: Bool
        ) throws -> [String: Any] {
            var transaction = Transaction(
                instructions: instructions, recentBlockhash: Fixture.blockhash, feePayer: feePayer)
            let message = try transaction.compileMessage()
            if requiredAllSignatures {
                try transaction.sign(signers: signers)
            } else {
                try transaction.partialSign(signers: signers)
            }
            let serialized = try transaction.serialize(requiredAllSignatures: requiredAllSignatures)

            return [
                "name": name,
                "feePayer": feePayer.base58EncodedString,
                "signers": signers.map(\.publicKey.base58EncodedString),
                "requiredAllSignatures": requiredAllSignatures,
                "header": [
                    "numRequiredSignatures": Int(message.header.numRequiredSignatures),
                    "numReadonlySignedAccounts": Int(message.header.numReadonlySignedAccounts),
                    "numReadonlyUnsignedAccounts": Int(message.header.numReadonlyUnsignedAccounts),
                ],
                "accountKeys": message.accountKeys.map(\.base58EncodedString),
                "messageBase64": try message.serialize().base64EncodedString(),
                "transactionBase64": serialized.base64EncodedString(),
                "transactionByteCount": serialized.count,
            ]
        }

        let cases: [[String: Any]] = [
            // What every ordinary message is: treasury pays, ephemeral partial-signs,
            // and the fee-payer signature slot is left empty for the relay.
            try record(
                "sponsored message, no compute limit",
                instructions: [priceIx, transferInstruction(from: ephemeral.publicKey),
                               memoInstruction(signer: ephemeral.publicKey)],
                feePayer: treasury, signers: [ephemeral], requiredAllSignatures: false),
            // A large memo (discovery publish) needs the raised limit, which adds an
            // instruction and changes nothing else.
            try record(
                "sponsored message, compute limit 600000",
                instructions: [limitIx, priceIx, transferInstruction(from: ephemeral.publicKey),
                               memoInstruction(signer: ephemeral.publicKey)],
                feePayer: treasury, signers: [ephemeral], requiredAllSignatures: false),
            // The self-paid path: one signer who is also the fee payer, fully signed.
            try record(
                "self-paid message, fully signed",
                instructions: [priceIx, transferInstruction(from: ephemeral.publicKey),
                               memoInstruction(signer: ephemeral.publicKey)],
                feePayer: ephemeral.publicKey, signers: [ephemeral], requiredAllSignatures: true),
        ]

        try VectorWriter.write([
            "note": "Legacy (non-versioned) transactions. Account ordering, the compact-u16 "
                  + "lengths and the all-zero placeholder for an unsigned slot are SolanaSwift's; "
                  + "the relay and the network both depend on them. Blockhash and the ephemeral "
                  + "signer are fixed here — the app draws both fresh.",
            "blockhash": Fixture.blockhash,
            "ephemeralSignerSeedHex": Fixture.fixedSeedHex("ephemeralSigner"),
            "ephemeralSignerPublicKey": ephemeral.publicKey.base58EncodedString,
            "treasury": RelayConfig.treasuryPubkey,
            "recipient": try Fixture.stealthRecipient,
            "memoBase64": memoBase64,
            "memoProgramId": MemoTransactionBuilder.memoProgramId,
            "computeBudgetProgramId": MemoTransactionBuilder.computeBudgetProgramId,
            "computeUnitPriceMicroLamports": Int(MemoTransactionBuilder.computeUnitPriceMicroLamports),
            "lamportsPerMessage": Int(MemoTransactionBuilder.lamportsPerMessage),
            "cases": cases,
        ], to: "transactions.json")
    }

    // MARK: 8. Irys data item (ANS-104)

    /// Photos and the PQ ciphertext travel off-chain through Irys, which accepts an
    /// ANS-104 data item signed the Arweave way: a SHA-384 "deep hash" over a fixed
    /// list of fields, not a hash of the serialized item. The tag strings
    /// ("dataitem", "1", "blob<len>", "list<n>") are part of the signature, so a
    /// typo there is only visible as a rejected upload.
    ///
    /// `IrysUploader.makeDataItem` is private and generates a random anchor, so the
    /// assembly is mirrored here with a fixed one. The deep-hash values are the part
    /// that matters, and they come from the same SHA-384 the app uses.
    @Test func exportIrysDataItem() throws {
        let keypair = try Fixture.fixedSolanaKeypair("irysSigner")
        let payload = CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data("irysPayload".utf8),
            outputByteCount: 512)
        let anchor = CryptoBox.hkdf(
            inputKeyMaterial: Data("PrivaMesh-interop-vectors".utf8),
            salt: Data("PrivaMesh-vectors-v1".utf8),
            info: Data("irysAnchor".utf8),
            outputByteCount: 32)

        let sigType: UInt16 = 2                       // Solana Ed25519
        let sigTypeBytes = Data([UInt8(sigType & 0xFF), UInt8(sigType >> 8)])
        let owner = keypair.publicKey.data

        func deepHashChunk(_ data: Data) -> Data {
            Data(SHA384.hash(data: Data("blob\(data.count)".utf8) + data))
        }
        func deepHash(_ chunks: [Data]) -> Data {
            var acc = Data(SHA384.hash(data: Data("list\(chunks.count)".utf8)))
            for chunk in chunks {
                acc = Data(SHA384.hash(data: acc + deepHashChunk(chunk)))
            }
            return acc
        }

        let fields: [Data] = [
            Data("dataitem".utf8), Data("1".utf8), sigTypeBytes, owner,
            Data(),      // no target
            anchor,
            Data(),      // no tags
            payload,
        ]
        let signed = deepHash(fields)
        let signature = try NaclSign.signDetached(message: signed, secretKey: keypair.secretKey)

        var item = Data()
        item.append(sigTypeBytes)
        item.append(signature)
        item.append(owner)
        item.append(0)          // target present = false
        item.append(1)          // anchor present = true
        item.append(anchor)
        item.append(contentsOf: [UInt8](repeating: 0, count: 8))   // num_tags
        item.append(contentsOf: [UInt8](repeating: 0, count: 8))   // num_tags_bytes
        item.append(payload)

        try VectorWriter.write([
            "note": "ANS-104 data item, sig_type 2 (Solana Ed25519). The signature covers the "
                  + "deep hash of the field list, never the serialized item. Anchor is fixed here; "
                  + "the app draws it at random per upload.",
            "signerSeedHex": Fixture.fixedSeedHex("irysSigner"),
            "signerPublicKey": keypair.publicKey.base58EncodedString,
            "anchorHex": anchor.hex,
            "payloadHex": payload.hex,
            "deepHash": [
                "emptyChunkHex": deepHashChunk(Data()).hex,
                "payloadChunkHex": deepHashChunk(payload).hex,
                "signedHex": signed.hex,
            ],
            "signatureHex": signature.hex,
            "dataItemHex": item.hex,
            "dataItemByteCount": item.count,
        ], to: "irys_data_item.json")
    }

    // MARK: 9. Wallet derivation (BIP-39 → SLIP-0010)

    /// The Solana address the recovery phrase produces. This is the one part of an
    /// account that is NOT derived by our own HKDF: SolanaSwift takes the BIP-39 seed
    /// and walks SLIP-0010 ed25519 down `m/44'/501'/0'/0'`. Restoring the same phrase
    /// on another platform has to land on this exact address, or the account is
    /// unreachable at its nickname and any SOL sent to it is gone.
    @Test func exportWalletDerivation() async throws {
        let keypair = try await KeyPair(
            phrase: Fixture.alicePhrase, network: .mainnetBeta, derivablePath: .default)
        let mnemonic = try Mnemonic(phrase: Fixture.alicePhrase)

        try VectorWriter.write([
            "note": "BIP-39 seed (PBKDF2-HMAC-SHA512, salt \"mnemonic\", 2048 rounds) then SLIP-0010 "
                  + "ed25519 down m/44'/501'/0'/0' — every level hardened. NOT the app's own HKDF "
                  + "derivation, which is used only for the messaging identity.",
            "phrase": Fixture.alicePhrase.joined(separator: " "),
            "derivationPath": DerivablePath.default.rawValue,
            "bip39SeedHex": Data(mnemonic.seed).hex,
            "publicKey": keypair.publicKey.base58EncodedString,
            "publicKeyHex": keypair.publicKey.data.hex,
        ], to: "wallet_derivation.json")
    }

    // MARK: 10. Generated nickname

    /// The handle every account gets for free, derived from its address. It is shown
    /// to contacts and published to the on-chain registry, so the two platforms must
    /// derive the same string from the same key — a different hash would rename every
    /// existing account on the other side.
    @Test func exportNickname() async throws {
        let keypair = try await KeyPair(
            phrase: Fixture.alicePhrase, network: .mainnetBeta, derivablePath: .default)
        let address = keypair.publicKey.base58EncodedString

        try VectorWriter.write([
            "note": "FNV-1a over the address's UTF-8 bytes; adjective = hash % adjectives, "
                  + "noun = (hash >> 8) % nouns, suffix = (hash >> 18) % 10000.",
            "address": address,
            "nickname": NicknameManager.generate(from: address),
            "walletAddressNickname": NicknameManager.generate(from: Fixture.walletAddress),
            "emptyKeyNickname": NicknameManager.generate(from: ""),
        ], to: "nickname.json")
    }

    // MARK: 11. On-chain discovery record

    /// The nickname → identity record published to the shared registry.
    ///
    /// Three things here are easy to get wrong and impossible to notice from one
    /// side: the bundle inside is the COMPACT packed form (not base64 JSON), the
    /// memo is raw JSON text (not base64), and the bundle is wallet-signed so a
    /// reader can bind it to the address. A record that misses any of them parses
    /// as nothing on the other platform.
    @Test func exportDiscoveryRecord() async throws {
        let identity = try CryptoIdentity.derive(fromSeedPhrase: Fixture.alicePhrase)
        let keypair = try await KeyPair(
            phrase: Fixture.alicePhrase, network: .mainnetBeta, derivablePath: .default)
        let address = keypair.publicKey.base58EncodedString

        // Deliberately the classical bundle: `discoveryPacked` has no room for the
        // PQ prekey, so signing a bundle that carries one produces a signature over
        // bytes the reader can never reconstruct.
        var bundle = try identity.prekeyBundle()
        bundle.pqPrekeyPublic = nil
        let signed = bundle.walletSigned(address: address, keypair: keypair)
        let packed = signed.discoveryPacked

        let rebuilt = PrekeyBundle(discoveryPacked: packed)

        try VectorWriter.write([
            "note": "Memo = \"PDIR1:\" + JSON(record), raw UTF-8. record.bundle = "
                  + "base64(PrekeyBundle.discoveryPacked) of a WALLET-SIGNED classical bundle.",
            "address": address,
            "nickname": "alice",
            "packedBase64": packed.base64EncodedString(),
            "packedLength": packed.count,
            "walletSignatureHex": (signed.walletSignature ?? Data()).hex,
            "canonicalBytesHex": signed.canonicalBytes.hex,
            "isBoundToAfterRoundTrip": rebuilt?.isBoundTo(address: address) ?? false,
        ], to: "discovery.json")
    }

    // MARK: 10. Manifest

    @Test func exportManifest() throws {
        var files = ["identity.json", "x3dh_stealth.json", "padding.json",
                     "envelope.json", "contact_card.json", "transactions.json",
                     "irys_data_item.json", "wallet_derivation.json", "nickname.json",
                     "discovery.json"]
        if #available(iOS 26.0, *) { files.append("pq_xwing.json") }

        try VectorWriter.write([
            "note": "Generated by privameshTests/InteropVectorExport.swift. Do not hand-edit: "
                  + "re-run the export against the iOS build that is live, and treat any diff as "
                  + "a wire-format change that breaks the installed base.",
            "generator": "InteropVectorExport.swift",
            "iosVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "pqAvailable": { if #available(iOS 26.0, *) { return PQXDH.enabled }; return false }(),
            "files": files,
        ], to: "manifest.json")
    }
}
