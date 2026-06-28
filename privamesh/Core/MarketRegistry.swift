//
//  MarketRegistry.swift
//  privamesh
//
//  Serverless marketplace over RPC. Listings are memo transactions sent to the
//  shared registry address (the dev wallet). Reconstruct the open lots by
//  scanning that address with getSignaturesForAddress and folding the
//  list/unlist/sold events — no backend.
//
//  TRUST CAVEAT: item ownership is not on-chain, so a `list` event is taken at
//  face value (the seller field is trusted). Spoofed listings are possible; a
//  real fix needs on-chain NFTs or an escrow program. Purchases pay the seller
//  + dev commission atomically, but without escrow a double-sell is possible.
//

import Foundation
import SolanaSwift

@Observable
@MainActor
final class MarketRegistry {
    /// Shared listings address — reuse the dev wallet.
    static var address: String { MarketService.devWallet }
    static var isConfigured: Bool { !address.isEmpty }

    /// How many recent registry signatures to scan (pages × pageSize).
    private static let pageSize = 100
    private static let maxPages = 3

    private(set) var listings: [MarketListing] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    // MARK: - Read

    /// Rebuild the open-listing set from the registry's on-chain history, and
    /// finalize any of MY lots that sold remotely.
    func refresh(rpc: SolanaRPCService, market: MarketService) async {
        guard Self.isConfigured else { return }
        let myAddress = market.myAddress
        isLoading = true
        defer { isLoading = false }

        var events: [(MarketEvent, Double)] = []   // event + blockTime
        var before: String?
        for _ in 0..<Self.maxPages {
            let config = RequestConfiguration(commitment: "confirmed", limit: Self.pageSize, before: before)
            guard let sigs = try? await rpc.client.getSignaturesForAddress(address: Self.address, configs: config),
                  !sigs.isEmpty else { break }
            for info in sigs {
                guard info.err == nil, let memo = info.memo,
                      let event = MarketEvent.from(memo: memo) else { continue }
                let t = info.blockTime.map(Double.init) ?? 0
                events.append((event, t))
            }
            before = sigs.last?.signature
            if sigs.count < Self.pageSize { break }
        }

        // Fold oldest → newest: a lot is open after `list`, closed after unlist/sold.
        events.sort { $0.1 < $1.1 }
        var open: [String: MarketEvent] = [:]
        var mySoldItemIds: [String] = []
        var soldAvatarRefs = Set<String>()   // designs sold by ANYONE → globally gone
        var soldNickRefs   = Set<String>()
        func recordSold(_ item: MarketItem) {
            switch item.kind {
            case .avatar:   soldAvatarRefs.insert(item.ref)
            case .nickname: soldNickRefs.insert(item.ref)
            }
        }
        for (event, _) in events {
            switch event.type {
            case .list:   open[event.lotId] = event
            case .unlist: open[event.lotId] = nil
            case .sold:
                if let listed = open[event.lotId], listed.seller == myAddress,
                   let itemId = listed.item?.id {
                    mySoldItemIds.append(itemId)
                }
                // Global 1-of-1: a genesis `.sold` carries the item directly; a
                // resale `.sold` is matched to its open `.list` for the item.
                if let item = event.item { recordSold(item) }
                else if let item = open[event.lotId]?.item { recordSold(item) }
                open[event.lotId] = nil
            }
        }

        listings = open.values.compactMap { event in
            guard let item = event.item else { return nil }
            return MarketListing(
                id: "live:\(event.lotId)", item: item,
                sellerIsMe: event.seller == myAddress, priceSOL: item.priceSOL,
                sellerAddress: event.seller)
        }
        .sorted { $0.priceSOL < $1.priceSOL }

        if !mySoldItemIds.isEmpty { market.finalizeRemoteSales(soldItemIds: mySoldItemIds) }
        market.adoptGlobalSales(avatarRefs: soldAvatarRefs, nickRefs: soldNickRefs)
        lastError = nil
    }

    // MARK: - Write (publish events)

    /// Publish a `list` event so others can discover and buy the lot.
    func publishList(item: MarketItem, seller: String,
                     keypair: KeyPair, rpc: SolanaRPCService) async throws {
        let event = MarketEvent(type: .list, lotId: MarketEvent.lotId(itemId: item.id, seller: seller),
                                item: item, seller: seller)
        try await publish(event, keypair: keypair, rpc: rpc)
    }

    /// Publish an `unlist` event (take the lot off the market).
    func publishUnlist(itemId: String, seller: String,
                       keypair: KeyPair, rpc: SolanaRPCService) async throws {
        let event = MarketEvent(type: .unlist, lotId: MarketEvent.lotId(itemId: itemId, seller: seller),
                                seller: seller)
        try await publish(event, keypair: keypair, rpc: rpc)
    }

    /// Publish a genesis primary `sold` event so the design leaves EVERYONE's
    /// market (true 1-of-1). Carries the item so others know which design is gone.
    func publishGenesisSold(item: MarketItem, buyer: String,
                            keypair: KeyPair, rpc: SolanaRPCService) async throws {
        let event = MarketEvent(type: .sold, lotId: "genesis:\(item.id)",
                                item: item, seller: Self.address, buyer: buyer)
        try await publish(event, keypair: keypair, rpc: rpc)
    }

    private func publish(_ event: MarketEvent, keypair: KeyPair, rpc: SolanaRPCService) async throws {
        guard Self.isConfigured, let memo = event.memoString() else { return }
        // A listing event carries the item (title, design, price, seller, buyer)
        // and can exceed ~566 B, which fails on the default compute budget with
        // "Program failed to complete". Raise the Memo program's compute limit.
        _ = try await MemoTransactionBuilder.send(
            from: keypair, to: Self.address, memoBase64: memo,
            endpointURL: rpc.currentEndpoint.address, apiClient: rpc.client,
            computeUnitLimit: 600_000)
    }
}
