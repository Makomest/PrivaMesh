//
//  PhotoBubble.swift
//  privamesh
//
//  Async photo bubble: downloads from Arweave, decrypts, and displays.
//

import SwiftUI

struct PhotoBubble: View {
    let txId: String
    let keyBase64: String
    let isOutgoing: Bool

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if failed {
                Label("Photo unavailable", systemImage: "photo.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.slate400)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.glassStroke)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 120, height: 120)
                    ProgressView().tint(Theme.accent)
                }
            }
        }
        .task(id: txId) { await load() }
    }

    private func load() async {
        do {
            let encrypted = try await IrysUploader.download(txId: txId)
            let decrypted = try PhotoEncryptor.decrypt(encrypted, keyBase64: keyBase64)
            #if os(iOS)
            if let uiImage = UIImage(data: decrypted) {
                image = Image(uiImage: uiImage)
            } else {
                failed = true
            }
            #else
            failed = true
            #endif
        } catch {
            failed = true
        }
    }
}
