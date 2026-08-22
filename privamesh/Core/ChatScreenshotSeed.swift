//
//  ChatScreenshotSeed.swift
//  privamesh
//
//  DEBUG-only. Seeds ONE conversation and opens it, so the same chat can be
//  captured from both sides: run with `-chatShot a` for Alex's phone and
//  `-chatShot b` for Emma's. The script is identical in both, only the direction
//  of each message flips, which is what makes the two screenshots line up.
//
//  Never compiled into a release build.
//

#if DEBUG
import Foundation
import SwiftData

enum ChatScreenshotSeed {

    /// Which phone we are pretending to be.
    enum Side: String { case a, b }

    static var requestedSide: Side? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-chatShot"), i + 1 < args.count else { return nil }
        return Side(rawValue: args[i + 1].lowercased())
    }

    /// The two people in the conversation.
    private static let alex = (id: "ShotA1exQuietLineKqR7tWpXyZaBcDeFgHjKmNpQr", name: "Alex", nick: "alex")
    private static let emma = (id: "ShotE44maMeshWaveStUvWxYz1aBcDeFgHjKmNpQrS", name: "Emma", nick: "emma")

    /// (text, sentByAlex, minutesAgo) — one script, read from either end.
    private static let script: [(String, Bool, Int)] = [
        ("hey, did you get home ok yesterday?",                 false, 196),
        ("yeah, ended up walking. it was warmer than i thought", true, 192),
        ("nice. also i finally moved off the group chat",        false, 180),
        ("this one?",                                            true, 176),
        ("yep. no phone number, nothing on a server",            false, 172),
        ("took me a day to stop looking for account settings 😅", false, 170),
        ("ha. there aren't any, that's the point",               true, 166),
        ("anyway, thursday still good for dinner?",              false, 24),
        ("thursday works. 7?",                                   true, 20),
        ("7 is perfect. i'll book it",                           false, 16),
        ("see you then 👋",                                      true, 12),
    ]

    /// Insert the conversation for `side` and return the contact whose chat should
    /// be opened. Idempotent per side.
    @MainActor
    static func seed(side: Side, ownerAddress: String, context: ModelContext) -> Contact? {
        // From Alex's phone the other person is Emma, and vice versa.
        let peer = (side == .a) ? emma : alex
        let iAmAlex = (side == .a)

        let existing = (try? context.fetch(FetchDescriptor<Contact>()))?
            .first { $0.id == peer.id && $0.ownerAddress == ownerAddress }
        if let existing {
            // Older runs seeded this contact without a key; give it one so the
            // screens that need it are not stuck on their empty state.
            if existing.prekeyBundleBase64.isEmpty,
               let bundle = try? CryptoIdentity.generate().prekeyBundle().base64Encoded {
                existing.prekeyBundleBase64 = bundle
                try? context.save()
            }
            return existing
        }

        // A real bundle, so screens that depend on the contact's keys (safety
        // number, session details) show what they would in a live conversation
        // instead of their empty state.
        let bundle = (try? CryptoIdentity.generate().prekeyBundle().base64Encoded) ?? ""
        let contact = Contact(id: peer.id, displayName: peer.name, prekeyBundleBase64: bundle)
        contact.ownerAddress = ownerAddress
        contact.isFavourite = true
        contact.inCircle = true
        var snap = ProfileSnapshot()
        snap.nickname = peer.nick
        contact.profileData = try? JSONEncoder().encode(snap)
        contact.createdAt = Date().addingTimeInterval(-90_000)
        context.insert(contact)

        for (i, line) in script.enumerated() {
            let (body, sentByAlex, minsAgo) = line
            // The same line is outgoing on one phone and incoming on the other.
            let outgoing = (sentByAlex == iAmAlex)
            let m = ChatMessage(id: "shot-\(side.rawValue)-\(i)", body: body, isOutgoing: outgoing,
                                sentAt: Date().addingTimeInterval(-Double(minsAgo) * 60),
                                status: outgoing ? "sent" : "received")
            m.isRead = true
            m.contact = contact
            context.insert(m)
        }
        try? context.save()
        return contact
    }
}
#endif
