//
//  PrivaLogo.swift
//  privamesh
//
//  PrivaMesh brand mark — a privacy "mesh" of connected nodes on a teal tile,
//  matching the app icon. Used across onboarding, headers, QR centre, etc.
//

import SwiftUI

struct PrivaLogo: View {
    var size: CGFloat = 28

    // Normalized node positions (x, y, radius scale).
    private static let nodes: [(CGFloat, CGFloat, CGFloat)] = [
        (0.50, 0.26, 1.15),  // top
        (0.28, 0.50, 1.0),   // left
        (0.72, 0.50, 1.0),   // right
        (0.50, 0.50, 1.35),  // center (hub)
        (0.34, 0.74, 1.0),   // bottom-left
        (0.66, 0.74, 1.0),   // bottom-right
    ]
    private static let edges = [(0,1),(0,2),(0,3),(3,1),(3,2),(3,4),(3,5),(1,4),(2,5),(4,5)]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 9/32, style: .continuous)
                .fill(Theme.accentGradient)

            Canvas { ctx, sz in
                func p(_ i: Int) -> CGPoint {
                    CGPoint(x: Self.nodes[i].0 * sz.width, y: Self.nodes[i].1 * sz.height)
                }
                // Edges.
                var path = Path()
                for (a, b) in Self.edges { path.move(to: p(a)); path.addLine(to: p(b)) }
                ctx.stroke(path, with: .color(.white.opacity(0.6)),
                           style: StrokeStyle(lineWidth: max(0.8, sz.width * 0.03), lineCap: .round))
                // Nodes.
                let base = sz.width * 0.07
                for (i, n) in Self.nodes.enumerated() {
                    let r = base * n.2
                    let pt = p(i)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(i == 3 ? 1 : 0.95)))
                }
            }
            .padding(size * 0.04)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        PrivaLogo(size: 28)
        PrivaLogo(size: 48)
        PrivaLogo(size: 80)
    }
    .padding()
}
