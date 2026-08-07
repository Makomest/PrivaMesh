//
//  PrivacyCoverView.swift
//  privamesh
//
//  Full-screen cover shown in iOS app switcher / when app is backgrounded.
//  Hides sensitive content (balance, messages) from screenshots.
//

import SwiftUI

struct PrivacyCoverView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Match the new brand identity (dark, monochrome geodesic sphere —
            // the same mark as the app icon), NOT the old teal mesh logo.
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                NetworkSphereView(diameter: 132, reduced: reduceMotion)
                Text("PrivaMesh")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    PrivacyCoverView()
}
