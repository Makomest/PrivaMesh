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
    private static let duressHashKey = "passcodeDuressHash"
    private static let duressSaltKey = "passcodeDuressSalt"
    private static let lengthKey = "privamesh.passcode.length"
    private static let attemptsKey  = "privamesh.passcode.failedAttempts"
    private static let lockUntilKey = "privamesh.passcode.lockUntil"
    private static let migratedKey  = "privamesh.passcode.protectionMigrated"

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

    /// Whether this device has a passcode. When the Keychain cannot be read yet,
    /// assume YES: sending someone to "enter your passcode" one screen too early is
    /// harmless, while sending them to "create a passcode" overwrites the one they
    /// already have.
    var isPasscodeSet: Bool {
        switch read(key: Self.hashKey) {
        case .found:       return true
        case .missing:     return false
        case .unavailable: return true
        }
    }

    /// True only when we positively know there is no passcode. Used before writing
    /// a new one, so a temporary Keychain failure can never silently replace it.
    var isPasscodeConfirmedAbsent: Bool {
        if case .missing = read(key: Self.hashKey) { return true }
        return false
    }

    init() {
        // Only skip the lock screen when we are sure there is nothing to unlock.
        if isPasscodeConfirmedAbsent {
            isUnlocked = true
        }
    }

    /// Re-store the passcode hash under the current protection class.
    ///
    /// Installs from 1.0 wrote it as WhenUnlocked, which is unreadable until the
    /// device is unlocked once per boot; that is what made the app occasionally
    /// think no passcode existed. Rewriting is only possible while the item IS
    /// readable, so this runs whenever the app becomes active and is a no-op
    /// afterwards.
    func migrateProtectionClassIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.migratedKey) else { return }
        guard case let .found(hash) = read(key: Self.hashKey),
              case let .found(salt) = read(key: Self.saltKey) else { return }
        guard writeKeychain(key: Self.saltKey, data: salt),
              writeKeychain(key: Self.hashKey, data: hash) else { return }
        UserDefaults.standard.set(true, forKey: Self.migratedKey)
    }

    func setPasscode(_ passcode: String, length: Int = 6) throws {
        // Refuse a passcode that is already the duress code. `check` tests the real
        // passcode first, so the collision would resolve as "unlock": the duress
        // code would stop working silently, and the person relying on it would find
        // out at the moment they need it.
        if matchesDuress(passcode) { throw PasscodeError.storageFailed }

        let salt = Self.randomSalt()
        let hash = Self.derive(passcode: passcode, salt: salt)

        // The duress code is stored under this salt, so changing it invalidates
        // that hash. Dropped rather than silently kept: a duress code that no
        // longer matches anything is worse than none, because the person relying
        // on it does not know.
        deleteKeychain(key: Self.duressHashKey)

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

    /// What a code turned out to be.
    ///
    /// `duress` is the second code the user may set: entering it means "destroy
    /// this account", and the caller must wipe without warning, confirmation or
    /// any message afterwards. Someone is standing over them, and each of those
    /// tells that person a second code exists.
    enum Verification: Equatable {
        case correct
        case duress
        case incorrect
        /// Refused without being checked, because a cooldown is running.
        case lockedOut
        /// The Keychain could not answer. Never counted as a failed attempt.
        case unavailable
        case notSet
    }

    @discardableResult
    func verify(_ passcode: String) -> Bool {
        check(passcode) == .correct
    }

    func check(_ passcode: String) -> Verification {
        // A Keychain that cannot be read right now is not a wrong passcode, so it
        // must not burn an attempt or trigger the brute-force cooldown.
        switch (read(key: Self.hashKey), read(key: Self.saltKey)) {
        case let (.found(storedHash), .found(salt)):
            var duressHash: Data?
            if case let .found(hash) = read(key: Self.duressHashKey) { duressHash = hash }

            // One derivation, checked against both stored hashes.
            //
            // The duress code shares the passcode's salt for exactly this reason:
            // a second salt would mean a second key derivation on every unlock,
            // doubling the wait for everyone - and skipping it when the code did
            // not match would make the duress path measurably faster, which the
            // person standing over the user's shoulder is the one who would
            // notice. A salt's job is to make precomputation useless, and one per
            // device does that for both codes.
            let attemptHash = Self.derive(passcode: passcode, salt: salt)

            let matchesReal = constantTimeCompare(storedHash, attemptHash)
            let matchesDuress: Bool = {
                guard let duressHash else { return false }
                return constantTimeCompare(duressHash, attemptHash)
            }()

            // The duress code is answered BEFORE the brute-force cooldown is
            // consulted. The cooldown exists to make guessing expensive, and the
            // duress code is not a way around it: guessing it right wipes the
            // device rather than opening it. Refusing it during a cooldown meant
            // that five wrong guesses by the person holding the phone disabled
            // the wipe for up to an hour — exactly when it is needed.
            //
            // The derivation above already ran, for every code and whether or not
            // a duress code exists, so a locked-out attempt costs the same either
            // way and the wait cannot be timed to reveal that a second code is set.
            if matchesDuress {
                // Clear the throttle on the way out: a freshly-installed app that
                // refuses passcodes for four minutes is not a freshly-installed app.
                resetAttempts()
                return .duress
            }

            guard lockoutRemaining == 0 else { return .lockedOut }

            if matchesReal {
                isUnlocked = true
                resetAttempts()
                return .correct
            }

            failedAttempts += 1
            if failedAttempts >= Self.freeAttempts {
                // Escalating cooldown: 30s, 60s, 2m, 4m … capped at 1h.
                let over = failedAttempts - Self.freeAttempts
                let delay = min(3600, 30 * pow(2.0, Double(over)))
                lockUntil = Date(timeIntervalSinceNow: delay)
            }
            return .incorrect

        case (.unavailable, _), (_, .unavailable):
            return .unavailable
        default:
            return .notSet
        }
    }

    /// Check a passcode without counting it against the throttle.
    ///
    /// For "confirm it is you" inside an app that is already unlocked: changing the
    /// passcode, setting the duress code, revealing the phrase. The throttle is
    /// there to make guessing expensive at the lock screen; applying it here lets
    /// someone lock themselves out of their own account by mistyping in Settings.
    ///
    /// The duress code deliberately does NOT satisfy this: it is not a passcode,
    /// and accepting it here would let it authorise changes to the settings it is
    /// meant to be protected by.
    func confirms(_ passcode: String) -> Bool {
        guard case let .found(storedHash) = read(key: Self.hashKey),
              case let .found(salt) = read(key: Self.saltKey)
        else { return false }
        return constantTimeCompare(storedHash, Self.derive(passcode: passcode, salt: salt))
    }

    // MARK: - Duress code

    /// True only when a duress code is positively there.
    ///
    /// The opposite of `isPasscodeSet`, and for the opposite reason: an
    /// unreadable Keychain must not be reported as "a duress code is set", or
    /// Settings tells someone they have a way out that may not exist. Claiming
    /// it is absent is safe — setting one again requires the passcode and simply
    /// overwrites whatever is stored.
    var isDuressSet: Bool {
        if case .found = read(key: Self.duressHashKey) { return true }
        return false
    }

    /// Set the code that wipes the account.
    ///
    /// Requires the real passcode, because this is the setting an attacker would
    /// want to change: quietly pointing the wipe at a code of their own turns a
    /// safety feature into a way to destroy someone's account.
    ///
    /// Refuses a code equal to the passcode. That collision resolves as "unlock",
    /// which would leave someone believing they have a way out that does nothing.
    @discardableResult
    func setDuressPasscode(_ duress: String, currentPasscode: String) -> Bool {
        guard !duress.isEmpty else { return false }
        // confirms, not check: a mistyped passcode in Settings must not burn an
        // attempt or start a cooldown on the lock screen.
        guard confirms(currentPasscode) else { return false }
        guard !confirms(duress) else { return false }

        // Stored under the passcode's own salt, so an unlock derives once and
        // compares twice. See the note in check().
        guard case let .found(salt) = read(key: Self.saltKey) else { return false }
        return writeKeychain(key: Self.duressHashKey, data: Self.derive(passcode: duress, salt: salt))
    }

    /// True when this code is the stored duress code.
    private func matchesDuress(_ candidate: String) -> Bool {
        guard case let .found(hash) = read(key: Self.duressHashKey),
              case let .found(salt) = read(key: Self.saltKey)
        else { return false }
        return constantTimeCompare(hash, Self.derive(passcode: candidate, salt: salt))
    }

    @discardableResult
    func removeDuressPasscode(currentPasscode: String) -> Bool {
        guard confirms(currentPasscode) else { return false }
        deleteKeychain(key: Self.duressHashKey)
        return true
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
        deleteKeychain(key: Self.duressHashKey)
        deleteKeychain(key: Self.duressSaltKey)
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

    /// Outcome of a Keychain read. "Missing" and "temporarily unreadable" are very
    /// different answers and must never be collapsed into nil: treating an
    /// unreadable item as missing is what made the app offer to CREATE a passcode
    /// for someone who already had one.
    enum KeychainRead {
        case found(Data)
        case missing
        case unavailable(OSStatus)
    }

    private func read(key: String) -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data { return .found(data) }
            return .unavailable(status)
        case errSecItemNotFound:
            return .missing
        default:
            // errSecInteractionNotAllowed (device still locked after a reboot) and
            // friends land here.
            return .unavailable(status)
        }
    }

    private func readKeychain(key: String) -> Data? {
        if case let .found(data) = read(key: key) { return data }
        return nil
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
        // AfterFirstUnlock, not WhenUnlocked: the app can be launched (or pre-warmed
        // by iOS) before the device has been unlocked in this boot, and a
        // WhenUnlocked item is unreadable then. Still device-only and still
        // unreadable while the phone is off.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

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
