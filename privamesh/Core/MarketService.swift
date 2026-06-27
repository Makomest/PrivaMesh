//
//  MarketService.swift
//  privamesh
//
//  Unified in-app marketplace. Trades two kinds of collectibles: NFT avatars
//  and NFT nicknames. Purchases pay real SOL (genesis → dev wallet; resale →
//  seller + commission) and mint a real on-chain SPL token (see OnChainNFT);
//  ownership is also cached locally per wallet. Resale lots are discovered via
//  the on-chain memo registry (MarketRegistry). 1-of-1: a bought item leaves
//  every user's market.
//
//  • Browse by category (avatars / nicknames) and buy.
//  • List your own items for sale at a chosen price; see/remove your listings.
//  • Favourite listings locally.
//
//  Avatar ownership/active selection live in AvatarService; this service owns
//  nickname collectibles, listings and favourites. Persisted per wallet.
//

import Foundation

struct MarketItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case avatar, nickname }
    let id: String          // avatar design id, or "nick:<handle>"
    let kind: Kind
    let name: String        // display name
    let ref: String         // avatar seed (= design id) or nickname handle
    var priceSOL: Double
    let rarity: String?     // avatars only
    var collection: String? = nil  // avatars only
}

struct MarketListing: Identifiable, Hashable {
    let id: String          // stable, derived from the item id
    let item: MarketItem
    let sellerIsMe: Bool
    var priceSOL: Double
    /// Seller's wallet address for a live (registry) resale lot; nil for genesis
    /// primary sales (paid entirely to the dev wallet).
    var sellerAddress: String? = nil
}

@Observable
@MainActor
final class MarketService {
    private let avatars: AvatarService

    // Persistence keys (+ wallet)
    private static let ownedNicksKey = "privamesh.market.ownedNicks."
    private static let soldNicksKey  = "privamesh.market.soldNicks."
    private static let myListingsKey = "privamesh.market.myListings."
    private static let favoritesKey  = "privamesh.market.favorites."
    private static let mintedKey     = "privamesh.market.minted."
    private static let paidKey       = "privamesh.market.paid."
    private static let processedKey  = "privamesh.market.processedSales."

    /// Dev wallet that receives marketplace payments. Genesis items are a
    /// primary sale → the full price goes here. Set this to YOUR Solana address
    /// (base58). Empty string disables purchases (no destination to pay).
    static let devWallet = "BXHeL81X5ihyn9WnodaBcgpo9J7fWSkYy1vunYZN1zAQ"

    var purchasesEnabled: Bool { !Self.devWallet.isEmpty }

    /// Official handles reserved to the dev wallet — never buyable, never
    /// mintable by anyone. Only the dev wallet "owns" them. Lowercased.
    static let reservedNicknames: Set<String> = [
        "support", "admin", "privamesh", "official", "team", "mod", "moderator",
        "help", "root", "system", "staff", "owner", "founder", "ceo",
    ]

    /// Reserved handles I own (only when signed in as the dev wallet).
    private var reservedOwned: [String] {
        walletKey == Self.devWallet ? Self.reservedNicknames.sorted() : []
    }

    /// Merge nickname NFTs the wallet owns ON-CHAIN (design ids "nick:<handle>")
    /// into the local collection — restores nicks from chain on a fresh device.
    func adoptOnChainNicks(_ designIds: [String]) {
        var changed = false
        for id in designIds where id.hasPrefix("nick:") {
            let handle = String(id.dropFirst("nick:".count))
            if !handle.isEmpty, !ownedNicknames.contains(handle) {
                ownedNicknames.append(handle); changed = true
            }
        }
        if changed { persist() }
    }

    /// A reserved (non-transferable) official handle.
    func isReserved(_ item: MarketItem) -> Bool {
        item.kind == .nickname && Self.reservedNicknames.contains(item.ref.lowercased())
    }

    /// Dev commission on user-to-user RESALE (percent). Genesis is a primary
    /// sale → 100% to dev (no split). Resale → seller gets the rest.
    static let resaleCommissionPercent = 5.0

    /// Free accounts can list up to this many lots; premium is unlimited.
    static let freeListingLimit = 3
    /// Premium accounts can mint up to this many custom NFT nicknames.
    static let maxMintsPremium = 3

    /// Nickname handles available to buy (first collection).
    let nicknameCatalog: [MarketItem]

