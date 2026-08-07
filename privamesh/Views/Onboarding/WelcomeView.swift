//
//  WelcomeView.swift
//  privamesh
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appear = false   // staggered reveal
    @State private var pop = false      // sphere spring-in

    var body: some View {
        ZStack {
            OrbitMeshBackground(intensity: 1.4)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 26) {
                    NetworkSphereView(diameter: 168, reduced: reduceMotion)
                        .scaleEffect(pop ? 1 : 0.6)
                        .opacity(pop ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("PrivaMesh")
                            .font(.system(size: 40, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Orbit.label)
                            .staggered(appear, index: 1)
                        Text("Trust Math, Not Companies")
                            .font(.system(size: 15))
                            .foregroundStyle(Orbit.label3)
                            .staggered(appear, index: 2)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    // Primary: solid white pill, ink text — the one bright action.
                    Button { router.go(to: .createWallet) } label: {
                        Text("Создать аккаунт")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Orbit.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Orbit.label, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .staggered(appear, index: 3)

                    // Secondary: ghost — hairline outline, white text.
                    Button { router.go(to: .importWallet) } label: {
                        Text("Восстановить по фразе")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Orbit.label)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(Capsule().stroke(Orbit.label.opacity(0.22), lineWidth: 1))
                            // Outlined pill has no fill, so without this SwiftUI
                            // hit-tests the glyphs only — on a wide layout (iPad)
                            // taps beside the text fall through the button.
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .staggered(appear, index: 4)
                }
                .padding(.horizontal, 24)

                Text("Приватный мессенджер.\nБез телефона и email — только твой ключ.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Orbit.label3)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .staggered(appear, index: 5)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { pop = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appear = true }
        }
    }
}

// MARK: - Staggered reveal

private extension View {
    func staggered(_ visible: Bool, index: Int) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 20)
            .animation(.spring(response: 0.5, dampingFraction: 0.78)
                .delay(0.15 + Double(index) * 0.08), value: visible)
    }
}

#Preview {
    WelcomeView()
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
