//
//  PrivateNetwork.swift
//  privamesh
//
//  A single outbound-HTTP seam for every network call the app makes to a named
//  host — the relay, Irys (photos), discovery, and the token issuer. Its job is
//  to break the IP↔activity link: the MESSAGES already ride Solana memos (public
//  ledger, E2E-encrypted content), so what leaks is *which IP submits/reads which
//  addresses*. Routing these calls through a mixnet (Nym) or an Oblivious HTTP
//  relay hides that linkage.
//
//  HONEST BY DEFAULT: with no gateway configured (`MixnetConfig` empty), `isActive`
//  is false and this is a thin pass-through to `URLSession.shared` — identical to
//  today. The Settings toggle can turn the PREFERENCE on, but protection only
//  actually engages once a real gateway is wired. The UI reflects that so a user
//  is never shown "mixnet on" while traffic still goes direct.
//
//  NOT YET COVERED: the main Solana RPC (getSignaturesForAddress / sendRawTx) goes
//  through SolanaSwift's own networking, not this seam. That is the biggest
//  metadata surface (which stealth addresses you poll) and must be routed by
//  pointing the RPC endpoint at a mixnet/OHTTP proxy — tracked separately.
//

import Foundation

/// Where a mixnet / Oblivious-HTTP gateway lives, if one is deployed. Empty = not
/// configured (the shipping default), which keeps the private path inert until
/// it's real. `gatewayURL` is the OHTTP relay/Nym-proxy entry point the transport
/// will encapsulate requests through once implemented.
enum MixnetConfig {
    static let gatewayURL = ""
    static var isConfigured: Bool { !gatewayURL.isEmpty }
}

@Observable
final class PrivateNetwork {
    static let shared = PrivateNetwork()

    private static let prefKey = "privamesh.mixnetPreferred"

    /// User preference from Settings. Persisted, but only *engages* when a gateway
    /// is configured (see `isActive`).
    var mixnetPreferred: Bool {
        didSet { UserDefaults.standard.set(mixnetPreferred, forKey: Self.prefKey) }
    }

    /// True only when the user asked for it AND a gateway actually exists. This is
    /// the flag the UI must show — never `mixnetPreferred` alone.
    var isActive: Bool { mixnetPreferred && MixnetConfig.isConfigured }

    /// Whether the toggle can even do anything yet. When false the Settings row is
    /// shown but disabled/"experimental", so it makes no promise it can't keep.
    var isAvailable: Bool { MixnetConfig.isConfigured }

    private init() {
        self.mixnetPreferred = UserDefaults.standard.bool(forKey: Self.prefKey)
    }

    /// The session for this request. Computed per-call (no shared mutable state,
    /// so no data race between a Settings toggle on main and a background fetch).
    private func session() -> URLSession {
        // iOS does NOT honour a SOCKS proxy on URLSession (those keys are macOS-
        // only), so a real mixnet path here means one of:
        //   • Oblivious HTTP — encapsulate each request to MixnetConfig.gatewayURL
        //     (pure HTTPS, app-layer), the practical iOS route; or
        //   • a NEPacketTunnelProvider Network Extension fronting a Nym client.
        // Until that lands, even an "active" preference stays on the direct session
        // (and `isActive` is false anyway, since no gateway is configured), so the
        // seam never silently pretends to protect traffic it doesn't.
        //
        // The direct session is pinned: this seam is the only place named-host
        // traffic leaves the app, so one delegate covers the relay, the token
        // issuer and Irys uploads at once. See CertificatePinning for which hosts
        // are actually pinned and why the leaf is not.
        return Self.pinnedSession
    }

    /// Built once. A URLSession with a delegate must be reused, or every request
    /// leaks a session object and its connection pool.
    private static let pinnedSession: URLSession = {
        URLSession(configuration: .default,
                   delegate: PinningSessionDelegate(),
                   delegateQueue: nil)
    }()

    // MARK: - The seam every named-host service should call

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session().data(for: request)
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session().data(from: url)
    }
}
