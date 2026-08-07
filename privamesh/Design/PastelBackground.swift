//
//  PastelBackground.swift
//  privamesh
//

import SwiftUI

struct PastelBackground: View {
    @Environment(\.colorScheme) private var scheme

    // Static mesh (perf: no per-frame redraw). Greyscale only — the mesh now
    // reads as a soft light gradient rather than a colour field, so it sits under
    // the monochrome sheets without introducing a hue.
    private let lightColors: [Color] = [
        Color(white: 0.97), Color(white: 0.93), Color(white: 0.90),
        Color(white: 0.95), Color(white: 0.99), Color(white: 0.91),
        Color(white: 0.94), Color(white: 0.96), Color(white: 0.89),
    ]
    private let darkColors: [Color] = [
        Color(white: 0.09), Color(white: 0.05), Color(white: 0.08),
        Color(white: 0.06), Color(white: 0.10), Color(white: 0.05),
        Color(white: 0.07), Color(white: 0.04), Color(white: 0.08),
    ]

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5],
                [0.45, 0.48],
                [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: scheme == .dark ? darkColors : lightColors
        )
        .ignoresSafeArea()
    }
}

#Preview {
    PastelBackground()
}
