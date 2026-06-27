//
//  SeedPhraseDisplayView.swift
//  privamesh
//

import SwiftUI

struct SeedPhraseDisplayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet

    @State private var savedConfirmed = false

    private var phrase: [String] {
        if case let .draft(phrase, _) = wallet.state {
            return phrase
        }
        return []
    }

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        Text("Твоя секретная фраза")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .padding(.top, 24)

                        Text("Запиши эти 12 слов **по порядку**. Без них аккаунт не восстановить.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Array(phrase.enumerated()), id: \.offset) { index, word in
                                HStack(spacing: 8) {
                                    Text("\(index + 1).")
                                        .foregroundStyle(Theme.slate400)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .fixedSize()
                                        .frame(width: 32, alignment: .trailing)
                                    Text(word)
                                        .font(.system(.body, design: .monospaced).weight(.semibold))
                                        .foregroundStyle(Theme.slate800)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .background(Theme.glass)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .stroke(Theme.glassStroke, lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, 16)

                        HStack(spacing: 6) {
                            Image(systemName: "camera.metering.none")
                                .font(.system(size: 12))
                            Text("Не делай скриншот этого экрана")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Theme.warning)
                        .padding(.top, 4)
                    }
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    Toggle(isOn: $savedConfirmed) {
                        Text("Я записал слова в надёжном месте")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.slate700)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .padding(.horizontal, 4)

                    Button {
                        router.go(to: .seedPhraseConfirm)
                    } label: {
                        Text("Продолжить")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(savedConfirmed
                                ? AnyShapeStyle(Theme.accentGradient)
                                : AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75)))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!savedConfirmed)

                    Button {
                        wallet.discardDraft()
                        router.go(to: .welcome)
                    } label: {
                        Text("Отмена")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glass)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    let wallet = WalletManager()
    return SeedPhraseDisplayView()
        .environment(AppRouter())
        .environment(wallet)
        .task {
            try? await wallet.generateDraft()
        }
}
