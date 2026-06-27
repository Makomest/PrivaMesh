//
//  PasscodeEnterView.swift
//  privamesh
//

import SwiftUI

struct PasscodeEnterView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PasscodeManager.self) private var passcode
    @Environment(WalletManager.self) private var wallet
    @Environment(BiometryService.self) private var biometry

    @State private var errorMessage: String?
    @State private var attempts: Int = 0
    @State private var didAutoPrompt = false

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                PasscodeKeypadView(
                    title: "PrivaMesh",
                    subtitle: "Введи пароль",
                    errorMessage: errorMessage,
                    length: passcode.passcodeLength
                ) { code in
                    attempt(code)
                }

                HStack(spacing: 24) {
                    if biometry.isAvailable && biometry.isEnabled {
                        Button {
                            Task { await tryBiometry() }
                        } label: {
                            Label(biometry.kind.label, systemImage: biometry.kind.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.accentDeep)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.glass)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    if attempts >= 3 {
                        Button {
                            resetWallet()
                        } label: {
                            Text("Забыл пароль? Сбросить")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.negative)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.negative.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            if biometry.isAvailable && biometry.isEnabled && !didAutoPrompt {
                didAutoPrompt = true
                Task { await tryBiometry() }
            }
        }
    }

    private func attempt(_ code: String) {
        if passcode.verify(code) {
            errorMessage = nil
            router.go(to: .main)
        } else {
            attempts += 1
            errorMessage = "Неверный пароль"
        }
    }

    private func tryBiometry() async {
        let success = await biometry.authenticate()
        if success {
            await MainActor.run {
                passcode.markUnlockedByBiometry()
                router.go(to: .main)
            }
        }
    }

    private func resetWallet() {
        wallet.wipe()
        passcode.wipe()
        biometry.disable()
        router.go(to: .welcome)
    }
}

#Preview {
    PasscodeEnterView()
        .environment(AppRouter())
        .environment(PasscodeManager())
        .environment(WalletManager())
        .environment(BiometryService())
}
