//
//  MessageEnvelope.swift
//  privamesh
//
//  Wire format wrapper around EncryptedMessage that is placed in the Solana Memo.
//
//  SessionInit envelope (first message to a contact):
//    [0x01] [IK_A: 32 bytes] [EK_A: 32 bytes] [EncryptedMessage bytes]
//
//  Regular envelope (subsequent messages):
//    [0x00] [EncryptedMessage bytes]
//
//  The whole envelope is base64-encoded before being written to the Memo instruction.
//

import Foundation

struct MessageEnvelope {
    enum Kind: UInt8 {
        case regular    = 0x00
        case sessionInit = 0x01
        /// Post-quantum session init: like sessionInit but also carries an off-chain
        /// (Irys) reference to the X-Wing KEM ciphertext, which is too large (~1.1KB)
        /// for a Solana memo. Only ever sent new-build → new-build (the initiator
        /// uses it solely when the contact published a PQ prekey), so an older build
        /// never has to parse it. See PQXDH.
        case sessionInitPQ = 0x02
    }

    let kind: Kind
    let senderIdentityPublic: Data?    // 32 bytes, only present for session init
    let senderEphemeralPublic: Data?   // 32 bytes, only present for session init
    /// Irys tx id of the X-Wing KEM ciphertext — only for `.sessionInitPQ`.
    var pqCiphertextRef: String? = nil
    let message: EncryptedMessage

    // MARK: - Serialization

    func serialize() -> Data {
        var d = Data()
        d.append(kind.rawValue)
        if kind == .sessionInit || kind == .sessionInitPQ {
            d.append(senderIdentityPublic!)
            d.append(senderEphemeralPublic!)
        }
        if kind == .sessionInitPQ {
            // 1-byte length + UTF-8 ref (Irys tx id is short and ASCII).
            let ref = Data((pqCiphertextRef ?? "").utf8)
            d.append(UInt8(min(ref.count, 255)))
            d.append(ref.prefix(255))
        }
        d.append(message.serialized)
        return d
    }

    var base64: String {
        serialize().base64EncodedString()
    }

    // MARK: - Deserialization

    static func fromBase64(_ string: String) throws -> MessageEnvelope {
        // Solana RPC can return the memo with a byte-count prefix "[N] " — strip it.
        let cleaned = string.hasPrefix("[") ? (string.drop(while: { $0 != " " }).dropFirst().trimmingCharacters(in: .whitespaces)) : string
        guard let data = Data(base64Encoded: cleaned) else {
            throw CryptoError.invalidData
        }
        return try deserialize(data)
    }

    static func deserialize(_ data: Data) throws -> MessageEnvelope {
        guard !data.isEmpty else { throw CryptoError.invalidData }
        guard let kind = Kind(rawValue: data[0]) else { throw CryptoError.invalidData }

        switch kind {
        case .regular:
            let msg = try EncryptedMessage.deserialize(Data(data[1...]))
            return MessageEnvelope(kind: .regular, senderIdentityPublic: nil,
                                   senderEphemeralPublic: nil, message: msg)
        case .sessionInit:
            // 1 flag + 32 IK + 32 EK + at least 41 EncryptedMessage
            guard data.count >= 1 + 32 + 32 + 41 else { throw CryptoError.invalidData }
            let ik  = Data(data[1..<33])
            let ek  = Data(data[33..<65])
            let msg = try EncryptedMessage.deserialize(Data(data[65...]))
            return MessageEnvelope(kind: .sessionInit, senderIdentityPublic: ik,
                                   senderEphemeralPublic: ek, message: msg)
        case .sessionInitPQ:
            // 1 flag + 32 IK + 32 EK + 1 refLen + ref + EncryptedMessage
            guard data.count >= 1 + 32 + 32 + 1 else { throw CryptoError.invalidData }
            let ik  = Data(data[1..<33])
            let ek  = Data(data[33..<65])
            let refLen = Int(data[65])
            let refStart = 66
            guard data.count >= refStart + refLen + 41 else { throw CryptoError.invalidData }
            let ref = String(data: Data(data[refStart..<refStart+refLen]), encoding: .utf8)
            let msg = try EncryptedMessage.deserialize(Data(data[(refStart+refLen)...]))
            return MessageEnvelope(kind: .sessionInitPQ, senderIdentityPublic: ik,
                                   senderEphemeralPublic: ek, pqCiphertextRef: ref, message: msg)
        }
    }
}
