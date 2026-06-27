//
//  NFTAvatarView.swift
//  privamesh
//
//  NFT avatar art. Themed collections (see AvatarCatalog) render as a halftone /
//  dithered subject silhouette over a dark themed background. Unknown/legacy
//  seeds fall back to the original procedural "cosmic orb".
//

import SwiftUI

struct NFTAvatarView: View {
    let seed: String
    var size: CGFloat = 72
    /// Optional rarity ring color drawn around the art.
    var ringColor: Color? = nil

    var body: some View {
        Group {
            if seed == AvatarService.logoDesignID {
                logoMesh
            } else if let resolved = AvatarCatalog.resolve(seed) {
                themed(collection: resolved.collection, item: resolved.item)
            } else {
                legacyOrb
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(ringColor ?? Theme.glassStroke,
                            lineWidth: ringColor == nil ? 1 : max(2, size * 0.04))
        )
    }

    // MARK: - Brand logo avatar (the PrivaMesh mesh, in a circle)

    private static let logoNodes: [(CGFloat, CGFloat, CGFloat)] = [
        (0.50, 0.28, 1.15), (0.28, 0.50, 1.0), (0.72, 0.50, 1.0),
        (0.50, 0.50, 1.35), (0.34, 0.74, 1.0), (0.66, 0.74, 1.0),
    ]
    private static let logoEdges = [(0,1),(0,2),(0,3),(3,1),(3,2),(3,4),(3,5),(1,4),(2,5),(4,5)]

    private var logoMesh: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [Color(red: 0.10, green: 0.78, blue: 0.68),
                         Color(red: 0.04, green: 0.45, blue: 0.42)],
                center: .init(x: 0.32, y: 0.28), startRadius: size * 0.05, endRadius: size * 0.95))
            Canvas { ctx, sz in
                func p(_ i: Int) -> CGPoint {
                    CGPoint(x: Self.logoNodes[i].0 * sz.width, y: Self.logoNodes[i].1 * sz.height)
                }
                var path = Path()
                for (a, b) in Self.logoEdges { path.move(to: p(a)); path.addLine(to: p(b)) }
                ctx.stroke(path, with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: max(0.8, sz.width * 0.03), lineCap: .round))
                let base = sz.width * 0.075
                for (i, n) in Self.logoNodes.enumerated() {
                    let r = base * n.2, pt = p(i)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(i == 3 ? 1 : 0.95)))
                }
            }
            .padding(size * 0.10)
        }
        .clipShape(Circle())
    }

    // MARK: - Themed halftone avatar

    private func themed(collection: AvatarCatalog.Collection, item: AvatarCatalog.Item) -> some View {
        let h = Self.hash(seed)
        let palette = collection.palettes[Int(h % UInt64(collection.palettes.count))]

        return ZStack {
            Circle()
                .fill(RadialGradient(colors: palette,
                                     center: .init(x: 0.32, y: 0.28),
                                     startRadius: size * 0.05, endRadius: size * 0.95))

            // Subject silhouette.
            Image(systemName: item.symbol)
                .resizable().scaledToFit()
                .fontWeight(.semibold)
                .frame(width: size * 0.52, height: size * 0.52)
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: size * 0.02, y: size * 0.01)

            // Halftone dot texture over everything for the dithered look.
            Canvas { ctx, sz in
                let step = max(3, sz.width / 16)
                let maxR = step * 0.52
                let center = CGPoint(x: sz.width * 0.42, y: sz.height * 0.38)
                let diag = hypot(sz.width, sz.height)
                var y = step * 0.5
                while y < sz.height {
                    var x = step * 0.5
                    while x < sz.width {
                        // Dot grows toward the edges → classic halftone falloff.
                        let d = hypot(x - center.x, y - center.y) / diag
                        let r = maxR * min(1, 0.25 + d * 1.4)
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        ctx.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.22)))
                        x += step
                    }
                    y += step
                }
            }
            .blendMode(.overlay)
            .clipShape(Circle())
        }
        .clipShape(Circle())
    }

    // MARK: - Legacy procedural orb (fallback)

    private var legacyOrb: some View {
        let h = Self.hash(seed)
        let palette = Self.palettes[Int(h % UInt64(Self.palettes.count))]
        let nodeCount = 5 + Int(h / 7 % 5)
        let arcCount  = 2 + Int(h / 13 % 3)
        let baseAngle = Self.rnd(h, 1) * 2 * .pi

        return ZStack {
            Circle()
                .fill(RadialGradient(colors: palette,
                                     center: .init(x: 0.35, y: 0.30),
                                     startRadius: size * 0.05, endRadius: size * 0.85))
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let R = sz.width / 2
                for a in 0..<arcCount {
                    let frac = 0.45 + Double(a) / Double(arcCount) * 0.4
                    let radius = R * frac
                    let start = Angle(radians: Self.rnd(h, UInt64(a) + 10) * 2 * .pi)
                    let sweep = Angle(radians: .pi * (0.6 + Self.rnd(h, UInt64(a) + 20) * 0.9))
                    var p = Path()
                    p.addArc(center: c, radius: radius,
                             startAngle: start, endAngle: start + sweep, clockwise: false)
                    ctx.stroke(p, with: .color(.white.opacity(0.30)), lineWidth: sz.width * 0.02)
                }
                let orbit = R * 0.62
                for i in 0..<nodeCount {
                    let ang = baseAngle + Double(i) / Double(nodeCount) * 2 * .pi
                    let rr  = orbit * (0.7 + Self.rnd(h, UInt64(i) + 30) * 0.3)
                    let pt  = CGPoint(x: c.x + CGFloat(cos(ang)) * rr, y: c.y + CGFloat(sin(ang)) * rr)
                    let dot = sz.width * (0.035 + Self.rnd(h, UInt64(i) + 40) * 0.04)
                    let rect = CGRect(x: pt.x - dot, y: pt.y - dot, width: dot * 2, height: dot * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)))
                }
                let coreR = R * 0.22
                let core = CGRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2)
                ctx.fill(Path(ellipseIn: core), with: .color(.white.opacity(0.9)))
            }
            .clipShape(Circle())
        }
    }

    // MARK: - Deterministic noise

    private static let palettes: [[Color]] = [
        [Color(red: 0.45, green: 0.20, blue: 0.95), Color(red: 0.05, green: 0.70, blue: 0.95), Color(red: 0.20, green: 0.95, blue: 0.75)],
        [Color(red: 0.98, green: 0.45, blue: 0.20), Color(red: 0.98, green: 0.75, blue: 0.20), Color(red: 0.98, green: 0.30, blue: 0.45)],
        [Color(red: 0.10, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.55, blue: 0.85), Color(red: 0.55, green: 0.95, blue: 0.40)],
        [Color(red: 0.95, green: 0.30, blue: 0.65), Color(red: 0.60, green: 0.25, blue: 0.95), Color(red: 0.30, green: 0.55, blue: 0.98)],
        [Color(red: 0.10, green: 0.20, blue: 0.45), Color(red: 0.20, green: 0.60, blue: 0.90), Color(red: 0.70, green: 0.90, blue: 1.00)],
        [Color(red: 0.95, green: 0.85, blue: 0.30), Color(red: 0.95, green: 0.45, blue: 0.20), Color(red: 0.60, green: 0.20, blue: 0.20)],
    ]

    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
    private static func rnd(_ h: UInt64, _ i: UInt64) -> Double {
        let x = (h &+ i &* 2654435761) &* 6364136223846793005 &+ 1442695040888963407
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}

#Preview {
    HStack(spacing: 12) {
        NFTAvatarView(seed: "animals-05", size: 72)
        NFTAvatarView(seed: "stars-07", size: 72)
        NFTAvatarView(seed: "anon-03", size: 72)
    }
    .padding().background(.black)
}