    private(set) var ownedNicknames: [String] = []
    private(set) var soldNicknames: Set<String> = []          // bought by someone → off market
    private(set) var myListedItemIDs: [String: Double] = [:]  // itemId → my asking price
    private(set) var favorites: Set<String> = []              // listing ids I favourited
    private(set) var mintedNicknames: Set<String> = []        // custom NFT nicks I minted
    private(set) var purchasePrices: [String: Double] = [:]   // itemId → price I paid
    private var processedSales: Set<String> = []              // itemIds whose remote sale I already finalized

    private var walletKey = ""

    init(avatars: AvatarService) {
        self.avatars = avatars
        nicknameCatalog = Self.makeNicknameCatalog()
    }

    // MARK: - Binding / persistence

    /// Active wallet address (the seller, when I list something).
    var myAddress: String { walletKey }

    func bind(to wallet: String) {
        guard !wallet.isEmpty, walletKey != wallet else { return }
        walletKey = wallet
        let d = UserDefaults.standard
        ownedNicknames  = d.stringArray(forKey: Self.ownedNicksKey + wallet) ?? []
        soldNicknames   = Set(d.stringArray(forKey: Self.soldNicksKey + wallet) ?? [])
        favorites       = Set(d.stringArray(forKey: Self.favoritesKey + wallet) ?? [])
        mintedNicknames = Set(d.stringArray(forKey: Self.mintedKey + wallet) ?? [])
        purchasePrices  = (d.dictionary(forKey: Self.paidKey + wallet) as? [String: Double]) ?? [:]
        myListedItemIDs = (d.dictionary(forKey: Self.myListingsKey + wallet) as? [String: Double]) ?? [:]
        processedSales  = Set(d.stringArray(forKey: Self.processedKey + wallet) ?? [])
    }

    private func persist() {
        guard !walletKey.isEmpty else { return }
        let d = UserDefaults.standard
        d.set(ownedNicknames, forKey: Self.ownedNicksKey + walletKey)
        d.set(Array(soldNicknames), forKey: Self.soldNicksKey + walletKey)
        d.set(Array(favorites), forKey: Self.favoritesKey + walletKey)
        d.set(Array(mintedNicknames), forKey: Self.mintedKey + walletKey)
        d.set(purchasePrices, forKey: Self.paidKey + walletKey)
        d.set(myListedItemIDs, forKey: Self.myListingsKey + walletKey)
        d.set(Array(processedSales), forKey: Self.processedKey + walletKey)
    }

    /// Finalize lots of mine that sold on-chain (the registry saw `sold` events).
    /// Removes them from my collection + listings and notifies once each.
    func finalizeRemoteSales(soldItemIds: [String]) {
        var changed = false
        for id in soldItemIds where !processedSales.contains(id) {
            // Only act on items I actually still hold/list.
            let listedPrice = myListedItemIDs[id]
            let item = myCollection.first { $0.id == id }
            guard listedPrice != nil || item != nil else { continue }
            processedSales.insert(id)
            myListedItemIDs[id] = nil
            if let item {
                let price = listedPrice ?? 0
                switch item.kind {
                case .avatar:
                    avatars.sell(item.ref)
                    NotificationService.shared.notifyAvatarSold(name: item.name, priceSOL: price)
                case .nickname:
                    ownedNicknames.removeAll { $0 == item.ref }
                    NotificationService.shared.notifyNicknameSold(nickname: item.name, priceSOL: price)
                }
            }
            changed = true
        }
        if changed { persist() }
    }

    func purchasePrice(_ itemID: String) -> Double? { purchasePrices[itemID] }

    /// Adopt items sold globally (folded from the on-chain registry) so a design
    /// bought by ANYONE disappears from this user's market too — true 1-of-1.
    /// Skips items this user already owns.
    func adoptGlobalSales(avatarRefs: Set<String>, nickRefs: Set<String>) {
        var changed = false
        for ref in avatarRefs { if avatars.markSold(ref) { changed = true } }
        for ref in nickRefs where !ownedNicknames.contains(ref) {
            if soldNicknames.insert(ref).inserted { changed = true }
        }
        if changed { persist() }
    }

    // MARK: - Items / collection

