//
//  MintNicknameSheet.swift
//  privamesh
//
//  Mint a custom NFT nickname (PrivaMesh+ feature). The marketplace was removed
//  before the App Store release, so nicknames can be minted for yourself but no
//  longer bought or sold. Minting creates a real on-chain SPL NFT (supply 1) and
//  costs only the Solana network fee.
//

import SwiftUI
import SolanaSwift

struct MintNicknameSheet: View {
    @Environment(MarketService.self) private var market
    @Environment(WalletManager.self) private var wallet
    @Environment(RelayService.self) private var relay
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(BiometryService.self) private var biometry
    @Environment(SOLPriceService.self) private var price
    @Environment(ToastManager.self) private var toast
    @Environment(\.dismiss) private var dismiss

    @State private var handle = ""
    @State private var minting = false
    @State private var feeLamports: UInt64?
    @State private var showPasscodeConfirm = false

    private var trimmed: String { handle.trimmingCharacters(in: .whitespaces) }
    private var available: Bool { market.isNicknameAvailable(trimmed) }
    /// Already minted the per-account maximum (3) — no more allowed.
    private var limitReached: Bool { !market.canMint() }
    private var canMint: Bool {
        available && market.canMint() && !minting
    }

    private var feeSOL: Double? { feeLamports.map { Double($0) / 1_000_000_000 } }
    private var feeUSD: Double? {
        guard let sol = feeSOL, let p = price.priceUSD else { return nil }
        return sol * p
    }
    private var feeText: String {
        guard let sol = feeSOL else { return String(localized: "вычисляю…") }
        let usd = feeUSD.map { String(format: " ≈ $%.4f", $0) } ?? ""
        return String(format: "%.6f SOL%@", sol, usd)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 18) {
                    Image(systemName: "sparkles").font(.system(size: 40))
                        .foregroundStyle(Theme.accentGradient).padding(.top, 24)
                    Text("Создать NFT-ник")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                    Text("Минт создаёт NFT в сети Solana — комиссия оплачивается приложением. Ник станет твоим.\nЗаминчено: \(market.mintedNicknames.count)/\(MarketService.maxMints)")
                        .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    HStack {
                        Text("@").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.slate400)
                        TextField("Твой ник", text: $handle)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Theme.glass).clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                    .padding(.horizontal, 24)

                    if !trimmed.isEmpty {
                        Label(available ? "@\(trimmed) свободен" : "@\(trimmed) уже занят",
                              systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(available ? Theme.positive : Theme.negative)
                    }

                    // Real network fee for the mint tx.
                    HStack(spacing: 6) {
                        Image(systemName: "fuelpump.fill").font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        Text("Комиссия сети: \(feeText)")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate600)
                    }

                    if canMint {
                        SlideToConfirm(text: minting ? "Минт…" : "Сдвинь, чтобы заминтить") {
                            Task { await mint() }
                        }
                        .padding(.horizontal, 24).padding(.top, 4)
                    } else if limitReached {
                        Label("Лимит достигнут: можно создать максимум \(MarketService.maxMints) NFT-ника",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24).frame(minHeight: 54)
                    } else {
                        Text(LocalizedStringKey(available ? "" : "Ник недоступен"))
                            .font(.system(size: 13)).foregroundStyle(Theme.slate400)
                            .frame(height: 54)
                    }
                    Spacer()
                }
            }
            .navigationTitle("NFT-ник")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            .task(id: trimmed) { await refreshFee() }
            .task { await price.refresh() }
        }
        .sheet(isPresented: $showPasscodeConfirm) {
            PasscodeConfirmSheet(reason: String(localized: "Подтвердить минт ника @\(trimmed)")) {
                Task { await performMint() }
            }
        }
    }

    private func refreshFee() async {
        guard trimmed.count >= 2, let keypair = try? await wallet.currentKeyPair() else { return }
        feeLamports = await MemoTransactionBuilder.estimateMintFee(
            from: keypair, handle: trimmed, endpointURL: rpc.currentEndpoint.address)
    }

    private func mint() async {
        // Guard the action itself, not just the button. Capped at maxMints.
        guard market.canMint() else {
            toast.show(String(localized: "Достигнут лимит NFT-ников (\(MarketService.maxMints))")); return
        }
        // Confirm with biometrics; if unavailable/declined, fall back to the app
        // passcode so the mint can be authorized without Face ID.
        if await biometry.confirm(reason: String(localized: "Подтвердить минт ника @\(trimmed)")) {
            await performMint()
        } else {
            showPasscodeConfirm = true
        }
    }

    private func performMint() async {
        guard market.canMint() else { return }
        guard let keypair = try? await wallet.currentKeyPair() else { return }
        minting = true
        defer { minting = false }
        do {
            // Mint a real on-chain SPL NFT (supply 1) — ownership is seed-portable.
            // Sponsored via the relay (treasury pays fee + rent) when configured,
            // so the subscriber spends no crypto.
            if relay.isConfigured {
                _ = try await relay.sponsorMint(designId: "nick:\(trimmed)", keypair: keypair, rpc: rpc)
            } else {
                _ = try await OnChainNFT.mint(designId: "nick:\(trimmed)", keypair: keypair, rpc: rpc)
            }
            market.mintNickname(trimmed)
            toast.show(String(localized: "Ник заминчен: \(trimmed)"))
            dismiss()
        } catch {
            toast.show(String(localized: "Ошибка минта: \(error.localizedDescription)"))
        }
    }
}
