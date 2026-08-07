//
//  IdentityAvatarView.swift
//  privamesh
//
//  Default avatar in the brand's language: a monochrome mesh-network disc — the
//  same white-hairlines-on-black look as the logo — with the first letter of the
//  name set large on top. The mesh is seeded by that letter, so every contact
//  whose name starts with the same letter shares one clean, consistent default
//  (A always looks like A), and there is one avatar per letter A–Z (0–9 / # too).
//

import SwiftUI

struct MeshAvatarView: View {
    let id: String
    /// Display name. Its first letter becomes the glyph and seeds the mesh. When
    /// nil (older call sites that only have a key), the id is used as the seed and
    /// its first alphanumeric character as the glyph.
    var name: String? = nil
    var size: CGFloat = 48

    // MARK: - Glyph + seed

    /// The single character shown — first letter/number of the name (or id).
    private var glyph: String {
        if let c = (name ?? "").first(where: { $0.isLetter || $0.isNumber }) {
            return String(c).uppercased()
        }
        if let c = id.first(where: { $0.isLetter || $0.isNumber }) {
            return String(c).uppercased()
        }
        return "#"
    }
    /// Everyone sharing a glyph shares a mesh — the default is per-letter, so the
    /// seed is the glyph, not the full identity.
    private var seed: UInt32 { Self.hash(glyph) }

    private static func hash(_ s: String) -> UInt32 {
        var h: Int32 = 0
        for c in s.unicodeScalars { h = 31 &* h &+ Int32(truncatingIfNeeded: c.value) }
        return UInt32(bitPattern: h)
    }
    private static func rnd(_ seed: UInt32, _ i: UInt32) -> Double {
        let s = seed &* 1664525 &+ i &* 1013904223 &+ 12345
        return Double(s) / Double(UInt32.max)
    }

    // MARK: - Mesh (seeded by the glyph, projected like the logo sphere)

    private struct Mesh { let nodes: [CGPoint]; let edges: [(Int, Int)]; let focal: Int }

    private func buildMesh() -> Mesh {
        // Points spread on a disc, biased toward a ring so the mesh reads as the
        // silhouette of a sphere rather than a flat scatter.
        let count = 9
        let c = CGPoint(x: size/2, y: size/2)
        var nodes: [CGPoint] = []
        var depth: [Double] = []
        for i in 0..<count {
            let a = Self.rnd(seed, UInt32(i*3 + 1)) * 2 * .pi
            let rr = 0.30 + 0.62 * Self.rnd(seed, UInt32(i*3 + 2))   // 0.30…0.92 of radius
            let R = size * 0.46 * rr
            nodes.append(CGPoint(x: c.x + CGFloat(cos(a)) * R, y: c.y + CGFloat(sin(a)) * R))
            depth.append(Self.rnd(seed, UInt32(i*3 + 3)))            // fake front/back for shading
        }
        // k-nearest-neighbour edges (k=2) — a light cage, never a dense web.
        var seen = Set<Int>(); var edges: [(Int, Int)] = []
        for i in 0..<count {
            let near = (0..<count).filter { $0 != i }
                .sorted { hypot(nodes[i].x-nodes[$0].x, nodes[i].y-nodes[$0].y)
                        < hypot(nodes[i].x-nodes[$1].x, nodes[i].y-nodes[$1].y) }
                .prefix(2)
            for j in near {
                let lo = min(i,j), hi = max(i,j), k = lo*100+hi
                if seen.insert(k).inserted { edges.append((lo, hi)) }
            }
        }
        let focal = depth.indices.max { depth[$0] < depth[$1] } ?? 0
        return Mesh(nodes: nodes, edges: edges, focal: focal)
    }

    // MARK: - View

    var body: some View {
        let mesh = buildMesh()
        ZStack {
            // Logo ground: near-black disc with a faint central lift.
            Circle().fill(Color(white: 0.10))
            Circle().fill(RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .init(x: 0.5, y: 0.44), startRadius: 0, endRadius: size * 0.6))

            Canvas { ctx, sz in
                var path = Path()
                for (a, b) in mesh.edges {
                    path.move(to: mesh.nodes[a]); path.addLine(to: mesh.nodes[b])
                }
                ctx.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: max(0.5, sz.width * 0.014))
                let r = sz.width * 0.028
                for (i, n) in mesh.nodes.enumerated() {
                    let rr = i == mesh.focal ? r * 1.7 : r
                    let op = i == mesh.focal ? 0.85 : 0.45
                    ctx.fill(Path(ellipseIn: CGRect(x: n.x-rr, y: n.y-rr, width: rr*2, height: rr*2)),
                             with: .color(.white.opacity(op)))
                }
            }
            .clipShape(Circle())

            // Hairline rim — the sphere's horizon, in miniature.
            Circle().strokeBorder(.white.opacity(0.14), lineWidth: max(0.5, size * 0.012))

            Text(glyph)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    let letters = ["A","B","C","D","E","F","G","M","R","Z"]
    return ZStack {
        Color.black
        VStack(spacing: 14) {
            ForEach([0, 5], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(letters[row..<min(row+5, letters.count)], id: \.self) { l in
                        MeshAvatarView(id: l, name: l, size: 60)
                    }
                }
            }
        }
    }
    .ignoresSafeArea()
}
