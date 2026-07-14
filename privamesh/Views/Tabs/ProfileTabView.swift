//
//  ProfileTabView.swift
//  privamesh
//

import SwiftUI
import SwiftData
import StoreKit
import SolanaSwift
#if os(iOS)
import UIKit
#endif

struct ProfileTabView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(PasscodeManager.self) private var passcode
    @Environment(BiometryService.self) private var biometry
    @Environment(AppRouter.self) private var router
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(MessageQuotaService.self) private var quota
    @Environment(UserProfileService.self) private var userProfile
    @Environment(MarketService.self) private var market
    @Environment(AccountManager.self) private var accountManager
    @Environment(MessagingIdentityManager.self) private var messagingIdentity
    @Environment(OnChainDiscovery.self) private var onChainDiscovery
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(CoverTrafficService.self) private var coverTraffic
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(MessageSender.self) private var messageSender
    @Environment(\.modelContext) private var context

    @AppStorage("privamesh.themeMode") private var themeModeRaw = ThemeMode.system.rawValue
    // "auto" follows the phone language; "ru"/"en" force an override.
    @AppStorage("privamesh.langPref") private var langPref = "auto"
    @State private var showLangRestart = false
    @State private var showRPCEditor = false
    @State private var coverEnabled = false
    @AppStorage("privamesh.shareVerifiedBadge") private var shareVerifiedBadge = true
    @State private var seedLockEnabled = false
    @State private var notifMuteAll = false
    @State private var notifPreview = true
    @State private var securing = false
    @State private var secureStatus: String?

    @State private var publishing = false
    @State private var publishStatus: String?
    @State private var searchEnabled = false

    @State private var showNickPicker = false
    @State private var showMint = false
    @State private var showNickEditor = false
    @State private var showBioEditor = false
    @State private var showResetAlert = false
    @State private var showPaywall = false
    @State private var showManageSubscriptions = false
    @State private var showAccounts = false

    private var publicKey: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        profileHeader
                        if subscription.isSubscribed { premiumStatusCard } else { premiumUpsellCard }
                        descriptionCard
                        nicknameCard
                        // NFT nickname minting / on-chain "secure" removed — no
                        // crypto-asset creation in the app.
                        discoveryCard
                        appearanceCard
                        securityCard
                        privacyCard
                        notificationsCard
                        rpcCard
                        biometryCard
                        dangerCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
            }
            .onAppear {
                coverEnabled = coverTraffic.isEnabled
                seedLockEnabled = SeedLock.isEnabled
                notifMuteAll = NotificationService.shared.muteAll
                notifPreview = NotificationService.shared.showPreview
                if let a = publicKey {
                    searchEnabled = onChainDiscovery.alreadyPublished(
                        nickname: nicknameManager.nickname, address: a, avatarSeed: nil)
                }
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .task(id: showManageSubscriptions) {
                // Re-sync after the user manages/cancels in the system sheet.
                if !showManageSubscriptions { await subscription.refreshStatus() }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .alert("Сбросить аккаунт?", isPresented: $showResetAlert) {
                Button("Отмена", role: .cancel) {}
                Button("Сбросить", role: .destructive) {
                    // Full wipe — leave no seeds, keys, or chats behind.
                    // Capture addresses before removeAll so every account's
                    // messaging identity gets wiped too.
                    let addrs = accountManager.accounts.map(\.publicKeyBase58)
                    accountManager.removeAll()       // per-account seeds in Keychain
                    messagingIdentity.wipeAll(addresses: addrs)   // per-account X3DH/DR keys
                    try? context.delete(model: Contact.self)      // contacts (cascade → messages)
                    try? context.delete(model: ChatMessage.self)
                    wallet.wipe()
                    passcode.wipe()
                    biometry.disable()
                    router.go(to: .welcome)
                }
            } message: {
                Text("Все данные удалятся с устройства. Восстановить можно только по фразе восстановления.")
            }
            .sheet(isPresented: $showPaywall) {
                QuotaPaywallSheet()
            }
            .sheet(isPresented: $showAccounts) {
                AccountSwitcherView()
            }
            .sheet(isPresented: $showBioEditor) {
                BioEditorSheet(userProfile: userProfile)
            }
            .sheet(isPresented: $showNickPicker) {
                NicknamePickerSheet(market: market, nicknameManager: nicknameManager)
            }
            .sheet(isPresented: $showNickEditor) { NicknameEditorSheet(nicknameManager: nicknameManager) }
            .sheet(isPresented: $showRPCEditor) { RPCEditorSheet(rpc: rpc) }
        }
    }

    // MARK: - RPC card

    private var rpcCard: some View {
        Button { showRPCEditor = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "network").font(.system(size: 18))
                    .foregroundStyle(Theme.accentDeep).frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("RPC-узел").font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                    Text(rpc.customRPC.map { LocalizedStringKey(shortURL($0)) } ?? LocalizedStringKey("По умолчанию (Helius)"))
                        .font(.system(size: 12, design: rpc.customRPC == nil ? .default : .monospaced))
                        .foregroundStyle(Theme.slate500).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.slate400)
            }
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func shortURL(_ s: String) -> String {
        URL(string: s)?.host ?? s
    }

    // MARK: - Premium upsell card (not subscribed)

    /// Real monthly price from StoreKit, falling back to the configured price.
    private var premiumPriceText: String { subscription.product?.displayPrice ?? "$2.99" }

    private var premiumUpsellCard: some View {
        Button { showPaywall = true } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    PrivaLogo(size: 28)
                    HStack(spacing: 2) {
                        Text("PrivaMesh").font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                        Text("+").font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    Spacer()
                    (Text(verbatim: premiumPriceText) + Text("/мес"))
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.accentGradient).clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    upsellFeature(icon: "checkmark.seal.fill", "Галочка верификации у профиля")
                    upsellFeature(icon: "person.2.fill", "До 3 аккаунтов на устройстве")
                }

                HStack {
                    Text("Оформить подписку").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func upsellFeature(icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.accent).frame(width: 20)
            Text(LocalizedStringKey(text)).font(.system(size: 13)).foregroundStyle(Theme.slate700)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Premium status card

    private var premiumStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.accent)
                Text("PrivaMesh+").font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate800)
                Spacer()
                Text("активна").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.positive)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.positive.opacity(0.12)).clipShape(Capsule())
            }

            if !subscription.expiryText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                    Text(subscription.autoRenew
                         ? "Продлится \(subscription.expiryText)"
                         : "Активна до \(subscription.expiryText)")
                        .font(.system(size: 13)).foregroundStyle(Theme.slate600)
                }
            }

            Divider().background(Theme.glassStroke)

            Button {
                showManageSubscriptions = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Управление подпиской").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.slate800)
                        Text(subscription.autoRenew
                             ? "Авто-продление включено"
                             : "Авто-продление выключено")
                            .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.slate400)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Description card

    private var descriptionCard: some View {
        Button { showBioEditor = true } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.quote")
                    .font(.system(size: 18)).foregroundStyle(Theme.accentDeep)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Описание").font(.system(size: 13)).foregroundStyle(Theme.slate500)
                    Text(LocalizedStringKey(userProfile.bio.isEmpty ? "Добавь описание профиля" : userProfile.bio))
                        .font(.system(size: 15))
                        .foregroundStyle(userProfile.bio.isEmpty ? Theme.slate400 : Theme.slate800)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(Theme.slate400)
            }
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 80, height: 80)
                    .blur(radius: 14)
                    .opacity(0.4)
                MeshAvatarView(id: publicKey ?? "", size: 72)
                    .overlay(Circle().stroke(Color.white.opacity(0.80), lineWidth: 2))
                    .clipShape(Circle())
            }

            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text(nicknameManager.nickname)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                    if subscription.isSubscribed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16)).foregroundStyle(Theme.accent)
                    }
                }

                if let pk = publicKey {
                    Text(String(pk.prefix(6)) + "…" + String(pk.suffix(6)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.slate400)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.positive)
                Text("Личность защищена сквозным шифрованием")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accentDeep)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.positive.opacity(0.10))
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 13)).foregroundStyle(Theme.slate400).padding(14)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showAccounts = true
        }
    }

    // MARK: - Nickname card

    private var nicknameCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Твой ник")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.slate500)
                    Text(nicknameManager.nickname)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                }
                Spacer()
            }

            Divider().background(Theme.glassStroke)
            Button { showNickEditor = true } label: {
                HStack {
                    Label("Свой ник", systemImage: "pencil")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentDeep)
                    Spacer()
                    Text(subscription.isSubscribed ? "до 3" : "1 · Pro для 3")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.slate400)
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.slate400)
                }
            }
            .buttonStyle(.plain)

            // Switch active nickname when you hold more than one.
            if market.ownedNicknames.count > 1 {
                Divider().background(Theme.glassStroke)
                Button { showNickPicker = true } label: {
                    HStack {
                        Label("Мои ники (\(market.ownedNicknames.count))", systemImage: "at")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentDeep)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.slate400)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Security

    private var securityCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SeedPhraseRevealView()
            } label: {
                settingsRow(icon: "key.fill", title: "Показать фразу восстановления", color: Theme.accentDeep)
            }
            Divider().padding(.leading, 56).background(Theme.slate300.opacity(0.4))
            NavigationLink {
                ChangePasscodeView()
            } label: {
                settingsRow(icon: "lock.rotation", title: "Изменить пароль", color: Theme.accentDeep)
            }
        }
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Biometry

    private var biometryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: biometry.kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(width: 28)
                Text(biometry.kind.label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.slate800)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { biometry.isEnabled },
                    set: { biometry.isEnabled = $0 }
                ))
                .tint(Theme.accent)
                .labelsHidden()
                .disabled(!biometry.isAvailable)
            }
            if !biometry.isAvailable {
                Text("Биометрия недоступна на этом устройстве")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate400)
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Danger

    private var dangerCard: some View {
        Button {
            showResetAlert = true
        } label: {
            settingsRow(icon: "trash.fill", title: "Сбросить аккаунт", color: Theme.negative)
        }
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
            .stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        cardChrome {
            // Optional decoy traffic. Each decoy is a real sponsored message and is
            // billed to the user's message balance — the subtitle makes the cost
            // explicit so enabling it is an informed choice.
            toggleRow(icon: "theatermasks.fill", title: "Маскирующий трафик",
                      subtitle: String(localized: "Скрывает, КОГДА ты пишешь. Тратит ~\(CoverTrafficService.approxPerHour) сообщений в час из твоего баланса."),
                      isOn: $coverEnabled)
            cardDivider
            toggleRow(icon: "checkmark.seal.fill", title: "Галочка верификации контактам",
                      subtitle: "Показывать контактам, что у тебя PrivaMesh+.",
                      isOn: $shareVerifiedBadge)
            cardDivider
            if SeedLock.isAvailable {
                toggleRow(icon: "key.viewfinder", title: "Защита seed по Face ID",
                          subtitle: "Чтение seed требует Face ID / пароль", isOn: $seedLockEnabled)
                cardDivider
            }
            HStack {
                Image(systemName: "lock.shield.fill").font(.system(size: 16))
                    .foregroundStyle(Theme.accentDeep).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stealth-адреса").font(.system(size: 15)).foregroundStyle(Theme.slate800)
                    Text("Получатель скрыт").font(.system(size: 11)).foregroundStyle(Theme.slate500)
                }
                Spacer()
                Text("Активны").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.positive)
            }
            .padding(16)
        }
        .onChange(of: coverEnabled) { _, v in
            coverTraffic.isEnabled = v
            guard let address = publicKey else { return }
            if v {
                coverTraffic.refresh(myAddress: address, wallet: wallet, gasWallet: gasWallet,
                                     identity: messagingIdentity, rpc: rpc, sender: messageSender, context: context)
            } else {
                coverTraffic.stop()
            }
        }
        .onChange(of: seedLockEnabled) { _, v in
            SeedLock.isEnabled = v
            // ACL read = blocking Face ID prompt → off the main thread.
            Task.detached(priority: .userInitiated) {
                wallet.reapplySeedProtection()
                accountManager.reapplySeedProtection()
                SeedLock.invalidate()
            }
        }
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        cardChrome {
            toggleRow(icon: "bell.slash.fill", title: "Не беспокоить",
                      subtitle: "Отключить все уведомления", isOn: $notifMuteAll)
            cardDivider
            toggleRow(icon: "eye.fill", title: "Имя отправителя в пуше",
                      subtitle: "Иначе — «Зашифрованное сообщение»", isOn: $notifPreview)
        }
        .onChange(of: notifMuteAll) { _, v in NotificationService.shared.muteAll = v }
        .onChange(of: notifPreview) { _, v in NotificationService.shared.showPreview = v }
    }

    // MARK: - Secure collection on-chain

    private var discoveryCard: some View {
        cardChrome {
            toggleRow(icon: "magnifyingglass.circle.fill", title: "Поиск по нику",
                      subtitle: publishStatus ?? "Разреши другим находить тебя по нику. Всё оплачиваем мы.",
                      isOn: Binding(get: { searchEnabled },
                                    set: { on in searchEnabled = on; Task { await setSearchable(on) } }))
        }
    }

    /// Toggle "searchable by nickname". Enabling publishes the nickname so others
    /// can find you; the cost is fully sponsored by us (no user charge). Disabling
    /// simply stops advertising.
    private func setSearchable(_ on: Bool) async {
        guard on, let address = publicKey else {
            if !on { publishStatus = String(localized: "Поиск по нику выключен") }
            return
        }
        if onChainDiscovery.alreadyPublished(nickname: nicknameManager.nickname,
                                             address: address, avatarSeed: nil) {
            publishStatus = String(localized: "Тебя можно найти по нику ✓"); return
        }
        publishing = true; defer { publishing = false }
        publishStatus = String(localized: "Включаю…")
        guard let keypair = try? await wallet.currentKeyPair(),
              let bundle = try? messagingIdentity.prekeyBundle() else {
            publishStatus = String(localized: "Профиль недоступен"); searchEnabled = false; return
        }
        let signed = bundle.walletSigned(address: address, keypair: keypair)
        let err = await onChainDiscovery.publish(
            nickname: nicknameManager.nickname, address: address,
            signedBundleBase64: signed.base64Encoded,
            avatarSeed: nil, keypair: keypair, rpc: rpc)
        // Cost is sponsored by us — no message is charged to the user.
        publishStatus = err == nil
            ? String(localized: "Тебя можно найти по нику ✓")
            : String(localized: "Не удалось включить, попробуй позже")
        if err != nil { searchEnabled = false }
    }

    private var secureOnChainCard: some View {
        cardChrome {
            Button {
                Task { await secureOnChain() }
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 16))
                        .foregroundStyle(Theme.accentDeep).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Защитить коллекцию on-chain").font(.system(size: 15)).foregroundStyle(Theme.slate800)
                        Text(secureStatus.map { LocalizedStringKey($0) } ?? LocalizedStringKey("Минт NFT-ников в блокчейн (портируемость по seed)"))
                            .font(.system(size: 11)).foregroundStyle(Theme.slate500).lineLimit(2)
                    }
                    Spacer()
                    if securing { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.slate400) }
                }
            }
            .buttonStyle(.plain)
            .disabled(securing)
            .padding(16)
        }
    }

    private func secureOnChain() async {
        guard let address = publicKey, let keypair = try? await wallet.currentKeyPair() else { return }
        securing = true; defer { securing = false }
        secureStatus = nil
        let onChain = Set(await OnChainNFT.ownedDesignIds(owner: address, rpc: rpc))
        // Locally-remembered mints: the chain takes a few seconds to confirm, so
        // without this a quick second tap would RE-MINT (and re-pay) the same
        // items before the scan sees them. Persisted per account.
        let securedKey = "privamesh.securedOnChain.\(address)"
        var secured = Set(UserDefaults.standard.stringArray(forKey: securedKey) ?? [])
        let todo = market.ownedNicknames.map { "nick:\($0)" }
        let missing = todo.filter { !onChain.contains($0) && !secured.contains($0) }
        guard !missing.isEmpty else {
            secureStatus = String(localized: "✓ Коллекция уже защищена on-chain. Повторно нажимать не нужно — каждый минт стоит комиссию.")
            return
        }

        // Pre-flight balance check. Each mint drains lamportsPerMint (mint acct +
        // token acct rent + fee). CRITICAL: the wallet itself must STAY rent-exempt
        // (~0.00089 SOL) after spending, else the tx is rejected with "account (0)
        // insufficient funds for rent collection". So keep a reserve and only mint
        // as many items as the balance can actually afford.
        let perMint = Double(OnChainNFT.lamportsPerMint) / 1_000_000_000
        let walletRentReserve: UInt64 = 1_000_000   // keep wallet above rent-exempt
        var affordable = missing.count
        if let lamports = try? await rpc.client.getBalance(account: address, commitment: "confirmed") {
            let spendable = lamports > walletRentReserve ? lamports - walletRentReserve : 0
            affordable = min(missing.count, Int(spendable / OnChainNFT.lamportsPerMint))
            if affordable == 0 {
                let have = Double(lamports) / 1_000_000_000
                let need = perMint + Double(walletRentReserve) / 1_000_000_000
                secureStatus = String(localized: "Недостаточно SOL: нужно ≈ \(String(format: "%.4f", need)) на 1 предмет (с резервом на ренту аккаунта), на балансе \(String(format: "%.4f", have)). Пополни баланс.")
                return
            }
        }

        var ok = 0
        var firstErr: String?
        for id in missing.prefix(affordable) {
            do {
                _ = try await OnChainNFT.mint(designId: id, keypair: keypair, rpc: rpc)
                ok += 1
                secured.insert(id)   // remember locally so a re-tap won't re-mint
                UserDefaults.standard.set(Array(secured), forKey: securedKey)
            }
            catch {
                let d = error.localizedDescription
                // Map the on-chain insufficient-funds/rent errors to readable text.
                if firstErr == nil {
                    firstErr = (d.contains("0x1") || d.lowercased().contains("negative") || d.lowercased().contains("rent"))
                        ? String(localized: "недостаточно SOL (нужно ≈ \(String(format: "%.4f", perMint)) на предмет + резерв)")
                        : d
                }
                break   // stop — likely out of funds, don't spam failed txs
            }
        }
        if firstErr == nil && affordable < missing.count {
            secureStatus = String(localized: "Заминчено \(ok)/\(missing.count). На остальные не хватает SOL — пополни баланс.")
        } else {
            secureStatus = firstErr == nil
                ? String(localized: "Заминчено on-chain: \(ok)")
                : String(localized: "Готово \(ok)/\(missing.count). Ошибка: \(firstErr ?? "")")
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        cardChrome {
            HStack {
                Image(systemName: "moon.stars.fill").font(.system(size: 16))
                    .foregroundStyle(Theme.accentDeep).frame(width: 28)
                Text("Тема").font(.system(size: 15)).foregroundStyle(Theme.slate800)
                Spacer()
                Picker("", selection: $themeModeRaw) {
                    ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accentDeep)
            }
            .padding(16)
            cardDivider
            HStack {
                Image(systemName: "globe").font(.system(size: 16))
                    .foregroundStyle(Theme.accentDeep).frame(width: 28)
                Text("Язык").font(.system(size: 15)).foregroundStyle(Theme.slate800)
                Spacer()
                Picker("", selection: $langPref) {
                    Text("Системный").tag("auto")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .pickerStyle(.menu)
                .tint(Theme.accentDeep)
                .onChange(of: langPref) { _, pref in
                    if pref == "auto" {
                        // Drop the override → app follows the phone's language.
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([pref], forKey: "AppleLanguages")
                    }
                    showLangRestart = true
                }
            }
            .padding(16)
        }
        .alert("Перезапусти приложение", isPresented: $showLangRestart) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text("Закрой и снова открой приложение, чтобы применить язык.")
        }
    }

    // MARK: - Card helpers

    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                .stroke(Theme.glassStroke, lineWidth: 1))
    }

    private var cardDivider: some View {
        Divider().padding(.leading, 56).background(Theme.slate300.opacity(0.4))
    }

    private func toggleRow(icon: String, title: String, subtitle: String? = nil,
                           isOn: Binding<Bool>, enabled: Bool = true) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundStyle(Theme.accentDeep).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.system(size: 15)).foregroundStyle(Theme.slate800)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 11)).foregroundStyle(Theme.slate500)
                }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.accent).disabled(!enabled)
        }
        .padding(16)
    }

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(LocalizedStringKey(title))
                .font(.system(size: 15))
                .foregroundStyle(Theme.slate800)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.slate400)
        }
        .padding(16)
        .contentShape(Rectangle())
    }
}

