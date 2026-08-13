//
//  InviteLinkTests.swift
//  privameshTests
//
//  Invite links carry a contact card through a URL, so the encoding has to survive
//  being a path component and the parser has to reject anything that isn't ours.
//

import Testing
import Foundation
@testable import privamesh

@Suite("Invite links")
struct InviteLinkTests {

    /// A card built the same way the app builds it: a real address and a bundle blob.
    private func sampleCard() -> ContactCard {
        ContactCard(address: "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V",
                    bundle: String(repeating: "QUJDREVG", count: 40))
    }

    @Test func webLink_roundTripsTheCard() throws {
        let card = sampleCard()
        let url = try #require(InviteLink.url(for: card))
        let parsed = try #require(InviteLink.card(from: url))

        #expect(parsed.address == card.address)
        #expect(parsed.bundle == card.bundle)
    }

    @Test func appSchemeLink_roundTripsTheCard() throws {
        let card = sampleCard()
        let url = try #require(InviteLink.appURL(for: card))
        let parsed = try #require(InviteLink.card(from: url))

        #expect(parsed.address == card.address)
        #expect(parsed.bundle == card.bundle)
    }

    /// The payload lands in a URL path, so `+` `/` `=` must not appear in it.
    @Test func payloadIsURLSafe() throws {
        let url = try #require(InviteLink.url(for: sampleCard()))
        let payload = try #require(InviteLink.payload(from: url))

        #expect(!payload.contains("+"))
        #expect(!payload.contains("/"))
        #expect(!payload.contains("="))
        #expect(url.absoluteString.hasPrefix("https://privamesh.org/i/"))
    }

    @Test func base64urlConversion_isReversible() {
        let standard = "ab+c/d=="
        let urlSafe = InviteLink.base64url(standard)
        #expect(urlSafe == "ab-c_d")
        #expect(InviteLink.base64Standard(urlSafe) == standard)
    }

    @Test func foreignURLs_areIgnored() {
        for s in ["https://example.com/i/whatever",
                  "https://privamesh.org/support",
                  "https://evil.org/i/payload",
                  "otherapp://add?c=payload"] {
            let url = URL(string: s)!
            #expect(InviteLink.payload(from: url) == nil, "should not accept \(s)")
        }
    }

    @Test func garbagePayload_yieldsNoCard() {
        let url = URL(string: "https://privamesh.org/i/not-a-real-payload")!
        #expect(InviteLink.card(from: url) == nil)
    }

    // MARK: - Inbox

    @MainActor
    @Test func inbox_holdsInviteUntilTaken() throws {
        let inbox = InviteInbox()
        let url = try #require(InviteLink.url(for: sampleCard()))

        #expect(inbox.accept(url))
        #expect(inbox.pendingPayload != nil)

        let taken = inbox.take()
        #expect(taken != nil)
        #expect(inbox.pendingPayload == nil, "an invite must only be acted on once")
    }

    @MainActor
    @Test func inbox_rejectsUnrelatedURL() {
        let inbox = InviteInbox()
        #expect(inbox.accept(URL(string: "https://example.com/hello")!) == false)
        #expect(inbox.pendingPayload == nil)
    }

    /// A card whose address isn't a real Solana key must not open the add screen.
    @MainActor
    @Test func inbox_rejectsCardWithInvalidAddress() throws {
        let bogus = ContactCard(address: "definitely-not-base58", bundle: "QUJD")
        let url = try #require(InviteLink.url(for: bogus))
        let inbox = InviteInbox()

        #expect(inbox.accept(url) == false)
        #expect(inbox.pendingPayload == nil)
    }
}
