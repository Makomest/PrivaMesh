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

    // MARK: - Primary accent — greyscale only, no hue anywhere in the product.
    // These stay DARK on purpose: ~34 call sites fill a control with
    // `accentGradient` and label it `.foregroundStyle(.white)`. A white accent
    // would render white-on-white. Dark grey + white label is the safe monochrome
    // equivalent and reads as a standard filled iOS control.
    /// FILL role (~40 sites): a control's background, almost always labelled
    /// `.foregroundStyle(.white)`. Must stay dark in both modes.
    static let accent = Color(white: 0.30)
    static let accentLight = Color(white: 0.38)
    /// TEXT/ICON/TINT role (~49 sites): drawn ON a background, so it has to
    /// invert with the mode — a fixed dark grey vanished on the dark sheets.
    /// Teal carried both roles at once; greyscale cannot, so the roles split here.
    static let accentDeep = dyn((64, 64, 64, 1), (205, 205, 205, 1))
    static let cyan = Color(white: 0.34)

    // Fixed near-black ink for QR modules — max scan contrast on white, both modes
    static let qrInk = Color(white: 0.05)

    // MARK: - Secondary tones (were pastels)
    static let sky = Color(white: 0.62)
    static let violet = Color(white: 0.54)
    static let emerald = Color(white: 0.70)

    // MARK: - Neutrals (adaptive — flip toward light in dark mode)
    static let slate900 = dyn((17, 17, 17, 1),    (248, 248, 248, 1))   // primary text
    static let slate800 = dyn((38, 38, 38, 1),    (229, 229, 229, 1))
    static let slate700 = dyn((64, 64, 64, 1),    (212, 212, 212, 1))
    static let slate600 = dyn((82, 82, 82, 1),    (180, 180, 180, 1))
    static let slate500 = dyn((115, 115, 115, 1), (150, 150, 150, 1))   // secondary
    static let slate400 = dyn((163, 163, 163, 1), (125, 125, 125, 1))   // tertiary/placeholder
    static let slate300 = dyn((212, 212, 212, 1), (64, 64, 64, 1))      // dividers

    // MARK: - Glass surfaces (adaptive)
    static let glass = dyn((255, 255, 255, 0.55), (255, 255, 255, 0.07))      // card fill
    static let glassStrong = dyn((255, 255, 255, 0.70), (255, 255, 255, 0.12))
    static let glassStroke = dyn((255, 255, 255, 0.50), (255, 255, 255, 0.12))

    // MARK: - Semantic
    // Greyscale too, per the monochrome direction. Note this drops the red that
    // iOS users read as "destructive" — delete/block now rely on wording alone.
    static let positive = Color(white: 0.72)
    static let negative = Color(white: 0.92)   // loudest grey we have = most urgent
    static let warning = Color(white: 0.82)

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

// ThemeMode removed: the app ships dark-only (UIUserInterfaceStyle=Dark). The
// orbit chat surface is a fixed monochrome dark world, so an appearance picker
// could only have repainted the secondary screens — a control that visibly does
// nothing, which is what App Review 2.1(a) flagged.
