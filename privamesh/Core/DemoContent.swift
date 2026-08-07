//
//  DemoContent.swift
//  privamesh
//
//  App Review demo. Chats and contacts are stored only on-device and never sync,
//  so a restored seed alone shows an empty app. To let App Review verify every
//  feature, the DEMO identity gets a realistic, pre-filled set of contacts and
//  two-way conversations seeded locally (nothing is sent on-chain, nothing
//  leaves the device). This is a review aid only; it triggers exclusively for
//  the one demo account whose address derives from the demo seed phrase.
//
//  Seeding runs on EVERY activation of the demo account (launch, account switch,
//  onboarding import), not just at import time — so however the reviewer signs
//  in, the account is populated. It is idempotent: a person is inserted only
//  when that contact row is missing.
//

import Foundation
import SwiftData
import SolanaSwift

enum DemoContent {
    /// The demo identity's seed phrase. Restoring it in the app populates the
    /// sample content below. Shared with App Review in the review notes.
    static let demoPhrase = ["drum", "need", "person", "expire", "large", "wrist",
                             "struggle", "labor", "label", "ill", "improve", "cloud"]

    /// Developer account the reviewer can also message live (searchable by nick).
    static let decartAddress = "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V"

    /// Cached wallet address of the demo seed. Derivation is BIP39 + ed25519, so
    /// it happens once per install and the answer is remembered.
    private static let addressKey = "privamesh.demoAccountAddress"

    static func isDemoPhrase(_ words: [String]) -> Bool {
        let a = words.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return a == demoPhrase
    }

    /// The demo seed's Solana address, derived once and cached.
    static func demoAddress() async -> String {
        if let cached = UserDefaults.standard.string(forKey: addressKey), !cached.isEmpty {
            return cached
        }
        guard let keypair = try? await KeyPair(phrase: demoPhrase,
                                               network: .mainnetBeta,
                                               derivablePath: .default) else { return "" }
        let pub = keypair.publicKey.base58EncodedString
        UserDefaults.standard.set(pub, forKey: addressKey)
        return pub
    }

    /// Seed the sample content if `address` is the demo account. Cheap and safe
    /// to call on every account activation.
    @MainActor
    static func populateIfDemo(address: String, context: ModelContext) async {
        guard !address.isEmpty else { return }
        guard await demoAddress() == address else { return }
        populate(ownerAddress: address, context: context)
    }

    // MARK: - Sample content

    /// One scripted conversation.
    private struct Person {
        let id: String
        let name: String
        let nick: String
        let premium: Bool
        let note: String
        let favourite: Bool
        let circle: Bool
        /// Minutes ago the LAST message landed; earlier ones are spaced back.
        let minsAgo: Int
        /// Trailing incoming messages left unread.
        let unread: Int
        /// (text, isOutgoing)
        let script: [(String, Bool)]
    }

