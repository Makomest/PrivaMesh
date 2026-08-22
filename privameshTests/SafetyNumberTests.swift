//
//  SafetyNumberTests.swift
//  privameshTests
//
//  The safety number is only worth showing if it has four properties: both sides
//  compute the same one, it changes when a key changes, it is stable across
//  launches, and it cannot be confused with anyone else's. Each is a test here.
//

import Testing
import Foundation
import CryptoKit
@testable import privamesh

@Suite("Safety number")
struct SafetyNumberTests {

    private let addrA = "JrDSXFpcZhhkjqhq1WL7aGbaRp3CF1vbTgv4cb7Hb7V"
    private let addrB = "AoxpJiPLVQbkYzghChb1UNXzq9HcLCprf3645kTFKHoG"

    private func identity(_ phrase: [String]) throws -> CryptoIdentity {
        try CryptoIdentity.derive(fromSeedPhrase: phrase)
    }

    private let alicePhrase = ["drum","need","person","expire","large","wrist",
                               "struggle","labor","label","ill","improve","cloud"]
    private let bobPhrase   = ["gospel","fault","alien","clip","mail","bounce",
                               "brave","dolphin","forum","brief","hazard","hobby"]

    /// The whole point: Alice's phone and Bob's phone must show the same digits,
    /// even though each computes it from a different point of view.
    @Test func bothSidesSeeTheSameNumber() throws {
        let alice = try identity(alicePhrase).prekeyBundle()
        let bob   = try identity(bobPhrase).prekeyBundle()

        let onAlicesPhone = SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                                theirBundle: bob, theirAddress: addrB)
        let onBobsPhone   = SafetyNumber.digits(myBundle: bob, myAddress: addrB,
                                                theirBundle: alice, theirAddress: addrA)

        #expect(onAlicesPhone != nil)
        #expect(onAlicesPhone == onBobsPhone)
    }

    @Test func numberIsSixtyDigits() throws {
        let alice = try identity(alicePhrase).prekeyBundle()
        let bob   = try identity(bobPhrase).prekeyBundle()
        let n = try #require(SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                                 theirBundle: bob, theirAddress: addrB))
        #expect(n.count == 60)
        #expect(n.allSatisfy { $0.isNumber })
    }

    /// If a key is swapped the number must change, otherwise comparing it proves
    /// nothing. This is the property a MITM would need to defeat.
    @Test func differentContactGivesDifferentNumber() throws {
        let alice   = try identity(alicePhrase).prekeyBundle()
        let bob     = try identity(bobPhrase).prekeyBundle()
        let malloryIdentity = try CryptoIdentity.generate()
        let mallory = try malloryIdentity.prekeyBundle()

        let withBob     = SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                              theirBundle: bob, theirAddress: addrB)
        let withMallory = SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                              theirBundle: mallory, theirAddress: addrB)
        #expect(withBob != withMallory)
    }

    /// Same keys, different account address: still a different person.
    @Test func differentAddressGivesDifferentNumber() throws {
        let alice = try identity(alicePhrase).prekeyBundle()
        let bob   = try identity(bobPhrase).prekeyBundle()

        let one = SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                      theirBundle: bob, theirAddress: addrB)
        let two = SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                      theirBundle: bob, theirAddress: addrA)
        #expect(one != two)
    }

    /// Derived from the phrase, so it must survive a reinstall unchanged: a number
    /// that drifts would train people to ignore a real change.
    @Test func numberIsStableAcrossDerivations() throws {
        let a1 = try identity(alicePhrase).prekeyBundle()
        let a2 = try identity(alicePhrase).prekeyBundle()
        let bob = try identity(bobPhrase).prekeyBundle()

        #expect(SafetyNumber.digits(myBundle: a1, myAddress: addrA, theirBundle: bob, theirAddress: addrB)
             == SafetyNumber.digits(myBundle: a2, myAddress: addrA, theirBundle: bob, theirAddress: addrB))
    }

    @Test func formattingGroupsByFive() {
        let digits = String(repeating: "1234567890", count: 6)   // 60 chars
        let out = SafetyNumber.formatted(digits)
        #expect(out.split(separator: " ").count == 12)
        #expect(out.split(separator: " ").allSatisfy { $0.count == 5 })
        #expect(out.replacingOccurrences(of: " ", with: "") == digits)
    }

    // MARK: - QR round trip

    @Test func qrPayloadRoundTrips() throws {
        let alice = try identity(alicePhrase).prekeyBundle()
        let bob   = try identity(bobPhrase).prekeyBundle()
        let n = try #require(SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                                 theirBundle: bob, theirAddress: addrB))
        #expect(SafetyNumber.digits(fromQR: SafetyNumber.qrPayload(n)) == n)
    }

    /// A scanned code that is not ours must be rejected rather than compared, or
    /// the screen would report a mismatch for the wrong reason.
    @Test func foreignQRIsRejected() {
        for payload in ["hello", "privamesh-sn:", "privamesh-sn:123", "sn:" + String(repeating: "1", count: 60),
                        "privamesh-sn:" + String(repeating: "a", count: 60)] {
            #expect(SafetyNumber.digits(fromQR: payload) == nil, "accepted \(payload)")
        }
    }

    /// An unreadable bundle yields no number at all. Showing digits derived from a
    /// partial key would look like verification while proving nothing.
    @Test func unreadableBundleYieldsNil() throws {
        let alice = try identity(alicePhrase).prekeyBundle()
        #expect(SafetyNumber.digits(myBundle: alice, myAddress: addrA,
                                    theirBundleBase64: "not-base64", theirAddress: addrB) == nil)
        #expect(SafetyNumber.digits(myBundle: alice, myAddress: "",
                                    theirBundle: alice, theirAddress: addrB) == nil)
    }
}
