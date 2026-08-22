//
//  KeyChangeTests.swift
//  privameshTests
//
//  A safety number checked once is worthless if the key behind it can be replaced
//  in silence. These cover the moment a contact's identity key changes: the mark
//  has to drop, the user has to be told, and an unchanged key must not nag.
//

import Testing
import Foundation
import SwiftData
@testable import privamesh

@Suite("Key change")
@MainActor
struct KeyChangeTests {

    /// In-memory store so the tests never touch the real database.
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Contact.self, ChatMessage.self, configurations: config)
        return ModelContext(container)
    }

    private func makeContact(in context: ModelContext) -> Contact {
        let c = Contact(id: "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V",
                        displayName: "Emma", prekeyBundleBase64: "")
        c.ownerAddress = "owner"
        context.insert(c)
        return c
    }

    private let keyA = Data(repeating: 0xA1, count: 32)
    private let keyB = Data(repeating: 0xB2, count: 32)

    /// Trust on first use: the first key is recorded and nothing is raised.
    @Test func firstKeyIsRecordedQuietly() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)

        PollingService.noteIdentityKey(keyA, on: contact, context: context)

        #expect(contact.knownIdentityKey == keyA)
        #expect(contact.keyChangedAt == nil)
        #expect(contact.messages.isEmpty, "a first key must not produce a warning")
    }

    /// The same key arriving again is the normal case and must stay silent.
    @Test func sameKeyDoesNotWarn() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)

        PollingService.noteIdentityKey(keyA, on: contact, context: context)
        PollingService.noteIdentityKey(keyA, on: contact, context: context)

        #expect(contact.keyChangedAt == nil)
        #expect(contact.messages.isEmpty)
    }

    /// The case this exists for.
    @Test func changedKeyRaisesNoticeAndFlag() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)

        PollingService.noteIdentityKey(keyA, on: contact, context: context)
        PollingService.noteIdentityKey(keyB, on: contact, context: context)

        #expect(contact.knownIdentityKey == keyB, "the new key must be adopted")
        #expect(contact.keyChangedAt != nil, "the banner flag must be set")
        #expect(contact.messages.count == 1)
        #expect(contact.messages.first?.kind == "system")
        #expect(contact.messages.first?.isRead == false, "the notice must count as unread")
    }

    /// The user verified the OLD key. A new key is not covered by that check, so
    /// the mark has to come off by itself.
    @Test func changedKeyDropsVerification() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)
        PollingService.noteIdentityKey(keyA, on: contact, context: context)

        contact.isVerified = true
        contact.verifiedAt = Date()

        PollingService.noteIdentityKey(keyB, on: contact, context: context)

        #expect(contact.isVerified == false)
        #expect(contact.verifiedAt == nil)
    }

    /// Verification survives an unchanged key, otherwise the mark would be
    /// impossible to keep.
    @Test func verificationSurvivesSameKey() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)
        PollingService.noteIdentityKey(keyA, on: contact, context: context)
        contact.isVerified = true

        PollingService.noteIdentityKey(keyA, on: contact, context: context)

        #expect(contact.isVerified)
    }

    /// Missing or empty keys are not a change: some legacy envelopes carry none,
    /// and warning on those would train people to dismiss the warning.
    @Test func absentKeyIsIgnored() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)
        PollingService.noteIdentityKey(keyA, on: contact, context: context)

        PollingService.noteIdentityKey(nil, on: contact, context: context)
        PollingService.noteIdentityKey(Data(), on: contact, context: context)

        #expect(contact.knownIdentityKey == keyA)
        #expect(contact.keyChangedAt == nil)
        #expect(contact.messages.isEmpty)
    }

    /// Two changes in a row must both be reported, not collapsed.
    @Test func repeatedChangesEachRaiseANotice() throws {
        let context = try makeContext()
        let contact = makeContact(in: context)
        PollingService.noteIdentityKey(keyA, on: contact, context: context)
        PollingService.noteIdentityKey(keyB, on: contact, context: context)
        PollingService.noteIdentityKey(Data(repeating: 0xC3, count: 32), on: contact, context: context)

        #expect(contact.messages.count == 2)
    }
}
