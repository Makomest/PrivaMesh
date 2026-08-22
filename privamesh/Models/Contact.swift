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
    /// Favourite, set by hand in the contact's profile: wears a ring on the
    /// globe and never ages off it. Independent of `inCircle` — being in the
    /// curated globe does NOT make someone a favourite. Defaults false so
    /// SwiftData migrates existing stores in place.
    var isFavourite: Bool = false
    /// Member of your curated ("circle") globe — your own hand-picked collection,
    /// added via that globe's "+", separate from `isFavourite`. Nothing here ages
    /// off, and it carries no favourite status. Defaults false (in-place migration).
    var inCircle: Bool = false
    var isBlocked: Bool = false            // stop receiving from + hide this contact (UGC moderation)
    /// You compared safety numbers with this person out of band and they matched.
    /// Set by hand only: nothing in the app may mark a contact verified on the
    /// user's behalf, or the mark stops meaning anything. Defaults false so
    /// SwiftData migrates existing stores in place.
    var isVerified: Bool = false
    /// When the comparison happened, shown next to the mark.
    var verifiedAt: Date?
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

    /// How many contacts may be favourites. Small on purpose: a favourite never
    /// ages off the auto globe AND a new message must always land on it, so if
    /// favourites could fill all the auto slots an arrival would have nowhere to
    /// go. Three leaves the rest for whoever just wrote.
    static let maxFavourites = 3

    /// How many contacts your curated ("circle") globe may hold — its own,
    /// separate collection. Capped at 12: a static hub-and-spoke ring around you,
    /// twelve spokes still stay evenly spaced and readable without spin or zoom.
    static let maxCircle = 12

    /// Whether `self` may be favourited right now — already-favourite contacts
    /// always pass, so un-favouriting is never blocked.
    static func canPin(_ c: Contact, among all: [Contact]) -> Bool {
        c.isFavourite || all.filter(\.isFavourite).count < maxFavourites
    }

    /// Whether `self` may be added to the circle right now — already-in contacts
    /// always pass, so removing one is never blocked.
    static func canCircle(_ c: Contact, among all: [Contact]) -> Bool {
        c.inCircle || all.filter(\.inCircle).count < maxCircle
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
    /// Primary line — everywhere you see this contact: the name YOU saved. Giving
    /// them a custom name is exactly so that name is what shows, not their handle.
    var primaryName: String { displayName.isEmpty ? (nftNick ?? displayName) : displayName }
    /// Secondary line, shown in the profile: their OWN real nick, when you've saved
    /// a different name — so renaming a contact never hides who they actually are.
    var secondaryName: String? {
        guard let nick = nftNick, nick != displayName else { return nil }
        return nick
    }
}
