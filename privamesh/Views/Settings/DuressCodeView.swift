//
//  DuressCodeView.swift
//  privamesh
//
//  The second code: the one that erases the account instead of opening it.
//
//  For the moment someone is made to unlock the phone — a border, a search, a
//  person standing over you. Entering it wipes everything this device holds and
//  leaves the first-run screen behind, with nothing that says a wipe happened.
//
//  The screen is blunt about what it cannot do. A safety feature believed to do
//  more than it does is worse than none.
//

import SwiftUI
import Combine

struct DuressCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PasscodeManager.self) private var passcode
    @Environment(TabBarVisibility.self) private var tabBarVisibility

    private enum Step {
        case explain
        case currentCode(then: Intent)
        case newCode(current: String)
        case confirm(current: String, duress: String)
        case done(String)
    }

    /// What the current passcode is being asked for.
    private enum Intent {
        case set
        case remove
    }

    @State private var step: Step = .explain
    @State private var errorMessage: String?
    @State private var lockoutSeconds: Int = 0

    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            PastelBackground()
            content
        }
        .navigationTitle("Код на случай принуждения")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            tabBarVisibility.hidden = true
            refreshLockout()
        }
        .onDisappear { tabBarVisibility.hidden = false }
        .onReceive(ticker) { _ in refreshLockout() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .explain:
            explanation

        case let .currentCode(intent):
            PasscodeKeypadView(
                title: "Текущий пароль",
                subtitle: "Подтверди, что это ты",
                errorMessage: errorMessage,
                length: passcode.passcodeLength,
                lockoutSeconds: lockoutSeconds
            ) { code in
                confirmOwner(code, intent: intent)
            }

        case let .newCode(current):
            PasscodeKeypadView(
                title: "Код принуждения",
                subtitle: "Другой код, не тот, которым ты входишь",
                errorMessage: errorMessage,
                length: passcode.passcodeLength
            ) { code in
                errorMessage = nil
                step = .confirm(current: current, duress: code)
            }

        case let .confirm(current, duress):
            PasscodeKeypadView(
                title: "Повтори код",
                subtitle: "Ещё раз, чтобы не ошибиться",
                errorMessage: errorMessage,
                length: passcode.passcodeLength
            ) { code in
                save(current: current, duress: duress, repeated: code)
            }

        case let .done(message):
            result(message)
        }
    }

    // MARK: - Screens

    private var explanation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Второй код, который стирает аккаунт вместо того, чтобы открыть его. С этого устройства уходит всё: переписка, контакты, ключи, оба кода. Остаётся экран, как будто приложение только что установили.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.slate700)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Чего он не делает")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.slate800)

                    limitation("Не стирает блокчейн. Отправленные сообщения остаются там навсегда. Без ключей их никто не прочитает, но сам факт переписки с твоего адреса виден всем и не удаляется.")
                    limitation("Не достаёт копию. Если с телефона уже сняли резервную копию, стирание сейчас до неё не дотянется.")
                    limitation("Не отменяется. Фраза восстановления вернёт аккаунт, но переписка на этом устройстве пропадёт навсегда.")
                }
                .padding(16)
                .background(Theme.glass)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if passcode.isDuressSet {
                    Text("Код принуждения установлен.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.slate800)
                }

                VStack(spacing: 12) {
                    Button {
                        errorMessage = nil
                        step = .currentCode(then: .set)
                    } label: {
                        Text(passcode.isDuressSet ? "Заменить код" : "Установить код")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if passcode.isDuressSet {
                        Button {
                            errorMessage = nil
                            step = .currentCode(then: .remove)
                        } label: {
                            Text("Убрать код")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(Theme.negative)
                                .background(Theme.negative.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
        }
    }

    private func limitation(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.slate500)
                .frame(width: 4, height: 4)
                .padding(.top, 7)
            Text(LocalizedStringKey(text))
                .font(.system(size: 13))
                .foregroundStyle(Theme.slate600)
        }
    }

    private func result(_ message: String) -> some View {
        VStack(spacing: 20) {
            Text(LocalizedStringKey(message))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.slate800)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                dismiss()
            } label: {
                Text("Готово")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Steps

    /// The current passcode gates both setting and removing.
    ///
    /// Without it, anyone holding an unlocked phone could point the wipe at a
    /// code of their own — which turns a safety feature into a way to destroy
    /// somebody's account.
    private func confirmOwner(_ code: String, intent: Intent) {
        switch intent {
        case .set:
            guard passcode.check(code) == .correct else {
                errorMessage = "Неверный пароль"
                refreshLockout()
                return
            }
            errorMessage = nil
            step = .newCode(current: code)

        case .remove:
            if passcode.removeDuressPasscode(currentPasscode: code) {
                step = .done("Код принуждения убран.")
            } else {
                errorMessage = "Неверный пароль"
                refreshLockout()
            }
        }
    }

    private func save(current: String, duress: String, repeated: String) {
        guard duress == repeated else {
            errorMessage = "Коды не совпали"
            step = .newCode(current: current)
            return
        }
        guard duress != current else {
            // This collision resolves as "unlock", so it would leave someone
            // believing they have a way out that does nothing.
            errorMessage = "Этот код совпадает с паролем входа"
            step = .newCode(current: current)
            return
        }
        if passcode.setDuressPasscode(duress, currentPasscode: current) {
            step = .done("Готово. Если ввести этот код на экране входа, аккаунт будет стёрт с этого устройства.")
        } else {
            errorMessage = "Не удалось сохранить код"
            step = .newCode(current: current)
        }
    }

    private func refreshLockout() {
        lockoutSeconds = Int(ceil(passcode.lockoutRemaining))
    }
}
