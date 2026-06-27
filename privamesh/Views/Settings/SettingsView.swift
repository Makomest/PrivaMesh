//
//  SettingsView.swift
//  privamesh
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet
    @Environment(PasscodeManager.self) private var passcode
    @Environment(BiometryService.self) private var biometry
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(AccountManager.self) private var accountManager
    @Environment(ToastManager.self) private var toast
    @Environment(MessagingIdentityManager.self) private var identity
    @Environment(\.modelContext) private var context

    @State private var biometryEnabled: Bool = false
    @State private var showingResetAlert = false
    @State private var showSubscriptions = false
    @State private var showAccountSwitcher = false

    private var publicKey: String? {
        if case let .ready(key) = wallet.state { return key }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                walletSection
                accountsSection
                premiumSection
                securitySection
                dangerSection
                legalSection
            }
            .sheet(isPresented: $showSubscriptions) {
                SubscriptionsView().environment(subscription)
            }
            .sheet(isPresented: $showAccountSwitcher) {
                AccountSwitcherView()
                    .environment(wallet)
                    .environment(accountManager)
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onAppear {
                biometryEnabled = biometry.isEnabled
            }
            .alert("Сбросить кошелёк?", isPresented: $showingResetAlert) {
                Button("Отмена", role: .cancel) {}
                Button("Сбросить", role: .destructive) {
                    resetWallet()
                }
            } message: {
                Text("Кошелёк и пароль удалятся с этого устройства. Восстановить можно только seed phrase. Без неё — потерян навсегда.")
            }
        }
    }

    private var walletSection: some View {
        Section("Кошелёк") {
            if let publicKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Адрес")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(publicKey)
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            copyToClipboard(publicKey)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var accountsSection: some View {
        Section("Accounts") {
            Button {
                showAccountSwitcher = true
            } label: {
                HStack {
                    Label("Manage Accounts", systemImage: "person.2.fill")
                    Spacer()
                    if let active = accountManager.activeAccount {
                        Text(active.shortKey)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(Theme.slate800)
        }
    }

    private var premiumSection: some View {
        Section("Premium") {
            Button {
                showSubscriptions = true
            } label: {
                HStack {
                    Label("PrivaMesh+", systemImage: "sparkles")
                    Spacer()
                    Text(subscription.isSubscribed ? "Active" : "Upgrade")
                        .font(.system(size: 12))
                        .foregroundStyle(subscription.isSubscribed ? Theme.positive : Theme.accentDeep)
                }
            }
            .foregroundStyle(Theme.slate800)
        }
    }

    private var securitySection: some View {
        Section("Безопасность") {
            NavigationLink {
                SeedPhraseRevealView()
            } label: {
                Label("Показать seed phrase", systemImage: "key.fill")
            }

            NavigationLink {
                ChangePasscodeView()
            } label: {
                Label("Сменить пароль", systemImage: "lock.rotation")
            }

            if biometry.isAvailable {
                Toggle(isOn: $biometryEnabled) {
                    Label(biometry.kind.label, systemImage: biometry.kind.systemImage)
                }
                .onChange(of: biometryEnabled) { _, newValue in
                    if newValue {
                        Task {
                            let ok = await biometry.authenticate(reason: "Включить \(biometry.kind.label)")
                            await MainActor.run {
                                biometry.isEnabled = ok
                                biometryEnabled = ok
                            }
                        }
                    } else {
                        biometry.disable()
                    }
                }
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                Label("Сбросить кошелёк", systemImage: "trash")
            }
        } header: {
            Text("Опасная зона")
        } footer: {
            Text("Перед сбросом убедись что записал seed phrase.")
        }
    }

    private var legalSection: some View {
        Section("Прочее") {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "hand.raised.fill")
            }
            HStack {
                Label("Version", systemImage: "info.circle")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyToClipboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        toast.show("Скопировано")
        #endif
    }

    private func resetWallet() {
        // Full wipe — leave no seeds, keys, or chats behind.
        let addrs = accountManager.accounts.map(\.publicKeyBase58)
        accountManager.removeAll()
        identity.wipeAll(addresses: addrs)
        try? context.delete(model: Contact.self)      // cascade → messages
        try? context.delete(model: ChatMessage.self)
        wallet.wipe()
        passcode.wipe()
        biometry.disable()
        dismiss()
        router.go(to: .welcome)
    }
}

#if os(iOS)
import UIKit
#endif

#Preview {
    SettingsView()
        .environment(AppRouter())
        .environment(WalletManager())
        .environment(PasscodeManager())
        .environment(BiometryService())
}
