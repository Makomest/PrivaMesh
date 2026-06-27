//
//  PasscodeSetupView.swift
//  privamesh
//

import SwiftUI

struct PasscodeSetupView: View {
    @Environment(AppRouter.self) private var router
    @Environment(PasscodeManager.self) private var passcode
    @Environment(BiometryService.self) private var biometry

    enum Step {
        case enter
        case confirm(firstCode: String)
    }

    @State private var step: Step = .enter
    @State private var errorMessage: String?
    @State private var selectedLength: Int = 6

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                if case .enter = step {
                    lengthPicker
                        .padding(.top, 20)
                        .padding(.horizontal, 40)
                }
                PasscodeKeypadView(
                    title: stepTitle,
                    subtitle: stepSubtitle,
                    errorMessage: errorMessage,
                    length: selectedLength
                ) { code in
                    handleCode(code)
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .enter:   return "Придумай пароль"
        case .confirm: return "Повтори пароль"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .enter:
            return "\(selectedLength) цифр для входа в приложение"
        case .confirm:
            return "Введи те же \(selectedLength) цифр ещё раз"
        }
    }

    private var lengthPicker: some View {
        HStack(spacing: 0) {
            lengthOption(digits: 4)
            lengthOption(digits: 6)
        }
        .background(Theme.glassStroke)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.glassStroke, lineWidth: 1))
    }

    private func lengthOption(digits: Int) -> some View {
        let isSelected = selectedLength == digits
        return Button {
            selectedLength = digits
        } label: {
            Text("\(digits) цифры")
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.slate600)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    isSelected
                        ? AnyShapeStyle(Theme.accentGradient)
                        : AnyShapeStyle(Color.clear)
                )
                .clipShape(Capsule())
                .padding(3)
        }
        .buttonStyle(.plain)
    }

    private func handleCode(_ code: String) {
        switch step {
        case .enter:
            errorMessage = nil
            step = .confirm(firstCode: code)

        case let .confirm(firstCode):
            if code == firstCode {
                save(code)
            } else {
                errorMessage = "Пароли не совпадают. Попробуй ещё раз."
                step = .enter
            }
        }
    }

    private func save(_ code: String) {
        do {
            try passcode.setPasscode(code, length: selectedLength)
            if biometry.isAvailable {
                router.go(to: .biometryPrompt)
            } else {
                router.go(to: .main)
            }
        } catch {
            errorMessage = String(localized: "Не удалось сохранить пароль: \(error.localizedDescription)")
            step = .enter
        }
    }
}

#Preview {
    PasscodeSetupView()
        .environment(AppRouter())
        .environment(PasscodeManager())
        .environment(BiometryService())
}
