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
                        // Decentralized mesh aura with message-passing pulses
                        MeshAura()
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

                Text("Приватный мессенджер на Solana.\nБез телефона и email — только твой ключ.")
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

// MARK: - Decentralized mesh aura

/// Minimalist decentralized network ringing the logo: nodes joined by edges,
/// with bright pulses traveling edge-to-edge to suggest messages hopping the mesh.
/// Stable pseudo-random in [0,1) from two integer seeds (frame-independent).
private func meshRnd(_ a: Int, _ b: Int) -> Double {
    var x = UInt64(bitPattern: Int64(a &* 73856093) ^ Int64(b &* 19349663))
    x ^= x >> 33; x = x &* 0xff51afd7ed558ccd
    x ^= x >> 33; x = x &* 0xc4ceb9fe1a85ec53; x ^= x >> 33
    return Double(x % 100_000) / 100_000
}

private struct MeshAura: View {
    /// Half-edge of the cube.
    var s: CGFloat = 44

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)

                // 8 cube vertices (±1 per axis), rotated slowly around Y with a
                // fixed isometric X-tilt, then orthographically projected.
                let ang = t * 0.3                       // slow spin
                let tilt = 0.62                          // ~35° iso tilt
                let cosA = cos(ang), sinA = sin(ang)
                let cosT = cos(tilt), sinT = sin(tilt)

                var pts: [CGPoint] = []
                var depth: [Double] = []
                for i in 0..<8 {
                    let x = Double((i & 1) != 0 ? 1 : -1)
                    let y = Double((i & 2) != 0 ? 1 : -1)
                    let z = Double((i & 4) != 0 ? 1 : -1)
                    // rotate around Y
                    let x1 = x * cosA + z * sinA
                    let z1 = -x * sinA + z * cosA
                    // tilt around X
                    let y2 = y * cosT - z1 * sinT
                    let z2 = y * sinT + z1 * cosT
                    pts.append(CGPoint(x: c.x + CGFloat(x1) * s, y: c.y + CGFloat(y2) * s))
                    depth.append(z2)
                }
                let dMin = depth.min() ?? -1, dMax = depth.max() ?? 1
                func norm(_ d: Double) -> Double { (d - dMin) / max(0.0001, dMax - dMin) }  // 0 far … 1 near

                // 12 cube edges: vertices differing in exactly one axis bit.
                var edges: [(Int, Int)] = []
                for i in 0..<8 {
                    for bit in [1, 2, 4] where i < (i ^ bit) { edges.append((i, i ^ bit)) }
                }

                // Edges — nearer ones brighter for depth.
                for (a, b) in edges {
                    let near = norm((depth[a] + depth[b]) / 2)
                    var p = Path()
                    p.move(to: pts[a]); p.addLine(to: pts[b])
                    ctx.stroke(p, with: .color(Theme.accent.opacity(0.10 + 0.22 * near)),
                               lineWidth: 0.8 + 0.7 * near)
                }

                // Vertices — nearer ones larger/brighter.
                for (i, pt) in pts.enumerated() {
                    let near = norm(depth[i])
                    let r = 2.2 + 2.0 * CGFloat(near)
                    let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.45 + 0.5 * near)))
                }

                // Message pulses — each pulse owns a disjoint bucket of edges, so
                // no two ride the same line. Each trip picks a fresh edge/direction,
                // so the relaying never settles into a loop.
                let pulseCount = 6
                for k in 0..<pulseCount {
                    let bucket = edges.indices.filter { $0 % pulseCount == k }
                    if bucket.isEmpty { continue }

                    let period = 2.2 + meshRnd(k, 901) * 1.6           // 2.2–3.8s
                    let local = t / period + Double(k) * 0.37          // desynced starts
                    let trip = Int(floor(local))
                    let progress = local - Double(trip)

                    let ei = bucket[Int(meshRnd(trip, k) * Double(bucket.count)) % bucket.count]
                    var (a, b) = edges[ei]
                    if meshRnd(k, trip + 7) < 0.5 { swap(&a, &b) }     // random direction

                    let pt = CGPoint(x: pts[a].x + (pts[b].x - pts[a].x) * progress,
                                     y: pts[a].y + (pts[b].y - pts[a].y) * progress)
                    let near = norm(depth[a] + (depth[b] - depth[a]) * progress)
                    let alpha = sin(progress * .pi) * (0.5 + 0.5 * near)  // fade ends + depth

                    let glow = CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
                    var blurred = ctx
                    blurred.addFilter(.blur(radius: 3))
                    blurred.fill(Path(ellipseIn: glow), with: .color(Theme.accentDeep.opacity(0.7 * alpha)))
                    let core = CGRect(x: pt.x - 2.4, y: pt.y - 2.4, width: 4.8, height: 4.8)
                    ctx.fill(Path(ellipseIn: core), with: .color(.white.opacity(0.95 * alpha)))
                }
            }
        }
        .frame(width: 170, height: 170)
        .allowsHitTesting(false)
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
