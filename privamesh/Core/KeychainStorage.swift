//
//  KeychainStorage.swift
//  privamesh
//

import Foundation
import Security
import LocalAuthentication

enum KeychainStorageError: Error {
    case unhandled(status: OSStatus)
    case decodingFailed
    case encodingFailed
}

enum KeychainKey: String {
    case seedPhrase = "privamesh.seedPhrase"
    case publicKey = "privamesh.publicKey"
}

struct KeychainStorage {
    private static let service = "com.privamesh.wallet"

    /// Access control requiring the user's presence (Face ID / Touch ID, with
    /// device-passcode fallback) on every read. `.userPresence` survives a
    /// biometric enrollment change (unlike `.biometryCurrentSet`), so adding a
    /// face/finger never bricks the stored seed.
    private static func userPresenceACL() -> SecAccessControl? {
        SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil)
    }

    static func save(_ value: String, for key: KeychainKey, requireBiometry: Bool = false) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStorageError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        if requireBiometry, let acl = userPresenceACL() {
            attributes[kSecAttrAccessControl as String] = acl
        } else {
            // The public key isn't secret and is needed at launch — including a
            // background/pre-warm launch while the device is still locked. With
            // WhenUnlocked that read fails intermittently (errSecInteractionNotAllowed)
            // and the app wrongly shows Welcome ("logged out"); a manual relaunch
            // when unlocked fixes it. AfterFirstUnlock is readable whenever the
            // device has been unlocked at least once since boot, so it doesn't.
            attributes[kSecAttrAccessible as String] = (key == .publicKey)
                ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStorageError.unhandled(status: status)
        }
    }

    static func read(_ key: KeychainKey, context: LAContext? = nil, prompt: String? = nil) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        if let prompt { query[kSecUseOperationPrompt as String] = prompt }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStorageError.unhandled(status: status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainStorageError.decodingFailed
        }

        return string
    }

    static func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func wipeAll() {
        delete(.seedPhrase)
        delete(.publicKey)
    }

    // MARK: - Raw string key + Data overloads (for messaging layer)

    static func save(key: String, data: Data, requireBiometry: Bool = false) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        if requireBiometry, let acl = userPresenceACL() {
            attributes[kSecAttrAccessControl as String] = acl
        } else {
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(key: String, context: LAContext? = nil, prompt: String? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        if let prompt { query[kSecUseOperationPrompt as String] = prompt }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
