//
//  OrbitPreviewSeed.swift
//  privamesh
//
//  DEBUG-only mock data for inspecting the Orbit chat surface in isolation.
//  Launch the app with `-orbitUIPreview` to boot straight into it. Never
//  compiled into a release build.
//

#if DEBUG
import Foundation
import SwiftData

enum OrbitPreviewSeed {
    /// Simulate messages landing while you watch, so the globe's reaction to an
    /// arrival can actually be exercised. `-orbitInjectArrival` sends one from
    /// the *oldest* contact (who has aged off the sphere); `-orbitInjectSpam`
    /// sends a burst from several, which must NOT set the globe spinning.
    @MainActor
    static func injectArrivals(context: ModelContext, spam: Bool) async {
        try? await Task.sleep(for: .seconds(6))
        let all = (try? context.fetch(FetchDescriptor<Contact>()))?
            .filter { $0.ownerAddress.isEmpty && !$0.isSelf } ?? []
        // Oldest last-message first — these are the list-only ones.
        let oldest = all.sorted {
            ($0.lastMessage?.sentAt ?? .distantPast) < ($1.lastMessage?.sentAt ?? .distantPast)
        }
        guard !oldest.isEmpty else { return }

        let english = CommandLine.arguments.contains("-orbitEnglish")
        let senders = spam ? Array(oldest.prefix(5)) : [oldest[0]]
        for (i, c) in senders.enumerated() {
            let body = spam ? (english ? "Spam \(i+1)" : "Спам \(i+1)")
                            : (english ? "Long time no see!" : "Давно не виделись")
            let m = ChatMessage(id: "inject-\(UUID().uuidString)",
                                body: body,
                                isOutgoing: false, sentAt: Date(), status: "received")
            m.isRead = false
            m.contact = c
            context.insert(m)
            try? context.save()
            if spam { try? await Task.sleep(for: .milliseconds(700)) }
        }
    }

    /// The harness has no account, so the free allowance resolves to 0 and the
    /// balance pill reads as broken. Credit a pack so the chrome shows a real
    /// number. Preview only.
    @MainActor
    static func seedQuota(_ quota: MessageQuotaService) {
        if quota.remaining == 0 { quota.creditPack(128) }
    }

    /// Contacts owned by "" so they pass OrbitChatsView's owner filter when no
    /// wallet is loaded. Idempotent — safe to call on every launch.
    ///
    /// `-orbitSeedCount N` seeds only the first N people, so the globe's growth
    /// stages (0 contacts → just the "+", 1, 2, … 16 = the full lattice) can each
    /// be inspected. Absent, all of them are seeded.
    @MainActor
    static func populate(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        guard existing.filter({ $0.ownerAddress.isEmpty }).isEmpty else { return }

        let args = CommandLine.arguments
        let limit: Int? = args.firstIndex(of: "-orbitSeedCount")
            .flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil }
        let english = args.contains("-orbitEnglish")

        // name, message count (drives node size + front-pole gravity),
        // unread incoming, minutes since last message
        let russian: [(String, Int, Int, Int)] = [
            ("Лина",   14, 3,   4), ("Артём",  11, 0,  35), ("Соня",    9, 2,  12),
            ("Марк",    8, 0, 180), ("Даша",    7, 5,   2), ("Кирилл",  6, 0, 420),
            ("Ника",    6, 1,  48), ("Гоша",    5, 0, 900), ("Вера",    5, 2,  20),
            ("Паша",    4, 0, 260), ("Юля",     4, 1,   8), ("Тимур",   3, 0, 640),
            ("Оля",     3, 0,   6), ("Женя",    3, 0, 1500), ("Рома",    2, 0, 2600),
            ("Катя",    2, 1,  90),
        ]
        let englishPeople: [(String, Int, Int, Int)] = [
            ("Emma",    14, 3,   4), ("Liam",   11, 0,  35), ("Olivia",   9, 2,  12),
            ("Noah",     8, 0, 180), ("Ava",     7, 5,   2), ("James",    6, 0, 420),
            ("Sophia",   6, 1,  48), ("Mason",   5, 0, 900), ("Isabella", 5, 2,  20),
            ("Lucas",    4, 0, 260), ("Mia",     4, 1,   8), ("Ethan",    3, 0, 640),
            ("Chloe",    3, 0,   6), ("Henry",   3, 0, 1500), ("Grace",    2, 0, 2600),
            ("Owen",     2, 1,  90),
        ]
        var people = english ? englishPeople : russian
        if let limit { people = Array(people.prefix(max(0, limit))) }
        let incoming = english
            ? ["Where are you now?", "Sent you the files — take a look",
               "I'll call you tonight, promise", "On my way, five minutes out",
               "How did the interview go?", "Call me back when you get a chance",
               "Did you see the photos from the trip?", "Lunch tomorrow?",
               "That meeting ran way too long 😅", "Thanks again for yesterday",
               "Can you send the address?", "Just landed, texting when I'm home"]
            : ["Ты где сейчас?", "Скинул файл, глянь", "Позвоню вечером",
               "Уже еду", "Как всё прошло?", "Перезвони, когда сможешь"]
        let outgoing = english
            ? ["Almost done, give me ten", "Yeah, I remember 🙂", "Be there soon",
               "Sounds good to me", "Sure, let's do it", "Haha same here",
               "Perfect, see you then", "On it now", "No worries at all",
               "Let me check and get back to you"]
            : ["Почти закончил", "Да, помню", "Скоро буду", "Ок", "На связи"]

