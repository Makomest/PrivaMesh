//
//  NFTAvatarView.swift
//  privamesh
//
//  NFT avatars were removed before the App Store release: everyone now uses the
//  default deterministic mesh avatar. This view is kept as a thin compatibility
//  wrapper so existing call sites (chats, contacts, profile) keep compiling and
//  render the default avatar derived from the same seed/id.
//

import SwiftUI

struct NFTAvatarView: View {
    let seed: String
    var size: CGFloat = 72
    /// Kept for source compatibility; ignored (no NFT rarity rings anymore).
    var ringColor: Color? = nil

    var body: some View {
        MeshAvatarView(id: seed, size: size)
            .overlay(Circle().stroke(Color.white.opacity(0.80), lineWidth: 2))
            .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 12) {
        NFTAvatarView(seed: "animals-05", size: 72)
        NFTAvatarView(seed: "stars-07", size: 72)
        NFTAvatarView(seed: "anon-03", size: 72)
    }
    .padding()
}
