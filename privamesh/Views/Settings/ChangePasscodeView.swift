//
//  ChangePasscodeView.swift
//  privamesh
//

import SwiftUI

struct ChangePasscodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PasscodeManager.self) private var passcode
    @Environment(TabBarVisibility.self) private var tabBarVisibility

    enum Step {
        case current
        case newCode
        case confirm(newCode: String)
        /// Shown only when the change removed a duress code.
        case duressCleared
    }

    @State private var step: Step = .current
    @State private var errorMessage: String?
    @State private var newLength: Int = 6

    var body: some View {
        ZStack {
            PastelBackground()
            content
        }
        .navigationTitle("Сменить пароль")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Hide the floating tab bar so it doesn't overlap the keypad.
        .onAppear { tabBarVisibility.hidden = true }
        .onDisappear { tabBarVisibility.hidden = false }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .current:
            PasscodeKeypadView(
                title: "Текущий пароль",
                subtitle: "Введи действующий пароль",
                errorMessage: errorMessage,
                length: passcode.passcodeLength
            ) { code in
                if passcode.verify(code) {
                    errorMessage = nil
                    step = .newCode
                } else {
                    errorMessage = "Неверный пароль"
                }
            }

        case .newCode:
            VStack(spacing: 16) {
                lengthPicker.padding(.horizontal, 40).padding(.top, 12)
                PasscodeKeypadView(
                    title: "Новый пароль",
                    subtitle: "Придумай новый код",
                    errorMessage: errorMessage,
                    length: newLength
                ) { code in
                    errorMessage = nil
                    step = .confirm(newCode: code)
                }
            }

        case let .confirm(newCode):
            PasscodeKeypadView(
                title: "Повтори новый",
                subtitle: "Введи новый пароль ещё раз",
                errorMessage: errorMessage,
                length: newLength
            ) { code in
                if code == newCode {
                    save(code, length: newLength)
                } else {
                    errorMessage = "Пароли не совпадают"
                    step = .newCode
                }
            }

        case .duressCleared:
            duressClearedNotice
        }
    }

    /// The duress code is stored under the passcode's salt, so a new passcode
    /// invalidates it and it is dropped. Saying so is the whole point: a duress
    /// code someone believes is armed, and is not, is worse than never having set
    /// one — they find out at the moment they were counting on it.
    private var duressClearedNotice: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentDeep)

            Text("Пароль изменён. Код на случай принуждения удалён — задай его заново в настройках безопасности.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.slate800)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button { dismiss() } label: {
                Text("Понятно")
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

    private var lengthPicker: some View {
        HStack(spacing: 0) {
            lengthOption(4)
            lengthOption(6)
        }
        .background(Theme.glassStroke)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
    }
    private func lengthOption(_ digits: Int) -> some View {
        let isSelected = newLength == digits
        return Button { newLength = digits } label: {
            Text("\(digits) цифры")
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.slate600)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear))
                .clipShape(Capsule()).padding(3)
        }
        .buttonStyle(.plain)
    }

    private func save(_ newCode: String, length: Int) {
        let hadDuressCode = passcode.isDuressSet
        do {
            try passcode.setPasscode(newCode, length: length)
            if hadDuressCode {
                step = .duressCleared
            } else {
                dismiss()
            }
        } catch {
            errorMessage = "Не удалось сохранить пароль"
            step = .current
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasscodeView()
            .environment(PasscodeManager())
    }
}
