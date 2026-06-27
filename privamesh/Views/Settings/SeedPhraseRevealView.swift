//
//  SeedPhraseRevealView.swift
//  privamesh
//

import SwiftUI

struct SeedPhraseRevealView: View {
    @Environment(WalletManager.self) private var wallet
    @Environment(PasscodeManager.self) private var passcode
    @Environment(BiometryService.self) private var biometry
    @Environment(TabBarVisibility.self) private var tabBarVisibility

    @State private var phrase: [String] = []
    @State private var isAuthenticated = false
    @State private var errorMessage: String?
    @State private var passcodeError: String?

    var body: some View {
        ZStack {
            PastelBackground()
            Group {
                if isAuthenticated {
                    phraseGrid
                } else {
                    authGate
                }
            }
        }
        .navigationTitle("Seed phrase")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { tabBarVisibility.hidden = true }
        .onDisappear { tabBarVisibility.hidden = false }
    }

    @ViewBuilder
    private var authGate: some View {
        if biometry.isAvailable && biometry.isEnabled {
            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Theme.accentGradient).frame(width: 80, height: 80).blur(radius: 18).opacity(0.4)
                    Image(systemName: biometry.kind.systemImage)
                        .font(.system(size: 56)).foregroundStyle(Theme.accentGradient)
                }
                Text("Подтверди личность чтобы увидеть seed phrase")
                    .font(.system(size: 15)).foregroundStyle(Theme.slate600)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Button { Task { await authWithBiometry() } } label: {
                    Text("Использовать \(biometry.kind.label)")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(Theme.accentGradient).clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await authWithBiometry() }
        } else {
            PasscodeKeypadView(
                title: "Введи пароль",
                subtitle: "Подтверди что это твой кошелёк",
                errorMessage: passcodeError
            ) { code in
                authWithPasscode(code)
            }
        }
    }

    private var phraseGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13))
                    Text("Никому не показывай эти слова").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color(red: 245/255, green: 158/255, blue: 11/255))
                .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(phrase.enumerated()), id: \.offset) { index, word in
                        HStack(spacing: 8) {
                            Text("\(index + 1).")
                                .foregroundStyle(Theme.slate400)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1).fixedSize()
                                .frame(width: 32, alignment: .trailing)
                            Text(word)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Theme.slate800)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.glassStroke, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 16)

                if let errorMessage {
                    Text(LocalizedStringKey(errorMessage))
                        .foregroundStyle(Theme.negative).font(.system(size: 12))
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func authWithBiometry() async {
        let ok = await biometry.authenticate(reason: "Показать seed phrase")
        if ok {
            loadPhrase()
        }
    }

    private func authWithPasscode(_ code: String) {
        if passcode.verify(code) {
            passcodeError = nil
            loadPhrase()
        } else {
            passcodeError = "Неверный пароль"
        }
    }

    private func loadPhrase() {
        do {
            phrase = try wallet.revealSeedPhrase()
            isAuthenticated = true
        } catch {
            errorMessage = "Не удалось прочитать seed phrase"
        }
    }
}

#Preview {
    NavigationStack {
        SeedPhraseRevealView()
            .environment(WalletManager())
            .environment(PasscodeManager())
            .environment(BiometryService())
    }
}
