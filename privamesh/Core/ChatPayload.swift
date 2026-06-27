//
//  ChatPayload.swift
//  privamesh
//
//  Typed wrapper for Double Ratchet plaintext payloads.
//  Encoded as JSON before padding + DR encryption.
//

import Foundation

struct ChatPayload: Codable {
    enum Kind: String, Codable { case text, photo, sol, gift, cover }

    let kind: Kind
    /// Text content for .text; Arweave TX ID for .photo; a short note otherwise.
    let body: String
    /// nil for text; base64-encoded AES-256-GCM key for photo messages.
    let photoKey: String?

    // .sol
    var amountSOL: Double?
    var solSignature: String?

    // .gift  (NFT avatar or nickname you owned and gave away)
    var giftKind: String?     // "avatar" | "nickname"
    var giftRef: String?      // avatar seed (= design id) | nickname handle
    var giftName: String?
    var giftRarity: String?

    // Sender's current public identity, stamped on every message so the
    // recipient sees your real nick + NFT avatar even without your QR.
    var senderNick: String?
    var senderAvatarSeed: String?
    /// Sender's MAIN wallet address (where they receive in-chat payments). Sent
    /// inside the E2E-encrypted payload so it works even when the on-chain fee
    /// payer is a throwaway gas wallet. Lets the recipient pay the real wallet.
    var senderWallet: String?

    static func text(_ content: String) -> ChatPayload {
        ChatPayload(kind: .text, body: content, photoKey: nil)
    }

    static func photo(txId: String, key: String) -> ChatPayload {
        ChatPayload(kind: .photo, body: txId, photoKey: key)
    }

    static func sol(amount: Double, signature: String) -> ChatPayload {
        ChatPayload(kind: .sol, body: "", photoKey: nil,
                    amountSOL: amount, solSignature: signature)
    }

    static func gift(kind: String, ref: String, name: String, rarity: String?) -> ChatPayload {
        ChatPayload(kind: .gift, body: "", photoKey: nil,
                    giftKind: kind, giftRef: ref, giftName: name, giftRarity: rarity)
    }

    /// Decoy message. Carries random bytes so its ciphertext varies; the
    /// recipient decrypts it (keeping the ratchet in sync) then silently drops
    /// it. On-chain it's indistinguishable from a real DR message — it hides
    /// WHEN a real conversation happens.
    static func cover() -> ChatPayload {
        var rnd = Data(count: 24)
        _ = rnd.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 24, $0.baseAddress!) }
        return ChatPayload(kind: .cover, body: rnd.base64EncodedString(), photoKey: nil)
    }

    func encode() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decode from Double Ratchet plaintext. Falls back to plain text for legacy messages.
    static func decode(from data: Data) -> ChatPayload {
        if let p = try? JSONDecoder().decode(ChatPayload.self, from: data) { return p }
        return .text(String(data: data, encoding: .utf8) ?? "")
    }
}
