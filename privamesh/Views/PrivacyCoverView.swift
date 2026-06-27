//
//  PrivacyCoverView.swift
//  privamesh
//
//  Full-screen cover shown in iOS app switcher / when app is backgrounded.
//  Hides sensitive content (balance, messages) from screenshots.
//

import SwiftUI

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            PastelBackground()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .opacity(0.35)
                    PrivaLogo(size: 72)
                }
                Text("PrivaMesh")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.slate800)
            }
        }
    }
}

#Preview {
    PrivacyCoverView()
}
