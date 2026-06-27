//
//  MarketEvent.swift
//  privamesh
//
//  Serverless marketplace event log. Listings live as memo transactions sent to
//  a shared "registry" address (the dev wallet). Anyone can reconstruct the open
//  listings by scanning that address's history via RPC (getSignaturesForAddress)
//  and folding the list/unlist/sold events — no backend, same mechanism as chat.
//
//  Memo wire format:  "PMKT1:" + base64(JSON(MarketEvent))
//  The prefix distinguishes market memos from binary message envelopes that also
//  reference the registry (e.g. purchase payments).
//

import Foundation

struct MarketEvent: Codable {
    enum Kind: String, Codable { case list, unlist, sold }

    var v: Int = 1
    let type: Kind
    /// Unique listing id: "<itemId>@<sellerAddress>".
    let lotId: String
    /// Present on `.list` — the item being sold (carries price in priceSOL).
    var item: MarketItem?
    /// Seller's Solana address (who gets paid).
    let seller: String
    /// Present on `.sold`.
    var buyer: String?
    var at: Double = Date().timeIntervalSince1970

    static func lotId(itemId: String, seller: String) -> String { "\(itemId)@\(seller)" }

    // MARK: - Wire codec

    static let memoPrefix = "PMKT1:"

    /// Encode to the memo string carried in the transaction.
    func memoString() -> String? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        return Self.memoPrefix + json.base64EncodedString()
    }

    /// Decode a memo string from `getSignaturesForAddress`. Strips an optional
    /// Solana "[N] " log prefix first. Returns nil for non-market memos.
    static func from(memo: String) -> MarketEvent? {
        let cleaned = memo.hasPrefix("[")
            ? String(memo.drop { $0 != " " }.dropFirst()).trimmingCharacters(in: .whitespaces)
            : memo
        guard cleaned.hasPrefix(memoPrefix) else { return nil }
        let b64 = String(cleaned.dropFirst(memoPrefix.count))
        guard let data = Data(base64Encoded: b64),
              let event = try? JSONDecoder().decode(MarketEvent.self, from: data) else { return nil }
        return event
    }
}
