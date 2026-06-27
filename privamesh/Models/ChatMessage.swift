//
//  ChatMessage.swift
//  privamesh
//

import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: String          // Solana transaction signature
    var body: String        // text content OR Arweave TX ID for photo messages
    var photoKey: String?   // nil = text message; base64 AES-256-GCM key = photo message
    var isOutgoing: Bool
    var sentAt: Date
    var status: String      // "sending" | "sent" | "received" | "failed"

    /// Network fee paid for an outgoing message, in lamports. nil for received
    /// messages (the sender paid) or legacy rows.
    var feeLamports: Int?
    /// Wall-clock seconds from tapping send until the signature returned.
    /// nil for received messages or legacy rows.
    var deliverySeconds: Double?

    /// false only for incoming messages not yet opened. Defaults true so
    /// outgoing/self/legacy rows never count as unread.
    var isRead: Bool = true

    /// "text" | "photo" | "sol" | "gift"
    var kind: String = "text"
    // .sol
    var solAmount: Double?
    // .gift
    var giftKind: String?     // "avatar" | "nickname"
    var giftRef: String?
    var giftName: String?
    var giftRarity: String?
    var giftClaimed: Bool = false

    var contact: Contact?

    init(id: String, body: String, photoKey: String? = nil, isOutgoing: Bool, sentAt: Date, status: String = "sending") {
        self.id = id
        self.body = body
        self.photoKey = photoKey
        self.isOutgoing = isOutgoing
        self.sentAt = sentAt
        self.status = status
    }
}
