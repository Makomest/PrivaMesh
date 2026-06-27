//
//  SeedPhraseConfirmView.swift
//  privamesh
//

import SwiftUI

struct SeedPhraseConfirmView: View {
    @Environment(AppRouter.self) private var router
    @Environment(WalletManager.self) private var wallet

    @State private var questions: [Question] = []
    @State private var selectedAnswers: [Int: String] = [:]
    @State private var errorMessage: String?

    struct Question: Identifiable {
        let id = UUID()
        let wordIndex: Int
        let correctWord: String
        let options: [String]
    }

    private var phrase: [String] {
        if case let .draft(phrase, _) = wallet.state {
            return phrase
        }
        return []
    }

    private var isAllCorrect: Bool {
        guard !questions.isEmpty else { return false }
        return questions.allSatisfy { selectedAnswers[$0.wordIndex] == $0.correctWord }
    }

    private var isAllAnswered: Bool {
        questions.allSatisfy { selectedAnswers[$0.wordIndex] != nil }
    }

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Проверим что ты записал")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .padding(.top, 24)

                        Text("Выбери правильное слово для каждой позиции.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.slate500)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                        ForEach(questions) { question in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Слово №\(question.wordIndex + 1)")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.slate800)

                                HStack(spacing: 8) {
                                    ForEach(question.options, id: \.self) { option in
                                        let isSelected = selectedAnswers[question.wordIndex] == option
                                        Button {
                                            selectedAnswers[question.wordIndex] = option
                                            errorMessage = nil
                                        } label: {
                                            Text(option)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(isSelected ? .white : Theme.slate700)
                                                .padding(.vertical, 10)
                                                .frame(maxWidth: .infinity)
                                                .background(
                                                    isSelected
                                                        ? AnyShapeStyle(Theme.accentGradient)
                                                        : AnyShapeStyle(Theme.glass)
                                                )
                                                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                                        .stroke(
                                                            isSelected ? Color.clear : Theme.glassStroke,
                                                            lineWidth: 1
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if let errorMessage {
                            Text(LocalizedStringKey(errorMessage))
                                .font(.footnote)
                                .foregroundStyle(Theme.negative)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 16)
                }

                VStack(spacing: 12) {
                    Button {
                        confirm()
                    } label: {
                        Text("Подтвердить")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isAllAnswered
                                ? AnyShapeStyle(Theme.accentGradient)
                                : AnyShapeStyle(Color(red: 0.75, green: 0.75, blue: 0.75)))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAllAnswered)

                    Button {
                        router.go(to: .seedPhraseDisplay)
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if questions.isEmpty {
                questions = makeQuestions()
            }
        }
    }

    private func makeQuestions() -> [Question] {
        guard phrase.count == 12 else { return [] }
        let positions = Array(0..<12).shuffled().prefix(3).sorted()
        return positions.map { idx in
            let correct = phrase[idx]
            var distractors = Set<String>()
            while distractors.count < 2 {
                let candidate = phrase.randomElement() ?? ""
                if candidate != correct { distractors.insert(candidate) }
            }
            var options = Array(distractors) + [correct]
            options.shuffle()
            return Question(wordIndex: idx, correctWord: correct, options: options)
        }
    }

    private func confirm() {
        guard isAllCorrect else {
            errorMessage = "Одно или несколько слов выбрано неправильно. Проверь свою запись."
            return
        }
        do {
            try wallet.confirmDraft()
            router.go(to: .passcodeSetup)
        } catch {
            errorMessage = String(localized: "Не удалось создать аккаунт: \(error.localizedDescription)")
        }
    }
}

#Preview {
    let wallet = WalletManager()
    return SeedPhraseConfirmView()
        .environment(AppRouter())
        .environment(wallet)
        .task {
            try? await wallet.generateDraft()
        }
}
