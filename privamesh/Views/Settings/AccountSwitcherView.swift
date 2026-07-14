//
//  AccountSwitcherView.swift
//  privamesh
//
//  Switch between independent accounts (each its own seed/balance/nick/chats),
//  create a new one, or import an existing one by фразу восстановления.
//

import SwiftUI

struct AccountSwitcherView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(AccountManager.self) private var accountManager
    @Environment(SubscriptionManager.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showImport = false

    /// Free accounts get a single wallet; PrivaMesh+ unlocks up to maxAccounts.
    private var accountCap: Int { subscription.isSubscribed ? AccountManager.maxAccounts : 1 }
    private var canAddMore: Bool { accountManager.accounts.count < accountCap }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                List {
                    Section {
                        ForEach(accountManager.accounts) { account in
                            accountRow(account)
                        }
                    } footer: {
                        Text("Каждый аккаунт — отдельный баланс, ник и чаты.")
                            .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                    }

                    if canAddMore {
                        Section {
                            Button { Task { await createNew() } } label: {
                                row(icon: "plus.circle.fill", "Создать новый аккаунт")
                            }.disabled(busy)
                            Button { showImport = true } label: {
                                row(icon: "square.and.arrow.down.fill", "Подключить по фразе восстановления")
                            }.disabled(busy)
                        } footer: {
                            Text("До \(AccountManager.maxAccounts) аккаунтов на устройстве. Каждый — отдельный баланс, ник и чаты.")
                                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        }
                    } else if !subscription.isSubscribed {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.fill").foregroundStyle(Theme.accentDeep)
                                Text("Несколько аккаунтов — в PrivaMesh+")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.slate600)
                            }
                        } footer: {
                            Text("PrivaMesh+ открывает до \(AccountManager.maxAccounts) аккаунтов на устройстве.")
                                .font(.system(size: 11)).foregroundStyle(Theme.slate400)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                if busy { ProgressView().tint(Theme.accent) }
            }
            .navigationTitle("Аккаунты")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("Готово") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
            #endif
            .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $showImport) {
                ImportAccountSheet { phrase in Task { await importExisting(phrase) } }
            }
        }
    }

    private func accountRow(_ account: WalletAccount) -> some View {
        HStack {
            MeshAvatarView(id: account.id, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.slate800)
                Text(account.shortKey).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.slate500)
            }
            Spacer()
            if account.id == accountManager.activePublicKey {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { activate(account) }
    }

    private func row(icon: String, _ title: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.accentDeep)
            Text(LocalizedStringKey(title)).foregroundStyle(Theme.accentDeep)
        }
    }

    // MARK: - Actions

    private func activate(_ account: WalletAccount) {
        guard account.id != accountManager.activePublicKey else { dismiss(); return }
        guard let seed = accountManager.seedPhrase(for: account.id) else {
            errorMessage = "Фраза восстановления не найдена"; return
        }
        wallet.activate(account: account, seedPhrase: seed)
        accountManager.setActive(account.id)
        dismiss()
    }

    private func createNew() async {
        guard gateNewAccount() else { return }
        busy = true; defer { busy = false }
        do {
            let result = try await accountManager.createAccount()
            activate(result.account)
        } catch { errorMessage = error.localizedDescription }
    }

    private func importExisting(_ phrase: [String]) async {
        guard gateNewAccount() else { return }
        busy = true; defer { busy = false }
        do {
            let account = try await accountManager.importAccount(phrase: phrase)
            activate(account)
        } catch { errorMessage = "Не удалось подключить: проверь фразу восстановления" }
    }

    private func gateNewAccount() -> Bool {
        guard canAddMore else {
            errorMessage = subscription.isSubscribed
                ? String(localized: "Максимум \(AccountManager.maxAccounts) аккаунта")
                : String(localized: "Несколько аккаунтов доступны в PrivaMesh+")
            return false
        }
        return true
    }
}

// MARK: - Import sheet

private struct ImportAccountSheet: View {
    let onImport: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var words: [String] {
        text.lowercased().split { $0 == " " || $0 == "\n" }.map(String.init)
    }
    private var valid: Bool { words.count == 12 || words.count == 24 }

    var body: some View {
        NavigationStack {
            ZStack {
                PastelBackground()
                VStack(spacing: 16) {
                    Text("Подключить аккаунт")
                        .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.slate800)
                        .padding(.top, 24)
                    Text("Введи фразу восстановления существующего аккаунта (12 или 24 слова).")
                        .font(.system(size: 13)).foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)

                    TextField("слово1 слово2 …", text: $text, axis: .vertical)
                        .font(.system(size: 15, design: .monospaced)).lineLimit(3...6)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .padding(14).background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium)).padding(.horizontal, 20)

                    Text("\(words.count) слов").font(.system(size: 11))
                        .foregroundStyle(valid ? Theme.positive : Theme.slate400)

                    Button {
                        onImport(words); dismiss()
                    } label: {
                        Text("Подключить").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(valid ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color(white: 0.75)))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(!valid).padding(.horizontal, 20)
                    Spacer()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }.foregroundStyle(Theme.accentDeep) } }
        }
    }
}
