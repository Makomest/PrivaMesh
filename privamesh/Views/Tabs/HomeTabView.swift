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
    @Environment(AvatarService.self) private var avatars
    @Environment(ToastManager.self) private var toast

    @Query(sort: \Contact.createdAt, order: .reverse) private var contacts: [Contact]

    @State private var balanceVisible = true
    @State private var activityTab: ActivityTab = .chats
    @State private var txPage = 0
    @State private var showAddContact = false
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
                        balanceCard.padding(.bottom, 12)
                        gasTracker.padding(.bottom, 12)
                        actionButtons.padding(.bottom, 16)
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

    // MARK: - Balance card

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Баланс SOL")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate500)
                Spacer()
                if let change = price.change24h {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 10))
                        Text(String(format: "%+.1f%% (24h)", change))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((change >= 0 ? Theme.positive : Theme.negative).opacity(0.12))
                    .clipShape(Capsule())
                }
                Button {
                    withAnimation { balanceVisible.toggle() }
                } label: {
                    Image(systemName: balanceVisible ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.slate400)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if balanceVisible {
                    Text(balanceText)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .contentTransition(.numericText())
                    Text("SOL")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.slate500)
                    if let usd = usdText {
                        Text(usd)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.slate400)
                    }
                } else {
                    Text("••••••")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate400)
                }
                Spacer()
                if case .loading = balance.state {
                    ProgressView().tint(Theme.accent)
                }
            }

            if let priceStr = solPriceText {
                Text(priceStr)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.slate400)
            }

            if case let .error(msg) = balance.state {
                Text(LocalizedStringKey(msg)).font(.caption2).foregroundStyle(Theme.negative).lineLimit(1)
            }
        }
        .padding(16)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            NavigationLink { SendSOLView() } label: {
                actionBtn(icon: "arrow.up.right", label: "Отправить")
            }
            .buttonStyle(.plain)

            Button {
                #if os(iOS)
                if let pk = publicKey {
                    UIPasteboard.general.string = pk
                    toast.show("Адрес скопирован")
                }
                #endif
            } label: {
                actionBtn(icon: "arrow.down.left", label: "Получить")
            }
            .buttonStyle(.plain)
        }
    }

    private func actionBtn(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentDeep)
            Text(LocalizedStringKey(label))
                .font(.system(size: 11))
                .foregroundStyle(Theme.slate600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
    }

    // MARK: - Activity section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 0) {
                tabButton("Недавние чаты", tab: .chats).frame(maxWidth: .infinity)
                tabButton("Недавние транзакции", tab: .tx).frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.glassStroke)
                    .frame(height: 1)
            }
            .padding(.bottom, 4)

            if activityTab == .chats {
                recentChats
            } else {
                recentTransactions
            }
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
                HStack {
                    Text(contact.primaryName)
                        .font(.system(size: 14, weight: unread > 0 ? .semibold : .regular))
                        .foregroundStyle(Theme.slate800)
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

    // MARK: - Recent transactions

    @ViewBuilder
    private var recentTransactions: some View {
        // Home shows only real money in/out — message txs (encrypted memos) live
        // in the Wallet tab's full history.
        let all = txHistory.transactions.filter { !$0.isMessage }
        if all.isEmpty {
            emptyRow(icon: "arrow.left.arrow.right.circle", text: "Нет транзакций")
        } else {
            let pageCount = max(1, Int(ceil(Double(all.count) / Double(Self.txPageSize))))
            let start = min(txPage, pageCount - 1) * Self.txPageSize
            let paged = Array(all[start..<min(start + Self.txPageSize, all.count)])
            VStack(spacing: 0) {
                ForEach(Array(paged.enumerated()), id: \.element.id) { idx, tx in
                    TransactionRowView(tx: tx)
                    if idx < paged.count - 1 {
                        Divider().background(Theme.slate300.opacity(0.4)).padding(.leading, 52)
                    }
                }
            }
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
            PageBar(page: $txPage, pageCount: pageCount)
        }
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

    // MARK: - Network gas tracker

    private var gasTracker: some View {
        let feeSOL = NSDecimalNumber(decimal: rpc.liveFeeSOL).doubleValue
        let usd = price.usdValue(sol: rpc.liveFeeSOL)
        let busy = rpc.networkPriorityMicroLamports
        let level: (String, Color) = busy > 50_000 ? ("высокая", Theme.negative)
            : busy > 5_000 ? ("средняя", Color(red: 245/255, green: 158/255, blue: 11/255))
            : ("низкая", Theme.positive)
        return HStack(spacing: 12) {
            Image(systemName: "fuelpump.fill").font(.system(size: 15))
                .foregroundStyle(level.1).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Комиссия сети Solana").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.slate700)
                Text("\(String(format: "%.6f", feeSOL)) SOL\(usd != nil ? " · ≈ $\(String(format: "%.4f", usd!))" : "") за транзакцию")
                    .font(.system(size: 11)).foregroundStyle(Theme.slate400)
            }
            Spacer()
            Text(LocalizedStringKey(level.0)).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(level.1)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(level.1.opacity(0.12), in: Capsule())
        }
        .padding(14)
        .background(Theme.glass)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium).stroke(Theme.glassStroke, lineWidth: 1))
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
