//
//  UserProfileService.swift
//  privamesh
//
//  Your own profile bio, plus a shareable snapshot of your public profile
//  (bio + inventory + active avatar + what you have for sale). The snapshot
//  rides inside the ContactCard so contacts can view your profile offline.
//  It is a point-in-time copy (no backend), so a contact sees what was true
//  when they added you / last received your card.
//

import Foundation

struct ProfileSnapshot: Codable, Hashable {
    /// The user's own display nickname (NFT nick or auto-generated).
    var nickname: String = ""
    var bio: String = ""
    var activeAvatarSeed: String?
    var nicknames: [String] = []
    var avatars: [SnapAvatar] = []
    var listings: [SnapListing] = []

    struct SnapAvatar: Codable, Hashable {
        let seed: String
        let name: String
        let rarity: String?
    }
    struct SnapListing: Codable, Hashable {
        let kind: String   // "avatar" | "nickname"
        let ref: String
        let name: String
        let price: Double
    }

    /// Price this profile is asking for an item ref (nil if not for sale).
    func price(forRef ref: String) -> Double? {
        listings.first { $0.ref == ref }?.price
    }
}

@Observable
@MainActor
final class UserProfileService {
    private static let bioKey = "privamesh.profile.bio."

    private(set) var bio = ""
    private var walletKey = ""

    func bind(to wallet: String) {
        guard !wallet.isEmpty, walletKey != wallet else { return }
        walletKey = wallet
        bio = UserDefaults.standard.string(forKey: Self.bioKey + wallet) ?? ""
    }

    func setBio(_ text: String) {
        bio = String(text.prefix(280))
        guard !walletKey.isEmpty else { return }
        UserDefaults.standard.set(bio, forKey: Self.bioKey + walletKey)
    }

    /// Slim snapshot for the QR code — only what fits comfortably (nick, active
    /// avatar, bio). Inventory/listings are omitted to keep the QR small.
    func qrSnapshot(nickname: String, avatars: AvatarService) -> ProfileSnapshot {
        ProfileSnapshot(nickname: nickname, bio: bio, activeAvatarSeed: avatars.activeDesign?.id)
    }

    /// Full snapshot (with inventory + listings) for non-QR sharing.
    func snapshot(nickname: String, avatars: AvatarService, market: MarketService) -> ProfileSnapshot {
        ProfileSnapshot(
            nickname: nickname,
            bio: bio,
            activeAvatarSeed: avatars.activeDesign?.id,
            nicknames: market.ownedNicknames,
            avatars: avatars.ownedDesigns.map {
                .init(seed: $0.id, name: $0.name, rarity: $0.rarity.rawValue)
            },
            listings: market.myListings.map {
                .init(kind: $0.item.kind.rawValue, ref: $0.item.ref, name: $0.item.name, price: $0.priceSOL)
            }
        )
    }
}
