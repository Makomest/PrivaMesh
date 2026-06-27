//
//  DoubleRatchet.swift
//  privamesh
//
//  Signal-compatible Double Ratchet algorithm.
//  Spec: https://signal.org/docs/specifications/doubleratchet/
//
//  KDF_RK  — HKDF-SHA256(salt=RK, IKM=DH_out, info="PrivaMesh-DR-RK")
//  KDF_CK  — HMAC-SHA256 based chain step
//  ENCRYPT — AES-256-GCM with header bytes as AAD
//

import Foundation
import CryptoKit

// MARK: - Supporting types

struct RatchetKeyPair: Codable {
    private let raw: Data   // Curve25519.KeyAgreement private key raw bytes

    init() {
        raw = Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }

    init(privateKey: Curve25519.KeyAgreement.PrivateKey) {
        raw = privateKey.rawRepresentation
    }

    func privateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        try .init(rawRepresentation: raw)
    }

    var publicKeyData: Data {
        (try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw).publicKey.rawRepresentation) ?? Data()
    }
}

struct SkippedKeyID: Hashable, Codable {
    let dhPublicKey: Data
    let messageNumber: UInt32
}

// MARK: - Wire format

/// Compact binary message:
///   [0..31]  — DH ratchet public key (32 bytes)
///   [32..35] — previous chain count  (UInt32 big-endian)
///   [36..39] — message number        (UInt32 big-endian)
///   [40..]   — AES-GCM combined      (nonce 12 + ciphertext + tag 16)
struct EncryptedMessage {
    let dhPublicKey: Data      // 32 bytes
    let previousCount: UInt32
    let messageNumber: UInt32
    let ciphertext: Data       // AES-GCM combined

    /// Header bytes (bytes 0-39) — used as AES-GCM associated data.
    var headerBytes: Data {
        var d = Data(capacity: 40)
        d.append(dhPublicKey)
        d.append(contentsOf: previousCount.beBytes)
        d.append(contentsOf: messageNumber.beBytes)
        return d
    }

    var serialized: Data {
        var d = headerBytes
        d.append(ciphertext)
        return d
    }

    static func deserialize(_ data: Data) throws -> EncryptedMessage {
        guard data.count >= 41 else { throw CryptoError.invalidData }
        return EncryptedMessage(
            dhPublicKey: Data(data[0..<32]),
            previousCount: UInt32(beBytes: data[32..<36]),
            messageNumber: UInt32(beBytes: data[36..<40]),
            ciphertext: Data(data[40...])
        )
    }
}

// MARK: - Double Ratchet state machine

struct DoubleRatchet: Codable {

    // Spec-defined maximum skipped messages per chain to bound stored keys.
    private static let maxSkip = 100

    var dhSending: RatchetKeyPair           // Our current DH ratchet key pair
    var dhRemote: Data?                     // Remote's current DH ratchet public key
    var rootKey: Data                       // 32-byte root key
    var sendingChainKey: Data?              // 32-byte sending chain key
    var receivingChainKey: Data?            // 32-byte receiving chain key
    var sendCount: UInt32 = 0              // Messages sent in current sending chain
    var receiveCount: UInt32 = 0           // Messages received in current receiving chain
    var previousSendCount: UInt32 = 0      // Messages sent in previous sending chain
    var skippedKeys: [SkippedKeyID: Data] = [:]  // Out-of-order message keys

    // MARK: - KDF helpers

    /// KDF_RK: HKDF-SHA256 with the current root key as HKDF salt.
    private static func kdfRK(rootKey: Data, dhOutput: Data) -> (rootKey: Data, chainKey: Data) {
        let out = CryptoBox.hkdf(
            inputKeyMaterial: dhOutput,
            salt: rootKey,
            info: Data("PrivaMesh-DR-RK".utf8),
            outputByteCount: 64
        )
        return (Data(out[..<32]), Data(out[32...]))
    }

    /// KDF_CK: one HMAC-SHA256 step advances the chain and produces a message key.
    private static func kdfCK(_ chainKey: Data) -> (nextChainKey: Data, messageKey: Data) {
        let mk = CryptoBox.hmac(key: chainKey, message: Data([0x01]))
        let ck = CryptoBox.hmac(key: chainKey, message: Data([0x02]))
        return (ck, mk)
    }

    // MARK: - Initialization

    /// Alice (sender) initializes after computing X3DH shared secret.
    /// - Parameters:
    ///   - sharedSecret: 32-byte SK from X3DH
    ///   - remoteSPKPublic: Bob's signed-prekey public key (becomes initial DHr)
    static func initSender(sharedSecret: Data, remoteSPKPublic: Data) throws -> DoubleRatchet {
        let dhS = RatchetKeyPair()
        let remKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteSPKPublic)
        let dhOut = try CryptoBox.dh(privateKey: dhS.privateKey(), publicKey: remKey)
        let (rk, cks) = kdfRK(rootKey: sharedSecret, dhOutput: dhOut)

