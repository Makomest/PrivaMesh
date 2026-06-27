//
//  OnChainDiscovery.swift
//  privamesh
//
//  Serverless contact discovery. Instead of an HTTP directory, each user
//  publishes a {nickname, address, bundle} record as a memo transaction to a
//  shared registry address. Search scans that address's history (RPC) and
//  matches by nickname — no backend, same mechanism as chat + market.
//
//  Wire format:  "PDIR1:" + base64(zlib(JSON(DiscoveryRecord)))
//  The bundle is already wallet-signed, so an added contact is verified against
//  its address (anti-MITM) — see PrekeyBundle.isBoundTo.
//

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
            let sig = try await MemoTransactionBuilder.send(
                from: keypair, to: Self.address, memoBase64: memo,
                endpointURL: rpc.currentEndpoint.address, apiClient: rpc.client,
                computeUnitLimit: 600_000)   // big memo → raise Memo program budget
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

    /// Find a contact by nickname (case-insensitive) or exact address. Newest
    /// record wins. Returns nil if not found.
    func search(query: String, rpc: SolanaRPCService) async -> DiscoveryService.DiscoveryUser? {
        guard Self.isConfigured else { return nil }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }

        var best: DiscoveryRecord?
        var before: String?
        for _ in 0..<Self.maxPages {
            let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize, before: before)
            guard let sigs = try? await rpc.client.getSignaturesForAddress(address: Self.address, configs: config),
                  !sigs.isEmpty else { break }
            for info in sigs {
                guard info.err == nil, let memo = info.memo, let rec = Self.decode(memo) else { continue }
                if rec.nickname.lowercased() == q || rec.address.lowercased() == q {
                    if best == nil || rec.at > best!.at { best = rec }
                }
            }
            before = sigs.last?.signature
            if sigs.count < Self.pageSize { break }
        }
        guard let r = best else { return nil }
        // Rebuild the canonical base64(JSON) bundle from the packed record so the
        // rest of the app (Contact storage, isBoundTo) keeps its usual format.
        guard let packed = Data(base64Encoded: r.bundle),
              let bundle = PrekeyBundle(discoveryPacked: packed) else { return nil }
        return DiscoveryService.DiscoveryUser(
            address: r.address, nickname: r.nickname, bundleBase64: bundle.base64Encoded,
            avatarSeed: r.avatarSeed)
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
