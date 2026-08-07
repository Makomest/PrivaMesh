//
//  privameshApp.swift
//  privamesh
//

import SwiftUI
import SwiftData

@main
struct privameshApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// Shared so the BGAppRefreshTask handler can build a ModelContext too.
    private let sharedModelContainer: ModelContainer

    init() {
        let storeConfig = ModelConfiguration()
        sharedModelContainer = try! ModelContainer(for: Contact.self, ChatMessage.self,
                                                   configurations: storeConfig)
        // Encrypt the local message store at rest. `.completeUntilFirstUserAuthentication`
        // keeps it readable for background polling after first unlock, while
        // protecting it before first unlock / when powered off. (`.complete`
        // would revoke access seconds after the screen locks and kill polling.)
        Self.protectStore(at: storeConfig.url)

        let slateGray = UIColor(red: 100/255, green: 116/255, blue: 139/255, alpha: 1.0)
        let accentTeal = UIColor(red: 20/255, green: 184/255, blue: 166/255, alpha: 1.0)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = .clear

        // Set icon + label colors explicitly for iOS 26 Liquid Glass bar
        for layout in [tabAppearance.stackedLayoutAppearance,
                       tabAppearance.inlineLayoutAppearance,
                       tabAppearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = slateGray
            layout.normal.titleTextAttributes = [.foregroundColor: slateGray]
            layout.selected.iconColor = accentTeal
            layout.selected.titleTextAttributes = [.foregroundColor: accentTeal]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        NotificationService.shared.bootstrap()
        BackgroundRefresh.register(container: sharedModelContainer)

        let avatarService = AvatarService()
        _avatars = State(initialValue: avatarService)
        _market  = State(initialValue: MarketService(avatars: avatarService))

        // Metered messaging: quota mirrors the user's Apple IAP allowance and is
        // fed by the store. Subscription tier drives the monthly bucket; pack
        // purchases credit non-expiring messages.
        let sub = SubscriptionManager()
        let quotaSvc = MessageQuotaService()
        let accounts = accountManager
        let relaySvc = RelayService()
        quotaSvc.tierProvider = { [weak sub] in sub?.tier ?? .none }
        quotaSvc.isFirstAccountActive = { [weak accounts] in accounts?.isFirstAccountActive ?? true }
        sub.onPackPurchased = { [weak quotaSvc] messages in quotaSvc?.creditPack(messages) }
        sub.onPackReceipt = { [weak relaySvc] jws in await relaySvc?.creditPack(jws: jws) }
        relaySvc.receiptProvider = { [weak sub] in await sub?.currentEntitlementJWS() }
        relaySvc.activeAccountProvider = { [weak accounts] in accounts?.activePublicKey ?? "" }
        // Anonymous blind tokens: a message spends a token the relay can't link to
        // the purchase, instead of sending the Apple receipt on every /send. When
        // the relay has no issuer key configured the pool stays empty and sends
        // transparently fall back to the receipt path above.
        let blindSvc = BlindTokenService()
        blindSvc.jwsProvider = { [weak sub] in await sub?.currentEntitlementJWS() }
        relaySvc.takeBlindToken = { [weak blindSvc] in blindSvc?.takeToken() }
        relaySvc.returnBlindToken = { [weak blindSvc] token in blindSvc?.returnToken(token) }
        // Derive each account's messaging identity deterministically from its seed
        // phrase, so re-entering the phrase on any device restores the identity.
        accounts.onSeedStored = { [weak messagingIdentity, weak relaySvc] pub, phrase in
            messagingIdentity?.provision(address: pub, seedPhrase: phrase)
            relaySvc?.provisionToken(address: pub, seedPhrase: phrase)
        }
        messageSender.relay = relaySvc
        coverTraffic.quota = quotaSvc
        onChainDiscovery.relay = relaySvc
        _subscription = State(initialValue: sub)
        _quota        = State(initialValue: quotaSvc)
        _relay        = State(initialValue: relaySvc)
        _blindTokens  = State(initialValue: blindSvc)
    }

    /// Apply data-protection to the SwiftData SQLite store and its WAL/SHM sidecars.
    private static func protectStore(at url: URL) {
        let fm = FileManager.default
        let attrs: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if fm.fileExists(atPath: path) {
                try? fm.setAttributes(attrs, ofItemAtPath: path)
            }
        }
    }
    @State private var router   = AppRouter()
    @State private var wallet   = WalletManager()
    @State private var passcode = PasscodeManager()
    @State private var biometry = BiometryService()
    @State private var rpc      = SolanaRPCService()
    @State private var balance  = WalletBalanceService()
    @State private var txHistory = TransactionHistoryService()
    @State private var messagingIdentity = MessagingIdentityManager()
    @State private var messageSender = MessageSender()
    @State private var polling = PollingService()
    @State private var coverTraffic = CoverTrafficService()
    @State private var gasWallet = GasWalletService()
    @State private var tabBarVisibility = TabBarVisibility()
    @State private var onChainDiscovery = OnChainDiscovery()
    @State private var subscription = SubscriptionManager()
    @State private var quota = MessageQuotaService()
    @State private var relay = RelayService()
    @State private var blindTokens = BlindTokenService()
    @State private var accountManager = AccountManager()
    @State private var nicknameManager = NicknameManager()
    @State private var discovery = DiscoveryService()
    @State private var toast = ToastManager()
    @State private var avatars: AvatarService
    @State private var market: MarketService
    @State private var userProfile = UserProfileService()


    /// Normally the full app. With `-orbitUIPreview` (DEBUG only) it boots
    /// straight into the Orbit chat surface on seeded mock contacts — no wallet,
    /// no passcode — so the scene itself can be inspected in isolation.
    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if CommandLine.arguments.contains("-orbitUIPreview") {
            OrbitChatsView()
                .task {
                    OrbitPreviewSeed.populate(context: sharedModelContainer.mainContext)
                    OrbitPreviewSeed.seedQuota(quota)
                    let args = CommandLine.arguments
                    if args.contains("-orbitInjectArrival") || args.contains("-orbitInjectSpam") {
                        await OrbitPreviewSeed.injectArrivals(
                            context: sharedModelContainer.mainContext,
                            spam: args.contains("-orbitInjectSpam"))
                    }
                }
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootView
                // Dark-only product: the chat surface is a single monochrome dark
                // world, so light mode would only have repainted the secondary
                // screens. Matches UIUserInterfaceStyle=Dark in Info.plist.
                .preferredColorScheme(.dark)
                .environment(router)
                .environment(wallet)
                .environment(passcode)
                .environment(biometry)
                .environment(rpc)
                .environment(balance)
                .environment(txHistory)
                .environment(messagingIdentity)
                .environment(messageSender)
                .environment(polling)
                .environment(coverTraffic)
                .environment(gasWallet)
                .environment(tabBarVisibility)
                .environment(onChainDiscovery)
                .environment(subscription)
                .environment(quota)
                .environment(relay)
                .environment(blindTokens)
                .environment(accountManager)
                .environment(nicknameManager)
                .environment(discovery)
                .environment(toast)
                .environment(avatars)
                .environment(market)
                .environment(userProfile)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { BackgroundRefresh.schedule() }
                    if phase == .active { Task { await blindTokens.ensureStock() } }
                }
                .task {
                    // Fetch the issuer key and top up the anonymous-token pool so a
                    // token is ready before the first message is sent.
                    await blindTokens.refreshIssuerKey()
                    await blindTokens.ensureStock()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
