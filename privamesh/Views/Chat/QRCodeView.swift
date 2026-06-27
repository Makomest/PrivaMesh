//
//  QRCodeView.swift
//  privamesh
//
//  Stylised QR (Telegram-like): rounded dot modules, gradient fill, rounded
//  corner "eyes", and a logo in the centre. We read the raw QR matrix from
//  CoreImage and render it ourselves. Uses correction level "H" (30%) so the
//  centre logo never breaks scanning.
//

import SwiftUI
#if os(iOS)
import CoreImage.CIFilterBuiltins
#endif

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 200

    // Cache the matrix; generating it (CoreImage + pixel read) is expensive and
    // must not run on the main thread inside body on every render.
    @State private var matrix: [[Bool]] = []

    var body: some View {
        #if os(iOS)
        let n = matrix.count

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(.white)
                .shadow(color: Theme.accent.opacity(0.18), radius: 16, x: 0, y: 8)

            if n == 0 {
                ProgressView().tint(Theme.accent)
            }

            if n > 0 {
                Canvas { ctx, sz in
                    let quiet = sz.width * 0.10
                    let area  = sz.width - quiet * 2
                    let cell  = area / CGFloat(n)
                    let dot   = cell * 0.82

                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [Theme.accent, Theme.accentDeep]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: sz.width, y: sz.height)
                    )

                    // Data modules as rounded dots (skip finder eyes + centre logo).
                    var dots = Path()
                    let cMid = Double(n) / 2
                    let clear = Double(n) * 0.11
                    for r in 0..<n {
                        for c in 0..<n where matrix[r][c] {
                            if isFinder(r, c, n) { continue }
                            if abs(Double(r) - cMid) < clear && abs(Double(c) - cMid) < clear { continue }
                            let x = quiet + CGFloat(c) * cell + (cell - dot) / 2
                            let y = quiet + CGFloat(r) * cell + (cell - dot) / 2
                            dots.addEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
                        }
                    }
                    ctx.fill(dots, with: shading)

                    // Rounded corner "eyes".
                    for (or, oc) in [(0, 0), (0, n - 7), (n - 7, 0)] {
                        let x = quiet + CGFloat(oc) * cell
                        let y = quiet + CGFloat(or) * cell
                        let outer = CGRect(x: x, y: y, width: 7 * cell, height: 7 * cell)
                        var ring = Path(roundedRect: outer, cornerRadius: cell * 2.2)
                        ring.addRoundedRect(in: outer.insetBy(dx: cell, dy: cell),
                                            cornerSize: CGSize(width: cell * 1.5, height: cell * 1.5))
                        ctx.fill(ring, with: shading, style: FillStyle(eoFill: true))
                        let pupil = outer.insetBy(dx: cell * 2, dy: cell * 2)
                        ctx.fill(Path(roundedRect: pupil, cornerRadius: cell * 1.0), with: shading)
                    }
                }
                .frame(width: size, height: size)

                // Centre logo on a white disc.
                PrivaLogo(size: size * 0.16)
                    .padding(size * 0.035)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .task(id: text) {
            // Generate off the main thread so switching to the QR tab is instant.
            let t = text
            let m = await Task.detached(priority: .userInitiated) { QRMatrix.generate(t) }.value
            matrix = m ?? []
        }
        #else
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(Text("QR").foregroundStyle(.secondary))
        #endif
    }

    /// True if (r, c) falls inside one of the three 7×7 finder patterns.
    private func isFinder(_ r: Int, _ c: Int, _ n: Int) -> Bool {
        (r < 7 && c < 7) || (r < 7 && c >= n - 7) || (r >= n - 7 && c < 7)
    }
}

#if os(iOS)
enum QRMatrix {
    /// Decode a string into a boolean QR module grid (true = dark).
    static func generate(_ text: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        let w = Int(extent.width), h = Int(extent.height)
        guard w > 0, h > 0 else { return nil }

        let ciCtx = CIContext()
        guard let cg = ciCtx.createCGImage(output, from: extent) else { return nil }

        var data = [UInt8](repeating: 0, count: w * h)
        guard let gctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Flip so buffer row 0 == image top (preserve QR orientation → scannable).
        gctx.translateBy(x: 0, y: CGFloat(h))
        gctx.scaleBy(x: 1, y: -1)
        gctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var grid = [[Bool]](repeating: [Bool](repeating: false, count: w), count: h)
        for y in 0..<h {
            for x in 0..<w { grid[y][x] = data[y * w + x] < 128 }
        }

        // Crop the quiet zone: tighten to the bounding box of dark modules.
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where grid[y][x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minY...maxY).map { Array(grid[$0][minX...maxX]) }
    }
}
#endif