    private func avatarItem(_ d: AvatarDesign) -> MarketItem {
        MarketItem(id: d.id, kind: .avatar, name: d.name, ref: d.id,
                   priceSOL: d.priceSOL, rarity: d.rarity.rawValue, collection: d.collection)
    }

    /// Avatar collections present on the market, with how many lots each has.
    var avatarCollections: [(name: String, count: Int)] {
        let grouped = Dictionary(grouping: listings(kind: .avatar)) { $0.item.collection ?? "Genesis" }
        return grouped.map { (name: $0.key, count: $0.value.count) }.sorted { $0.name < $1.name }
    }

    /// Everything the user owns (avatars + nicknames).
    var myCollection: [MarketItem] {
        avatars.ownedDesigns.map(avatarItem)
        + (ownedNicknames + reservedOwned).map {
            MarketItem(id: "nick:\($0)", kind: .nickname, name: $0, ref: $0,
                       priceSOL: 0, rarity: nil)
        }
    }

    /// Already own this item? Guards against paying for something `buy()` would
    /// no-op on (avatar already owned / nickname already held).
    func owns(_ item: MarketItem) -> Bool {
        switch item.kind {
        case .avatar:   return avatars.ownedDesigns.contains { $0.id == item.ref }
        case .nickname: return ownedNicknames.contains(item.ref)
        }
    }

    // MARK: - Market listings

    private func listing(for item: MarketItem, mine: Bool) -> MarketListing {
        let price = mine ? (myListedItemIDs[item.id] ?? item.priceSOL) : item.priceSOL
        return MarketListing(id: "lot:\(item.id)", item: item, sellerIsMe: mine,
                             priceSOL: price)
    }

    func listings(kind: MarketItem.Kind) -> [MarketListing] {
        switch kind {
        case .avatar:
            // Catalog avatars still on the market + any I listed.
            let market = avatars.marketDesigns.map { avatarItem($0) }.map { listing(for: $0, mine: false) }
            let mine = myCollection.filter { $0.kind == .avatar && myListedItemIDs[$0.id] != nil }
                .map { listing(for: $0, mine: true) }
            return mine + market
        case .nickname:
            let market = nicknameCatalog
                .filter { !soldNicknames.contains($0.ref) && !ownedNicknames.contains($0.ref) }
                .map { listing(for: $0, mine: false) }
            let mine = myCollection.filter { $0.kind == .nickname && myListedItemIDs[$0.id] != nil }
                .map { listing(for: $0, mine: true) }
            return mine + market
        }
    }

    var myListings: [MarketListing] {
        myCollection.filter { myListedItemIDs[$0.id] != nil }.map { listing(for: $0, mine: true) }
    }

    // MARK: - Favourites

    func isFavorite(_ listing: MarketListing) -> Bool { favorites.contains(listing.id) }
    func toggleFavorite(_ listing: MarketListing) {
        if favorites.contains(listing.id) { favorites.remove(listing.id) }
        else { favorites.insert(listing.id) }
        persist()
    }
    var favoriteListings: [MarketListing] {
        let all = listings(kind: .avatar) + listings(kind: .nickname)
        return all.filter { favorites.contains($0.id) }
    }

    /// Drop favourited ids whose item is no longer on the market (sold/owned),
    /// so the local favourites set doesn't accumulate dead entries.
    func pruneFavorites() {
        let valid = Set(favoriteListings.map(\.id))
        if valid != favorites { favorites = valid; persist() }
    }

    // MARK: - Actions

    func buy(_ listing: MarketListing) {
        // Can't buy your own listing.
        guard !listing.sellerIsMe else { return }
        switch listing.item.kind {
        case .avatar:
            if let d = avatars.catalog.first(where: { $0.id == listing.item.ref }) { avatars.buy(d) }
        case .nickname:
            if !ownedNicknames.contains(listing.item.ref) {
                ownedNicknames.append(listing.item.ref)
                soldNicknames.insert(listing.item.ref)
            }
        }
        purchasePrices[listing.item.id] = listing.priceSOL   // remember what I paid
        myListedItemIDs[listing.item.id] = nil               // if it was my listing, it's gone
        persist()
    }

    /// Free accounts: max `freeListingLimit` lots. Premium: unlimited.
    func canList(isPremium: Bool) -> Bool {
        isPremium || myListings.count < Self.freeListingLimit
    }

