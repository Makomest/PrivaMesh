//
//  CertificatePinningTests.swift
//  privameshTests
//
//  Pinning fails in one direction quietly and in the other loudly: a wrong pin
//  set means nobody can reach the relay. These tests exist so that failure shows
//  up here rather than in the App Store reviews.
//

import Testing
import Foundation
@testable import privamesh

@Suite("Certificate pinning")
struct CertificatePinningTests {

    @Test func onlyTheRelayIsPinned() {
        #expect(CertificatePinning.shouldPin(host: "privamesh-relay.privamesh.workers.dev"))
        #expect(CertificatePinning.shouldPin(host: "PrivaMesh-Relay.PrivaMesh.Workers.Dev"),
                "host comparison must be case-insensitive")
        // Solana RPC is user-configurable and Irys is a third party: pinning either
        // would break the day they change hosts.
        #expect(CertificatePinning.shouldPin(host: "api.mainnet-beta.solana.com") == false)
        #expect(CertificatePinning.shouldPin(host: "uploader.irys.xyz") == false)
        #expect(CertificatePinning.shouldPin(host: "evil.example.com") == false)
    }

    /// Several pins, so one CA change is survivable.
    @Test func pinSetHasSpares() {
        #expect(CertificatePinning.pins.count >= 3)
        for pin in CertificatePinning.pins {
            #expect(pin.count == 44, "a SHA-256 pin is 44 base64 chars: \(pin)")
            #expect(Data(base64Encoded: pin)?.count == 32)
        }
    }

    /// The expiry is the safety valve: an abandoned build must fall back to system
    /// trust rather than becoming unable to connect.
    @Test func pinningExpires() {
        #expect(CertificatePinning.enforceUntil > Date(), "pins already expired — bump enforceUntil")
        let year: TimeInterval = 365 * 24 * 3600
        #expect(CertificatePinning.enforceUntil < Date().addingTimeInterval(5 * year),
                "an expiry this far out is not a safety valve")
    }

    /// The one that catches a rotated CA. Talks to the real host, so it is skipped
    /// when the machine is offline rather than failing the suite.
    @Test func livePinsStillMatchTheRelay() async throws {
        let host = "privamesh-relay.privamesh.workers.dev"
        guard let url = URL(string: "https://\(host)/pubkey") else { return }

        let probe = PinProbe()
        let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            _ = try await session.data(from: url)
        } catch {
            // Offline, or the request itself failed: nothing to assert.
            return
        }
        guard let matched = probe.matched else { return }
        #expect(matched, """
            The live relay chain no longer carries any pinned key. Regenerate the \
            pins (see CertificatePinning) before shipping, or the app will be \
            unable to reach the relay.
            """)
    }

    /// Captures whether the real chain matched, without enforcing anything.
    private final class PinProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
        var matched: Bool?
        func urlSession(_ session: URLSession,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if let trust = challenge.protectionSpace.serverTrust {
                matched = CertificatePinning.chainMatchesPin(trust)
            }
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
