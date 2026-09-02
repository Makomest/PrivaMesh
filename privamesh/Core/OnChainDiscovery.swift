//
//  OnChainDiscovery.swift
//  privamesh

//  Serverless contact discovery. Instead of an HTTP directory, each user
//  publishes a {nickname, address, bundle} record as a memo transaction to a
//  shared registry address. Search scans that address's history (RPC) and
//  matches by nickname — no backend, same mechanism as chat + market.

//  Wire format:  "PDIR1:" + base64(zlib(JSON(DiscoveryRecord)))
//  The bundle is already wallet-signed, so an added contact is verified against
//  its address (anti-MITM) — see PrekeyBundle.isBoundTo.


import Foundation
import SolanaSwift

struct DiscoveryRecord: Codable {
    var v = 1
    let nickname: String
    let address: String
    let bundle: String          // base64 PrekeyBundle (wallet-signed)
    var avatarSeed: String?     // equipped NFT avatar design id (so search shows it)
    var at = Date().timeIntervalSince1970
}

@Observable
@MainActor
final class OnChainDiscovery {
    static var address: String { MarketService.devWallet }      // shared bulletin board
    static var isConfigured: Bool { !address.isEmpty }
    static let memoPrefix = "PDIR1:"

    private static let pageSize = 100
    private static let maxPages = 4
    // v2: bumped after the compact-bundle fix so every account re-publishes once
    // (old oversized publishes silently failed and were never recorded).
    private static let publishedKey = "privamesh.discovery.publishedNick.v2."

    // MARK: - Publish

    /// Sponsoring relay. When configured, the publish fee is paid by the app
    /// treasury (and metered as one message), so the user needs no SOL. Set by
    /// the app root.
    weak var relay: RelayService?

    /// Last publish outcome, surfaced in the UI so failures aren't silent.
    var lastPublishError: String?
    var lastPublishedSig: String?

    /// True if this address already published this exact nick+avatar (so a manual
    /// re-publish would only burn another fee for nothing).
    func alreadyPublished(nickname: String, address: String, avatarSeed: String?) -> Bool {
        let stamp = nickname.trimmingCharacters(in: .whitespaces) + "|" + (avatarSeed ?? "")
        return UserDefaults.standard.string(forKey: Self.publishedKey + address) == stamp
    }

    /// Throttled: skips when this address already published this exact nickname+avatar.
    func publishIfNeeded(nickname: String, address: String, signedBundleBase64: String,
                         avatarSeed: String?, keypair: KeyPair, rpc: SolanaRPCService) async {
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        let key = Self.publishedKey + address
        // Re-publish when either the nick OR the equipped avatar changes.
        let stamp = nick + "|" + (avatarSeed ?? "")
        if UserDefaults.standard.string(forKey: key) == stamp { return }
        _ = await publish(nickname: nick, address: address,
                          signedBundleBase64: signedBundleBase64, avatarSeed: avatarSeed,
                          keypair: keypair, rpc: rpc)
    }

    /// Publish now (NOT throttled). Returns nil on success, else an error string.
    /// Use for the manual "make me searchable" action.
    @discardableResult
    func publish(nickname: String, address: String, signedBundleBase64: String,
                 avatarSeed: String?, keypair: KeyPair, rpc: SolanaRPCService) async -> String? {
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        guard Self.isConfigured else {
            let e = "Реестр не настроен"; lastPublishError = e; return e
        }
        guard !nick.isEmpty else {
            let e = "Пустой никнейм"; lastPublishError = e; return e
        }
        guard let bundle = try? PrekeyBundle.fromBase64(signedBundleBase64) else {
            let e = "Не удалось прочитать бандл"; lastPublishError = e; return e
        }
        let compact = bundle.discoveryPacked.base64EncodedString()
        let record = DiscoveryRecord(nickname: nick, address: address, bundle: compact, avatarSeed: avatarSeed)
        guard let memo = Self.encode(record) else {
            let e = "Не удалось закодировать запись"; lastPublishError = e; return e
        }
        do {
            // Sponsored path (treasury pays, metered) when the relay is set; the
            // record is self-authenticating (wallet-signed bundle inside), so an
            // ephemeral on-chain signer is fine. Fall back to the direct path.
            let sig: String
            if let relay, relay.isConfigured {
                // Discovery publishes claim a nickname → the relay needs the
                // account path for authoritative ownership (an anonymous token
                // has no stable owner). Never spend a blind token here.
                sig = try await relay.sendMessage(
                    to: Self.address, memoBase64: memo,
                    endpointURL: rpc.currentEndpoint.address, computeUnitLimit: 600_000,
                    allowAnonymousToken: false)
            } else {
                sig = try await MemoTransactionBuilder.send(
                    from: keypair, to: Self.address, memoBase64: memo,
                    endpointURL: rpc.currentEndpoint.address, apiClient: rpc.client,
                    computeUnitLimit: 600_000)   // big memo → raise Memo program budget
            }
            UserDefaults.standard.set(nick + "|" + (avatarSeed ?? ""), forKey: Self.publishedKey + address)
            lastPublishedSig = sig
            lastPublishError = nil
            return nil
        } catch {
            let e = error.localizedDescription
            lastPublishError = e
            return e
        }
    }