    /// Put an owned item up for sale at `price`. Caller checks `canList` first.
    /// No fake buyer — a real resale market needs a shared listings registry
    /// (backend / on-chain accounts), which doesn't exist yet, so the lot simply
    /// stays listed until removed.
    func list(item: MarketItem, price: Double) {
        guard myCollection.contains(where: { $0.id == item.id }) else { return }
        myListedItemIDs[item.id] = price
        persist()
    }

    // MARK: - Minting (premium)

    func canMint(isPremium: Bool) -> Bool {
        isPremium && mintedNicknames.count < Self.maxMintsPremium
    }

    /// Is this handle free to mint? Checks the catalog and everything known
    /// locally (owned/minted/sold). NOTE: no backend — this is a local-only
    /// availability check; true global uniqueness needs a shared registry.
    func isNicknameAvailable(_ handle: String) -> Bool {
        let h = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard h.count >= 2 else { return false }
        if Self.reservedNicknames.contains(h) { return false }   // dev-only handles
        if ownedNicknames.contains(where: { $0.lowercased() == h }) { return false }
        if mintedNicknames.contains(where: { $0.lowercased() == h }) { return false }
        if soldNicknames.contains(where:   { $0.lowercased() == h }) { return false }
        if nicknameCatalog.contains(where: { $0.ref.lowercased() == h }) { return false }
        return true
    }

    /// Create a custom NFT nickname owned by the user (premium). The on-chain
    /// "creation fee" is paid by the caller via a memo tx; this records ownership.
    func mintNickname(_ handle: String) {
        let h = handle.trimmingCharacters(in: .whitespaces)
        guard isNicknameAvailable(h) else { return }
        ownedNicknames.append(h)
        mintedNicknames.insert(h)
        persist()
    }

    func delist(itemID: String) {
        myListedItemIDs[itemID] = nil
        persist()
    }

    func isListed(_ itemID: String) -> Bool { myListedItemIDs[itemID] != nil }

    // MARK: - Gifting

    /// Remove a gifted nickname from my collection.
    func giveAwayNickname(_ handle: String) {
        ownedNicknames.removeAll { $0 == handle }
        myListedItemIDs["nick:\(handle)"] = nil
        persist()
    }

    /// Claim an NFT gifted to me in chat.
    func claimGift(kind: String, ref: String) {
        if kind == "avatar" {
            if let d = avatars.catalog.first(where: { $0.id == ref }) { avatars.buy(d) }
        } else {
            if !ownedNicknames.contains(ref) {
                ownedNicknames.append(ref)
                soldNicknames.insert(ref)
            }
        }
        persist()
    }

    // MARK: - Generators

    private static func makeNicknameCatalog() -> [MarketItem] {
        // All nicks cost 1 SOL. Mix of short, crypto, film/pop-culture and long
        // "cool" handles. Reserved handles are excluded (dev-only).
        let handles = [
            // short
            "Zero", "Vortex", "Echo", "Nyx", "Apex", "Rune", "Flux",
            "Onyx", "Cipher", "Halo", "Pixel", "Ghost", "Raven", "Volt", "Hex",
            "Nova", "Ace", "Zen", "Riot", "Drift", "Saint", "Vibe", "Kilo",
            // crypto
            "Satoshi", "Vitalik", "Hodl", "Degen", "Whale", "Diamond", "Moon",
            "Lambo", "Wagmi", "Alpha", "Anatoly", "Phantom", "Gwei", "Solana",
            // film / pop-culture
            "Morpheus", "Trinity", "Vendetta", "Joker", "Wick", "Maverick",
            "Vader", "Yoda", "Gandalf", "Loki", "Thanos", "Bond",
            // long & cool
            "Nightcrawler", "Quicksilver", "Voidwalker", "Stormbringer",
            "Bladerunner", "Cyberpunk", "Singularity", "Darkmatter",
        ]
        let regular = handles
            .filter { !reservedNicknames.contains($0.lowercased()) }
            .map { h in
                MarketItem(id: "nick:\(h)", kind: .nickname, name: h, ref: h,
                           priceSOL: 1.0, rarity: nil)
            }
        // Test/cheap nicks at the rent-safe minimum (0.001 SOL).
        let cheap = ["Decart", "Neo"].map { h in
            MarketItem(id: "nick:\(h)", kind: .nickname, name: h, ref: h, priceSOL: 0.001, rarity: nil)
        }
        return cheap + regular
    }
}
