//
//  BiometryService.swift
//  privamesh
//

import Foundation
import LocalAuthentication

@Observable
final class BiometryService {
    enum BiometryKind {
        case none
        case touchID
        case faceID
        case opticID

        var label: String {
            switch self {
            case .none: return String(localized: "Биометрия")
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            case .opticID: return "Optic ID"
            }
        }

        var systemImage: String {
            switch self {
            case .none: return "lock"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            case .opticID: return "opticid"
            }
        }
    }

    private static let enabledKey = "privamesh.biometry.enabled"

    private(set) var kind: BiometryKind = .none
    private(set) var isAvailable: Bool = false

    /// True while an in-app auth prompt is showing. Used to suppress the
    /// privacy cover / auto-relock (the system prompt backgrounds the scene).
    private(set) var isAuthenticating = false
    /// When the last in-app auth finished. A short grace window after it covers
    /// the race where the scene returns to .active just after the flag clears.
    private(set) var lastAuthAt: Date?

    /// In an in-app auth or just finished one — don't lock / cover.
    var recentlyAuthenticated: Bool {
        if isAuthenticating { return true }
        if let t = lastAuthAt, Date().timeIntervalSince(t) < 3 { return true }
        return false
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    init() {
        refresh()
    }

    func refresh() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isAvailable = canEvaluate

        if canEvaluate {
            switch context.biometryType {
            case .touchID: kind = .touchID
            case .faceID: kind = .faceID
            case .opticID: kind = .opticID
            default: kind = .none
            }
        } else {
            kind = .none
        }
    }

    /// Show system biometry prompt. Returns true on success.
    func authenticate(reason: String = "Разблокировать PrivaMesh") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        isAuthenticating = true
        defer { isAuthenticating = false; lastAuthAt = Date() }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    func disable() {
        isEnabled = false
    }

    /// Confirmation gate for sensitive actions (payments, purchases, gifts).
    /// Uses biometrics with device-passcode fallback so it works even without
    /// Face/Touch ID enrolled. If the device has no passcode at all (can't
    /// authenticate), it allows the action rather than hard-blocking.
    func confirm(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return true   // no passcode/biometrics available — can't gate
        }
        isAuthenticating = true
        defer { isAuthenticating = false; lastAuthAt = Date() }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
