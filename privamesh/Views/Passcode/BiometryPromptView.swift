//
//  BiometryPromptView.swift
//  privamesh
//

import SwiftUI

struct BiometryPromptView: View {
    @Environment(AppRouter.self) private var router
    @Environment(BiometryService.self) private var biometry

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: biometry.kind.systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(.tint)

                Text("Включить \(biometry.kind.label)?")
                    .font(.title2.bold())

                Text("Будешь разблокировать приложение биометрией вместо ввода пароля каждый раз.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    enable()
                } label: {
                    Text("Включить \(biometry.kind.label)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)

                Button("Пока нет") {
                    biometry.disable()
                    router.go(to: .main)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func enable() {
        Task {
            let success = await biometry.authenticate(reason: "Включить \(biometry.kind.label) для PrivaMesh")
            await MainActor.run {
                biometry.isEnabled = success
                router.go(to: .main)
            }
        }
    }
}

#Preview {
    BiometryPromptView()
        .environment(AppRouter())
        .environment(BiometryService())
}
