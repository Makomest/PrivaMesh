//
//  PasscodeManager.swift
//  privamesh
//

import Foundation
import CryptoKit
import Security

enum PasscodeError: Error {
    case storageFailed
    case notSet
}

@Observable
final class PasscodeManager {
    private static let service = "com.privamesh.passcode"
    private static let hashKey = "passcodeHash"
    private static let saltKey = "passcodeSalt"
    private static let lengthKey = "privamesh.passcode.length"
    private static let attemptsKey  = "privamesh.passcode.failedAttempts"
    private static let lockUntilKey = "privamesh.passcode.lockUntil"

    /// Brute-force throttle: free attempts before a cooldown kicks in.
    private static let freeAttempts = 5

    var passcodeLength: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.lengthKey)
        return stored == 4 ? 4 : 6
    }

    private var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: Self.attemptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.attemptsKey) }
    }
    private var lockUntil: Date? {
        get { UserDefaults.standard.object(forKey: Self.lockUntilKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lockUntilKey) }
    }

    /// Seconds left in a brute-force cooldown (0 = may attempt now). UI shows this.
    var lockoutRemaining: TimeInterval {
        guard let lockUntil else { return 0 }
        return max(0, lockUntil.timeIntervalSinceNow)
    }

    private func resetAttempts() {
        UserDefaults.standard.removeObject(forKey: Self.attemptsKey)
        UserDefaults.standard.removeObject(forKey: Self.lockUntilKey)
    }

    /// In-memory session unlock state. Resets when app fully restarts.
    var isUnlocked: Bool = false

    /// Seconds in background after which app should re-prompt for passcode/biometry.
    var autoLockSeconds: TimeInterval = 30

    private var backgroundedAt: Date?

    var isPasscodeSet: Bool {
        readKeychain(key: Self.hashKey) != nil
    }

    init() {
        if !isPasscodeSet {
            isUnlocked = true
        }
    }

    func setPasscode(_ passcode: String, length: Int = 6) throws {
        let salt = Self.randomSalt()
        let hash = Self.derive(passcode: passcode, salt: salt)

        guard
            writeKeychain(key: Self.saltKey, data: salt),
            writeKeychain(key: Self.hashKey, data: hash)
        else {
            throw PasscodeError.storageFailed
        }

        UserDefaults.standard.set(length, forKey: Self.lengthKey)
        isUnlocked = true
        resetAttempts()
    }

    func verify(_ passcode: String) -> Bool {
        // Refuse during a brute-force cooldown (offline guessing throttle).
        guard lockoutRemaining == 0 else { return false }
        guard
            let storedHash = readKeychain(key: Self.hashKey),
            let salt = readKeychain(key: Self.saltKey)
        else {
            return false
        }

        let attemptHash = Self.derive(passcode: passcode, salt: salt)
        let match = constantTimeCompare(storedHash, attemptHash)
        if match {
            isUnlocked = true
            resetAttempts()
        } else {
            failedAttempts += 1
            if failedAttempts >= Self.freeAttempts {
                // Escalating cooldown: 30s, 60s, 2m, 4m … capped at 1h.
                let over = failedAttempts - Self.freeAttempts
                let delay = min(3600, 30 * pow(2.0, Double(over)))
                lockUntil = Date(timeIntervalSinceNow: delay)
            }
        }
        return match
    }

    func lock() {
        isUnlocked = false
    }

    /// Mark session as unlocked via biometry (skips passcode hash verification).
    /// Use only after BiometryService.authenticate() succeeded.
    func markUnlockedByBiometry() {
        isUnlocked = true
        backgroundedAt = nil
        resetAttempts()
    }

    /// Call when app goes to background.
    func noteBackgrounded() {
        backgroundedAt = Date()
    }

    /// Call when app returns to foreground.
    /// Returns true if app should re-lock (i.e. enough time passed and a passcode is set).
    func shouldRelockOnForeground() -> Bool {
        guard isPasscodeSet, let backgroundedAt else { return false }
        let elapsed = Date().timeIntervalSince(backgroundedAt)
        return elapsed >= autoLockSeconds
    }

    func wipe() {
        deleteKeychain(key: Self.hashKey)
        deleteKeychain(key: Self.saltKey)
        UserDefaults.standard.removeObject(forKey: Self.lengthKey)
        resetAttempts()
        isUnlocked = true
    }

    // MARK: - Hashing

    private static func derive(passcode: String, salt: Data) -> Data {
        let passcodeData = Data(passcode.utf8)
        var combined = Data()
        combined.append(salt)
        combined.append(passcodeData)
        // 100k rounds of SHA-256 — sufficient delay against brute force
        var hash = Data(SHA256.hash(data: combined))
        for _ in 0..<100_000 {
            hash = Data(SHA256.hash(data: hash + salt))
        }
        return hash
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private func constantTimeCompare(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count {
            diff |= a[i] ^ b[i]
        }
        return diff == 0
    }

    // MARK: - Keychain raw helpers (Data values for binary hash/salt)

    private func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private func writeKeychain(key: String, data: Data) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private func deleteKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
