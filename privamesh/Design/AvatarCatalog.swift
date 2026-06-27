//
//  AvatarCatalog.swift
//  privamesh
//
//  Themed avatar collections. Each design id is "<collectionKey>-NN"; both the
//  market catalog (AvatarService) and the renderer (NFTAvatarView) resolve a
//  design's theme + subject symbol from this single source by parsing the id.
//
//  4 collections × 10 unique pieces, all priced at 1 SOL, in the halftone /
//  dithered style.
//

import SwiftUI

enum AvatarCatalog {
    struct Item: Hashable { let symbol: String; let name: String }

    struct Collection: Identifiable {
        let key: String          // id prefix, e.g. "animals"
        let title: String        // display collection name
        let palettes: [[Color]]  // background gradients, picked per-item by hash
        let items: [Item]        // exactly 10
        var id: String { key }
    }

    /// All avatars cost the same.
    static let priceSOL: Double = 1

    static let collections: [Collection] = [animals, stars, people, anon]

    // MARK: - Collections

    private static let animals = Collection(
        key: "animals", title: "Animals",
        palettes: [
            [c(0.13, 0.55, 0.42), c(0.04, 0.20, 0.16)],
            [c(0.85, 0.45, 0.15), c(0.25, 0.12, 0.05)],
            [c(0.20, 0.60, 0.30), c(0.06, 0.18, 0.10)],
            [c(0.70, 0.65, 0.25), c(0.20, 0.16, 0.05)],
        ],
        items: [
            Item(symbol: "hare.fill", name: "Hare"),
            Item(symbol: "tortoise.fill", name: "Tortoise"),
            Item(symbol: "bird.fill", name: "Falcon"),
            Item(symbol: "fish.fill", name: "Shark"),
            Item(symbol: "lizard.fill", name: "Croc"),
            Item(symbol: "pawprint.fill", name: "Wolf"),
            Item(symbol: "ant.fill", name: "Beetle"),
            Item(symbol: "ladybug.fill", name: "Ladybug"),
            Item(symbol: "dog.fill", name: "Hound"),
            Item(symbol: "cat.fill", name: "Lynx"),
        ])

    private static let stars = Collection(
        key: "stars", title: "Stars",
        palettes: [
            [c(0.20, 0.30, 0.85), c(0.03, 0.04, 0.18)],
            [c(0.45, 0.20, 0.85), c(0.08, 0.04, 0.20)],
            [c(0.10, 0.65, 0.80), c(0.02, 0.10, 0.16)],
            [c(0.85, 0.40, 0.20), c(0.18, 0.06, 0.04)],
        ],
        items: [
            Item(symbol: "moon.fill", name: "Luna"),
            Item(symbol: "moon.stars.fill", name: "Nebula"),
            Item(symbol: "star.fill", name: "Nova"),
            Item(symbol: "sparkles", name: "Stardust"),
            Item(symbol: "sun.max.fill", name: "Sol"),
            Item(symbol: "globe.americas.fill", name: "Terra"),
            Item(symbol: "moon.haze.fill", name: "Eclipse"),
            Item(symbol: "atom", name: "Quasar"),
            Item(symbol: "circle.hexagongrid.fill", name: "Cluster"),
            Item(symbol: "sparkle", name: "Pulsar"),
        ])

    private static let people = Collection(
        key: "people", title: "People",
        palettes: [
            [c(0.35, 0.40, 0.55), c(0.08, 0.10, 0.16)],
            [c(0.85, 0.45, 0.20), c(0.20, 0.10, 0.04)],
            [c(0.20, 0.55, 0.85), c(0.04, 0.12, 0.20)],
            [c(0.55, 0.55, 0.58), c(0.12, 0.12, 0.14)],
        ],
        items: [
            Item(symbol: "person.fill", name: "Cipher"),
            Item(symbol: "person.bust.fill", name: "Boss"),
            Item(symbol: "figure.stand", name: "Agent"),
            Item(symbol: "figure.walk", name: "Wanderer"),
            Item(symbol: "figure.wave", name: "Greeter"),
            Item(symbol: "face.smiling.fill", name: "Joker"),
            Item(symbol: "lightbulb.fill", name: "Mastermind"),
            Item(symbol: "mustache.fill", name: "Gentleman"),
            Item(symbol: "hand.wave.fill", name: "Nomad"),
            Item(symbol: "figure.mind.and.body", name: "Monk"),
        ])

    private static let anon = Collection(
        key: "anon", title: "Anonymity",
        palettes: [
            [c(0.16, 0.18, 0.20), c(0.03, 0.03, 0.04)],
            [c(0.12, 0.45, 0.35), c(0.02, 0.10, 0.08)],
            [c(0.30, 0.30, 0.34), c(0.05, 0.05, 0.06)],
            [c(0.20, 0.22, 0.40), c(0.03, 0.03, 0.10)],
        ],
        items: [
            Item(symbol: "eye.slash.fill", name: "Unseen"),
            Item(symbol: "person.fill.questionmark", name: "Nobody"),
            Item(symbol: "theatermasks.fill", name: "Masked"),
            Item(symbol: "lock.fill", name: "Sealed"),
            Item(symbol: "lock.shield.fill", name: "Guarded"),
            Item(symbol: "key.fill", name: "Keyholder"),
            Item(symbol: "shield.fill", name: "Shade"),
            Item(symbol: "hand.raised.fill", name: "Silence"),
            Item(symbol: "person.fill.xmark", name: "Ghost"),
            Item(symbol: "nosign", name: "Redacted"),
        ])

    // MARK: - Lookup

    /// Resolve a design id like "animals-03" to its collection + subject.
    static func resolve(_ id: String) -> (collection: Collection, item: Item, index: Int)? {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let idx = Int(parts[1]),
              let collection = collections.first(where: { $0.key == String(parts[0]) }),
              idx >= 1, idx <= collection.items.count else { return nil }
        return (collection, collection.items[idx - 1], idx - 1)
    }

    static func id(_ key: String, _ index: Int) -> String { String(format: "%@-%02d", key, index) }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}
