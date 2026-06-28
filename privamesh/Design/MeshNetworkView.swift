//
//  MeshNetworkView.swift
//  privamesh
//
//  Minimalist animated decentralized network: a ring of nodes wired to a centre
//  hub, with little message packets gliding along the edges. Brand teal, soft
//  glow, gentle node breathing. Used behind the logo on the Welcome screen.
//

import SwiftUI

struct MeshNetworkView: View {
    var size: CGFloat = 200
    var logoSize: CGFloat = 72

    // Normalised node layout (0...1): a centre hub + 6 outer nodes on a ring.
    private let outerCount = 6
    private let ringR: CGFloat = 0.40

    private var nodes: [CGPoint] {
        var pts = [CGPoint(x: 0.5, y: 0.5)]                 // 0 = hub
        for k in 0..<outerCount {
            let a = -CGFloat.pi / 2 + CGFloat(k) * 2 * .pi / CGFloat(outerCount)
            pts.append(CGPoint(x: 0.5 + ringR * cos(a), y: 0.5 + ringR * sin(a)))
        }
        return pts
    }

    // Spokes (hub↔outer) + ring (outer↔neighbour).
    private var edges: [(Int, Int)] {
        var e: [(Int, Int)] = []
        for i in 1...outerCount { e.append((0, i)) }
        for i in 1...outerCount { e.append((i, i % outerCount + 1)) }
        return e
    }

    var body: some View {
        let pts = nodes
        let eds = edges
        ZStack {
            // Breathing halo behind everything.
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, sz in
                    func P(_ n: CGPoint) -> CGPoint { CGPoint(x: n.x * sz.width, y: n.y * sz.height) }

                    // Edges — thin, low-opacity teal.
                    for (a, b) in eds {
                        var path = Path()
                        path.move(to: P(pts[a])); path.addLine(to: P(pts[b]))
                        ctx.stroke(path, with: .color(Theme.accent.opacity(0.20)), lineWidth: 1.1)
                    }

                    // Packets — a message glides along each spoke; direction and
                    // phase staggered so it reads as send + receive across the mesh.
                    for (idx, (a, b)) in eds.enumerated() {
                        // Only animate a lively subset (all spokes + every 2nd ring edge).
                        let isSpoke = a == 0
                        if !isSpoke && idx % 2 == 1 { continue }
                        let speed = isSpoke ? 0.32 : 0.22
                        let phase = Double(idx) * 0.37
                        var f = (t * speed + phase).truncatingRemainder(dividingBy: 1)
                        // Alternate travel direction for variety.
                        if idx % 2 == 0 { f = 1 - f }
                        let pa = P(pts[a]); let pb = P(pts[b])
                        // Short fading trail (3 dots).
                        for s in 0..<3 {
                            let ff = f - Double(s) * 0.05
                            guard ff >= 0, ff <= 1 else { continue }
                            let x = pa.x + (pb.x - pa.x) * ff
                            let y = pa.y + (pb.y - pa.y) * ff
                            let r = (isSpoke ? 3.0 : 2.4) - Double(s) * 0.7
                            let op = (0.9 - Double(s) * 0.28)
                            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(Theme.accentLight.opacity(op)))
                        }
                    }

                    // Nodes — soft glow + breathing core.
                    for (i, n) in pts.enumerated() where i != 0 {     // hub hidden under logo
                        let p = P(n)
                        let pulse = 1 + 0.18 * sin(t * 1.6 + Double(i))
                        let r = 3.6 * pulse
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.2, y: p.y - r * 2.2,
                                                        width: r * 4.4, height: r * 4.4)),
                                 with: .color(Theme.accent.opacity(0.12)))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Theme.accentDeep.opacity(0.85)))
                    }
                }
            }
            .frame(width: size, height: size)

            PrivaLogo(size: logoSize)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        Color(white: 0.97)
        MeshNetworkView()
    }
    .ignoresSafeArea()
}
