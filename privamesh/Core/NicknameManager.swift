//
//  NicknameManager.swift
//  privamesh
//
//  Generates a deterministic human-readable nickname from the Solana public key.
//  The nickname is stable: same key → same nickname, even after reinstall.
//  PrivaMesh+ subscribers can override it with a custom handle.
//

import Foundation

@Observable
final class NicknameManager {
    private static let customKey = "privamesh.nickname.custom."  // + publicKey

    private var publicKey: String = ""
    private(set) var customNickname: String?

    // The active nickname — custom if set, otherwise generated.
    var nickname: String {
        customNickname ?? Self.generate(from: publicKey)
    }

    // The auto-generated nickname regardless of custom override.
    var generatedNickname: String {
        Self.generate(from: publicKey)
    }

    // Call this as soon as the wallet public key is known.
    func bind(to publicKey: String) {
        guard !publicKey.isEmpty, self.publicKey != publicKey else { return }
        self.publicKey = publicKey
        let stored = UserDefaults.standard.string(forKey: Self.customKey + publicKey)
        customNickname = stored
    }

    func setCustomNickname(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !publicKey.isEmpty else { return }
        customNickname = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.customKey + publicKey)
    }

    func clearCustomNickname() {
        customNickname = nil
        if !publicKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.customKey + publicKey)
        }
    }

    // MARK: - Deterministic generation (FNV-1a hash of public key)

    static func generate(from publicKey: String) -> String {
        guard !publicKey.isEmpty else { return "Anonymous" }

        var hash: UInt32 = 2166136261
        for byte in publicKey.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16777619
        }

        let adjIdx  = Int(hash % UInt32(adjectives.count))
        let nounIdx = Int((hash &>> 8) % UInt32(nouns.count))
        // 4-digit suffix from independent hash bits — turns ~adj×noun into
        // millions of distinct handles so real users practically never collide.
        let num     = Int((hash &>> 18) % 10000)

        return "\(adjectives[adjIdx])\(nouns[nounIdx])\(num)"
    }

    // MARK: - Word lists  (adjectives × nouns × 10000 ≈ tens of millions)

    private static let adjectives: [String] = [
        "Silent", "Swift", "Dark", "Bright", "Calm", "Bold", "Cool",
        "Wild", "Deep", "Fast", "Cold", "Warm", "Sharp", "Wise", "Pure",
        "Ghost", "Neon", "Cyber", "Shadow", "Lunar", "Solar", "Stealth",
        "Quantum", "Cosmic", "Prism", "Radiant", "Mystic", "Ultra",
        "Frozen", "Blazing",
        "Hidden", "Secret", "Astral", "Vivid", "Noble", "Royal", "Iron",
        "Steel", "Golden", "Silver", "Crimson", "Azure", "Onyx", "Jade",
        "Amber", "Velvet", "Electric", "Atomic", "Phantom", "Mythic",
        "Arctic", "Desert", "Storm", "Thunder", "Crystal", "Obsidian",
        "Feral", "Rapid", "Grand", "Eternal"
    ]

    private static let nouns: [String] = [
        "Wolf", "Fox", "Panda", "Tiger", "Eagle", "Hawk", "Bear", "Lion",
        "Raven", "Phoenix", "Storm", "Wave", "Flame", "Frost", "Blade",
        "Arrow", "Cipher", "Node", "Hash", "Key", "Chain", "Mesh",
        "Vault", "Shield", "Comet", "Nova", "Spark", "Pulse", "Echo", "Drift",
        "Falcon", "Panther", "Cobra", "Viper", "Lynx", "Otter", "Heron",
        "Orca", "Mantis", "Scarab", "Golem", "Titan", "Oracle", "Specter",
        "Saber", "Talon", "Ember", "Glacier", "Quartz", "Prism", "Beacon",
        "Circuit", "Relay", "Vector", "Matrix", "Pixel", "Byte", "Photon",
        "Nebula", "Quasar"
    ]
}
