//
//  PasscodeEnterView.swift
//  privamesh
//

import SwiftUI
import Combine
import SwiftData

struct PasscodeEnterView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PasscodeManager.self) private var passcode
    @Environment(WalletManager.self) private var wallet
    @Environment(BiometryService.self) private var biometry
    @Environment(\.modelContext) private var modelContext

    @State private var errorMessage: String?
    @State private var attempts: Int = 0
    @State private var didAutoPrompt = false
    /// Counted down while a brute-force cooldown is running, so the screen can
    /// say how long the wait is instead of just refusing taps.
    @State private var lockoutSeconds: Int = 0

    /// Fires only while a cooldown is on screen.
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                PasscodeKeypadView(
                    title: "PrivaMesh",
                    subtitle: "Введи пароль",
                    errorMessage: errorMessage,
                    length: passcode.passcodeLength,
                    lockoutSeconds: lockoutSeconds
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

                    if attempts >= 3 && lockoutSeconds == 0 {
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
            refreshLockout()
            // Biometry during a cooldown would hand back the shortcut the wait
            // exists to remove.
            if biometry.isAvailable && biometry.isEnabled && !didAutoPrompt && lockoutSeconds == 0 {
                didAutoPrompt = true
                Task { await tryBiometry() }
            }
        }
        .onReceive(ticker) { _ in refreshLockout() }
    }

    private func attempt(_ code: String) {
        switch passcode.check(code) {
        case .correct:
            errorMessage = nil
            router.go(to: .main)

        // The duress code. No warning, no confirmation, nothing on screen
        // afterwards: what is left has to look like a fresh install, because
        // someone is watching this screen.
        case .duress:
            AccountDestroyer.destroy(context: modelContext,
                                     wallet: wallet,
                                     passcode: passcode,
                                     biometry: biometry)
            errorMessage = nil
            attempts = 0
            router.go(to: .welcome)

        case .incorrect:
            attempts += 1
            errorMessage = "Неверный пароль"
            refreshLockout()

        case .lockedOut:
            refreshLockout()

        case .unavailable:
            // Not a wrong passcode: the Keychain could not answer, so nothing is
            // counted and nothing is locked.
            errorMessage = "Не удалось проверить пароль. Попробуй ещё раз."

        case .notSet:
            router.go(to: .main)
        }
    }

    private func refreshLockout() {
        lockoutSeconds = Int(ceil(passcode.lockoutRemaining))
        if lockoutSeconds > 0 { errorMessage = nil }
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

    /// "Forgot the passcode" - the same erase, but asked for out loud.
    ///
    /// It is the same destruction the duress code performs, because there is no
    /// way to recover an account without its phrase, and pretending otherwise
    /// would mean keeping a back door that works for anyone holding the phone.
    private func resetWallet() {
        AccountDestroyer.destroy(context: modelContext,
                                 wallet: wallet,
                                 passcode: passcode,
                                 biometry: biometry)
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
