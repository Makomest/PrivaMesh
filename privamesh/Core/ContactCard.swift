//
//  ContactCard.swift
//  privamesh
//
//  QR / share payload that carries BOTH a contact's Solana wallet address and
//  their X3DH prekey bundle. The address is required to send on-chain memos
//  (the 1-lamport transfer lands in the recipient's tx history); the bundle is
//  required to encrypt. Older QRs carried only the bundle, which left contacts
//  without a valid recipient address — see [[privamesh-pubkey-validation-footgun]].
//

import Foundation
import SolanaSwift

struct ContactCard: Codable {
    /// Schema version, so future QR formats can evolve without silent misreads.
    var v: Int = 1
    /// Solana wallet address (base58) — the on-chain recipient.
    let address: String
    /// X3DH PrekeyBundle, JSON-encoded then base64.
    let bundle: String
    /// Optional public profile snapshot (bio, inventory, listings).
    var profile: ProfileSnapshot? = nil

    /// `true` if `address` decodes to a real 32-byte Solana public key.
    /// Guards against SolanaSwift's PublicKey(string:) accepting non-base58
    /// strings with empty bytes.
    var hasValidAddress: Bool {
        guard let key = try? PublicKey(string: address) else { return false }
        return key.bytes.count == PublicKey.numberOfBytes
    }

    // MARK: - QR payload (zlib-compressed JSON, base64)

    var qrPayload: String {
        guard let json = try? JSONEncoder().encode(self) else { return "" }
        if let zipped = try? (json as NSData).compressed(using: .zlib) as Data {
            return zipped.base64EncodedString()
        }
        return json.base64EncodedString()
    }

    /// Parse a scanned/pasted QR payload. Handles the compressed format and,
    /// for back-compat, plain base64 JSON.
    static func fromQRPayload(_ string: String) -> ContactCard? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else { return nil }
        if let inflated = try? (data as NSData).decompressed(using: .zlib) as Data,
           let card = try? JSONDecoder().decode(ContactCard.self, from: inflated) {
            return card
        }
        return try? JSONDecoder().decode(ContactCard.self, from: data)
    }
}