    private static var people: [Person] {
        [
            Person(id: "DemoA1iceHphM3sh2ndKqR7tWpXyZaBcDeFgHjKmNpQr",
                   name: "Alice", nick: "alice", premium: true, note: "college",
                   favourite: true, circle: true, minsAgo: 4, unread: 2,
                   script: [
                    ("Hey! Have you tried PrivaMesh?", false),
                    ("Yes — no phone number, no email. Just a key 🔐", true),
                    ("And it's free to start, no sign-up at all.", false),
                    ("Exactly. I open it and message, that's it.", true),
                    ("Sending you the meetup address in a sec", false),
                    ("Here it is — see you at seven?", false),
                   ]),
            Person(id: "DemoB0bMessengerKqR7tWpXyZaBcDeFgHjKmNpQrStu",
                   name: "Bob", nick: "bob", premium: false, note: "work",
                   favourite: true, circle: true, minsAgo: 26, unread: 1,
                   script: [
                    ("Sending you the notes now.", true),
                    ("Got them, thanks!", false),
                    ("Everything is end-to-end encrypted, right?", false),
                    ("Yep — X3DH + Double Ratchet. Only you can read them.", true),
                    ("Nice. Can I read the old ones on a new phone?", false),
                    ("No — history stays on the device. That's the point.", true),
                    ("Makes sense. Ping me tomorrow morning?", false),
                   ]),
            Person(id: decartAddress,
                   name: "Decart", nick: "Decart", premium: true,
                   note: "developer — you can message this account live",
                   favourite: true, circle: true, minsAgo: 55, unread: 2,
                   script: [
                    ("Welcome to PrivaMesh! This is the developer account.", false),
                    ("You can reply here to test live messaging.", false),
                   ]),
            Person(id: "DemoC1araNodeMeshQrStUvWxYz1aBcDeFgHjKmNpQrS",
                   name: "Clara", nick: "clara", premium: false, note: "gym",
                   favourite: false, circle: true, minsAgo: 95, unread: 0,
                   script: [
                    ("Are we still on for tomorrow?", false),
                    ("Yes, same time.", true),
                    ("Perfect 🙌", false),
                    ("I'll bring the tickets.", true),
                   ]),
            Person(id: "DemoD4nielPrivaKeyStUvWxYz1aBcDeFgHjKmNpQrSt",
                   name: "Daniel", nick: "daniel", premium: true, note: "",
                   favourite: false, circle: true, minsAgo: 240, unread: 0,
                   script: [
                    ("Did the photo come through?", true),
                    ("Yes — opened fine, thanks.", false),
                    ("Photos are encrypted too; only the key travels with the message.", true),
                    ("Good. Nothing sitting on a server then.", false),
                   ]),
            Person(id: "DemoE11aSignalPathUvWxYz1aBcDeFgHjKmNpQrStUv",
                   name: "Ella", nick: "ella", premium: false, note: "",
                   favourite: false, circle: true, minsAgo: 620, unread: 0,
                   script: [
                    ("Landed. Texting you when I'm home.", false),
                    ("Safe trip! 👋", true),
                    ("Home. All good.", false),
                   ]),
            Person(id: "DemoF3lixQuietLineWxYz1aBcDeFgHjKmNpQrStUvWx",
                   name: "Felix", nick: "felix", premium: false, note: "",
                   favourite: false, circle: false, minsAgo: 1_500, unread: 0,
                   script: [
                    ("Can you send the address again?", false),
                    ("Sent — check the message above.", true),
                    ("Found it, thanks.", false),
                   ]),
            Person(id: "DemoG1naOffGridChanYz1aBcDeFgHjKmNpQrStUvWxY",
                   name: "Gina", nick: "gina", premium: true, note: "",
                   favourite: false, circle: false, minsAgo: 2_800, unread: 0,
                   script: [
                    ("Long time no see!", false),
                    ("Way too long. Coffee next week?", true),
                    ("Deal 🙂", false),
                   ]),
            Person(id: "DemoH3nryDarkMeshZ1aBcDeFgHjKmNpQrStUvWxYzA",
                   name: "Henry", nick: "henry", premium: false, note: "",
                   favourite: false, circle: false, minsAgo: 5_400, unread: 0,
                   script: [
                    ("Sent you the files — take a look.", false),
                    ("Got them. Will review tonight.", true),
                   ]),
        ]
    }

    /// Populate sample contacts + chat history for the demo account. Idempotent:
    /// each person is inserted only if that contact row is missing, so the
    /// auto-created "Saved Messages" contact never blocks seeding, and a relaunch
    /// restores anything the reviewer cleared.
    @MainActor
    static func populate(ownerAddress: String, context: ModelContext) {
        guard !ownerAddress.isEmpty else { return }

        let existingIDs = Set(((try? context.fetch(FetchDescriptor<Contact>())) ?? [])
            .filter { $0.ownerAddress == ownerAddress }
            .map(\.id))

        var inserted = false
        for p in people where !existingIDs.contains(p.id) {
            insert(p, ownerAddress: ownerAddress, context: context)
            inserted = true
        }
        guard inserted else { return }
        try? context.save()
    }

    @MainActor
    private static func insert(_ p: Person, ownerAddress: String, context: ModelContext) {
        // A real, locally generated bundle: the contact behaves like any other one
        // in the UI (profile, safety details) instead of a half-filled row.
        let bundle = (try? CryptoIdentity.generate().prekeyBundle().base64Encoded) ?? ""

        let c = Contact(id: p.id, displayName: p.name, prekeyBundleBase64: bundle)
        c.ownerAddress = ownerAddress
        c.myNote = p.note
        c.isFavourite = p.favourite
        c.inCircle = p.circle
        var snap = ProfileSnapshot()
        snap.nickname = p.nick
        snap.isPremium = p.premium
        c.profileData = try? JSONEncoder().encode(snap)
        c.createdAt = Date().addingTimeInterval(-Double(p.minsAgo) * 60
                                                - Double(p.script.count) * 900 - 86_400)
        context.insert(c)

        // Oldest first, 15 min apart; the last `unread` incoming ones stay unopened.
        for (i, line) in p.script.enumerated() {
            let (body, outgoing) = line
            let fromEnd = p.script.count - 1 - i
            let at = Date().addingTimeInterval(-Double(p.minsAgo) * 60 - Double(fromEnd) * 900)
            let m = ChatMessage(id: "demo-\(p.id)-\(i)", body: body, isOutgoing: outgoing,
                                sentAt: at, status: outgoing ? "sent" : "received")
            m.isRead = outgoing || fromEnd >= p.unread
            m.contact = c
            context.insert(m)
        }
    }
}
