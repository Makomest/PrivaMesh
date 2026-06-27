//
//  IdentityAvatarView.swift
//  privamesh
//
//  Deterministic mesh-network avatar. Same ID always produces the same
//  color palette, node layout, and label — matches MeshAvatar.tsx exactly.
//

import SwiftUI

struct MeshAvatarView: View {
    let id: String
    var size: CGFloat = 48

    // MARK: - Palette (matches MeshAvatar.tsx PALETTES)

    private static let palettes: [(Color, Color)] = [
        (Color(red: 0.204, green: 0.827, blue: 0.600), Color(red: 0.024, green: 0.714, blue: 0.831)),
        (Color(red: 0.506, green: 0.549, blue: 0.973), Color(red: 0.220, green: 0.737, blue: 0.973)),
        (Color(red: 0.957, green: 0.447, blue: 0.714), Color(red: 0.984, green: 0.443, blue: 0.522)),
        (Color(red: 0.984, green: 0.573, blue: 0.188), Color(red: 0.984, green: 0.749, blue: 0.141)),
        (Color(red: 0.655, green: 0.545, blue: 0.980), Color(red: 0.204, green: 0.827, blue: 0.600)),
        (Color(red: 0.220, green: 0.737, blue: 0.973), Color(red: 0.506, green: 0.549, blue: 0.973)),
        (Color(red: 0.302, green: 0.871, blue: 0.500), Color(red: 0.639, green: 0.894, blue: 0.208)),
        (Color(red: 0.957, green: 0.247, blue: 0.369), Color(red: 0.655, green: 0.545, blue: 0.980)),
    ]

    // MARK: - Hash (matches hash() in MeshAvatar.tsx)

    private static func hash(_ s: String) -> UInt32 {
        var h: Int32 = 0
        for c in s.unicodeScalars {
            h = 31 &* h &+ Int32(truncatingIfNeeded: c.value)
        }
        return UInt32(bitPattern: h)
    }

    private static func seededFloat(seed: UInt32, index: UInt32) -> Double {
        let s = seed &* 1664525 &+ index &* 1013904223
        return Double(s) / Double(UInt32.max)
    }

    // MARK: - Mesh data

    private struct MeshData {
        let from: Color
        let to: Color
        let nodes: [CGPoint]
        let edges: [(Int, Int)]
        let label: String
    }

    private func buildMesh() -> MeshData {
        let h = Self.hash(id)
        let palette = Self.palettes[Int(h % 8)]

        let count = 5 + Int(h % 3)
        var nodes: [CGPoint] = []
        for i in 0..<count {
            let col = i % 3
            let row = i / 3
            let base   = size * 0.15
            let step   = size * 0.30
            let jx = CGFloat(Self.seededFloat(seed: h, index: UInt32(i * 7 + 1))) * size * 0.12
            let jy = CGFloat(Self.seededFloat(seed: h, index: UInt32(i * 7 + 2))) * size * 0.12
            nodes.append(CGPoint(x: base + CGFloat(col) * step + jx,
                                 y: base + CGFloat(row) * step + jy))
        }

        let threshold = size * 0.55
        var edges: [(Int, Int)] = []
        for a in 0..<nodes.count {
            for b in (a + 1)..<nodes.count {
                let dx = nodes[a].x - nodes[b].x
                let dy = nodes[a].y - nodes[b].y
                if sqrt(dx * dx + dy * dy) < threshold { edges.append((a, b)) }
            }
        }

        return MeshData(from: palette.0, to: palette.1,
                        nodes: nodes, edges: edges,
                        label: String(id.prefix(4)))
    }

    // MARK: - View

    var body: some View {
        let mesh = buildMesh()

        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [mesh.from, mesh.to],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Canvas { ctx, sz in
                var path = Path()
                for (a, b) in mesh.edges {
                    path.move(to: mesh.nodes[a])
                    path.addLine(to: mesh.nodes[b])
                }
                ctx.stroke(path,
                           with: .color(.white.opacity(0.35)),
                           lineWidth: sz.width * 0.025)

                let dotR = sz.width * 0.055
                for node in mesh.nodes {
                    let r = CGRect(x: node.x - dotR, y: node.y - dotR,
                                   width: dotR * 2, height: dotR * 2)
                    ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.70)))
                }
            }
            .clipShape(Circle())

            Text(mesh.label)
                .font(.system(size: size * 0.22, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.95))
                .offset(y: size * 0.07)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 12) {
        MeshAvatarView(id: "7xKp...3mQr", size: 64)
        MeshAvatarView(id: "9nRz...8wKv", size: 64)
        MeshAvatarView(id: "2pJn...6sLw", size: 64)
    }
    .padding()
}
