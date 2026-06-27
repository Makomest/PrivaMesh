//
//  Contact.swift
//  privamesh
//

import Foundation
import SwiftData

@Model
final class Contact {
    @Attribute(.unique) var id: String      // recipient's Solana public key
    var displayName: String
    var prekeyBundleBase64: String          // their PrekeyBundle, JSON-encoded then base64
    var sessionData: Data?                  // serialized DoubleRatchet state (JSONEncoder)
    var myEphemeralKeyData: Data?           // my EK_A raw bytes used in X3DH
    var isSessionEstablished: Bool = false
    var stealthRoot: Data?                  // shared root for one-time addresses (HKDF of X3DH SK)
    var isInitiator: Bool = false           // true if I started this session (X3DH sender)
    var sendIndex: Int = 0                  // next index on MY outgoing stealth chain
    var recvIndex: Int = 0                  // next expected index on THEIR stealth chain
    var isSelf: Bool = false               // true for the "Saved Messages" self-contact
    var profileData: Data?                 // encoded ProfileSnapshot shared via ContactCard
    var ownerAddress: String = ""          // which account (wallet address) owns this chat
    var myNote: String = ""                // your private short note about this contact
    var isMuted: Bool = false              // suppress notifications from this contact
    var isBlocked: Bool = false            // stop receiving from + hide this contact (UGC moderation)
    var disappearSeconds: Int = 0          // 0 = off; else auto-delete local msgs older than this
    var paymentAddress: String = ""        // their real main wallet (from encrypted payload); for in-chat SOL
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var messages: [ChatMessage] = []

    init(id: String, displayName: String, prekeyBundleBase64: String) {
        self.id = id
        self.displayName = displayName
        self.prekeyBundleBase64 = prekeyBundleBase64
        self.createdAt = Date()
    }

    var lastMessage: ChatMessage? {
        messages.max { $0.sentAt < $1.sentAt }
    }

    /// Incoming messages not yet opened.
    var unreadCount: Int {
        messages.reduce(0) { $0 + (!$1.isOutgoing && !$1.isRead ? 1 : 0) }
    }

    /// Where to send this contact in-chat SOL: their real main wallet if known
    /// (learned from the encrypted payload), else the contact id.
    var payTo: String { paymentAddress.isEmpty ? id : paymentAddress }

    /// My outgoing stealth chain label (the one I send on).
    var myStealthLabel: String {
        isInitiator ? StealthAddress.initiatorToResponder : StealthAddress.responderToInitiator
    }
    /// Their stealth chain label (the one I poll for incoming).
    var theirStealthLabel: String {
        isInitiator ? StealthAddress.responderToInitiator : StealthAddress.initiatorToResponder
    }

    /// Decoded public profile snapshot, if the contact shared one.
    var profile: ProfileSnapshot? {
        guard let data = profileData else { return nil }
        return try? JSONDecoder().decode(ProfileSnapshot.self, from: data)
    }

    /// The contact's own NFT/display nickname (from their shared profile).
    var nftNick: String? {
        guard let n = profile?.nickname, !n.isEmpty else { return nil }
        return n
    }
    /// Primary line: their own nick if known, else the name you saved.
    var primaryName: String { nftNick ?? displayName }
    /// Secondary line: the name you saved — only when it differs from the nick.
    var secondaryName: String? {
        guard let nick = nftNick, nick != displayName else { return nil }
        return displayName
    }
}
