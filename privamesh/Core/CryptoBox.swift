//
//  CryptoBox.swift
//  privamesh
//
//  Low-level cryptographic primitives used by the Double Ratchet layer.
//

import Foundation
import CryptoKit

// MARK: - Errors

enum CryptoError: Error, LocalizedError {
    case invalidKey
    case invalidSignature
    case invalidPadding
    case invalidData
    case decryptionFailed
    case missingChainKey
    case tooManySkippedMessages

    var errorDescription: String? {
        switch self {
        case .invalidKey:               return "Invalid cryptographic key"
        case .invalidSignature:         return "Bundle signature verification failed"
        case .invalidPadding:           return "Message padding is corrupt"
        case .invalidData:              return "Malformed data"
        case .decryptionFailed:         return "Decryption failed (wrong key or tampered data)"
        case .missingChainKey:          return "Ratchet chain key not initialized"
        case .tooManySkippedMessages:   return "Too many consecutive skipped messages"
        }
    }
}

// MARK: - Primitives

enum CryptoBox {
    /// X25519 Diffie-Hellman — returns raw 32-byte shared secret.
    static func dh(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return shared.withUnsafeBytes { Data($0) }
    }

    /// HKDF-SHA256.
    static func hkdf(inputKeyMaterial: Data, salt: Data, info: Data, outputByteCount: Int) -> Data {
        let result = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKeyMaterial),
            salt: salt,
            info: info,
            outputByteCount: outputByteCount
        )
        return result.withUnsafeBytes { Data($0) }
    }

    /// HMAC-SHA256.
    static func hmac(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    /// AES-256-GCM encrypt. Returns combined bytes: 12-byte nonce ‖ ciphertext ‖ 16-byte tag.
    static func encrypt(plaintext: Data, key: Data, associatedData: Data = Data()) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: associatedData)
        guard let combined = box.combined else { throw CryptoError.invalidData }
        return combined
    }

    /// AES-256-GCM decrypt.
    static func decrypt(combined: Data, key: Data, associatedData: Data = Data()) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: associatedData)
        } catch is CryptoKitError {
            throw CryptoError.decryptionFailed
        }
    }
}
