//
//  PastelBackground.swift
//  privamesh
//

import SwiftUI

struct PastelBackground: View {
    @Environment(\.colorScheme) private var scheme

    // Static mesh (perf: no per-frame redraw). Adapts to a deep slate/teal mesh
    // in dark mode so adaptive text + glass surfaces read correctly.
    private let lightColors: [Color] = [
        Color(red: 0.80, green: 0.96, blue: 0.95),
        Color(red: 0.74, green: 0.87, blue: 1.00),
        Color(red: 0.88, green: 0.79, blue: 1.00),
        Color(red: 0.72, green: 0.97, blue: 0.91),
        Color(red: 0.93, green: 0.96, blue: 1.00),
        Color(red: 0.87, green: 0.80, blue: 1.00),
        Color(red: 0.76, green: 0.97, blue: 0.87),
        Color(red: 0.79, green: 0.90, blue: 1.00),
        Color(red: 0.91, green: 0.83, blue: 1.00),
    ]
    private let darkColors: [Color] = [
        Color(red: 0.05, green: 0.13, blue: 0.16),
        Color(red: 0.04, green: 0.08, blue: 0.16),
        Color(red: 0.09, green: 0.06, blue: 0.18),
        Color(red: 0.04, green: 0.14, blue: 0.14),
        Color(red: 0.06, green: 0.09, blue: 0.13),
        Color(red: 0.08, green: 0.06, blue: 0.16),
        Color(red: 0.04, green: 0.13, blue: 0.12),
        Color(red: 0.05, green: 0.09, blue: 0.15),
        Color(red: 0.08, green: 0.06, blue: 0.15),
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
