//
//  PerfProbe.swift — TEMPORARY AUDIT PROBE
//

import Testing
import Foundation
import SwiftData
@testable import privamesh

@Suite("Perf probe", .serialized)
struct PerfProbe {

    @MainActor
    private func seed(contacts: Int, messagesEach: Int) throws -> (ModelContainer, ModelContext, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let container = try ModelContainer(for: Contact.self, ChatMessage.self,
                                           configurations: ModelConfiguration(url: dir.appendingPathComponent("p.store")))
        let context = container.mainContext
        for c in 0..<contacts {
            let contact = Contact(id: "peer-\(c)", displayName: "peer \(c)", prekeyBundleBase64: "")
            context.insert(contact)
            for m in 0..<messagesEach {
                let msg = ChatMessage(id: "sig-\(c)-\(m)", body: String(repeating: "x", count: 120),
                                      isOutgoing: m % 2 == 0, sentAt: .now, status: "received")
                msg.isRead = m % 7 != 0
                msg.contact = contact
                context.insert(msg)
            }
        }
        try context.save()
        return (container, context, dir)
    }

    /// The expression SwiftUI evaluates on every body pass of the root screen:
    /// OrbitChatsView's .onChange(of: contacts.map { "\(id)#\(messages.count)#\(unreadCount)" }).
    @MainActor
    @Test func rootScreenChangeKey() throws {
        let (container, context, dir) = try seed(contacts: 20, messagesEach: 500)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = container

        // Cold: relationships not yet faulted, as after a launch.
        let fresh = ModelContext(container)
        let cold0 = Date()
        let coldContacts = (try? fresh.fetch(FetchDescriptor<Contact>())) ?? []
        _ = coldContacts.map { "\($0.id)#\($0.messages.count)#\($0.unreadCount)" }
        let cold = Date().timeIntervalSince(cold0)

        let contacts = (try? context.fetch(FetchDescriptor<Contact>())) ?? []
        _ = contacts.map { "\($0.id)#\($0.messages.count)#\($0.unreadCount)" }   // warm the faults
        let warm0 = Date()
        for _ in 0..<10 {
            _ = contacts.map { "\($0.id)#\($0.messages.count)#\($0.unreadCount)" }
        }
        let warm = Date().timeIntervalSince(warm0) / 10

        // What the same screen does per row.
        let last0 = Date()
        for _ in 0..<10 { _ = contacts.map { $0.messages.max { $0.sentAt < $1.sentAt } } }
        let last = Date().timeIntervalSince(last0) / 10

        Issue.record(Comment(rawValue: """

        === ROOT SCREEN, 20 contacts x 500 messages (10 000 rows) ===
        onChange key, cold faults : \(String(format: "%.3f", cold))s
        onChange key, warm        : \(String(format: "%.3f", warm))s per body pass
        lastMessage for all rows  : \(String(format: "%.3f", last))s per body pass
        ============================================================
        """))
    }

    /// The passcode KDF: 100 000 SHA-256 rounds, run on the main thread by the
    /// lock screen, the duress check and every Settings confirmation.
    @MainActor
    @Test func passcodeKeyDerivation() throws {
        let manager = PasscodeManager()
        manager.wipe()
        defer { manager.wipe() }
        try manager.setPasscode("1234", length: 4)

        let started = Date()
        _ = manager.check("1234")
        let correct = Date().timeIntervalSince(started)

        let started2 = Date()
        _ = manager.check("9999")
        let wrong = Date().timeIntervalSince(started2)

        Issue.record(Comment(rawValue: """

        === PASSCODE KDF (main thread) ===
        check(correct code) = \(String(format: "%.3f", correct))s
        check(wrong code)   = \(String(format: "%.3f", wrong))s
        ==================================
        """))
    }
}
