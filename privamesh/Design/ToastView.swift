//
//  ToastView.swift
//  privamesh
//

import SwiftUI

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
            Text(message)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Theme.positive)
        .clipShape(Capsule())
        .shadow(color: Theme.positive.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    ToastView(message: "Скопировано")
}
