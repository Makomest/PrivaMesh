//
//  ChatDetailView.swift
//  privamesh
//
//  Matches ChatDetail.tsx 1:1 — custom glass header, encryption badge,
//  info panel, tailed bubbles, glass composer bar.
//

import SwiftUI
import SwiftData
import SolanaSwift
#if os(iOS)
import PhotosUI
#endif

struct ChatDetailView: View {
    let contact: Contact

    @Environment(\.dismiss)                  private var dismiss
    @Environment(MessageSender.self)         private var sender
    @Environment(WalletManager.self)         private var wallet
    @Environment(GasWalletService.self)      private var gasWallet
    @Environment(TabBarVisibility.self)      private var tabBarVisibility
    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(SolanaRPCService.self)      private var rpc
    @Environment(\.modelContext)             private var context
    @Environment(WalletBalanceService.self)  private var balance
    @Environment(ToastManager.self)          private var toast
    @Environment(SOLPriceService.self)       private var solPrice
    @Environment(AvatarService.self)         private var avatars
    @Environment(MarketService.self)         private var market
    @Environment(BiometryService.self)       private var biometry
    @Environment(NicknameManager.self)       private var nicknameManager

    @State private var sendSOLService = SendSOLService()
    @State private var showPhotoPicker = false
    @State private var showSOLSheet    = false
    // One-time privacy consent: an in-chat SOL transfer is paid by the MAIN
    // wallet, revealing its address to the recipient + on-chain observers.
    @AppStorage("privamesh.solRevealConsent") private var solRevealConsent = false
    @State private var showSolPrivacyAlert = false
    @State private var pendingSolAmount: Decimal?
    @State private var showGiftSheet   = false
    @State private var showContactProfile = false
    @State private var inputText          = ""
    @State private var isSending          = false
    @State private var showInfo           = false
    @State private var showLowBalanceAlert = false
    @State private var infoMessage: MessageInfo?

    /// My main wallet address — stamped into outgoing payloads so contacts can
    /// pay me even when my on-chain fee payer is a gas wallet.
    private var walletAddress: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    /// Identifiable wrapper so a long-pressed message can drive `.sheet(item:)`
    /// without colliding with ChatMessage's own `id` (a tx signature).
    private struct MessageInfo: Identifiable {
        let id = UUID()
        let msg: ChatMessage
    }
    #if os(iOS)
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSendingPhoto = false
    #endif

