//
//  ScreenCaptureGuard.swift
//  privamesh
//
//  Hides secrets while the screen is being recorded or mirrored.
//
//  The recovery phrase is the entire account: anyone who reads it owns the
//  identity forever. A line of copy asking people not to screenshot does nothing
//  about a share on a video call, a screen recording left running, or an AirPlay
//  session to a TV in someone else's living room — and those are the ways it
//  actually leaks.
//
//  iOS reports capture state through `UIScreen.isCaptured` and posts a
//  notification when it flips. That covers recordings, mirroring and sharing.
//  It does NOT cover a single screenshot, which iOS only tells us about after the
//  fact, so the words stay covered until capture stops.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Observes whether this device's screen is being captured right now.
@Observable
@MainActor
final class ScreenCaptureMonitor {
    private(set) var isCaptured = false
    /// Observer tokens live in a nonisolated box: `deinit` cannot touch main-actor
    /// state, and leaking notification observers for the life of the process is
    /// not an acceptable alternative.
    private let tokens = TokenBox()

    init() {
        #if canImport(UIKit)
        isCaptured = UIScreen.main.isCaptured
        let center = NotificationCenter.default
        tokens.keep(center.addObserver(forName: UIScreen.capturedDidChangeNotification,
                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isCaptured = UIScreen.main.isCaptured }
        })
        // Mirroring shows up as a second screen rather than as capture on some
        // setups, so treat connect/disconnect as a reason to re-read the state.
        for name in [UIScreen.didConnectNotification, UIScreen.didDisconnectNotification] {
            tokens.keep(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isCaptured = UIScreen.main.isCaptured || UIScreen.screens.count > 1
                }
            })
        }
        if UIScreen.screens.count > 1 { isCaptured = true }
        #endif
    }

    /// Holds notification tokens and unregisters them when the monitor goes away.
    private final class TokenBox {
        private var tokens: [NSObjectProtocol] = []
        func keep(_ token: NSObjectProtocol) { tokens.append(token) }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}

/// Replaces its content with a warning while the screen is being captured.
///
/// Blur alone is not enough: a recording keeps the frames, and a blur that leaks
/// word shapes is worse than an honest cover because it looks like protection.
struct CaptureShielded<Content: View>: View {
    @State private var monitor = ScreenCaptureMonitor()
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
                .opacity(monitor.isCaptured ? 0 : 1)
                .accessibilityHidden(monitor.isCaptured)
            if monitor.isCaptured {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.warning)
                    Text("Экран записывается")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.slate800)
                    Text("Фраза скрыта, пока идёт запись или трансляция экрана. Останови её, чтобы увидеть слова.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.slate500)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: monitor.isCaptured)
    }
}
