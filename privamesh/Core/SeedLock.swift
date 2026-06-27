//
//  SeedLock.swift
//  privamesh
//
//  Optional hardware-enforced protection for the wallet seed. When enabled,
//  every Keychain seed item (active slot + per-account backups) is stored with a
//  `.userPresence` access control, so reading the seed requires Face ID / Touch
//  ID (passcode fallback) — even with the device already unlocked and the app
//  in the foreground. A shared, reuse-windowed LAContext keeps a burst of reads
//  (switch + sign, migration) down to a single prompt.
//

import Foundation
import LocalAuthentication

enum SeedLock {
    private static let key = "privamesh.seedBiometricLock"
    /// A burst of seed reads within this window reuses one authentication.
    private static let reuseWindow: TimeInterval = 15

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Whether the device can actually enforce a biometric/passcode gate.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private static var shared: LAContext?
    private static var sharedAt: Date?

    /// A reuse-windowed context for seed reads; nil when the lock is off.
    static func context() -> LAContext? {
        guard isEnabled else { return nil }
        if let shared, let at = sharedAt, Date().timeIntervalSince(at) < reuseWindow {
            return shared
        }
        let ctx = LAContext()
        ctx.touchIDAuthenticationAllowableReuseDuration = reuseWindow
        shared = ctx
        sharedAt = Date()
        return ctx
    }

    static func invalidate() {
        shared?.invalidate()
        shared = nil
        sharedAt = nil
    }
}
