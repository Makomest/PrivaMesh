//
//  GasWalletView.swift
//  privamesh
//
//  Manage the optional gas (fee) wallet that pays + signs message transactions
//  so the main wallet never appears on-chain for messages.
//

import SwiftUI
import SolanaSwift
#if os(iOS)
import UIKit
#endif

struct GasWalletView: View {
    @Environment(GasWalletService.self) private var gasWallet
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(ToastManager.self) private var toast

    @State private var enabled = false
    @State private var balanceSOL: Double?
    @State private var addressCopied = false
    @State private var showSeed = false
    @State private var showImport = false
    @State private var showRemoveAlert = false
    @State private var importText = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            PastelBackground()
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if gasWallet.exists {
                        addressCard
                        toggleCard
                        manageCard
                    } else {
                        createCard
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Газ-кошелёк")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { enabled = gasWallet.isEnabled }
        .task { await loadBalance() }
        .sheet(isPresented: $showSeed) { seedSheet }
        .sheet(isPresented: $showImport) { importSheet }
        .alert("Удалить газ-кошелёк?", isPresented: $showRemoveAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                gasWallet.remove()
                toast.show("Газ-кошелёк удалён. Выведи остаток заранее.")
            }
        } message: {
            Text("Seed удалится с устройства. Сначала выведи остаток SOL — иначе он потеряется.")
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.accentGradient).frame(width: 64, height: 64)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 4)
                Image(systemName: "fuelpump.fill").font(.system(size: 26)).foregroundStyle(.white)
            }
            Text("Газ-кошелёк для комиссий")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
            Text("Комиссии сообщений платит этот кошелёк — твой основной адрес не появляется в блокчейне для переписки. Пополняй его из НЕсвязанного источника (биржа, другой кошелёк), иначе связь восстановится on-chain.")
                .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center)
        }
        .padding(20).frame(maxWidth: .infinity)
        .glassCard()
    }

    private var createCard: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    busy = true
                    _ = try? await gasWallet.create()
                    enabled = gasWallet.isEnabled
                    busy = false
                    await loadBalance()
                    toast.show("Газ-кошелёк создан")
                }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    else { Image(systemName: "plus.circle.fill") }
                    Text("Создать газ-кошелёк").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.accentGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(busy)

            Button { showImport = true } label: {
                Label("Импортировать по seed", systemImage: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.glass).clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("Отдельный одноразовый кошелёк только для оплаты комиссий.")
                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                .multilineTextAlignment(.center).padding(.top, 2)
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Адрес для пополнения").font(.system(size: 12)).foregroundStyle(Theme.slate500)
            if let addr = gasWallet.address {
                Text(addr).font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.slate700).textSelection(.enabled).lineLimit(2)
                HStack {
                    Text(balanceLabel).font(.system(size: 12)).foregroundStyle(Theme.slate500)
                    Spacer()
                    Button { copy(addr) } label: {
                        Label(addressCopied ? LocalizedStringKey("Скопировано") : LocalizedStringKey("Скопировать адрес"),
                              systemImage: addressCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(addressCopied ? Theme.positive : Theme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $enabled) {
                Label("Платить комиссии этим кошельком", systemImage: "fuelpump.fill")
                    .font(.system(size: 15)).foregroundStyle(Theme.slate800)
            }
            .tint(Theme.accent)
            .onChange(of: enabled) { _, v in gasWallet.isEnabled = v }
            Text(enabled
                 ? "Сообщения подписываются газ-кошельком. Держи на нём немного SOL."
                 : "Сейчас комиссии платит основной кошелёк.")
                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
        }
        .padding(16).glassCard()
    }

    private var manageCard: some View {
        VStack(spacing: 0) {
            Button { showSeed = true } label: {
                row(icon: "key.fill", title: "Показать seed газ-кошелька", tint: Theme.accentDeep)
            }.buttonStyle(.plain)
            Divider().padding(.leading, 52).background(Theme.glassStroke)
            Button { showRemoveAlert = true } label: {
                row(icon: "trash", title: "Удалить газ-кошелёк", tint: Theme.negative)
            }.buttonStyle(.plain)
        }
        .glassCard()
    }

    private func row(icon: String, title: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint).frame(width: 24)
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.slate800)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.slate400)
        }
        .padding(16).contentShape(Rectangle())
    }

    // MARK: - Sheets

    @ViewBuilder private var seedSheet: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    let words = gasWallet.revealSeed()
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                            Text("\(i + 1). \(w)").font(.system(.body, design: .monospaced))
                                .foregroundStyle(Theme.slate800)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20).glassCard().padding(20)
                }
            }
            .navigationTitle("Seed газ-кошелька")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showSeed = false } } }
        }
    }

    @ViewBuilder private var importSheet: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        TextField("слова через пробел", text: $importText, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .lineLimit(3, reservesSpace: true)
                            .padding(14).glassCard()
                        Button {
                            let words = importText.split(whereSeparator: { $0 == " " || $0.isNewline }).map(String.init)
                            guard words.count == 12 || words.count == 24 else { toast.show("Нужно 12 или 24 слова"); return }
                            Task {
                                do {
                                    try await gasWallet.importSeed(words)
                                    enabled = gasWallet.isEnabled
                                    importText = ""; showImport = false
                                    await loadBalance()
                                    toast.show("Газ-кошелёк импортирован")
                                } catch { toast.show("Не удалось импортировать seed") }
                            }
                        } label: {
                            Text("Импортировать").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(Theme.accentGradient).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Импорт газ-кошелька")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { showImport = false } } }
        }
    }

    // MARK: - Helpers

    private var balanceLabel: String {
        guard let b = balanceSOL else { return String(localized: "Баланс: …") }
        return String(localized: "Баланс: \(String(format: "%.4f", b)) SOL")
    }

    private func loadBalance() async {
        guard let addr = gasWallet.address else { return }
        if let lamports = try? await rpc.client.getBalance(account: addr, commitment: "confirmed") {
            await MainActor.run { balanceSOL = Double(lamports) / 1_000_000_000 }
        }
    }

    private func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #endif
        withAnimation { addressCopied = true }
        Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { addressCopied = false } }
    }
}

private extension View {
    /// App glass card chrome.
    func glassCard() -> some View {
        self.background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }
}
