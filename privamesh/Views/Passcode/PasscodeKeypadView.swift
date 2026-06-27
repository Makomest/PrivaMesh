//
//  PasscodeKeypadView.swift
//  privamesh
//

import SwiftUI

struct PasscodeKeypadView: View {
    let title: String
    let subtitle: String?
    let errorMessage: String?
    let length: Int
    let onComplete: (String) -> Void

    @State private var entered: String = ""
    @State private var shake: CGFloat = 0

    init(
        title: String,
        subtitle: String? = nil,
        errorMessage: String? = nil,
        length: Int = 6,
        onComplete: @escaping (String) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.errorMessage = errorMessage
        self.length = length
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate800)

                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            Spacer(minLength: 32)

            dots
                .offset(x: shake)
                .animation(.default, value: entered)

            if let errorMessage {
                Text(LocalizedStringKey(errorMessage))
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
                    .padding(.top, 16)
            }

            Spacer(minLength: 24)

            keypad
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .onChange(of: errorMessage) { _, newValue in
            if newValue != nil {
                triggerShake()
                entered = ""
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<length, id: \.self) { index in
                Circle()
                    .fill(index < entered.count ? Theme.accent : Theme.glass)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().stroke(
                            index < entered.count ? Color.clear : Theme.glass,
                            lineWidth: 1.5
                        )
                    )
            }
        }
    }

    private var keypad: some View {
        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["",  "0", "⌫"],
        ]

        return VStack(spacing: 16) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 16) {
                    ForEach(rows[rowIndex], id: \.self) { key in
                        keypadButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keypadButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        } else if key == "⌫" {
            Button {
                if !entered.isEmpty { entered.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.title2)
                    .foregroundStyle(Theme.slate700)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                tap(key)
            } label: {
                Text(key)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.slate800)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.glass)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func tap(_ digit: String) {
        guard entered.count < length else { return }
        entered.append(digit)
        if entered.count == length {
            let captured = entered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                entered = ""
                onComplete(captured)
            }
        }
    }

    private func triggerShake() {
        withAnimation(.default) { shake = -10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.default) { shake = 10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.default) { shake = -5 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.default) { shake = 0 }
        }
    }
}

#Preview {
    PasscodeKeypadView(
        title: "Введи пароль",
        subtitle: "6 цифр для входа в приложение"
    ) { code in
        print(code)
    }
}
