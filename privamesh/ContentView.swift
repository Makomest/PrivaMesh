//
//  ContentView.swift
//  privamesh
//

import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet
    @Environment(PasscodeManager.self) private var passcode
    @Environment(BiometryService.self) private var biometry
    @Environment(ToastManager.self) private var toast

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                switch router.route {
                case .onboarding:
                    OnboardingExplainerView()
                        .transition(.opacity)
                case .welcome:
                    WelcomeView()
                        .transition(.opacity)
                case .createWallet:
                    CreateWalletView()
                        .transition(.move(edge: .trailing))
                case .seedPhraseDisplay:
                    SeedPhraseDisplayView()
                        .transition(.move(edge: .trailing))
                case .seedPhraseConfirm:
                    SeedPhraseConfirmView()
                        .transition(.move(edge: .trailing))
                case .importWallet:
                    ImportWalletView()
                        .transition(.move(edge: .trailing))
                case .passcodeSetup:
                    PasscodeSetupView()
                        .transition(.move(edge: .trailing))
                case .biometryPrompt:
                    BiometryPromptView()
                        .transition(.move(edge: .trailing))
                case .passcodeEnter:
                    PasscodeEnterView()
                        .transition(.opacity)
                case .main:
                    MainTabView()
                        .transition(.opacity)
                }
            }
            .animation(.default, value: router.route)

            if shouldShowPrivacyCover {
                PrivacyCoverView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Global copy toast
            VStack {
                Spacer()
                if toast.isVisible {
                    ToastView(message: toast.message)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(3)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: toast.isVisible)
        }
        .animation(.easeInOut(duration: 0.15), value: shouldShowPrivacyCover)
        .onAppear {
            purgeStaleSecretsOnFreshInstall()
            decideInitialRoute()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhase(old: oldPhase, new: newPhase)
        }
    }

    private var shouldShowPrivacyCover: Bool {
        // Hide content when app is in app switcher or backgrounded.
        // Only if a wallet exists (no point covering onboarding).
        guard case .ready = wallet.state else { return false }
        // The system passkey/biometric prompt makes the scene inactive — don't
        // treat that as backgrounding (otherwise the app "closes" mid-payment).
        if biometry.recentlyAuthenticated { return false }
        return scenePhase != .active
    }

    private static let onboardingDoneKey = "privamesh.onboardingDone"
    private static let installMarkerKey = "privamesh.installMarker"

    /// iOS Keychain items SURVIVE app deletion, but UserDefaults and the app
    /// container do not. After a delete + reinstall the stale seed + passcode are
    /// still in the Keychain, so `WalletManager.init` reads them and the app
    /// jumps straight to the passcode lock instead of onboarding. Detect a fresh
    /// install via a UserDefaults marker (wiped on uninstall) and purge the
    /// orphaned secrets so a reinstall starts clean at onboarding.
    private func purgeStaleSecretsOnFreshInstall() {
        guard !UserDefaults.standard.bool(forKey: Self.installMarkerKey) else { return }
        wallet.wipe()          // clears seed/publicKey in Keychain + resets state
        passcode.wipe()        // clears passcode hash/salt in Keychain
        UserDefaults.standard.set(true, forKey: Self.installMarkerKey)
    }

    private func decideInitialRoute() {
        guard router.route == .welcome else { return }

        switch (wallet.state, passcode.isPasscodeSet) {
        case (.ready, true) where !passcode.isUnlocked:
            router.go(to: .passcodeEnter)
        case (.ready, true):
            router.go(to: .main)
        case (.ready, false):
            router.go(to: .passcodeSetup)
        default:
            // No wallet yet — show onboarding on very first launch
            if !UserDefaults.standard.bool(forKey: Self.onboardingDoneKey) {
                router.go(to: .onboarding)
            }
        }
    }

    private func handleScenePhase(old: ScenePhase, new: ScenePhase) {
        // Ignore scene changes caused by an in-app passkey/biometric prompt
        // (and the brief grace window after it).
        if biometry.recentlyAuthenticated { return }
        switch new {
        case .background:
            passcode.noteBackgrounded()
        case .active:
            // Self-heal a transient Keychain read failure at launch: if the app
            // came up with no wallet (e.g. pre-warmed while the device was locked)
            // but one is actually stored, reload + re-route instead of waiting for
            // a manual relaunch.
            if case .noWallet = wallet.state {
                wallet.reloadFromKeychain()
                decideInitialRoute()
            }
            if passcode.shouldRelockOnForeground() {
                passcode.lock()
                router.go(to: .passcodeEnter)
            }
        default:
            break
        }
    }
}

extension AppRouter.Route: Equatable {}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(WalletManager())
        .environment(PasscodeManager())
        .environment(BiometryService())
}
