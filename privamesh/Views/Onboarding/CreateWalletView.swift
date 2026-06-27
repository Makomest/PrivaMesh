//
//  CreateWalletView.swift
//  privamesh
//

import SwiftUI

struct CreateWalletView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet

    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 32)

                        Text("Создай свой аккаунт")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .frame(maxWidth: .infinity, alignment: .center)

                        VStack(alignment: .leading, spacing: 14) {
                            infoRow(icon: "key.fill",
                                    text: "Ты получишь **12 секретных слов** — единственный способ восстановить аккаунт.")
                            infoRow(icon: "pencil.and.list.clipboard",
                                    text: "**Запиши их на бумаге** и храни в надёжном месте. Не делай скриншот.")
                            infoRow(icon: "eye.slash.fill",
                                    text: "**Никому не показывай** эти слова. Любой кто их увидит — получит доступ к твоему аккаунту.")
                            infoRow(icon: "server.rack",
                                    text: "**Мы не сможем помочь** если ты потеряешь слова. Нет серверов, нет аккаунтов на наших серверах.")
                        }
                        .padding(16)
                        .background(Theme.glass)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(Theme.glassStroke, lineWidth: 1))

                        if let errorMessage {
                            Text(LocalizedStringKey(errorMessage))
                                .font(.footnote)
                                .foregroundStyle(Theme.negative)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    Button {
                        generate()
                    } label: {
                        HStack(spacing: 8) {
                            if isGenerating { ProgressView().tint(.white) }
                            Text(LocalizedStringKey(isGenerating ? "Создание..." : "Создать аккаунт"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isGenerating
                            ? AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75))
                            : AnyShapeStyle(Theme.accentGradient))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)

                    Button {
                        router.go(to: .welcome)
                    } label: {
                        Text("Назад")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glass)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isGenerating)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20, alignment: .center)
            Text(.init(text))
                .font(.system(size: 14))
                .foregroundStyle(Theme.slate700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        Task {
            do {
                try await wallet.generateDraft()
                await MainActor.run {
                    isGenerating = false
                    router.go(to: .seedPhraseDisplay)
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = String(localized: "Не удалось создать аккаунт: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    CreateWalletView()
        .environment(AppRouter())
        .environment(WalletManager())
}
