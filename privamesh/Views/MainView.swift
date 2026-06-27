//
//  MainView.swift
//  privamesh
//

import SwiftUI
import SolanaSwift

struct MainView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(AppRouter.self) private var router
    @Environment(PasscodeManager.self) private var passcode
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(WalletBalanceService.self) private var balance
    @Environment(ToastManager.self) private var toast

    @State private var showingSettings = false

    private var publicKey: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    private var balanceText: String {
        guard let sol = balance.balanceSOL else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        return formatter.string(from: sol as NSDecimalNumber) ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    balanceCard
                    actionButtons
                    addressCard
                    statusFooter
                }
                .padding()
            }
            .navigationTitle("PrivaMesh")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .refreshable {
                await refresh()
            }
            .task {
                await refresh()
            }
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text("Баланс")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if case .loading = balance.state {
                    ProgressView()
                }
                Text(balanceText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("SOL")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if case let .error(message) = balance.state {
                Text(LocalizedStringKey(message))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else if let last = balance.lastUpdated {
                Text("обновлено \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await refresh() }
            } label: {
                Label("Обновить", systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            NavigationLink {
                SendSOLView()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                    Text("Отправить")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                    Text("Получить")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var addressCard: some View {
        if let publicKey {
            VStack(alignment: .leading, spacing: 8) {
                Text("Твой адрес")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(publicKey)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button {
                        copyAddress(publicKey)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var statusFooter: some View {
        VStack(spacing: 4) {
            Text("RPC: \(rpc.currentEndpoint.address)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Дальше: чаты + отправка SOL")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func copyAddress(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        toast.show("Адрес скопирован")
        #endif
    }

    private func refresh() async {
        guard let publicKey else { return }
        await balance.refresh(publicKey: publicKey, rpc: rpc)
    }
}

#if os(iOS)
import UIKit
#endif

#Preview {
    MainView()
        .environment(WalletManager())
        .environment(AppRouter())
        .environment(PasscodeManager())
        .environment(BiometryService())
        .environment(SolanaRPCService())
        .environment(WalletBalanceService())
}
