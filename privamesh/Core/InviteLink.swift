//
//  InviteLink.swift
//  privamesh
//
//  Sharing a contact card as a link instead of a QR code.
//
//  Adding someone used to require the two of you to be in the same room (scan a
//  QR) or to copy a wall of base64 through some other messenger. Both work, both
//  lose most people. A link is one tap: send it however you already talk, the
//  other side opens it and lands on a pre-filled "add contact" screen.
//
//  Two forms of the same payload:
//    privamesh://add?c=<payload>              opens the app directly
//    https://privamesh.org/i/<payload>        opens the app if installed, else the
//                                             web page sends them to the App Store
//
//  The payload is the same compressed contact card the QR carries, re-encoded as
//  base64url so it survives being a URL path component. Nothing secret travels in
//  it: it is the public prekey bundle and address, exactly what the QR shows.
//

import Foundation

enum InviteLink {
    /// Custom scheme. Works with no server setup, which is why it is the primary
    /// form; the https form needs the site to serve an apple-app-site-association
    /// file before iOS will hand it to the app.
    static let scheme = "privamesh"
    static let webHost = "privamesh.org"
    /// Path prefix on the website: privamesh.org/i/<payload>
    static let webPathPrefix = "/i/"

    // MARK: - Making a link

    /// Link that opens this contact card in the app. Web form, since it also works
    /// for people who don't have the app yet.
    static func url(for card: ContactCard) -> URL? {
        let payload = base64url(card.qrPayload)
        guard !payload.isEmpty else { return nil }
        return URL(string: "https://\(webHost)\(webPathPrefix)\(payload)")
    }

    /// Same card via the custom scheme. Used when we know the app is installed.
    static func appURL(for card: ContactCard) -> URL? {
        let payload = base64url(card.qrPayload)
        guard !payload.isEmpty else { return nil }
        return URL(string: "\(scheme)://add?c=\(payload)")
    }

    // MARK: - Reading a link

    /// Extract a contact card from an incoming URL, in either form. Returns nil for
    /// anything that isn't one of ours or doesn't decode to a valid card.
    static func card(from url: URL) -> ContactCard? {
        guard let payload = payload(from: url) else { return nil }
        return ContactCard.fromQRPayload(base64Standard(payload))
    }

    /// The raw payload from either link form.
    static func payload(from url: URL) -> String? {
        if url.scheme?.lowercased() == scheme {
            // privamesh://add?c=<payload>
            guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let value = items.first(where: { $0.name == "c" })?.value,
                  !value.isEmpty else { return nil }
            return value
        }
        // https://privamesh.org/i/<payload>
        guard let host = url.host?.lowercased(),
              host == webHost || host == "www.\(webHost)",
              url.path.hasPrefix(webPathPrefix) else { return nil }
        let payload = String(url.path.dropFirst(webPathPrefix.count))
        return payload.isEmpty ? nil : payload
    }

    // MARK: - base64url

    /// Standard base64 → URL-safe. `+/` collide with URL syntax and `=` padding is
    /// noise in a path, so they go.
    static func base64url(_ standard: String) -> String {
        standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// URL-safe base64 → standard, padding restored so Data(base64Encoded:) accepts it.
    static func base64Standard(_ urlSafe: String) -> String {
        var s = urlSafe
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder > 0 { s += String(repeating: "=", count: 4 - remainder) }
        return s
    }
}

/// Holds an invite that arrived while the app was opening, until a screen is ready
/// to act on it. `onOpenURL` can fire before the UI exists, so the payload waits
/// here rather than being dropped.
@Observable
@MainActor
final class InviteInbox {
    /// Contact card payload from the last opened invite link, in QR (base64) form.
    private(set) var pendingPayload: String?
    /// Nickname carried in the invite, for a friendlier prompt.
    private(set) var pendingNickname: String?

    /// Accept a URL. Returns true if it was one of ours and held a usable card.
    @discardableResult
    func accept(_ url: URL) -> Bool {
        guard let payload = InviteLink.payload(from: url) else { return false }
        let standard = InviteLink.base64Standard(payload)
        guard let card = ContactCard.fromQRPayload(standard), card.hasValidAddress else { return false }
        pendingPayload = standard
        pendingNickname = card.profile?.nickname
        return true
    }

    /// Take the invite, clearing it so it is handled once.
    func take() -> String? {
        defer { pendingPayload = nil; pendingNickname = nil }
        return pendingPayload
    }
}
