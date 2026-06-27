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
    }

    let kind: Kind
    let senderIdentityPublic: Data?    // 32 bytes, only present for sessionInit
    let senderEphemeralPublic: Data?   // 32 bytes, only present for sessionInit
    let message: EncryptedMessage

    // MARK: - Serialization

    func serialize() -> Data {
        var d = Data()
        d.append(kind.rawValue)
        if kind == .sessionInit {
            d.append(senderIdentityPublic!)
            d.append(senderEphemeralPublic!)
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
        }
    }
}
