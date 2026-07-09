//
//  DemoContent.swift
//  privamesh
//
//  App Review demo. Chats and contacts are stored only on-device and never sync,
//  so a restored seed alone shows an empty app. To let App Review verify every
//  feature, restoring the DEMO seed phrase populates a realistic, pre-filled set
//  of contacts and two-way conversations locally (nothing is sent on-chain).
//  This is a review aid only; it triggers exclusively for the demo identity.
//

import Foundation
import SwiftData

enum DemoContent {
    /// The demo identity's seed phrase. Restoring it in the app populates the
    /// sample content below. Shared with App Review in the review notes.
    static let demoPhrase = ["drum", "need", "person", "expire", "large", "wrist",
                             "struggle", "labor", "label", "ill", "improve", "cloud"]

    /// Developer account the reviewer can also message live (searchable by nick).
    static let decartAddress = "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V"

    static func isDemoPhrase(_ words: [String]) -> Bool {
        let a = words.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return a == demoPhrase
    }

    /// Populate sample contacts + chat history for the demo account. Idempotent:
    /// does nothing if this owner already has contacts.
    @MainActor
    static func populate(ownerAddress: String, context: ModelContext) {
        guard !ownerAddress.isEmpty else { return }
        // Skip if this account already has any contacts (avoid duplicates).
        let existing = (try? context.fetch(FetchDescriptor<Contact>()))?.filter { $0.ownerAddress == ownerAddress } ?? []
        guard existing.isEmpty else { return }

        func profile(nick: String, premium: Bool) -> Data? {
            var snap = ProfileSnapshot()
            snap.nickname = nick
            snap.isPremium = premium
            return try? JSONEncoder().encode(snap)
        }

        func makeContact(id: String, name: String, nick: String, premium: Bool,
                         note: String, messages: [(String, Bool, Int)]) {
            let c = Contact(id: id, displayName: name, prekeyBundleBase64: "")
            c.ownerAddress = ownerAddress
            c.profileData = profile(nick: nick, premium: premium)
            c.myNote = note
            c.createdAt = Date().addingTimeInterval(-Double(messages.count) * 3600 - 86_400)
            context.insert(c)
            for (i, m) in messages.enumerated() {
                let (body, outgoing, minsAgo) = (m.0, m.1, m.2)
                let msg = ChatMessage(id: "demo-\(id)-\(i)", body: body, isOutgoing: outgoing,
                                      sentAt: Date().addingTimeInterval(-Double(minsAgo) * 60),
                                      status: outgoing ? "sent" : "received")
                msg.isRead = true
                msg.contact = c
                context.insert(msg)
            }
        }

        makeContact(
            id: "DemoA1iceHphM3sh2ndKqR7tWpXyZaBcDeFgHjKmNpQr",
            name: "Alice", nick: "alice", premium: true,
            note: "verified member",
            messages: [
                ("Hey! Have you tried PrivaMesh?", false, 240),
                ("Yes — no phone number, no email. Just a key 🔐", true, 236),
                ("And the fees are paid for us, no crypto needed.", false, 232),
                ("Exactly. I just message, that's it.", true, 230),
            ])

        makeContact(
            id: "DemoB0bMessengerKqR7tWpXyZaBcDeFgHjKmNpQrStu",
            name: "Bob", nick: "bob", premium: false,
            note: "",
            messages: [
                ("Sending you the notes now.", true, 120),
                ("Got them, thanks!", false, 118),
                ("Everything is end-to-end encrypted, right?", false, 60),
                ("Yep — X3DH + Double Ratchet. Only you can read them.", true, 58),
            ])

        makeContact(
            id: decartAddress,
            name: "Decart", nick: "Decart", premium: true,
            note: "developer — you can message this account live",
            messages: [
                ("Welcome to PrivaMesh! This is the developer account.", false, 30),
                ("You can reply here to test live messaging.", false, 29),
            ])

        try? context.save()
    }
}
