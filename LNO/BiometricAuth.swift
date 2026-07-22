import LocalAuthentication

/// Thin wrapper around LocalAuthentication — the only file that touches LAContext.
enum BiometricAuth {
    /// Whether this device has Face ID/Touch ID enrolled and usable right now.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// "Face ID" / "Touch ID" / "Biometrics" depending on what the device actually has.
    static var kindName: String {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return "Biometrics" }
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrics"
        }
    }

    /// Prompts for biometric auth. Returns true on success, false on any failure or cancel.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return await withCheckedContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                cont.resume(returning: success)
            }
        }
    }
}