        // Contact ids stand in for Solana pubkeys. The mesh avatar shows the
        // first 4 chars, so these must LOOK like a key — an "orbit-…" id printed
        // "orbi" on every avatar, which is not a name this product uses.
        let b58 = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz123456789")
        func keyLike(_ salt: Int) -> String {
            var h = UInt64(salt &* 2654435761 &+ 1)
            return String((0..<44).map { _ -> Character in
                h = h &* 6364136223846793005 &+ 1442695040888963407
                return b58[Int((h >> 33) % UInt64(b58.count))]
            })
        }

        // A self "Saved Messages" contact so the curated circle globe has its
        // centre (your avatar) to branch from.
        let me = Contact(id: keyLike(999), displayName: "Saved Messages", prekeyBundleBase64: "")
        me.ownerAddress = ""
        me.isSelf = true
        me.createdAt = Date().addingTimeInterval(-100_000)
        context.insert(me)

        // Two favourites so the ring has something to show in the preview — the
        // ring is manual-only, so without this the harness renders none and the
        // mark looks broken rather than absent. Circle membership is separate:
        // the same two by default, or (with -orbitAllFav) everyone, so the curated
        // globe's fill can be inspected without touching favourite status.
        let favTwo: Set<String> = english ? ["Emma", "Mason"] : ["Лина", "Гоша"]
        let favourite = favTwo
        let circle: Set<String> = args.contains("-orbitAllFav")
            ? Set(people.map(\.0)) : favTwo

        for (idx, p) in people.enumerated() {
            let (name, count, unread, minsAgo) = p
            let c = Contact(id: keyLike(idx), displayName: name, prekeyBundleBase64: "")
            c.ownerAddress = ""
            c.isFavourite = favourite.contains(name)
            c.inCircle = circle.contains(name)
            // A couple of private notes so the "note beside the name" can be seen.
            let notes: [String: String] = english
                ? ["Ava": "gym buddy", "Liam": "work", "Emma": "college"]
                : ["Даша": "спортзал", "Артём": "работа", "Лина": "универ"]
            c.myNote = notes[name] ?? ""
            c.createdAt = Date().addingTimeInterval(-Double(count) * 3600 - 86_400)
            context.insert(c)

            // Oldest first; the last `unread` incoming ones stay unopened.
            for i in 0..<count {
                let fromEnd = count - 1 - i
                let mine = (i % 2 == 1) && fromEnd >= unread
                let body = mine ? outgoing[i % outgoing.count] : incoming[i % incoming.count]
                let at = Date().addingTimeInterval(-Double(minsAgo) * 60 - Double(fromEnd) * 900)
                let m = ChatMessage(id: "orbit-\(idx)-\(i)", body: body, isOutgoing: mine,
                                    sentAt: at, status: mine ? "sent" : "received")
                m.isRead = mine || fromEnd >= unread
                m.contact = c
                context.insert(m)
            }
        }
        try? context.save()
    }
}
#endif