// MARK: - Nickname editor (PrivaMesh+ only)

private struct NicknameEditorSheet: View {
    let nicknameManager: NicknameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var wallet
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(MarketService.self) private var market
    @Environment(OnChainDiscovery.self) private var discovery
    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(SolanaRPCService.self) private var rpc
    @State private var draft = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var cap: Int { subscription.isSubscribed ? 3 : 1 }

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Твой ник")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                    Text("Этот ник будут видеть твои контакты. Свободный ник закрепляется за тобой.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center)
                    Text("Только буквы — цифры можно добавить по желанию (напр. Alex42)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.slate400)
                        .multilineTextAlignment(.center)
                    if let errorMessage {
                        Text(LocalizedStringKey(errorMessage))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.negative)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 32)

                TextField("Введи ник", text: $draft)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Theme.slate800)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(Theme.glassStroke, lineWidth: 1))
                    .padding(.horizontal, 24)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Task { await reserve() }
                    } label: {
                        HStack(spacing: 8) {
                            if saving { ProgressView().tint(.white) }
                            Text(saving ? "Проверяю…" : "Сохранить")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty
                            ? AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                            : AnyShapeStyle(Theme.accentGradient))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || saving)

                    Button {
                        dismiss()
                    } label: {
                        Text("Отмена")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glass)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            draft = nicknameManager.customNickname ?? ""
        }
    }

    /// Claim a nickname: it must be unique (a free name is reserved to you), and
    /// the count is limited (1 for free, 3 for PrivaMesh+). Reservation cost is
    /// sponsored by us — the user spends nothing.
    private func reserve() async {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { errorMessage = "Минимум 2 буквы"; return }
        // Limit: free 1, PrivaMesh+ 3.
        if !market.ownedNicknames.contains(name), market.ownedNicknames.count >= cap {
            errorMessage = cap == 1
                ? "Доступен 1 ник. Оформи PrivaMesh+ для 3."
                : "Достигнут лимит ников (3)."
            return
        }
        guard case let .ready(address) = wallet.state else { errorMessage = "Профиль недоступен"; return }
        saving = true; defer { saving = false }
        errorMessage = nil
        // Uniqueness: if someone else already holds this name, block.
        if let found = await discovery.search(query: name, rpc: rpc), found.address != address {
            errorMessage = String(localized: "Ник «\(name)» уже занят"); return
        }
        // Reserve: publish the nickname→identity record (sponsored) so it's yours.
        guard let bundle = try? identity.prekeyBundle(),
              let keypair = try? await wallet.currentKeyPair() else {
            errorMessage = "Профиль недоступен"; return
        }
        let signed = bundle.walletSigned(address: address, keypair: keypair)
        let err = await discovery.publish(
            nickname: name, address: address, signedBundleBase64: signed.base64Encoded,
            avatarSeed: nil, keypair: keypair, rpc: rpc)
        if err != nil { errorMessage = "Не удалось закрепить, попробуй позже"; return }
        market.mintNickname(name)                 // record as owned/reserved
        nicknameManager.setCustomNickname(name)
        dismiss()
    }
}


