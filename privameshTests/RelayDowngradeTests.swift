//
//  RelayDowngradeTests.swift
//  privameshTests

//  Reported externally on 19 September 2026.

//  The blind token exists so /send carries no identity. The client used to fall
//  back to the Apple receipt whenever a token was not available - when the relay
//  answered `enabled: false` at /pubkey, and equally when it just rejected the
//  token it was handed. Either answer is the relay's to choose, so the property
//  the signatures provide could be switched off by the party it protects against,
//  for everyone, without forging anything.

//  What holds now: a device that has been served an issuer key keeps the
//  anonymous path or does not send. A device that never saw one still takes the
//  receipt path, because it has no anonymity to lose and the alternative is an
//  install that cannot send at all.


import Testing
import Foundation
@testable import privamesh

@Suite("Relay downgrade")
struct RelayDowngradeTests {

    private let token = BlindToken(t: "bm9uY2U", sig: "c2ln")

    /// The whole point of the token path: nothing on it identifies the sender.
    @Test func aTokenSendCarriesNoReceiptAndNoAccount() {
        let body = RelayService.sendBody(txBase64: "dHg", jws: "receipt-jws",
                                         token: token, account: "account-token")

        #expect(body["token"] != nil)
        #expect(body["jws"] == nil, "the receipt names the purchase that paid")
        #expect(body["account"] == nil, "the account token is stable across sends")
    }

    /// Reading the account token provisions one on first use. The token path must
    /// not cause that, which is why `account` is an autoclosure.
    @Test func theTokenPathNeverReadsTheAccountToken() {
        var reads = 0
        _ = RelayService.sendBody(txBase64: "dHg", jws: nil, token: token,
                                  account: { reads += 1; return "account-token" }())
        #expect(reads == 0)
    }

    /// The legacy path is unchanged for devices that have never had a token.
    @Test func theReceiptPathStillCarriesBoth() {
        let body = RelayService.sendBody(txBase64: "dHg", jws: "receipt-jws",
                                         token: nil, account: "account-token")

        #expect(body["token"] == nil)
        #expect(body["jws"] as? String == "receipt-jws")
        #expect(body["account"] as? String == "account-token")
    }

    /// A relay that stops serving tokens must not be able to pull a device that
    /// had them back onto the receipt path.
    @Test func anEstablishedDeviceMayNotUseTheReceiptPath() {
        #expect(RelayService.mayUseReceiptPath(allowAnonymousToken: true,
                                               anonymityExpected: true) == false)
    }

    /// A device with no token to expect — no issuer key yet, or the free tier,
    /// which the relay mints no tokens for — has no anonymity to lose here, and
    /// refusing would only make it unable to send.
    @Test func aDeviceWithNoTokensToExpectStillSends() {
        #expect(RelayService.mayUseReceiptPath(allowAnonymousToken: true,
                                               anonymityExpected: false) == true)
    }

    /// Discovery publishes claim a public nickname and need the account path for
    /// ownership - the relay rejects them on the token path. They are identifying
    /// by construction, so the guard leaves them alone rather than blocking
    /// nickname publishing outright.
    @Test func discoveryPublishesKeepTheAccountPath() {
        #expect(RelayService.mayUseReceiptPath(allowAnonymousToken: false,
                                               anonymityExpected: true) == true)
    }
}
