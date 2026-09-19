//
//  SenderAttributionTests.swift
//  privameshTests
//
//  Reported externally on 19 September 2026.
//
//  Every sponsored message is paid for by one treasury wallet, and the fee payer
//  is accountKeys[0]. The client read that key as "the sender", so every opener
//  from a stranger named the same address. All message requests landed in one
//  contact, each new opener replaced its ratchet and stealth root, and the reply
//  the user wrote to the first stranger was encrypted to the latest one and sent
//  to a stealth address only that stranger polls.
//
//  Two rules close it: a fee payer counts as the sender only when it also signed
//  the memo (never true on the sponsored path, where a throwaway key signs), and
//  contacts are matched on the identity key in the envelope before any address.
//

import Testing
import Foundation
import SwiftData
@testable import privamesh

@Suite("Sender attribution")
@MainActor
struct SenderAttributionTests {

    private let treasury  = RelayConfig.treasuryPubkey
    private let memo      = MemoTransactionBuilder.memoProgramId
    private let strangerA = "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V"
    private let strangerB = "8ZrT4aBqNvXk2mWc5sPdRfGh1JyLu9QeVo3TnAiCbXkM"

    private let keyA = Data(repeating: 0xA1, count: 32)
    private let keyB = Data(repeating: 0xB2, count: 32)

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Contact.self, ChatMessage.self, configurations: config)
        return ModelContext(container)
    }

    private func contacts(in context: ModelContext) -> [Contact] {
        ((try? context.fetch(FetchDescriptor<Contact>())) ?? []).filter { $0.ownerAddress == "me" }
    }

    // MARK: - Transaction shapes

    /// The sponsored shape MemoTransactionBuilder.buildSponsoredMessageBase64
    /// produces: treasury pays, a per-message ephemeral key signs the memo.
    private func sponsoredMessage(ephemeral: String, recipient: String) -> [String: Any] {
        [
            "accountKeys": [treasury, ephemeral, recipient, memo],
            "instructions": [
                ["programIdIndex": 3, "accounts": [1], "data": "…"],   // memo, signed by the ephemeral
            ],
        ]
    }

    /// The direct shape MemoTransactionBuilder.send produces: the sender pays
    /// their own fee and signs the memo with the same key.
    private func directMessage(sender: String, recipient: String) -> [String: Any] {
        [
            "accountKeys": [sender, recipient, memo],
            "instructions": [
                ["programIdIndex": 2, "accounts": [0], "data": "…"],   // memo, signed by the fee payer
            ],
        ]
    }

    @Test func aSponsoredTransactionNamesNoSender() {
        let message = sponsoredMessage(ephemeral: strangerA, recipient: "me")

        #expect(PollingService.senderAddress(inTransactionMessage: message) == nil,
                "the treasury pays for everyone; naming it as the sender merges every stranger")
    }

    @Test func anUnsponsoredTransactionNamesItsFeePayer() {
        let message = directMessage(sender: strangerA, recipient: "me")

        #expect(PollingService.senderAddress(inTransactionMessage: message) == strangerA)
    }

    /// A transaction carrying no memo instruction says nothing about a sender.
    @Test func aTransactionWithoutAMemoNamesNoSender() {
        let message: [String: Any] = [
            "accountKeys": [strangerA, "me"],
            "instructions": [["programIdIndex": 1, "accounts": [0], "data": "…"]],
        ]

        #expect(PollingService.senderAddress(inTransactionMessage: message) == nil)
    }

    // MARK: - Contact resolution

    /// The bug, as reported: two strangers, no address on either opener.
    @Test func twoStrangersGetTwoContacts() throws {
        let context = try makeContext()

        let first = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)
        PollingService.noteIdentityKey(keyA, on: first, context: context)

        let second = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyB,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(first !== second, "distinct senders must not share a conversation")
        #expect(first.id != second.id)
        #expect(contacts(in: context).count == 2)
    }

    /// What the collapse looked like: both openers arriving with the treasury as
    /// their "sender" must still not meet in one contact.
    @Test func theTreasuryAddressDoesNotMergeStrangers() throws {
        let context = try makeContext()

        // fetchSenderAddress now returns nil for these, but pass the treasury in
        // anyway: even handed the shared address, the key has to win.
        let first = PollingService.findOrCreateContact(
            senderAddress: treasury, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)
        PollingService.noteIdentityKey(keyA, on: first, context: context)

        let second = PollingService.findOrCreateContact(
            senderAddress: treasury, senderIdentityKey: keyB,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(first !== second)
        #expect(contacts(in: context).count == 2)
    }

    /// The same stranger writing twice stays one conversation - the point of
    /// matching at all.
    @Test func theSameSenderReusesTheirContact() throws {
        let context = try makeContext()

        let first = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)
        PollingService.noteIdentityKey(keyA, on: first, context: context)

        let second = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(first === second)
        #expect(contacts(in: context).count == 1)
    }

    /// A contact added by search or QR is still found when its owner writes from
    /// a transaction that does name them.
    @Test func aKnownAddressStillMatchesWhenTheKeyIsNew() throws {
        let context = try makeContext()
        let known = Contact(id: strangerA, displayName: "Emma", prekeyBundleBase64: "")
        known.ownerAddress = "me"
        context.insert(known)

        let found = PollingService.findOrCreateContact(
            senderAddress: strangerA, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(found === known, "a first opener from a saved contact belongs in their chat")
        #expect(contacts(in: context).count == 1)
    }

    /// The key decides even when an address points elsewhere: a sender whose key
    /// we know keeps their chat whatever address the transaction carries.
    @Test func theKeyWinsOverTheAddress() throws {
        let context = try makeContext()

        let byKey = Contact(id: "message-request", displayName: "Stranger", prekeyBundleBase64: "")
        byKey.ownerAddress = "me"
        byKey.knownIdentityKey = keyA
        context.insert(byKey)

        let byAddress = Contact(id: strangerB, displayName: "Someone else", prekeyBundleBase64: "")
        byAddress.ownerAddress = "me"
        context.insert(byAddress)

        let found = PollingService.findOrCreateContact(
            senderAddress: strangerB, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(found === byKey)
    }

    /// Different message requests must not look alike in the list either: the
    /// name came from the (shared) address, so every request showed one name.
    @Test func messageRequestsFromDifferentSendersAreNamedDifferently() throws {
        let context = try makeContext()

        let first = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)
        PollingService.noteIdentityKey(keyA, on: first, context: context)

        let second = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyB,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(first.displayName != second.displayName)
        #expect(!first.displayName.isEmpty)
    }

    /// Chats are per account: another account's contact is never reused, whatever
    /// key it holds.
    @Test func anotherAccountsContactIsNotReused() throws {
        let context = try makeContext()
        let theirs = Contact(id: "other-account-contact", displayName: "Theirs", prekeyBundleBase64: "")
        theirs.ownerAddress = "someone-else"
        theirs.knownIdentityKey = keyA
        context.insert(theirs)

        let found = PollingService.findOrCreateContact(
            senderAddress: nil, senderIdentityKey: keyA,
            ownerAddress: "me", in: contacts(in: context), context: context)

        #expect(found !== theirs)
        #expect(found.ownerAddress == "me")
    }
}