// MARK: - NFT nickname picker

private struct NicknamePickerSheet: View {
    let market: MarketService
    let nicknameManager: NicknameManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 10) {
                        Text("Выбери активный ник")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 8)

                        ForEach(market.ownedNicknames, id: \.self) { handle in
                            let active = nicknameManager.customNickname == handle
                            Button {
                                nicknameManager.setCustomNickname(handle)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        Text("@").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    }.frame(width: 44, height: 44)
                                    Text(handle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.slate800)
                                    Spacer()
                                    if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive) }
                                }
                                .padding(14)
                                .background(Theme.glass)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                    .stroke(active ? Theme.accent : Theme.glassStroke, lineWidth: active ? 2 : 1))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            nicknameManager.clearCustomNickname()
                            dismiss()
                        } label: {
                            Text("Вернуть авто-ник (\(nicknameManager.generatedNickname))")
                                .font(.system(size: 13)).foregroundStyle(Theme.accentDeep)
                        }
                        .buttonStyle(.plain).padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
            }
            .navigationTitle("Мои ники")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Готово") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
        }
    }
}

// MARK: - RPC editor

private struct RPCEditorSheet: View {
    let rpc: SolanaRPCService
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 16) {
                    Image(systemName: "network").font(.system(size: 40))
                        .foregroundStyle(Theme.accentGradient).padding(.top, 24)
                    Text("Свой RPC-узел")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                    Text("Добавь свой сетевой узел (https). Приложение будет ходить через него; дефолтные остаются резервом. Пусто = дефолт.")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    TextField("https://your-rpc…", text: $url)
                        .font(.system(size: 14, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .padding(14).background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium)).padding(.horizontal, 24)

                    if let error {
                        Text(LocalizedStringKey(error)).font(.system(size: 12)).foregroundStyle(Theme.negative)
                    }

                    Button {
                        if rpc.setCustomRPC(url) { dismiss() }
                        else { error = "Неверный URL — нужен https://" }
                    } label: {
                        Text("Сохранить").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accentGradient).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).padding(.horizontal, 24)

                    if rpc.customRPC != nil {
                        Button {
                            rpc.setCustomRPC(nil); dismiss()
                        } label: {
                            Text("Сбросить к умолчанию (Helius)")
                                .font(.system(size: 13)).foregroundStyle(Theme.accentDeep)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .navigationTitle("RPC")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .onAppear { url = rpc.customRPC ?? "" }
        }
    }
}

// MARK: - Bio editor

private struct BioEditorSheet: View {
    let userProfile: UserProfileService
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 16) {
                    Text("Описание профиля")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                        .padding(.top, 24)
                    Text("Это описание видят контакты, которые добавят тебя по QR.")
                        .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    TextField("О себе…", text: $draft, axis: .vertical)
                        .font(.system(size: 15)).lineLimit(4...8)
                        .padding(14)
                        .background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .padding(.horizontal, 20)

                    Text("\(draft.count)/280").font(.system(size: 11)).foregroundStyle(Theme.slate400)

                    Button {
                        userProfile.setBio(draft)
                        dismiss()
                    } label: {
                        Text("Сохранить").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(Theme.accentGradient).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).padding(.horizontal, 20)
                    Spacer()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .onAppear { draft = userProfile.bio }
            .onChange(of: draft) { _, v in if v.count > 280 { draft = String(v.prefix(280)) } }
        }
    }
}

#Preview {
    ProfileTabView()
        .environment(WalletManager())
        .environment(PasscodeManager())
        .environment(BiometryService())
        .environment(AppRouter())
        .environment(NicknameManager())
        .environment(SubscriptionManager())
}
