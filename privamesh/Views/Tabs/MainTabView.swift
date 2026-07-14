//
//  MainTabView.swift
//  privamesh
//
//  Tab container with native iOS 26 Liquid Glass styling.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct MainTabView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(PollingService.self) private var polling
    @Environment(CoverTrafficService.self) private var coverTraffic
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(MessageSender.self) private var messageSender
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(DiscoveryService.self) private var discovery
    @Environment(OnChainDiscovery.self) private var onChainDiscovery
    @Environment(AvatarService.self) private var avatars
    @Environment(MarketService.self) private var market
    @Environment(UserProfileService.self) private var userProfile
    @Environment(AccountManager.self) private var accountManager
    @Environment(TabBarVisibility.self) private var tabBarVisibility
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme

    @Query private var contacts: [Contact]
    private var activeAddress: String {
        if case let .ready(pk) = wallet.state { return pk }
        return ""
    }
    private var totalUnread: Int {
        contacts.filter { $0.ownerAddress == activeAddress || $0.ownerAddress.isEmpty }
            .reduce(0) { $0 + $1.unreadCount }
    }

    @AppStorage("privamesh.securitySetupDone") private var securitySetupDone = false
    @State private var showSecuritySetup = false

    // Single-screen layout (no bottom tab bar): the chat list is the root; the
    // profile/settings and add-contact live in its nav bar (Messages-app style).
    var body: some View {
        ChatsTabView()
        .sheet(isPresented: $showSecuritySetup) { SecuritySetupView() }
        .task {
            if case let .ready(address) = wallet.state {
                // Register the onboarding wallet as the primary account once.
                if let phrase = try? wallet.revealSeedPhrase(), !phrase.isEmpty {
                    accountManager.ensurePrimary(phrase: phrase, publicKey: address)
                }
                migrateLegacyContacts(to: address)
                activate(address)
                // One-time: offer the privacy hardening options to a new user.
                if !securitySetupDone {
                    securitySetupDone = true
                    showSecuritySetup = true
                }
                await syncOnChain(address: address)
            }
        }
        .onChange(of: wallet.state) { _, newState in
            if case let .ready(address) = newState {
                polling.stop()           // restart for the newly active account
                coverTraffic.stop()
                activate(address)
                // Switching accounts must (re)publish discovery for the newly
                // active account — otherwise its nickname is never searchable.
                Task { await syncOnChain(address: address) }
            } else {
                polling.stop()
                coverTraffic.stop()
            }
        }
        .onChange(of: nicknameManager.nickname) { _, _ in
            // Picking/changing the active nickname must re-publish discovery so
            // the new nick becomes searchable. publishIfNeeded is throttled (only
            // sends when the stored nick actually changed).
            if case let .ready(address) = wallet.state {
                Task { await syncOnChain(address: address) }
            }
        }
        .onChange(of: avatars.activeID) { _, _ in
            // Equipping a different NFT avatar re-publishes so contacts who add
            // you by nickname see your current avatar.
            if case let .ready(address) = wallet.state {
                Task { await syncOnChain(address: address) }
            }
        }
    }

    /// Restore on-chain NFTs (throttled) + publish the wallet-signed discovery
    /// bundle for `address`. Runs on launch, account switch, and nick change.
    private func syncOnChain(address: String) async {
        let stampKey = "privamesh.onchainRestore.\(address)"
        let last = UserDefaults.standard.double(forKey: stampKey)
        if Date().timeIntervalSince1970 - last > 1800 {
            let onChainIDs = await OnChainNFT.ownedDesignIds(owner: address, rpc: rpc)
            avatars.adoptOnChain(onChainIDs)
            market.adoptOnChainNicks(onChainIDs)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
        }
        if let bundle = try? identity.prekeyBundle(),
           let keypair = try? await wallet.currentKeyPair() {
            // Wallet-signed bundle → contacts find us by nickname (anti-MITM).
            let signed = bundle.walletSigned(address: address, keypair: keypair)
            await onChainDiscovery.publishIfNeeded(
                nickname: nicknameManager.nickname, address: address,
                signedBundleBase64: signed.base64Encoded,
                avatarSeed: nil, keypair: keypair, rpc: rpc)
        }
    }

    /// Bind all per-account services + (re)start polling for `address`.
    private func activate(_ address: String) {
        identity.bind(to: address)        // per-account messaging keys (accounts unlinkable)
        nicknameManager.bind(to: address)
        avatars.bind(to: address)
        market.bind(to: address)
        userProfile.bind(to: address)
        gasWallet.bind(to: address)       // per-account gas wallet (no shared fee payer)
        NotificationService.shared.requestAuthorization()
        polling.start(myAddress: address, identity: identity, rpc: rpc, context: context)
        coverTraffic.start(myAddress: address, wallet: wallet, gasWallet: gasWallet, identity: identity,
                           rpc: rpc, sender: messageSender, context: context)
        if let bundle = try? identity.prekeyBundle() {
            ensureSelfContact(address: address, bundleBase64: bundle.base64Encoded)
        }
    }

    /// One-time: assign pre-multi-account chats to the current account.
    private func migrateLegacyContacts(to address: String) {
        let desc = FetchDescriptor<Contact>(predicate: #Predicate { $0.ownerAddress == "" })
        guard let legacy = try? context.fetch(desc), !legacy.isEmpty else { return }
        for c in legacy { c.ownerAddress = address }
        try? context.save()
    }

    // MARK: - Saved Messages bootstrap

    private func ensureSelfContact(address: String, bundleBase64: String) {
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.id == address }
        )
        guard (try? context.fetchCount(descriptor)) == 0 else { return }
        let self_ = Contact(id: address, displayName: "Saved Messages", prekeyBundleBase64: bundleBase64)
        self_.isSelf = true
        self_.ownerAddress = address
        context.insert(self_)
        try? context.save()
    }
}

#Preview {
    MainTabView()
        .environment(AppRouter())
        .environment(WalletManager())
        .environment(PasscodeManager())
        .environment(BiometryService())
        .environment(SolanaRPCService())
        .environment(WalletBalanceService())
        .environment(NicknameManager())
}
