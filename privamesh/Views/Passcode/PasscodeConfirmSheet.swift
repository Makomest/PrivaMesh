//
//  PasscodeConfirmSheet.swift
//  privamesh
//
//  Reusable confirmation gate using the in-app passcode. Presented as a fallback
//  when biometric confirmation isn't available or is declined, so sensitive
//  actions (e.g. minting an NFT nickname) can be authorized by the app passcode,
//  not only Face ID / Touch ID.
//

import SwiftUI

struct PasscodeConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PasscodeManager.self) private var passcode

    let reason: String
    let onSuccess: () -> Void

    @State private var error: String?

    var body: some View {
        ZStack {
            PastelBackground().ignoresSafeArea()
            PasscodeKeypadView(
                title: reason,
                subtitle: "Введи пароль приложения",
                errorMessage: error,
                length: passcode.passcodeLength
            ) { code in
                if passcode.verify(code) {
                    onSuccess()
                    dismiss()
                } else {
                    error = "Неверный пароль"
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(Theme.slate400)
            }
            .buttonStyle(.plain).padding(16)
        }
    }
}
