//
//  NetworkSphereView.swift
//  privamesh
//
//  The brand mark, alive: the same geodesic network sphere as the app icon,
//  rendered in white hairlines on black and turning slowly. One node — "you" —
//  sits solid at the front. Shares the globe's visual language with the chats
//  surface so onboarding already looks like the app it opens into.
//

import SwiftUI

struct NetworkSphereView: View {
    /// Diameter of the sphere's bounding circle in points.
    var diameter: CGFloat = 150
    /// Whether to draw the faint hairline horizon ring (the clean silhouette).
    var horizon: Bool = true
    /// Turn speed in radians/sec. Slow enough to read as "alive", not spinning.
    var speed: Double = 0.22
    /// Line/node colour. White on black by default; pass a dark ink for use on a
    /// light ground (e.g. the centre of a QR code).
    var color: Color = .white
    var reduced: Bool = false

    var body: some View {
        TimelineView(.animation(paused: reduced)) { tl in
            let t = reduced ? 0 : tl.date.timeIntervalSinceReferenceDate * speed
            Canvas { ctx, size in Self.draw(ctx, size, yaw: t, color: color, horizon: horizon) }
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }

    // MARK: geometry (subdivided icosahedron — same as the app icon)

    private static let mesh: (verts: [SIMD3<Double>], edges: [(Int, Int)]) = {
        func unit(_ p: SIMD3<Double>) -> SIMD3<Double> {
            let n = (p.x*p.x + p.y*p.y + p.z*p.z).squareRoot()
            return n == 0 ? p : p / n
        }
        let t = (1 + 5.0.squareRoot()) / 2
        var verts: [SIMD3<Double>] = [
            [-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0],
            [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
            [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1],
        ].map { unit($0) }
        let faces: [(Int, Int, Int)] = [
            (0,11,5),(0,5,1),(0,1,7),(0,7,10),(0,10,11),(1,5,9),(5,11,4),(11,10,2),
            (10,7,6),(7,1,8),(3,9,4),(3,4,2),(3,2,6),(3,6,8),(3,8,9),(4,9,5),
            (2,4,11),(6,2,10),(8,6,7),(9,8,1),
        ]
        var mid: [Int: Int] = [:]
        func midpoint(_ a: Int, _ b: Int) -> Int {
            let key = min(a,b) * 100 + max(a,b)
            if let m = mid[key] { return m }
            let m = unit((verts[a] + verts[b]) / 2)
            verts.append(m); mid[key] = verts.count - 1
            return verts.count - 1
        }
        var edgeSet = Set<Int>()
        var edges: [(Int, Int)] = []
        func addEdge(_ a: Int, _ b: Int) {
            let lo = min(a,b), hi = max(a,b), k = lo * 1000 + hi
            if edgeSet.insert(k).inserted { edges.append((lo, hi)) }
        }
        for (a,b,c) in faces {
            let ab = midpoint(a,b), bc = midpoint(b,c), ca = midpoint(c,a)
            for (x,y) in [(a,ab),(ab,ca),(ca,a),(b,bc),(bc,ab),(ab,b),(c,ca),(ca,bc),(bc,c),(ab,bc),(bc,ca),(ca,ab)] {
                addEdge(x, y)
            }
        }
        // Orient a vertex to the camera so "you" projects to the centre, plus a
        // gentle fixed tilt for a 3D read.
        let v0 = verts[0]
        let ry = -atan2(v0.x, v0.z)
        let rho = (v0.x*v0.x + v0.z*v0.z).squareRoot()
        let rx = atan2(v0.y, rho)
        func orient(_ p: SIMD3<Double>) -> SIMD3<Double> {
            let x1 = p.x*cos(ry) + p.z*sin(ry)
            let z1 = -p.x*sin(ry) + p.z*cos(ry)
            var q = SIMD3(x1, p.y*cos(rx) - z1*sin(rx), p.y*sin(rx) + z1*cos(rx))
            // tilt -0.28 around X
            let a = -0.28
            q = SIMD3(q.x, q.y*cos(a) - q.z*sin(a), q.y*sin(a) + q.z*cos(a))
            return q
        }
        return (verts.map(orient), edges)
    }()

    private static func draw(_ ctx: GraphicsContext, _ size: CGSize, yaw: Double,
                             color: Color = .white, horizon: Bool = true) {
        let c = CGPoint(x: size.width/2, y: size.height/2)
        let R = min(size.width, size.height) * 0.47
        let cy = cos(yaw), sy = sin(yaw)
        // Rotate the pre-oriented mesh around the vertical axis for the live turn.
        var P: [SIMD3<Double>] = []
        for v in mesh.verts {
            let x = v.x*cy + v.z*sy
            let z = -v.x*sy + v.z*cy
            P.append(SIMD3(x, v.y, z))
        }
        func proj(_ p: SIMD3<Double>) -> CGPoint { CGPoint(x: c.x + p.x*R, y: c.y - p.y*R) }
        func depth(_ p: SIMD3<Double>) -> Double { (p.z + 1) / 2 }
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b-a)*t }
        // "You" is a FIXED vertex (0), so it rides the rotation smoothly. Picking
        // the frontmost vertex each frame made the solid dot jump from node to node
        // as the sphere turned — it teleported. Vertex 0 was oriented to the camera
        // at build, so it starts centred and simply orbits from there.
        let focal = 0

        // hairline horizon
        if horizon {
            let rect = CGRect(x: c.x - R, y: c.y - R, width: R*2, height: R*2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.20)), lineWidth: 1.2)
        }
        // depth-sorted draw queue (painter's algorithm)
        enum Item { case edge(Int, Int, Double); case node(Int, Double) }
        var items: [(Double, Item)] = []
        for (a,b) in mesh.edges {
            let sh = pow((depth(P[a]) + depth(P[b]))/2, 1.35)
            items.append((sh, .edge(a, b, sh)))
        }
        for i in P.indices { items.append((pow(depth(P[i]), 1.35), .node(i, pow(depth(P[i]), 1.35)))) }
        items.sort { $0.0 < $1.0 }
        for (_, it) in items {
            switch it {
            case let .edge(a, b, sh):
                var path = Path(); path.move(to: proj(P[a])); path.addLine(to: proj(P[b]))
                ctx.stroke(path, with: .color(color.opacity(lerp(0.08, 0.85, sh))), lineWidth: 1.3)
            case let .node(i, sh):
                let p = proj(P[i])
                if i == focal {
                    let r = R * 0.058
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                             with: .color(color.opacity(lerp(0.5, 1.0, depth(P[i])))))
                } else if depth(P[i]) >= 0.4 {
                    let r = R * 0.032
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x-r, y: p.y-r, width: r*2, height: r*2)),
                             with: .color(color.opacity(lerp(0.45, 1.0, sh))))
                }
            }
        }
    }
}

#Preview {
    ZStack { Color.black; NetworkSphereView(diameter: 220) }.ignoresSafeArea()
}
