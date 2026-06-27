//
//  ToastManager.swift
//  privamesh
//
//  Global ephemeral toast notifications (e.g. "Скопировано").
//  Inject via .environment(toastManager) and call toast.show().
//

import SwiftUI

@Observable
@MainActor
final class ToastManager {
    private(set) var message: String = ""
    private(set) var isVisible: Bool = false
    private var hideTask: Task<Void, Never>?

    func show(_ message: String = "Скопировано") {
        hideTask?.cancel()
        // Localize the (Russian-key) message through the String Catalog so toasts
        // follow the app language even though callers pass plain String literals.
        self.message = String(localized: String.LocalizationValue(message))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isVisible = true
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = false
            }
        }
    }
}