    private var sortedMessages: [ChatMessage] {
        contact.messages.sorted { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                chatHeader
                if showInfo {
                    infoPanel
                } else {
                    encryptionBadge
                }
                messageList
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .alert("Недостаточно SOL", isPresented: $showLowBalanceAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            let feeStr = (rpc.estimatedFeeSOL as NSDecimalNumber).stringValue
            Text("Нужно минимум \(feeStr) SOL для оплаты комиссии сети. Пополни кошелёк и попробуй снова.")
        }
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .sheet(item: $infoMessage) { info in
            MessageInfoSheet(msg: info.msg, solPrice: solPrice)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSOLSheet) {
            SendSOLInChatSheet(balanceSOL: balance.balanceSOL, consented: solRevealConsent,
                               feeSOL: rpc.liveFeeSOL) { amount in
                Task { await sendSOL(amount) }
            }
            .presentationDetents([.medium])
        }
        .alert("Перевод раскроет твой адрес", isPresented: $showSolPrivacyAlert) {
            Button("Отмена", role: .cancel) { pendingSolAmount = nil }
            Button("Понятно, отправить") {
                solRevealConsent = true
                if let amt = pendingSolAmount { pendingSolAmount = nil; Task { await sendSOL(amt) } }
            }
        } message: {
            Text("Перевод SOL в чате оплачивается твоим ОСНОВНЫМ кошельком — его адрес станет виден получателю и в блокчейне. Сообщения остаются приватными (stealth-адреса), но платёж — нет.")
        }
        .sheet(isPresented: $showGiftSheet) {
            GiftPickerSheet { item in
                Task { await giftItem(item) }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showContactProfile) {
            ContactProfileView(contact: contact)
        }
        .onAppear {
            tabBarVisibility.hidden = true
            NotificationService.shared.activeChatId = contact.id   // suppress its notifications
        }
        .onDisappear {
            tabBarVisibility.hidden = false
            if NotificationService.shared.activeChatId == contact.id {
                NotificationService.shared.activeChatId = nil
            }
        }
        .task {
            DisappearingMessages.purge(contact, context: context)
            markMessagesRead()
            sender.setSenderProfile(nick: nicknameManager.nickname,
                                    avatarSeed: avatars.activeDesign?.id,
                                    wallet: walletAddress)
            if !contact.isSelf, let keypair = try? await wallet.currentKeyPair() {
                await rpc.refreshFee(senderKeyPair: keypair)
            }
        }
        .onChange(of: contact.messages.count) { markMessagesRead() }
    }

    /// Block a send (and warn) when the gas wallet is active but underfunded.
    private func gasFundsOK() async -> Bool {
        if await gasWallet.needsTopUp(rpc: rpc) {
            toast.show("Пополни газ-кошелёк — не хватает SOL на комиссию")
            return false
        }
        return true
    }

    private func markMessagesRead() {
        var changed = false
        for m in contact.messages where !m.isOutgoing && !m.isRead {
            m.isRead = true
            changed = true
        }
        if changed {
            try? context.save()
            // Update the app-icon badge to drop these now-read messages.
            NotificationService.shared.refreshBadge(context: context, myAddress: contact.ownerAddress)
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.slate600)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            if contact.isSelf {
                ZStack {
                    LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(Circle())
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            } else {
                Button { showContactProfile = true } label: {
                    if let seed = contact.profile?.activeAvatarSeed {
                        NFTAvatarView(seed: seed, size: 36)
                    } else {
                        MeshAvatarView(id: contact.id, size: 36)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(contact.isSelf ? "Избранное" : contact.primaryName))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.slate800)
                    .lineLimit(1)
                if !contact.isSelf && !contact.myNote.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.system(size: 9))
                        Text(contact.myNote).font(.system(size: 11)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.slate500)
                } else if let saved = contact.secondaryName {
                    Text(saved).font(.system(size: 11)).foregroundStyle(Theme.slate400).lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: contact.isSelf ? "bookmark.fill" : "lock.fill")
                            .font(.system(size: 9))
                        Text(LocalizedStringKey(contact.isSelf ? "заметки" : "зашифровано"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(contact.isSelf ? Theme.accentDeep : Theme.positive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !contact.isSelf {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showInfo.toggle() } } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(showInfo ? Theme.accentDeep : Theme.slate500)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.glassStroke).frame(height: 1)
        }
    }

    // MARK: - Info panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(icon: "shield.fill", color: Theme.accent,
                    bold: "Double Ratchet:", text: "новый ключ на каждое сообщение (PFS)")
            infoRow(icon: "lock.fill", color: Color(red: 0.55, green: 0.35, blue: 0.96),
                    bold: "Stealth-адреса:", text: "уникальный одноразовый адрес на сообщение")
            infoRow(icon: "bolt.fill", color: Color(red: 245/255, green: 158/255, blue: 11/255),
                    bold: "Cover-трафик:", text: "паттерн активности скрыт автоматически")
            Text("Хранение: блокчейн Solana · зашифровано · ключи не покидают устройство")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.slate400)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.4)).frame(height: 1)
        }
    }

    private func infoRow(icon: String, color: Color, bold: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)
            Group {
                Text(LocalizedStringKey(bold)).bold() + Text(verbatim: " ") + Text(LocalizedStringKey(text))
            }
            .font(.system(size: 12))
            .foregroundStyle(slate700)
        }
    }

    // MARK: - Encryption badge

    private var encryptionBadge: some View {
        HStack {
            Spacer()
            if contact.isSelf {
                HStack(spacing: 5) {
                    Image(systemName: "bookmark.fill").font(.system(size: 10))
                    Text("Хранится только на устройстве").font(.system(size: 11))
                }
                .foregroundStyle(Theme.accentDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.accent.opacity(0.10))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 10))
                    Text("Сообщения зашифрованы сквозным шифрованием").font(.system(size: 11))
                }
                .foregroundStyle(Theme.positive)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.positive.opacity(0.10))
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            // Sort once per render; change-handlers key off the raw count and the
            // newest message (max) without re-sorting the whole history.
            let messages = sortedMessages
            ScrollView {
                LazyVStack(spacing: 10) {
                    if messages.isEmpty { emptyState.padding(.top, 60) }
                    ForEach(messages) { msg in
                        messageBubble(msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: contact.messages.count) {
                if let last = contact.messages.max(by: { $0.sentAt < $1.sentAt }) {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentGradient)
            Text("Сообщения зашифрованы сквозным шифрованием")
                .font(.system(size: 13))
                .foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bubble

    @ViewBuilder
    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.isOutgoing { Spacer(minLength: 50) }

            Group {
                if msg.kind == "sol" {
                    solBubble(msg)
                } else if msg.kind == "gift" {
                    giftBubble(msg)
                } else if let key = msg.photoKey {
                    PhotoBubble(txId: msg.body, keyBase64: key, isOutgoing: msg.isOutgoing)
                } else {
                    bubbleContent(msg)
                }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                infoMessage = MessageInfo(msg: msg)
            }

            if !msg.isOutgoing { Spacer(minLength: 50) }
        }
    }

    // MARK: - SOL / gift bubbles

    private func solBubble(_ msg: ChatMessage) -> some View {
        let amount = msg.solAmount ?? 0
        return VStack(spacing: 6) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 28)).foregroundStyle(.white)
            Text("\(Self.formatSOL(amount)) SOL")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
            if let usd = solPrice.usdValue(sol: Decimal(amount)) {
                Text(Self.formatUSD(usd))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
            Text(LocalizedStringKey(msg.isOutgoing ? "Отправлено" : "Получено"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.7, blue: 0.5), Theme.accentDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Plain decimal (no scientific notation), trimming trailing zeros.
    static func formatSOL(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 9
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.9f", value)
    }

    static func formatUSD(_ usd: Double) -> String {
        if usd > 0 && usd < 0.01 { return "< $0.01" }
        return String(format: "≈ $%.2f", usd)
    }

    private func giftBubble(_ msg: ChatMessage) -> some View {
        VStack(spacing: 8) {
            Text(msg.isOutgoing ? LocalizedStringKey("🎁 Подарок") : LocalizedStringKey("🎁 Вам подарок"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
            Group {
                if msg.giftKind == "avatar", let ref = msg.giftRef {
                    NFTAvatarView(seed: ref, size: 72)
                } else {
                    ZStack {
                        Circle().fill(.white.opacity(0.25))
                        Text("@").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }.frame(width: 72, height: 72)
                }
            }
            Text(msg.giftName ?? "NFT").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            if !msg.isOutgoing {
                if msg.giftClaimed {
                    Text("Забрано ✓").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Button { claimGift(msg) } label: {
                        Text("Забрать").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 18).padding(.vertical, 7)
                            .background(.white).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Отправлено").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(LinearGradient(colors: [Color(red: 0.65, green: 0.35, blue: 0.95), Theme.accent],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func bubbleContent(_ msg: ChatMessage) -> some View {
        VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 2) {
            Text(msg.body)
                .font(.system(size: 14))
                .foregroundStyle(msg.isOutgoing ? .white : slate700)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 3) {
                Text(msg.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(msg.isOutgoing ? .white.opacity(0.70) : Theme.slate400)
                if msg.isOutgoing {
                    Image(systemName: statusIcon(msg.status))
                        .font(.system(size: 9))
                        .foregroundStyle(msg.status == "failed" ? Theme.negative : .white.opacity(0.70))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            if msg.isOutgoing {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 18,
                    bottomTrailingRadius: 4, topTrailingRadius: 18
                )
                .fill(Theme.accentGradient)
            } else {
                UnevenRoundedRectangle(
                    topLeadingRadius: 18, bottomLeadingRadius: 4,
                    bottomTrailingRadius: 18, topTrailingRadius: 18
                )
                .fill(Theme.glass)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 18, bottomLeadingRadius: 4,
                        bottomTrailingRadius: 18, topTrailingRadius: 18
                    )
                    .stroke(Theme.glass, lineWidth: 1)
                )
            }
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "sending": return "clock"
        case "failed":  return "exclamationmark.circle"
        default:        return "checkmark"
        }
    }

    // MARK: - Input bar

    private static let maxInputBytes = 350

    private var inputBar: some View {
        HStack(spacing: 8) {
            #if os(iOS)
            if !contact.isSelf {
                Menu {
                    Button { showSOLSheet = true } label: { Label("Отправить SOL", systemImage: "dollarsign.circle") }
                    Button { showGiftSheet = true } label: { Label("Подарить NFT", systemImage: "gift") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accentDeep)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.70))
                        .clipShape(Circle())
                }
            }
            #endif

            HStack(spacing: 0) {
                TextField(contact.isSelf ? LocalizedStringKey("Заметка…") : LocalizedStringKey("Сообщение"), text: $inputText, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.slate800)
                    .lineLimit(1...4)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
                    .onChange(of: inputText) { _, new in
                        if new.utf8.count > Self.maxInputBytes {
                            // Trim to stay within the Solana memo size limit
                            var trimmed = new
                            while trimmed.utf8.count > Self.maxInputBytes {
                                trimmed.removeLast()
                            }
                            inputText = trimmed
                        }
                    }

                let remaining = Self.maxInputBytes - inputText.utf8.count
                if remaining < 80 {
                    Text("\(remaining)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(remaining < 20 ? Color.red : Theme.slate400)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.glass)
            .overlay(
                Capsule().stroke(Theme.glass, lineWidth: 1)
            )
            .clipShape(Capsule())

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: isSending ? "clock" : "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        inputText.isEmpty
                            ? AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                            : AnyShapeStyle(Theme.accentGradient)
                    )
                    .clipShape(Circle())
                    .shadow(color: Theme.accent.opacity(inputText.isEmpty ? 0 : 0.45), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.glassStroke).frame(height: 1)
        }
    }

    // MARK: - Actions

    // Minimum balance = estimated fee × 3 safety buffer (updated from RPC)
    private var minBalanceSOL: Decimal { rpc.estimatedFeeSOL * 3 }

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // All messages go through blockchain — check balance. When the gas
        // wallet pays fees, the main balance is irrelevant for messages.
        if !gasWallet.isActive, let bal = balance.balanceSOL, bal < minBalanceSOL {
            showLowBalanceAlert = true
            return
        }

        guard let keypair = try? await wallet.currentKeyPair() else { return }
        guard await gasFundsOK() else { return }
        let payer = await gasWallet.feePayer(fallback: keypair)
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        inputText = ""
        isSending = true
        await sender.send(text: text, to: contact, senderKeyPair: payer,
                          identity: identity, rpc: rpc, context: context)
        if case let .failure(message) = sender.state {
            toast.show(message)
        }
        isSending = false
    }

    // MARK: - SOL / gifts

    private func sendSOL(_ amount: Decimal) async {
        guard amount > 0 else { return }
        // First in-chat SOL transfer: require one-time consent that it reveals
        // the main wallet address. Afterwards a passive reminder in the sheet.
        guard solRevealConsent else {
            pendingSolAmount = amount
            showSolPrivacyAlert = true
            return
        }
        guard await gasFundsOK() else { return }
        guard await biometry.confirm(reason: "Подтвердить перевод \(amount) SOL") else { return }
        guard let keypair = try? await wallet.currentKeyPair() else { return }
        // The real SOL transfer is genuine value — always from the main wallet,
        // to their real wallet (payTo), not a gas-wallet contact id.
        await sendSOLService.send(from: keypair, to: contact.payTo, amountSOL: amount, rpc: rpc)
        guard case let .success(signature) = sendSOLService.state else {
            if case let .failure(msg) = sendSOLService.state { toast.show(msg) }
            return
        }
        // The chat note is just a message — route it through the gas wallet.
        let payer = await gasWallet.feePayer(fallback: keypair)
        await sender.sendSOLNote(amount: NSDecimalNumber(decimal: amount).doubleValue,
                                 signature: signature, to: contact, senderKeyPair: payer,
                                 identity: identity, rpc: rpc, context: context)
        toast.show(String(localized: "Отправлено \(amount) SOL"))
    }

    private func giftItem(_ item: MarketItem) async {
        guard await gasFundsOK() else { return }
        guard await biometry.confirm(reason: "Подтвердить подарок: \(item.name)") else { return }
        guard let keypair = try? await wallet.currentKeyPair() else { return }
        // Remove from my collection (sim ownership transfer).
        switch item.kind {
        case .avatar:   avatars.sell(item.ref)            // leaves my collection
        case .nickname: market.giveAwayNickname(item.ref)
        }
        let payer = await gasWallet.feePayer(fallback: keypair)
        await sender.sendGift(itemKind: item.kind.rawValue, ref: item.ref, name: item.name,
                              rarity: item.rarity, to: contact, senderKeyPair: payer,
                              identity: identity, rpc: rpc, context: context)
        toast.show(String(localized: "Подарок отправлен: \(item.name)"))
    }

    private func claimGift(_ msg: ChatMessage) {
        guard !msg.giftClaimed, let ref = msg.giftRef, let kind = msg.giftKind else { return }
        market.claimGift(kind: kind, ref: ref)
        msg.giftClaimed = true
        try? context.save()
        toast.show(String(localized: "Подарок забран: \(msg.giftName ?? "")"))
    }

    #if os(iOS)
    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let keypair = try? await wallet.currentKeyPair() else {
            selectedPhoto = nil; return
        }
        guard await gasFundsOK() else { selectedPhoto = nil; return }
        selectedPhoto = nil
        isSendingPhoto = true
        let payer = await gasWallet.feePayer(fallback: keypair)
        await sender.sendPhoto(image: image, to: contact, senderKeyPair: payer,
                               identity: identity, rpc: rpc, context: context)
        isSendingPhoto = false
    }
    #endif
}

// Adaptive: dark text in light mode, light text in dark mode (was a hardcoded
// dark slate → unreadable incoming-bubble text on the dark theme).
private let slate700 = Theme.slate700

// MARK: - Send SOL sheet

private struct SendSOLInChatSheet: View {
    let balanceSOL: Decimal?
    var consented: Bool = false
    var feeSOL: Decimal = 0
    let onSend: (Decimal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }
    private var feeText: String {
        let d = NSDecimalNumber(decimal: feeSOL).doubleValue
        return String(format: "%.6f", d)
    }
    private var canSend: Bool {
        guard let a = amount, a > 0 else { return false }
        if let bal = balanceSOL { return a <= bal }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 18) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Theme.accentGradient).padding(.top, 24)
                    if let bal = balanceSOL {
                        Text("Баланс: \(NSDecimalNumber(decimal: bal).stringValue) SOL")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                    }
                    HStack {
                        TextField("0.0", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("SOL").font(.system(size: 16)).foregroundStyle(Theme.slate500)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                    .background(Theme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, 24)

                    if feeSOL > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "fuelpump.fill").font(.system(size: 10))
                            Text("Комиссия сети ≈ \(feeText) SOL").font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.slate400)
                    }
                    if consented {
                        // Passive reminder after the one-time consent.
                        HStack(spacing: 6) {
                            Image(systemName: "eye.fill").font(.system(size: 11))
                            Text("Платёж раскроет твой основной адрес")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Theme.slate400)
                        .padding(.horizontal, 24)
                    }

                    if canSend {
                        SlideToConfirm(text: "Сдвинь, чтобы отправить") {
                            if let a = amount { onSend(a); dismiss() }
                        }
                        .padding(.horizontal, 24)
                    } else {
                        Text("Введи сумму")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate400)
                            .frame(height: 54)
                    }
                    Spacer()
                }
            }
            .navigationTitle("Отправить SOL")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
        }
    }
}

// MARK: - Gift picker sheet

private struct GiftPickerSheet: View {
    let onPick: (MarketItem) -> Void
    @Environment(MarketService.self) private var market
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    let items = market.myCollection
                    if items.isEmpty {
                        Text("Нет NFT для подарка.\nКупи аватар или ник в маркете.")
                            .font(.system(size: 14)).foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center).padding(.top, 60)
                    } else {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(items) { item in
                                Button { onPick(item); dismiss() } label: {
                                    VStack(spacing: 8) {
                                        Group {
                                            if item.kind == .avatar {
                                                NFTAvatarView(seed: item.ref, size: 80)
                                            } else {
                                                ZStack {
                                                    Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    Text("@").font(.system(size: 40, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white)
                                                }.frame(width: 80, height: 80)
                                            }
                                        }
                                        Text(item.name).font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Theme.slate700).lineLimit(1)
                                    }
                                    .padding(12).frame(maxWidth: .infinity)
                                    .background(Theme.glass)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                        .stroke(Theme.glassStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Подарить NFT")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Закрыть") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
        }
    }
}

#if os(iOS)
import UIKit
#endif
