//
//  SlideToConfirm.swift
//  privamesh
//
//  "Slide to confirm" control shown before a passkey prompt for sensitive
//  actions (payments, mint, buy/sell). Drag the thumb to the end to trigger.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SlideToConfirm: View {
    var text: String = "Сдвинь для подтверждения"
    var onConfirm: () -> Void

    @State private var offset: CGFloat = 0
    @State private var confirmed = false
    private let thumb: CGFloat = 50
    private let height: CGFloat = 54

    var body: some View {
        GeometryReader { geo in
            let maxX = max(0, geo.size.width - thumb)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accent.opacity(0.15))

                Text(confirmed ? "Подтверждено" : text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity)

                // Filled track behind the thumb.
                Capsule().fill(Theme.accentGradient)
                    .frame(width: offset + thumb)

                Circle()
                    .fill(.white)
                    .frame(width: thumb - 6, height: thumb - 6)
                    .overlay(
                        Image(systemName: confirmed ? "checkmark" : "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.accentDeep)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .padding(3)
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                guard !confirmed else { return }
                                offset = min(max(0, v.translation.width), maxX)
                            }
                            .onEnded { _ in
                                guard !confirmed else { return }
                                if offset > maxX * 0.82 {
                                    withAnimation(.spring(response: 0.25)) { offset = maxX }
                                    confirmed = true
                                    #if os(iOS)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    #endif
                                    onConfirm()
                                } else {
                                    withAnimation(.spring(response: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: height)
    }
}
