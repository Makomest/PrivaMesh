//
//  Contact.swift
//  privamesh
//

import CryptoKit
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
    /// The messaging identity key this contact was last seen using. A session-init
    /// carrying a different one means they reinstalled, switched device, or someone
    /// took their place — and the user has to be told either way, because a safety
    /// number checked once is worthless if the key can be replaced in silence.
    var knownIdentityKey: Data?
    /// Set when `knownIdentityKey` changed under us and cleared once the user has
    /// seen it. Blocks nothing by itself; the chat shows a banner while it is set.
    var keyChangedAt: Date?
    /// Digests of session-opening envelopes already accepted from this contact.
    ///
    /// A session-init is self-contained by design: it carries everything needed
    /// to derive the shared secret, so it decrypts again every time it is seen.
    /// Replay detection used to rely on the Solana transaction signature, and a
    /// copy of the same memo in a new transaction has a new signature - so anyone
    /// who could read the public chain could make an old opener reappear as a new
    /// message from a trusted contact, and replace the live ratchet with it.
    /// Reported by Mudit (mudit.raj32@gmail.com).
    ///
    /// Stored as concatenated 32-byte SHA-256 digests, newest last, capped at
    /// `Contact.maxConsumedInits`. See `hasConsumedSessionInit` / `noteConsumedSessionInit`.
    var consumedInitDigests: Data?

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

// MARK: - Session-init replay protection

extension Contact {
    /// How many openers to remember. Enough for a contact who legitimately
    /// re-initialises a session now and then, small enough that the row stays
    /// small: 32 digests is one kilobyte.
    static let maxConsumedInits = 32

    /// Digest of the parts of a session-init that decide what it decrypts to.
    ///
    /// The sender's identity and ephemeral keys fix the X3DH secret; the
    /// ciphertext fixes the message. A replay must reproduce all three to decrypt
    /// at all, so a copy cannot dodge this by changing anything else in the
    /// envelope - and two genuinely different openers never collide.
    static func sessionInitDigest(_ envelope: MessageEnvelope) -> Data {
        var input = Data()
        input.append(envelope.senderIdentityPublic ?? Data())
        input.append(envelope.senderEphemeralPublic ?? Data())
        // The ratchet header is inside the digest too: it is authenticated as
        // associated data, so a replay cannot alter it either.
        input.append(envelope.message.headerBytes)
        input.append(envelope.message.ciphertext)
        return Data(SHA256.hash(data: input))
    }

    func hasConsumedSessionInit(_ digest: Data) -> Bool {
        guard let stored = consumedInitDigests, !stored.isEmpty else { return false }
        return stride(from: 0, to: stored.count, by: 32).contains { offset in
            guard offset + 32 <= stored.count else { return false }
            return stored[offset..<(offset + 32)] == digest
        }
    }

    /// Record an opener as used. Oldest entries fall off the front.
    func noteConsumedSessionInit(_ digest: Data) {
        var stored = consumedInitDigests ?? Data()
        stored.append(digest)
        let maxBytes = Contact.maxConsumedInits * 32
        if stored.count > maxBytes {
            stored = Data(stored.suffix(maxBytes))
        }
        consumedInitDigests = stored
    }
}
