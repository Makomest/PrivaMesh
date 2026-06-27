//
//  SendSOLView.swift
//  privamesh
//

import SwiftUI
import SolanaSwift

struct SendSOLView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WalletManager.self) private var wallet
    @Environment(SolanaRPCService.self) private var rpc
    @Environment(WalletBalanceService.self) private var balance
    @Environment(BiometryService.self) private var biometry
    @Environment(PasscodeManager.self) private var passcode

    @State private var recipient: String = ""
    @State private var amountText: String = ""
    @State private var service = SendSOLService()
    @State private var passcodeSheet = false
    @State private var passcodeError: String?

    private var amountDecimal: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    private var amountValid: Bool {
        guard let amount = amountDecimal else { return false }
        return amount > 0
    }

    private var recipientValid: Bool {
        guard !recipient.isEmpty else { return false }
        return (try? PublicKey(string: recipient)) != nil
    }

    private var hasEnoughBalance: Bool {
        guard let sol = balance.balanceSOL, let amount = amountDecimal else { return false }
        return sol >= amount + rpc.liveFeeSOL
    }

    private var canSend: Bool {
        amountValid && recipientValid && hasEnoughBalance
    }

    var body: some View {
        ZStack {
            PastelBackground()
            Group {
                switch service.state {
                case .idle, .sending:
                    form
                case .success(let signature):
                    successView(signature: signature)
                case .failure(let message):
                    failureView(message: message)
                }
            }
        }
        .navigationTitle("Отправить SOL")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $passcodeSheet) {
            passcodeConfirmSheet
        }
        .task {
            await rpc.refreshNetworkFee()
            if let keypair = try? await wallet.currentKeyPair() {
                await rpc.refreshFee(senderKeyPair: keypair)
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Recipient
                card {
                    sectionLabel("Получатель")
                    TextField("Solana адрес", text: $recipient, axis: .vertical)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Theme.slate800)
                        .autocorrectionDisabled()
                        .lineLimit(2...3)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    #if os(iOS)
                    Button {
                        if let pasted = UIPasteboard.general.string {
                            recipient = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentDeep)
                    }
                    .buttonStyle(.plain)
                    #endif
                    if !recipient.isEmpty && !recipientValid {
                        warn("Невалидный адрес")
                    }
                }

                // Amount
                card {
                    sectionLabel("Сумма")
                    HStack {
                        TextField("0.0", text: $amountText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                        Text("SOL").font(.system(size: 15)).foregroundStyle(Theme.slate500)
                    }
                    if let sol = balance.balanceSOL {
                        HStack {
                            Text("Баланс: \(formatSOL(sol)) SOL")
                                .font(.system(size: 12)).foregroundStyle(Theme.slate500)
                            Spacer()
                            Button("MAX") { setMaxAmount() }
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accentDeep)
                                .buttonStyle(.plain)
                        }
                    }
                    if amountValid && !hasEnoughBalance {
                        warn("Недостаточно баланса с учётом комиссии")
                    }
                }

                // Fee
                card {
                    HStack {
                        Label("Комиссия сети", systemImage: "fuelpump.fill")
                            .font(.system(size: 13)).foregroundStyle(Theme.slate600)
                        Spacer()
                        Text("~\(formatSOL(rpc.liveFeeSOL)) SOL")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.slate700)
                    }
                }

                // Send — slide to confirm
                if canSend {
                    SlideToConfirm(text: isSending ? "Отправляем…" : "Сдвинь, чтобы отправить") {
                        authThenSend()
                    }
                    .disabled(isSending)
                    .padding(.top, 4)
                } else {
                    Text("Заполни адрес и сумму")
                        .font(.system(size: 13)).foregroundStyle(Theme.slate400)
                        .frame(height: 54).padding(.top, 4)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Style helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.glass)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge).stroke(Theme.glassStroke, lineWidth: 1))
    }
    private func sectionLabel(_ t: String) -> some View {
        Text(LocalizedStringKey(t)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.slate500)
    }
    private func warn(_ t: String) -> some View {
        Label(LocalizedStringKey(t), systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12)).foregroundStyle(Theme.negative)
    }

    private func successView(signature: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84)).foregroundStyle(Theme.positive)
            Text("Транзакция отправлена")
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)

            VStack(spacing: 6) {
                Text("Signature").font(.system(size: 12)).foregroundStyle(Theme.slate400)
                Text(signature)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.slate600)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 24)
            }

            Link(destination: solscanURL(signature: signature)) {
                Label("Открыть в Solscan", systemImage: "arrow.up.right.square")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.glass).clipShape(Capsule())
            }

            Button { dismiss() } label: {
                Text("Готово").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.accentGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.horizontal, 24)
        }
        .padding(24)
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 72)).foregroundStyle(Theme.negative)
            Text("Не удалось отправить")
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
            Text(LocalizedStringKey(message))
                .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
            Button { service.reset() } label: {
                Text("Попробовать снова").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Theme.accentGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.horizontal, 24)
        }
        .padding(24)
    }

    private var passcodeConfirmSheet: some View {
        NavigationStack {
            PasscodeKeypadView(
                title: "Подтверди отправку",
                subtitle: "Введи пароль чтобы подписать транзакцию",
                errorMessage: passcodeError
            ) { code in
                if passcode.verify(code) {
                    passcodeError = nil
                    passcodeSheet = false
                    Task { await performSend() }
                } else {
                    passcodeError = "Неверный пароль"
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        passcodeSheet = false
                    }
                }
            }
        }
    }

    private var isSending: Bool {
        if case .sending = service.state { return true }
        return false
    }

    private func authThenSend() {
        if biometry.isAvailable && biometry.isEnabled {
            Task {
                let ok = await biometry.authenticate(reason: "Подтверди отправку SOL")
                if ok {
                    await performSend()
                }
            }
        } else {
            passcodeSheet = true
        }
    }

    private func performSend() async {
        guard let amount = amountDecimal else { return }
        do {
            let keypair = try await wallet.currentKeyPair()
            await service.send(
                from: keypair,
                to: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                amountSOL: amount,
                rpc: rpc
            )
            // Refresh balance after successful send
            if case .success = service.state, case let .ready(pk) = wallet.state {
                await balance.refresh(publicKey: pk, rpc: rpc)
            }
        } catch {
            await MainActor.run {
                service.state = .failure(message: "Ошибка ключа: \(error.localizedDescription)")
            }
        }
    }

    private func setMaxAmount() {
        guard let sol = balance.balanceSOL else { return }
        let max = sol - rpc.estimatedFeeSOL
        if max > 0 {
            amountText = formatSOL(max)
        }
    }

    private func formatSOL(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 9
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "0"
    }

    private func solscanURL(signature: String) -> URL {
        URL(string: "https://solscan.io/tx/\(signature)")!
    }
}

#if os(iOS)
import UIKit
#endif

#Preview {
    NavigationStack {
        SendSOLView()
            .environment(WalletManager())
            .environment(SolanaRPCService())
            .environment(WalletBalanceService())
            .environment(BiometryService())
            .environment(PasscodeManager())
    }
}
