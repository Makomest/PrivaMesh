//
//  PhotoEncryptor.swift
//  privamesh
//
//  Compresses a photo to fit Irys free tier (<100 KB),
//  then encrypts/decrypts with AES-256-GCM.
//

import Foundation
import CryptoKit

#if os(iOS)
import UIKit
#endif

enum PhotoError: LocalizedError {
    case compressionFailed
    case encryptionFailed
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Photo is too large to send"
        case .encryptionFailed:  return "Photo encryption failed"
        case .invalidKey:        return "Invalid photo decryption key"
        }
    }
}

enum PhotoEncryptor {
    /// Max plaintext bytes before encryption. Stays under Irys 100 KB free tier.
    static let maxBytes = 75_000

    // MARK: - Compression (iOS only)

#if os(iOS)
    /// Resize to 1200px max side, then compress to JPEG until ≤ maxBytes.
    static func compressForSend(_ image: UIImage) throws -> Data {
        let maxDim: CGFloat = 1200
        let w = image.size.width, h = image.size.height
        let sized: UIImage
        if max(w, h) > maxDim {
            let s = maxDim / max(w, h)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: w * s, height: h * s))
            sized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: w * s, height: h * s))) }
        } else {
            sized = image
        }
        var quality = 0.8
        while quality >= 0.05 {
            if let d = sized.jpegData(compressionQuality: quality), d.count <= maxBytes { return d }
            quality -= 0.1
        }
        throw PhotoError.compressionFailed
    }
#endif

    // MARK: - Encrypt / Decrypt

    static func encrypt(_ data: Data) throws -> (encrypted: Data, keyBase64: String) {
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw PhotoError.encryptionFailed }
        let keyBytes = key.withUnsafeBytes { Data($0) }
        return (combined, keyBytes.base64EncodedString())
    }

    static func decrypt(_ combined: Data, keyBase64: String) throws -> Data {
        guard let keyData = Data(base64Encoded: keyBase64) else { throw PhotoError.invalidKey }
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }
}
