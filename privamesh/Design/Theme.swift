//
//  Theme.swift
//  privamesh
//
//  Design tokens matching the Figma "Liquid Glass" PrivaMesh design.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum Theme {
    /// Adaptive color: `l` in light mode, `d` in dark. RGB 0–255, alpha 0–1.
    static func dyn(_ l: (Double, Double, Double, Double), _ d: (Double, Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { tc in
            let c = tc.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.0/255, green: c.1/255, blue: c.2/255, alpha: c.3)
        })
        #else
        return Color(red: l.0/255, green: l.1/255, blue: l.2/255).opacity(l.3)
        #endif
    }

    // MARK: - Primary accent (emerald → teal → cyan) — fixed brand, both modes
    static let accent = Color(red: 20/255, green: 184/255, blue: 166/255)        // teal-500
    static let accentLight = Color(red: 52/255, green: 211/255, blue: 153/255)   // emerald-400
    static let accentDeep = Color(red: 13/255, green: 148/255, blue: 136/255)    // teal-600
    static let cyan = Color(red: 34/255, green: 211/255, blue: 238/255)          // cyan-400

    // MARK: - Secondary pastels
    static let sky = Color(red: 125/255, green: 211/255, blue: 252/255)          // sky-300
    static let violet = Color(red: 196/255, green: 181/255, blue: 253/255)       // violet-300
    static let emerald = Color(red: 110/255, green: 231/255, blue: 183/255)      // emerald-300

    // MARK: - Slate neutrals (adaptive — flip toward light in dark mode)
    static let slate900 = dyn((15, 23, 42, 1),    (248, 250, 252, 1))   // primary text
    static let slate800 = dyn((30, 41, 59, 1),    (226, 232, 240, 1))
    static let slate700 = dyn((51, 65, 85, 1),    (203, 213, 225, 1))
    static let slate600 = dyn((71, 85, 105, 1),   (170, 182, 200, 1))
    static let slate500 = dyn((100, 116, 139, 1), (148, 163, 184, 1))   // secondary
    static let slate400 = dyn((148, 163, 184, 1), (120, 132, 150, 1))   // tertiary/placeholder
    static let slate300 = dyn((203, 213, 225, 1), (51, 65, 85, 1))      // dividers

    // MARK: - Glass surfaces (adaptive)
    static let glass = dyn((255, 255, 255, 0.55), (255, 255, 255, 0.07))      // card fill
    static let glassStrong = dyn((255, 255, 255, 0.70), (255, 255, 255, 0.12))
    static let glassStroke = dyn((255, 255, 255, 0.50), (255, 255, 255, 0.12))

    // MARK: - Semantic
    static let positive = Color(red: 16/255, green: 185/255, blue: 129/255)      // emerald-500
    static let negative = Color(red: 244/255, green: 63/255, blue: 94/255)       // rose-500
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)       // amber-500

    // MARK: - Gradients
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accentLight, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var logoGradient: LinearGradient {
        LinearGradient(
            colors: [accentLight, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var chartGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.5), accent.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Radii
    static let radiusSmall: CGFloat = 12
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 24
}

/// User-selectable appearance. Persisted via @AppStorage("privamesh.themeMode").
enum ThemeMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return String(localized: "Системная")
        case .light:  return String(localized: "Светлая")
        case .dark:   return String(localized: "Тёмная")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
