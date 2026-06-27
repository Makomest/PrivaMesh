//
//  AvatarService.swift
//  privamesh
//
//  NFT avatar system.
//
//  • Collections = procedurally generated designs (see NFTAvatarView).
//  • You buy a design with real SOL → you own it; it leaves the market (1-of-1).
//  • Owned avatars: pick the active one or sell it back.
//  • Primary sale revenue goes to the dev wallet (real SOL); purchases mint a
//    real on-chain SPL token (OnChainNFT) so ownership is seed-portable.
//
//  Ownership/active selection are cached per wallet in UserDefaults; global
//  1-of-1 uniqueness is enforced via the on-chain market registry (sold events).
//

import Foundation

struct AvatarDesign: Identifiable, Codable, Hashable {
    let id: String          // unique seed, e.g. "genesis-001"
    let collection: String
    let name: String
    let priceSOL: Double
    let rarity: Rarity

    enum Rarity: String, Codable, CaseIterable {
        case common    = "Common"
        case rare      = "Rare"
        case epic      = "Epic"
        case legendary = "Legendary"
    }
}

@Observable
final class AvatarService {
    /// Developer wallet that receives primary-sale revenue.
    static let developerRoyaltyAddress = "BXHeL81X5ihyn9WnodaBcgpo9J7fWSkYy1vunYZN1zAQ"

    private static let ownedKey  = "privamesh.avatars.owned."   // + wallet
    private static let activeKey = "privamesh.avatars.active."  // + wallet
    private static let soldKey   = "privamesh.avatars.sold."    // + wallet (primary-sold ids)

    /// The full first collection, available to browse.
    let catalog: [AvatarDesign]

    private(set) var ownedIDs: [String] = []
    private(set) var activeID: String?
    /// Designs whose sale already happened (owned by someone, locally or adopted
    /// from the on-chain registry) — hidden from the market for 1-of-1 uniqueness.
    private(set) var soldIDs: Set<String> = []

    private var walletKey = ""

    init() {
        catalog = Self.makeGenesisCollection()
    }

    // MARK: - Binding / persistence

    func bind(to walletPublicKey: String) {
        guard !walletPublicKey.isEmpty, walletKey != walletPublicKey else { return }
        walletKey = walletPublicKey
        let d = UserDefaults.standard
        ownedIDs = d.stringArray(forKey: Self.ownedKey + walletKey) ?? []
        activeID = d.string(forKey: Self.activeKey + walletKey)
        soldIDs  = Set(d.stringArray(forKey: Self.soldKey + walletKey) ?? [])
    }

    private func persist() {
        guard !walletKey.isEmpty else { return }
        let d = UserDefaults.standard
        d.set(ownedIDs, forKey: Self.ownedKey + walletKey)
        d.set(Array(soldIDs), forKey: Self.soldKey + walletKey)
        if let activeID { d.set(activeID, forKey: Self.activeKey + walletKey) }
        else { d.removeObject(forKey: Self.activeKey + walletKey) }
    }

    // MARK: - Derived

    var ownedDesigns: [AvatarDesign] {
        ownedIDs.compactMap { id in catalog.first { $0.id == id } }
    }

    /// Market = designs not yet sold to anyone.
    var marketDesigns: [AvatarDesign] {
        catalog.filter { !soldIDs.contains($0.id) && !ownedIDs.contains($0.id) }
    }

    var activeDesign: AvatarDesign? {
        guard let activeID else { return nil }
        return catalog.first { $0.id == activeID }
    }

    func isOwned(_ id: String) -> Bool { ownedIDs.contains(id) }

    // MARK: - Actions

    func buy(_ design: AvatarDesign) {
        guard !ownedIDs.contains(design.id) else { return }
        ownedIDs.append(design.id)
        soldIDs.insert(design.id)          // gone from the market — now unique to owner
        if activeID == nil { activeID = design.id }
        persist()
    }

    /// Mark a catalog design as sold by SOMEONE ELSE (from the global registry)
    /// so it leaves this user's market too — true 1-of-1. Returns true if changed.
    @discardableResult
    func markSold(_ id: String) -> Bool {
        guard catalog.contains(where: { $0.id == id }),
              !soldIDs.contains(id), !ownedIDs.contains(id) else { return false }
        soldIDs.insert(id)
        persist()
        return true
    }

    /// Merge avatar design ids the wallet owns ON-CHAIN (see OnChainNFT) into the
    /// local collection — restores avatars from chain on a fresh device.
    func adoptOnChain(_ designIds: [String]) {
        var changed = false
        for id in designIds where catalog.contains(where: { $0.id == id }) && !ownedIDs.contains(id) {
            ownedIDs.append(id); soldIDs.insert(id); changed = true
        }
        if changed { persist() }
    }

    func setActive(_ id: String?) {
        if let id, !ownedIDs.contains(id) { return }
        activeID = id
        persist()
    }

    func sell(_ id: String) {
        ownedIDs.removeAll { $0 == id }
        soldIDs.remove(id)                 // back on the market
        if activeID == id { activeID = nil }
        persist()
    }

    // MARK: - First collection (generated)

    /// Special test/brand NFT — the PrivaMesh logo, priced at a dust amount so
    /// the marketplace can be exercised end-to-end on mainnet for ~nothing.
    static let logoDesignID = "privamesh"

    private static func makeGenesisCollection() -> [AvatarDesign] {
        // 0.001 SOL: a transfer must leave the recipient at/above Solana's
        // rent-exempt minimum (~0.00089 SOL), so a dust price like 1e-7 is
        // rejected ("insufficient funds for rent"). 0.001 is the cheapest safe.
        let logo = AvatarDesign(
            id: logoDesignID, collection: "PrivaMesh", name: "PrivaMesh Genesis",
            priceSOL: 0.001, rarity: .legendary)
        // 4 themed collections × 10 pieces, all priced at 1 SOL. Rarity only
        // tints the ring (no longer drives price).
        return [logo] + AvatarCatalog.collections.flatMap { collection in
            collection.items.enumerated().map { idx, item in
                AvatarDesign(
                    id: AvatarCatalog.id(collection.key, idx + 1),
                    collection: collection.title,
                    name: item.name,
                    priceSOL: AvatarCatalog.priceSOL,
                    rarity: rarity(forIndex: idx)
                )
            }
        }
    }

    /// Ring flavor by position within a 10-piece collection (price is flat).
    private static func rarity(forIndex i: Int) -> AvatarDesign.Rarity {
        switch i {
        case 0, 1: return .legendary
        case 2, 3: return .epic
        case 4, 5, 6: return .rare
        default: return .common
        }
    }
}
