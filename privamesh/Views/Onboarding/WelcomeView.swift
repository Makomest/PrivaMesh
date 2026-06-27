//
//  WelcomeView.swift
//  privamesh
//

import SwiftUI

struct WelcomeView: View {
    @Environment(AppRouter.self) private var router

    @State private var appear = false   // staggered reveal
    @State private var pop = false      // logo spring-in
    @State private var glow = false     // breathing halo
    @State private var float = false    // gentle logo bob

    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentGradient)
                            .frame(width: 96, height: 96)
                            .blur(radius: 26)
                            .opacity(glow ? 0.5 : 0.25)
                            .scaleEffect(glow ? 1.15 : 0.9)
                        // Rotating dashed aura
                        Circle()
                            .stroke(AngularGradient(colors: [Theme.accent, Theme.accentDeep, Theme.accent],
                                                    center: .center),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 8]))
                            .frame(width: 104, height: 104)
                            .rotationEffect(.degrees(appear ? 360 : 0))
                            .opacity(0.5)
                            .animation(.linear(duration: 18).repeatForever(autoreverses: false), value: appear)
                        PrivaLogo(size: 72)
                            .offset(y: float ? -5 : 5)
                    }
                    .scaleEffect(pop ? 1 : 0.5)
                    .opacity(pop ? 1 : 0)

                    VStack(spacing: 6) {
                        Text("PrivaMesh")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.slate800)
                            .staggered(appear, index: 1)
                        Text("Trust Math, Not Companies")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.slate500)
                            .staggered(appear, index: 2)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        router.go(to: .createWallet)
                    } label: {
                        Text("Создать аккаунт")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accentGradient)
                            .clipShape(Capsule())
                            .shadow(color: Theme.accent.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .buttonStyle(.plain)
                    .staggered(appear, index: 3)

                    Button {
                        router.go(to: .importWallet)
                    } label: {
                        Text("Восстановить из seed phrase")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glass)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.glass, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .staggered(appear, index: 4)
                }
                .padding(.horizontal, 24)

                Text("Приватный мессенджер, кошелёк и NFT-маркет на Solana.\nБез серверов и слежки.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.slate400)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .staggered(appear, index: 5)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { pop = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) { appear = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { glow = true }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { float = true }
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
}
