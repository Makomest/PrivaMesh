//
//  HomeTabView.swift
//  privamesh
//
//  Matches HomeScreen.tsx: glass cards, line-under activity tabs,
//  deterministic MeshAvatarView, SOL price, privacy strip.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct HomeTabView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(WalletBalanceService.self) private var balance
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(SOLPriceService.self) private var price
    @Environment(TransactionHistoryService.self) private var txHistory
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(NicknameManager.self) private var nicknameManager
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(MessageQuotaService.self) private var quota
    @Environment(AvatarService.self) private var avatars
    @Environment(ToastManager.self) private var toast

    @Query(sort: \Contact.createdAt, order: .reverse) private var contacts: [Contact]

    @State private var balanceVisible = true
    @State private var activityTab: ActivityTab = .chats
    @State private var txPage = 0
    @State private var showAddContact = false
    @State private var showPaywall = false
    private static let txPageSize = 5

    enum ActivityTab { case chats, tx }

    // MARK: - Computed

    private var publicKey: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    private var shortAddress: String {
        guard let pk = publicKey else { return "—" }
        return String(pk.prefix(4)) + "…" + String(pk.suffix(4))
    }

    private var balanceText: String {
        guard let sol = balance.balanceSOL else { return "0.00" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 4
        fmt.minimumFractionDigits = 2
        return fmt.string(from: sol as NSDecimalNumber) ?? "0.00"
    }

    private var usdText: String? {
        guard let sol = balance.balanceSOL else { return nil }
        guard let usd = price.usdValue(sol: sol) else { return nil }
        return "≈ $\(String(format: "%.2f", usd))"
    }

    private var solPriceText: String? {
        guard let p = price.priceUSD else { return nil }
        return "1 SOL = $\(String(format: "%.2f", p))"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 0) {
                        brandRow.padding(.bottom, 16)
                        greetingRow.padding(.bottom, 16)
                        identityHaloCard.padding(.bottom, 12)
                        quotaCard.padding(.bottom, 16)
                        activitySection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
                .refreshable { await refresh() }
                .task { await refresh() }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $showAddContact) { AddContactView() }
            .sheet(isPresented: $showPaywall) { QuotaPaywallSheet() }
        }
    }

    // MARK: - Brand row

    private var brandRow: some View {
        HStack {
            HStack(spacing: 8) {
                PrivaLogo(size: 26)
                Text("Privamesh")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.slate800)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.positive)
                    .frame(width: 6, height: 6)
                    .shadow(color: Theme.positive.opacity(0.5), radius: 6)
                Text("Децентрализованное соединение активно")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.slate600)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.glass)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
        }
    }

    // MARK: - Greeting

    private var greetingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("С возвращением,")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.slate500)
                Text(nicknameManager.nickname)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentDeep)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Identity card

    private var identityHaloCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 60, height: 60).blur(radius: 8).opacity(0.55)
                Group {
                    if let active = avatars.activeDesign {
                        NFTAvatarView(seed: active.id, size: 56)
                    } else {
                        MeshAvatarView(id: publicKey ?? shortAddress, size: 56)
                            .overlay(Circle().stroke(Color.white.opacity(0.80), lineWidth: 2))
                            .clipShape(Circle())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(nicknameManager.nickname)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .lineLimit(1)
                    if subscription.isSubscribed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.accent)
                    }
                }
                // Copyable address.
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = publicKey
                    toast.show("Адрес скопирован")
                    #endif
                } label: {
                    HStack(spacing: 6) {
                        Text(shortAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.slate500)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 10)).foregroundStyle(Theme.positive)
                    Text("Защищено сквозным шифрованием")
                        .font(.system(size: 10)).foregroundStyle(Theme.accentDeep)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Message quota card

    private var quotaCard: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accentGradient).frame(width: 44, height: 44).opacity(0.9)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Осталось сообщений")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                    Text("\(quota.remaining)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .contentTransition(.numericText())
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(subscription.isSubscribed ? "Ещё" : "Купить")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentDeep)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.slate400)
                }
            }
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Activity section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Недавние чаты")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.slate800)
                Spacer()
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.glassStroke).frame(height: 1)
            }
            .padding(.bottom, 4)

            recentChats
        }
    }

    private func tabButton(_ title: String, tab: ActivityTab) -> some View {
        let active = activityTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { activityTab = tab }
        } label: {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13))
                .foregroundStyle(active ? Theme.slate800 : Theme.slate400)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(active ? Theme.accent : Color.clear)
                        .frame(height: 2)
                        .clipShape(Capsule())
                }
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent chats

    /// Max chats shown on the home screen — the full list lives in the Chats tab.
    private static let recentChatLimit = 4

    @ViewBuilder
    private var recentChats: some View {
        let scoped = contacts
            .filter { !$0.isSelf && ($0.ownerAddress == (publicKey ?? "") || $0.ownerAddress.isEmpty) }
            .sorted { ($0.lastMessage?.sentAt ?? $0.createdAt) > ($1.lastMessage?.sentAt ?? $1.createdAt) }
        let recent = Array(scoped.prefix(Self.recentChatLimit))
        if recent.isEmpty {
            Button { showAddContact = true } label: {
                emptyRow(icon: "person.badge.plus", text: "Пока нет чатов — добавь контакт", tappable: true)
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 6) {
                ForEach(recent) { contact in
                    NavigationLink {
                        ChatDetailView(contact: contact)
                    } label: {
                        chatRow(contact)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chatRow(_ contact: Contact) -> some View {
        let unread = contact.unreadCount
        return HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                if let seed = contact.profile?.activeAvatarSeed {
                    NFTAvatarView(seed: seed, size: 40)
                } else {
                    MeshAvatarView(id: contact.id, size: 40)
                }
                if unread > 0 {
                    Circle().fill(Theme.negative).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 2, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(contact.primaryName)
                        .font(.system(size: 14, weight: unread > 0 ? .semibold : .regular))
                        .foregroundStyle(Theme.slate800)
                    if !contact.isSelf, contact.profile?.isPremium == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    if let last = contact.lastMessage {
                        Text(last.sentAt.formatted(.relative(presentation: .named)))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.slate400)
                    }
                }
                HStack {
                    if let last = contact.lastMessage {
                        Text(last.body)
                            .font(.system(size: 12))
                            .foregroundStyle(unread > 0 ? Theme.slate700 : Theme.slate500)
                            .lineLimit(1)
                    } else {
                        Text("Нет сообщений")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.slate400)
                    }
                    Spacer()
                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(minWidth: 18).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.accentGradient).clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: - Empty row

    private func emptyRow(icon: String, text: String, tappable: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentGradient)
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .foregroundStyle(tappable ? Theme.accentDeep : Theme.slate500)
            if tappable {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accentDeep)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Refresh

    private func refresh() async {
        guard let pk = publicKey else { return }
        async let balanceRefresh: () = balance.refresh(publicKey: pk, rpc: rpc)
        async let priceRefresh: () = price.refresh()
        async let feeRefresh: () = rpc.refreshNetworkFee()
        async let txRefresh: () = txHistory.refresh(publicKey: pk, rpc: rpc, price: price,
                                                    gasAddress: gasWallet.address)
        _ = await (balanceRefresh, priceRefresh, feeRefresh, txRefresh)
    }

}

#if os(iOS)
import UIKit
#endif

#Preview {
    HomeTabView()
        .environment(WalletManager())
        .environment(WalletBalanceService())
        .environment(SolanaRPCService())
        .environment(SOLPriceService())
        .environment(TransactionHistoryService())
        .modelContainer(for: [Contact.self, ChatMessage.self], inMemory: true)
}
