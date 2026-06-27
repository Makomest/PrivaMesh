//
//  MessagePadding.swift
//  privamesh
//
//  Pads plaintext to fixed-size buckets before encryption to prevent
//  message-length traffic analysis.
//

import Foundation

enum MessagePadding {
    /// Bucket sizes in bytes. Plaintext is padded up to the nearest bucket.
    /// Capped at 512: larger buckets produce memos that exceed Solana's 1232-byte tx limit.
    static let buckets: [Int] = [32, 64, 128, 256, 512]

    /// Maximum raw plaintext bytes that safely fit in a Solana memo transaction.
    static let maxPlaintextBytes = 460

    /// Pad data to the next bucket boundary using ISO/IEC 7816-4 padding:
    /// append 0x80 followed by 0x00 bytes.
    static func pad(_ data: Data) -> Data {
        let clamped = data.count > maxPlaintextBytes ? Data(data.prefix(maxPlaintextBytes)) : data
        let needed = clamped.count + 1  // at least 1 byte for the 0x80 marker
        let target = buckets.first { $0 >= needed } ?? 512
        var padded = clamped
        padded.append(0x80)
        while padded.count < target {
            padded.append(0x00)
        }
        return padded
    }

    /// Remove padding. Throws if the padding marker is absent.
    static func unpad(_ data: Data) throws -> Data {
        guard let markerIndex = data.lastIndex(where: { $0 != 0x00 }) else {
            throw CryptoError.invalidPadding
        }
        guard data[markerIndex] == 0x80 else {
            throw CryptoError.invalidPadding
        }
        return Data(data[..<markerIndex])
    }
}
