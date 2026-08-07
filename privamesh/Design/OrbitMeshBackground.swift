//
//  OrbitMeshBackground.swift
//  privamesh
//
//  Black ground with a faint mesh texture — the same wireframe language as the
//  contact globe, so a chat feels like a place inside the same world. Static and
//  deterministic: no per-frame redraw, and the pattern never jumps between
//  appearances.
//

import SwiftUI

struct OrbitMeshBackground: View {
    /// How strongly the mesh reads. It is texture, not decoration — keep it low.
    var intensity: Double = 1.0

    private static let pointCount = 30

    /// Deterministic point field (seeded LCG, not `random()`), normalised 0…1.
    private static let points: [CGPoint] = {
        var seed: UInt64 = 0x9E3779B9
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        return (0..<pointCount).map { _ in CGPoint(x: next(), y: next()) }
    }()

    /// Each point wired to its 2 nearest neighbours — enough to read as a mesh,
    /// sparse enough to stay behind the content.
    private static let edges: [(Int, Int)] = {
        var seen = Set<Int>()
        var out: [(Int, Int)] = []
        for i in points.indices {
            let near = points.indices
                .filter { $0 != i }
                .sorted { sq(points[i], points[$0]) < sq(points[i], points[$1]) }
                .prefix(2)
            for j in near {
                let lo = min(i, j), hi = max(i, j)
                if seen.insert(lo * 1000 + hi).inserted { out.append((lo, hi)) }
            }
        }
        return out
    }()

    private static func sq(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return Double(dx*dx + dy*dy)
    }

    var body: some View {
        ZStack {
            Color.black
            // A soft lift so the mesh has something to sit in and the black
            // doesn't read as a dead void.
            RadialGradient(colors: [Color(white: 0.075), .black.opacity(0)],
                           center: .init(x: 0.5, y: 0.32), startRadius: 0, endRadius: 460)

            // Broad, soft light. This is what glass on top actually refracts:
            // a 0.5pt mesh line does not survive a material's blur — it smears
            // to nothing and every panel above it comes out a flat grey slab.
            // Only large gradients read through frost, which is exactly what the
            // glassmorphism reference has behind its pane.
            if intensity > 1 {
                RadialGradient(colors: [Color.white.opacity(0.055 * intensity), .clear],
                               center: .init(x: 0.12, y: 0.18), startRadius: 0, endRadius: 300)
                RadialGradient(colors: [Color.white.opacity(0.04 * intensity), .clear],
                               center: .init(x: 0.9, y: 0.55), startRadius: 0, endRadius: 340)
                RadialGradient(colors: [Color.white.opacity(0.03 * intensity), .clear],
                               center: .init(x: 0.35, y: 0.88), startRadius: 0, endRadius: 280)
            }
            Canvas { ctx, size in
                let pts = Self.points.map {
                    CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                }
                for e in Self.edges {
                    var p = Path()
                    p.move(to: pts[e.0])
                    p.addLine(to: pts[e.1])
                    ctx.stroke(p, with: .color(.white.opacity(0.055 * intensity)), lineWidth: 0.5)
                }
                for p in pts {
                    let r = 1.4
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                             with: .color(.white.opacity(0.14 * intensity)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Frosted panel used by chat bubbles and other floating surfaces: material,
/// tinted back down (a material alone lightens to grey over black), plus a
/// hairline that catches light at the top-left.
struct OrbitGlassPanel: ViewModifier {
    var cornerRadius: CGFloat
    /// Outgoing messages sit slightly brighter than incoming — the only
    /// difference between the two, since there is no colour to spend.
    var emphasis: Double = 0

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.black.opacity(0.55 - 0.18*emphasis))
                    shape.fill(Color.white.opacity(0.05 + 0.07*emphasis))
                }
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.24 + 0.10*emphasis), .white.opacity(0.08), .white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.75)
            )
    }
}

extension View {
    func orbitGlassPanel(_ cornerRadius: CGFloat, emphasis: Double = 0) -> some View {
        modifier(OrbitGlassPanel(cornerRadius: cornerRadius, emphasis: emphasis))
    }
}

#Preview {
    ZStack {
        OrbitMeshBackground()
        Text("Сообщение").padding(14).orbitGlassPanel(18, emphasis: 1).foregroundStyle(.white)
    }
}