    // MARK: - Search

    /// Find a contact by nickname (case-insensitive) or exact address.

    /// FIRST CLAIM WINS, decided by the chain rather than by the record.

    /// The registry is a public address anyone can write a memo to, and the relay
    /// only sees the publishes that go through it - so a direct publish never
    /// passed its ownership check at all. Ranking by the record's own `at` field
    /// then handed the result to whoever wrote the largest number in it: an
    /// attacker could claim any existing handle for one network fee and receive
    /// the opening messages meant for its owner. Reported externally.

    /// What a chain can prove without a server is order. The earliest valid
    /// record for a handle fixes which wallet owns it, and later records are
    /// accepted only from that same wallet - which is how a key rotation still
    /// works. Every record is checked for a wallet signature binding the bundle
    /// to its address before any of this, so a record cannot claim someone else's
    /// keys either.

    /// What this still cannot do: prove that the wallet which got there first is
    /// the person you have in mind. Compare a safety number for that.
    func search(query: String, rpc: SolanaRPCService) async -> DiscoveryService.DiscoveryUser? {
        guard Self.isConfigured else { return nil }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }

        // Every matching record, with the time the chain says it landed.
        var matches: [(record: DiscoveryRecord, at: Int64)] = []
        var before: String?
        for _ in 0..<Self.maxPages {
            let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize, before: before)
            guard let sigs = try? await rpc.client.getSignaturesForAddress(address: Self.address, configs: config),
                  !sigs.isEmpty else { break }
            for info in sigs {
                guard info.err == nil, let memo = info.memo, let rec = Self.decode(memo) else { continue }
                guard rec.nickname.lowercased() == q || rec.address.lowercased() == q else { continue }
                // A record whose bundle is not signed by the wallet it names is
                // not a candidate for anything.
                guard Self.isSelfConsistent(rec) else { continue }
                // No block time means the transaction is too fresh to be ordered
                // against anything, and a record that cannot be ordered cannot be
                // allowed to win a first-claim contest.
                guard let blockTime = info.blockTime else { continue }
                matches.append((rec, Int64(blockTime)))
            }
            before = sigs.last?.signature
            if sigs.count < Self.pageSize { break }
        }

        guard let owner = matches.min(by: { $0.at < $1.at })?.record.address else { return nil }
        // The owner's most recent record, so rotating keys still works.
        guard let r = matches
            .filter({ $0.record.address == owner })
            .max(by: { $0.at < $1.at })?.record
        else { return nil }
        // Rebuild the canonical base64(JSON) bundle from the packed record so the
        // rest of the app (Contact storage, isBoundTo) keeps its usual format.
        guard let packed = Data(base64Encoded: r.bundle),
              let bundle = PrekeyBundle(discoveryPacked: packed) else { return nil }
        return DiscoveryService.DiscoveryUser(
            address: r.address, nickname: r.nickname, bundleBase64: bundle.base64Encoded,
            avatarSeed: r.avatarSeed)
    }

    /// True when the record's bundle is signed by the wallet the record names.

    /// This is what stops a record from claiming somebody else's keys. It says
    /// nothing about whether that wallet is entitled to the handle - that is what
    /// the first-claim rule above is for.
    private static func isSelfConsistent(_ record: DiscoveryRecord) -> Bool {
        guard let packed = Data(base64Encoded: record.bundle),
              let bundle = PrekeyBundle(discoveryPacked: packed) else { return false }
        return bundle.isBoundTo(address: record.address)
    }

    // MARK: - Codec

    /// Memo = "PDIR1:" + JSON(record) as raw UTF-8 text. The bundle inside is
    /// compact-packed; storing the JSON directly (no base64 wrapper, which added
    /// ~33%) keeps the memo small enough for the Memo program's compute budget.
    private static func encode(_ record: DiscoveryRecord) -> String? {
        guard let json = try? JSONEncoder().encode(record),
              let str = String(data: json, encoding: .utf8) else { return nil }
        return memoPrefix + str
    }

    private static func decode(_ memo: String) -> DiscoveryRecord? {
        let cleaned = memo.hasPrefix("[")
            ? String(memo.drop { $0 != " " }.dropFirst()).trimmingCharacters(in: .whitespaces)
            : memo
        guard cleaned.hasPrefix(memoPrefix) else { return nil }
        let jsonStr = String(cleaned.dropFirst(memoPrefix.count))
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DiscoveryRecord.self, from: data)
    }
}
