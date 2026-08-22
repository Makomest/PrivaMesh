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
    /// When opened from a message-search hit, the message to scroll to and flash.
    var jumpToMessageID: String? = nil

    /// The message currently flashing after a search jump (cleared after ~2s).
    @State private var highlightID: String?
    /// Drives the decaying shake on the flashed bubble (0 → 1 over the pulse).
    @State private var shakeAmt: CGFloat = 0
    /// Gates message entrance animations so the initial history draws flat.
    @State private var didInitialLoad = false
    /// Slow breathing of the empty-chat lock icon.
    @State private var emptyBreathe = false

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
    @Environment(AvatarService.self)         private var avatars
    @Environment(MarketService.self)         private var market
    @Environment(BiometryService.self)       private var biometry
    @Environment(NicknameManager.self)       private var nicknameManager
    @Environment(MessageQuotaService.self)   private var quota
    @Environment(SubscriptionManager.self)   private var subscription

    @State private var showPhotoPicker = false
    @State private var showQuotaPaywall = false
    // Whether to reveal the PrivaMesh+ verification badge to contacts (metadata).
    @AppStorage("privamesh.shareVerifiedBadge") private var shareVerifiedBadge = true
    @State private var showContactProfile = false
    @State private var inputText          = ""
    @State private var isSending          = false
    @State private var showInfo           = false
    @State private var infoMessage: MessageInfo?
    /// Cached sorted history. Sorting `contact.messages` is O(N log N); doing it
    /// inside `body` re-sorts the whole history on every keystroke (the input
    /// field lives in this view). Recompute only when the message count changes.
    @State private var sortedCache: [ChatMessage] = []

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

    private func recomputeSorted() {
        sortedCache = contact.messages.sorted { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        ZStack {
            // Louder than the globe's own backdrop on purpose: the bubbles are
            // glass, and glass is only visible when it has something to refract.
            // At the default weight the mesh vanished under the blur and every
            // bubble read as a flat grey slab.
            OrbitMeshBackground(intensity: 2.6)
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
        #if os(iOS)
        .navigationBarHidden(true)
        #endif
        .sheet(item: $infoMessage) { info in
            MessageInfoSheet(msg: info.msg)
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showContactProfile) {
            ContactProfileView(contact: contact).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showQuotaPaywall) {
            QuotaPaywallSheet()
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
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
                                    isPremium: subscription.isSubscribed && shareVerifiedBadge)
            // Fee refresh is incidental — opening a chat must never pop Face ID.
            // Use the keypair only if it's already unlocked this session; if not,
            // the fee refreshes at send time instead.
            if !contact.isSelf, let keypair = wallet.readyKeyPair {
                await rpc.refreshFee(senderKeyPair: keypair)
            }
        }
        .onChange(of: contact.messages.count) { markMessagesRead() }
    }

    /// Block a send (and warn) when the gas wallet is active but underfunded.
    private func gasFundsOK() async -> Bool {
        if await gasWallet.needsTopUp(rpc: rpc) {
            toast.show("Не удалось отправить сообщение")
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
                    .foregroundStyle(.white.opacity(0.75))
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
                        MeshAvatarView(id: contact.id, name: contact.primaryName, size: 36)
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(contact.isSelf ? "Избранное" : contact.primaryName))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    // Two different claims, so two different marks: the shield
                    // means YOU compared safety numbers, the seal only means the
                    // person pays for PrivaMesh+. Sharing one glyph would let a
                    // subscription read as a verified identity.
                    if !contact.isSelf, contact.isVerified {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 12)).foregroundStyle(.white)
                            .accessibilityLabel("Контакт проверен")
                    }
                    if !contact.isSelf, contact.profile?.isPremium == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                if !contact.isSelf && !contact.myNote.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text").font(.system(size: 9))
                        Text(contact.myNote).font(.system(size: 11)).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                } else if let saved = contact.secondaryName {
                    Text(saved).font(.system(size: 11)).foregroundStyle(.white.opacity(0.40)).lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: contact.isSelf ? "bookmark.fill" : "lock.fill")
                            .font(.system(size: 9))
                        Text(LocalizedStringKey(contact.isSelf ? "заметки" : "зашифровано"))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !contact.isSelf {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showInfo.toggle() } } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(showInfo ? 1.0 : 0.55))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            // Same glass as the bubbles: a translucent pane, not a material. The
            // mesh runs through it instead of being blurred into grey.
            Rectangle().fill(Color.white.opacity(0.05))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
    }

    // MARK: - Info panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(icon: "shield.fill", color: .white.opacity(0.55),
                    bold: "Double Ratchet:", text: "новый ключ на каждое сообщение (PFS)")
            infoRow(icon: "lock.fill", color: .white.opacity(0.55),
                    bold: "Stealth-адреса:", text: "уникальный одноразовый адрес на сообщение")
            infoRow(icon: "bolt.fill", color: .white.opacity(0.55),
                    bold: "Cover-трафик:", text: "паттерн активности скрыт автоматически")
            Text("Зашифровано · ключи не покидают устройство")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.40))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Denser than the header: this pane is four lines of dense text, and
            // at the header's weight the mesh ran straight through the words.
            // Legibility outranks the effect where there is something to read.
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.black.opacity(0.45))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
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
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: 10))
                    Text("Сообщения зашифрованы сквозным шифрованием").font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            // Use the cached sorted history (recomputed only on count change) so
            // typing in the input field does not re-sort the whole conversation.
            ScrollView {
                LazyVStack(spacing: 10) {
                    if sortedCache.isEmpty { emptyState.padding(.top, 60) }
                    ForEach(sortedCache) { msg in
                        messageBubble(msg).id(msg.id)
                            // A new message eases in — a soft rise + scale from the
                            // side it belongs to. Only NEW ones: the initial history
                            // is drawn flat (didInitialLoad gates the animation), so
                            // opening a chat never plays a wall of transitions.
                            .transition(.opacity.combined(
                                with: .scale(scale: 0.92,
                                             anchor: msg.isOutgoing ? .bottomTrailing : .bottomLeading)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .animation(didInitialLoad ? .spring(response: 0.4, dampingFraction: 0.82) : nil,
                           value: sortedCache.count)
            }
            .scrollIndicators(.hidden)
            .onChange(of: contact.messages.count) {
                recomputeSorted()
                if let last = sortedCache.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                recomputeSorted()
                // Let the initial history render flat, then arm entrance animations.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { didInitialLoad = true }
                if let jump = jumpToMessageID, sortedCache.contains(where: { $0.id == jump }) {
                    // Jump to the searched message. A tiny delay lets the LazyVStack
                    // build the target row before we scroll to it (scrolling to a
                    // not-yet-realised id in a LazyVStack silently no-ops).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(jump, anchor: .center)
                        }
                        flash(jump)
                    }
                } else if let last = sortedCache.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// Flash the jumped-to message: a decaying shake + a highlight tint that fades
    /// out after ~2s, so the eye lands on exactly the message the search matched.
    private func flash(_ id: String) {
        highlightID = id
        shakeAmt = 0
        withAnimation(.easeOut(duration: 1.1)) { shakeAmt = 1 }   // decaying jitter
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.45)) { highlightID = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.35))   // accentGradient is a fill token, unreadable as art here
                // A slow, calm breath — the empty chat feels alive, not dead.
                .scaleEffect(emptyBreathe ? 1.06 : 1.0)
                .opacity(emptyBreathe ? 0.5 : 0.32)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                        emptyBreathe = true
                    }
                }
            Text("Сообщения зашифрованы сквозным шифрованием")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
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
                if let key = msg.photoKey {
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
            // Search-jump flash: a tint that fades out and a decaying shake.
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.accent.opacity(highlightID == msg.id ? 0.22 : 0))
                    .padding(-6)
            )
            .modifier(ShakeEffect(animatableData: highlightID == msg.id ? shakeAmt : 0))

            if !msg.isOutgoing { Spacer(minLength: 50) }
        }
    }


    private func bubbleContent(_ msg: ChatMessage) -> some View {
        // Colours are pinned light rather than taken from the adaptive Theme
        // tokens: this screen paints its own black ground, so an adaptive token
        // would hand us black text on black in light mode.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: msg.isOutgoing ? 18 : 4,
            bottomTrailingRadius: msg.isOutgoing ? 4 : 18,
            topTrailingRadius: 18,
            style: .continuous
        )
        return VStack(alignment: msg.isOutgoing ? .trailing : .leading, spacing: 2) {
            Text(msg.body)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 3) {
                Text(msg.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                if msg.isOutgoing {
                    Image(systemName: statusIcon(msg.status))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(msg.status == "failed" ? 0.95 : 0.45))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Frosted glass. The material already blurs and darkens the backdrop in
        // a dark scheme — piling black on top of it (0.34/0.52) was what turned
        // these into opaque slabs. Only a faint white lift now, so the mesh
        // behind stays legible THROUGH the bubble. Outgoing sits a step
        // brighter; that difference is all that separates the two sides now
        // that colour is gone.
        // NOT a material. `.ultraThinMaterial` blurs whatever is behind it, and a
        // 0.5pt mesh line does not survive a blur — it averages into the grey the
        // material already is over black. The result was a slab every time.
        //
        // A translucent fill instead: the mesh runs visibly THROUGH the bubble,
        // which is what actually reads as glass. Frost comes from the hairline
        // edge, not from destroying the thing behind it.
        .background {
            ZStack {
                shape.fill(Color.white.opacity(msg.isOutgoing ? 0.16 : 0.075))
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
        }
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: msg.isOutgoing
                        ? [.white.opacity(0.34), .white.opacity(0.10), .white.opacity(0.04)]
                        : [.white.opacity(0.18), .white.opacity(0.06), .white.opacity(0.02)],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75)
        )
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

            HStack(spacing: 0) {
                TextField(contact.isSelf ? LocalizedStringKey("Заметка…") : LocalizedStringKey("Сообщение"), text: $inputText, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(.white.opacity(remaining < 20 ? 0.95 : 0.40))
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // The frost lives HERE now, on the pill itself — it is the only thing
            // that must hide the messages scrolling behind it. The bar around it
            // is plain black, so nothing grey frames the composer.
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.black.opacity(0.32))
                }
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.75))
            .clipShape(Capsule())

            Button {
                Task { await sendMessage() }
            } label: {
                Image(systemName: isSending ? "clock" : "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(inputText.isEmpty ? 0.22 : 1.0)))
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isSending)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 28)
        // Bar background: just the black mesh ground, no grey slab. The frosted
        // pill above handles hiding the scroll; only the strip directly behind
        // the pill needs cover, and a soft top-to-bottom black scrim gives it
        // without boxing the composer in grey.
        .background {
            LinearGradient(
                stops: [.init(color: .black.opacity(0), location: 0),
                        .init(color: .black, location: 0.45),
                        .init(color: .black, location: 1)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Actions

    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        #if DEBUG
        // Design-preview harness has no wallet, so the real send path bails out at
        // currentKeyPair() and the button looks dead. Append the message locally
        // so the flow can be demoed. Never compiled into a release build.
        if CommandLine.arguments.contains("-orbitUIPreview") {
            let m = ChatMessage(id: UUID().uuidString, body: text, isOutgoing: true,
                                sentAt: Date(), status: "sent")
            m.isRead = true
            m.contact = contact
            context.insert(m)
            try? context.save()
            inputText = ""
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            return
        }
        #endif

        // Metered messaging: delivery is sponsored by the app, so access is gated
        // by the Apple IAP allowance.
        guard quota.canSend else { showQuotaPaywall = true; return }

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
        switch sender.state {
        case .failure(let message):
            if sender.lastFailureIsQuota { showQuotaPaywall = true } else { toast.show(message) }
        case .success:
            quota.consume()   // charge one message only on success
        default:
            break
        }
        isSending = false
    }


    #if os(iOS)
    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard quota.canSend else { selectedPhoto = nil; showQuotaPaywall = true; return }
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
        if case .success = sender.state { quota.consume() }
        isSendingPhoto = false
    }
    #endif
}

// Adaptive: dark text in light mode, light text in dark mode (was a hardcoded
// dark slate → unreadable incoming-bubble text on the dark theme).
private let slate700 = Color.white.opacity(0.72)   // pinned: see infoRow

#if os(iOS)
import UIKit
#endif

/// A decaying horizontal shake driven by `animatableData` 0→1: a few oscillations
/// that shrink to nothing. Used to flash the message a search jump landed on.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var shakes: CGFloat = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let decay = 1 - animatableData
        let dx = travel * decay * sin(animatableData * .pi * shakes * 2)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}
