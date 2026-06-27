//
//  WalletTabView.swift
//  privamesh
//

import SwiftUI

struct WalletTabView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(WalletBalanceService.self) private var balance
    @Environment(TransactionHistoryService.self) private var txHistory
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(SOLPriceService.self) private var price
    @Environment(ToastManager.self) private var toast

    @State private var balanceVisible = true
    @State private var showReceive = false
    @State private var addressCopied = false
    @State private var txTab: TxTab = .payments
    @State private var txPage = 0
    private static let pageSize = 6

    private enum TxTab { case payments, messages }

    private var publicKey: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    private var balanceText: String {
        guard let sol = balance.balanceSOL else { return "0.00" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 4
        f.minimumFractionDigits = 2
        return f.string(from: sol as NSDecimalNumber) ?? "0.00"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        header
                        balanceCard
                        actionButtons
                        addressCard
                        transactionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await refresh()
                }
                .task {
                    await refresh()
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Кошелёк")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.slate800)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.positive)
                    Text("Self-custodial · Solana")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            Spacer()
            Button {
                balanceVisible.toggle()
            } label: {
                Image(systemName: balanceVisible ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.slate500)
                    .padding(10)
            }
            .glassEffect(.regular, in: .circle)
            .buttonStyle(.plain)
        }
    }

    private var usdText: String? {
        guard let sol = balance.balanceSOL else { return nil }
        guard let usd = price.usdValue(sol: sol) else { return nil }
        return "≈ $\(String(format: "%.2f", usd))"
    }

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
                            .font(.system(size: 11))
                        Text(String(format: "%+.1f%% (24h)", change))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(change >= 0 ? Theme.positive : Theme.negative)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((change >= 0 ? Theme.positive : Theme.negative).opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if balanceVisible {
                    Text(balanceText)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate800)
                        .contentTransition(.numericText())
                    Text("SOL")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.slate500)
                    if let usd = usdText {
                        Text(usd)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.slate400)
                    }
                } else {
                    Text("•••••")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.slate400)
                }
                Spacer()
                if case .loading = balance.state {
                    ProgressView().tint(Theme.accent)
                }
            }

            if let p = price.priceUSD {
                Text("1 SOL = $\(String(format: "%.2f", p))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.slate400)
            } else if let last = balance.lastUpdated {
                Text("обновлено \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.slate400)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusLarge))
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            NavigationLink {
                SendSOLView()
            } label: {
                actionPill(icon: "arrow.up.right", text: "Отправить")
            }
            .buttonStyle(.plain)

            Button {
                showReceive = true
            } label: {
                actionPill(icon: "arrow.down.left", text: "Получить")
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showReceive) {
                receiveSheet
            }
        }
    }

    private func actionPill(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentDeep)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
            Text(LocalizedStringKey(text))
                .font(.system(size: 11))
                .foregroundStyle(Theme.slate500)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var addressCard: some View {
        if let publicKey {
            VStack(alignment: .leading, spacing: 6) {
                Text("Адрес")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate500)
                HStack {
                    Text(publicKey)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.slate800)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = publicKey
                        toast.show("Адрес скопирован")
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
        }
    }

    private var txRows: [TransactionHistoryService.TxRow] {
        txHistory.transactions.filter {
            txTab == .messages ? $0.isMessage : !$0.isMessage
        }
    }
    private var pageCount: Int { max(1, Int(ceil(Double(txRows.count) / Double(Self.pageSize)))) }
    private var pagedRows: [TransactionHistoryService.TxRow] {
        let start = txPage * Self.pageSize
        guard start < txRows.count else { return [] }
        return Array(txRows[start..<min(start + Self.pageSize, txRows.count)])
    }

    private var txTabPicker: some View {
        HStack(spacing: 0) {
            txTabButton("Переводы", .payments)
            txTabButton("Сообщения", .messages)
        }
        .background(Theme.glassStroke).clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func txTabButton(_ label: String, _ value: TxTab) -> some View {
        let on = txTab == value
        return Button { withAnimation(.easeInOut(duration: 0.2)) { txTab = value } } label: {
            Text(LocalizedStringKey(label))
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .white : Theme.slate600)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .clipShape(Capsule()).padding(3)
        }
        .buttonStyle(.plain)
    }

    private var transactionsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Транзакции")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.slate500)
                Spacer()
                if case .loading = txHistory.state {
                    ProgressView().scaleEffect(0.7).tint(Theme.accent)
                }
            }
            .padding(.top, 4)

            txTabPicker

            if case let .error(msg) = txHistory.state {
                Text(LocalizedStringKey(msg))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.negative)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
            } else if txRows.isEmpty && !txHistory.isLoading && !txHistory.isIdle {
                Text(LocalizedStringKey(txTab == .messages ? "Нет сообщений-транзакций" : "Нет переводов"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.slate400)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pagedRows.enumerated()), id: \.element.id) { idx, tx in
                        TransactionRowView(tx: tx)
                        if idx < pagedRows.count - 1 {
                            Divider()
                                .background(Theme.slate300.opacity(0.4))
                                .padding(.leading, 52)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: Theme.radiusMedium))
                PageBar(page: $txPage, pageCount: pageCount)
                if txHistory.isLoadingMore {
                    ProgressView().scaleEffect(0.7).tint(Theme.accent).padding(.top, 2)
                }
            }
        }
        .onChange(of: txTab) { txPage = 0 }
        .onChange(of: txRows.count) { if txPage >= pageCount { txPage = max(0, pageCount - 1) } }
        .onChange(of: txPage) { loadMoreIfNeeded() }
    }

    /// Reaching the last page pulls the next chain page so paging goes past the
    /// initial 20 signatures.
    private func loadMoreIfNeeded() {
        guard let publicKey, txPage >= pageCount - 1,
              txHistory.canLoadMore, !txHistory.isLoadingMore else { return }
        Task { await txHistory.loadMore(publicKey: publicKey, rpc: rpc, price: price) }
    }


    // MARK: - Receive sheet

    private var receiveSheet: some View {
        NavigationStack {
            ZStack {
                PastelBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // QR code card
                        VStack(spacing: 16) {
                            if let pk = publicKey {
                                QRCodeView(text: pk, size: 220)
                                    .padding(16)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                    .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                            }

                            Text("Solana Address")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.slate400)

                            if let pk = publicKey {
                                Text(pk)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(Theme.slate700)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge)
                            .stroke(Theme.glassStroke, lineWidth: 1))

                        // Action buttons
                        VStack(spacing: 12) {
                            Button {
                                #if os(iOS)
                                if let pk = publicKey {
                                    UIPasteboard.general.string = pk
                                    flashCopied()
                                }
                                #endif
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: addressCopied ? "checkmark" : "doc.on.doc")
                                    Text(addressCopied ? LocalizedStringKey("Скопировано") : LocalizedStringKey("Скопировать адрес"))
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.accentGradient)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            if let pk = publicKey {
                                ShareLink(item: pk) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Поделиться")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    .foregroundStyle(Theme.accentDeep)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Theme.glass)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Получить SOL")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { showReceive = false }
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            #endif
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func flashCopied() {
        withAnimation { addressCopied = true }
        Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { addressCopied = false } }
    }

    private func refresh() async {
        guard let publicKey else { return }
        async let bal: () = balance.refresh(publicKey: publicKey, rpc: rpc)
        async let hist: () = txHistory.refresh(publicKey: publicKey, rpc: rpc, price: price,
                                               gasAddress: gasWallet.address)
        async let p: () = price.refresh()
        _ = await (bal, hist, p)
    }
}

#if os(iOS)
import UIKit
#endif

#Preview {
    WalletTabView()
        .environment(WalletManager())
        .environment(WalletBalanceService())
        .environment(TransactionHistoryService())
        .environment(SolanaRPCService())
        .environment(SOLPriceService())
        .environment(BiometryService())
        .environment(PasscodeManager())
}