        return DoubleRatchet(
            dhSending: dhS,
            dhRemote: remoteSPKPublic,
            rootKey: rk,
            sendingChainKey: cks,
            receivingChainKey: nil,
            sendCount: 0, receiveCount: 0, previousSendCount: 0,
            skippedKeys: [:]
        )
    }

    /// Bob (receiver) initializes after computing X3DH shared secret.
    /// - Parameters:
    ///   - sharedSecret: 32-byte SK from X3DH
    ///   - localSPK: Bob's signed-prekey private key (becomes initial DHs)
    static func initReceiver(sharedSecret: Data, localSPK: Curve25519.KeyAgreement.PrivateKey) -> DoubleRatchet {
        DoubleRatchet(
            dhSending: RatchetKeyPair(privateKey: localSPK),
            dhRemote: nil,
            rootKey: sharedSecret,
            sendingChainKey: nil,
            receivingChainKey: nil,
            sendCount: 0, receiveCount: 0, previousSendCount: 0,
            skippedKeys: [:]
        )
    }

    // MARK: - Encrypt

    /// Encrypt plaintext. The plaintext should already be padded via MessagePadding.pad.
    mutating func encrypt(plaintext: Data) throws -> EncryptedMessage {
        guard let ck = sendingChainKey else { throw CryptoError.missingChainKey }
        let (nextCK, mk) = Self.kdfCK(ck)
        sendingChainKey = nextCK

        let msg = EncryptedMessage(
            dhPublicKey: dhSending.publicKeyData,
            previousCount: previousSendCount,
            messageNumber: sendCount,
            ciphertext: Data()  // placeholder to build header bytes
        )
        sendCount += 1

        let ct = try CryptoBox.encrypt(plaintext: plaintext, key: mk, associatedData: msg.headerBytes)

        return EncryptedMessage(
            dhPublicKey: msg.dhPublicKey,
            previousCount: msg.previousCount,
            messageNumber: msg.messageNumber,
            ciphertext: ct
        )
    }

    // MARK: - Decrypt

    /// Decrypt a received message. Handles DH ratchet steps and out-of-order delivery.
    mutating func decrypt(message: EncryptedMessage) throws -> Data {
        // 1. Check skipped message key cache
        let skipID = SkippedKeyID(dhPublicKey: message.dhPublicKey, messageNumber: message.messageNumber)
        if let mk = skippedKeys[skipID] {
            skippedKeys.removeValue(forKey: skipID)
            return try CryptoBox.decrypt(combined: message.ciphertext, key: mk, associatedData: message.headerBytes)
        }

        // 2. DH ratchet step if sender used a new DH key
        if message.dhPublicKey != dhRemote {
            try skipMessageKeys(until: message.previousCount)
            try dhRatchetStep(newRemotePK: message.dhPublicKey)
        }

        // 3. Skip any messages in the receiving chain up to this one
        try skipMessageKeys(until: message.messageNumber)

        // 4. Advance receiving chain
        guard let ck = receivingChainKey else { throw CryptoError.missingChainKey }
        let (nextCK, mk) = Self.kdfCK(ck)
        receivingChainKey = nextCK
        receiveCount += 1

        return try CryptoBox.decrypt(combined: message.ciphertext, key: mk, associatedData: message.headerBytes)
    }

    // MARK: - Private helpers

    private mutating func skipMessageKeys(until targetCount: UInt32) throws {
        guard let ck = receivingChainKey, let remDH = dhRemote else { return }
        guard targetCount <= receiveCount + UInt32(Self.maxSkip) else {
            throw CryptoError.tooManySkippedMessages
        }
        var currentCK = ck
        while receiveCount < targetCount {
            let (nextCK, mk) = Self.kdfCK(currentCK)
            skippedKeys[SkippedKeyID(dhPublicKey: remDH, messageNumber: receiveCount)] = mk
            currentCK = nextCK
            receiveCount += 1
        }
        receivingChainKey = currentCK
    }

    private mutating func dhRatchetStep(newRemotePK: Data) throws {
        let remKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: newRemotePK)

        // Finish old sending chain
        previousSendCount = sendCount
        sendCount = 0
        receiveCount = 0
        dhRemote = newRemotePK

        // Receiving chain: DH with our current sending key pair
        let dhOut1 = try CryptoBox.dh(privateKey: dhSending.privateKey(), publicKey: remKey)
        let (rk1, ckr) = Self.kdfRK(rootKey: rootKey, dhOutput: dhOut1)
        rootKey = rk1
        receivingChainKey = ckr

        // Generate new sending key pair
        dhSending = RatchetKeyPair()

        // Sending chain: DH with our new key pair
        let dhOut2 = try CryptoBox.dh(privateKey: dhSending.privateKey(), publicKey: remKey)
        let (rk2, cks) = Self.kdfRK(rootKey: rootKey, dhOutput: dhOut2)
        rootKey = rk2
        sendingChainKey = cks
    }
}

// MARK: - UInt32 big-endian helpers

private extension UInt32 {
    var beBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >>  8) & 0xFF),
            UInt8( self        & 0xFF)
        ]
    }

    init(beBytes slice: Data) {
        let b = Array(slice)
        self = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }
}
