import SwiftUI
import AuthenticationServices

/// Owns authentication state for the whole app. The JWT lives in the Keychain; the
/// current `User` drives which screens are available.
@MainActor
final class AuthStore: NSObject, ObservableObject {
    /// `.locked` sits between a stored session and `.signedIn`: a token exists in
    /// the Keychain but Face ID/Touch ID is required to reveal it.
    enum Phase: Equatable { case loading, signedOut, locked, signedIn }

    @Published var phase: Phase = .loading
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var busy = false

    private static let faceIDKey = "lno_faceid_enabled"
    @Published private(set) var faceIDEnabled: Bool = UserDefaults.standard.bool(forKey: AuthStore.faceIDKey)
    func setFaceIDEnabled(_ on: Bool) {
        faceIDEnabled = on
        UserDefaults.standard.set(on, forKey: Self.faceIDKey)
    }

    private(set) var token: String? { didSet { client = APIClient(token: token) } }
    private(set) var client = APIClient(token: nil)

    /// Set only by the DEBUG-only "Preview demo" path — tells PortfolioStore to load
    /// static sample data instead of calling the real API. Never true in Release.
    private(set) var isDemo = false

    #if DEBUG
    /// Simulates a successful sign-in with static sample data, for walking through
    /// the app in the Simulator without a real backend session.
    func enterDemoMode() {
        isDemo = true
        user = MockData.user
        errorMessage = nil
        phase = .signedIn
    }

    /// Seeds a fake stored session + enables Face ID, then runs a normal
    /// `bootstrap()` — exercises the real Keychain → `.locked` → biometric-unlock
    /// path (Simulator: Features ▸ Face ID ▸ Enrolled, then Matching Face) without
    /// needing a real backend session.
    private static let demoToken = "lno-demo-token"
    func enterLockedDemoMode() async {
        Keychain.save(Self.demoToken)
        setFaceIDEnabled(true)
        await bootstrap()
    }
    #endif

    // MARK: - Bootstrap

    func bootstrap() async {
        token = Keychain.load()
        guard token != nil else { phase = .signedOut; return }
        if faceIDEnabled && BiometricAuth.isAvailable {
            phase = .locked
            return
        }
        await validateSession()
    }

    private func validateSession() async {
        #if DEBUG
        if token == Self.demoToken {
            isDemo = true
            user = MockData.user
            phase = .signedIn
            return
        }
        #endif
        do {
            user = try await client.me()
            phase = .signedIn
        } catch APIClientError.unauthorized {
            signOut()
        } catch {
            // Network hiccup at launch — keep the stored token but let the user in
            // optimistically only if we have a cached identity; otherwise sign out.
            signOut()
        }
    }

    // MARK: - Face ID / Touch ID unlock

    /// Prompts biometrics; on success reveals the already-stored session (still
    /// re-validates the token with the server, same as a cold-launch bootstrap).
    func unlockWithFaceID() async {
        errorMessage = nil
        let ok = await BiometricAuth.authenticate(reason: "Unlock LNO Control Center")
        guard ok else { return }
        await validateSession()
    }

    // MARK: - Emailed one-time code (shareholders — no password auth on this app)

    @Published var otpRequestedAt: Date?

    func requestOtp(email: String) async -> Bool {
        errorMessage = nil; busy = true; defer { busy = false }
        do {
            try await APIClient.requestOtp(email: email.trimmingCharacters(in: .whitespaces))
            otpRequestedAt = Date()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not send the code"
            return false
        }
    }

    func verifyOtp(email: String, code: String) async {
        errorMessage = nil; busy = true; defer { busy = false }
        do {
            let res = try await APIClient.verifyOtp(email: email.trimmingCharacters(in: .whitespaces), code: code)
            apply(res)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Invalid or expired code"
        }
    }

    // MARK: - Google (default) — reuses the real web login page, same technical
    // config as cc.lno.company: the actual Google Identity Services button, the
    // already-authorized JS origin, the same OAuth client. No separate iOS OAuth
    // client, no PKCE reimplementation. The page runs inside an
    // ASWebAuthenticationSession (a system browser context, not a plain in-app
    // WebView, so Google doesn't block it) and hands back the JWT via a custom
    // URL scheme once sign-in succeeds — see main.tsx's `mobileHandoff`.

    func signInWithGoogle() async {
        errorMessage = nil; busy = true; defer { busy = false }
        do {
            var comps = URLComponents(url: Config.webBase, resolvingAgainstBaseURL: false)!
            comps.queryItems = [.init(name: "mobile_redirect", value: "\(Config.authCallbackScheme)://auth")]
            let callbackURL = try await webAuth(url: comps.url!, scheme: Config.authCallbackScheme)
            guard let token = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "token" })?.value else {
                throw APIClientError.server("Sign-in did not complete")
            }
            let user = try await APIClient(token: token).me()
            apply(AuthResponse(token: token, user: user))
        } catch is CancellationError {
            // user dismissed — no error
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            // user cancelled the web sheet
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Google sign-in failed"
        }
    }

    private func webAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { cont.resume(returning: callback) }
                else { cont.resume(throwing: error ?? CancellationError()) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() { cont.resume(throwing: APIClientError.server("Could not start sign-in")) }
        }
    }

    // MARK: - Session

    private func apply(_ res: AuthResponse) {
        Keychain.save(res.token)
        token = res.token
        user = res.user
        errorMessage = nil
        phase = .signedIn
    }

    func signOut() {
        Keychain.clear()
        token = nil
        user = nil
        isDemo = false
        phase = .signedOut
    }

    /// Called by data views when the API returns 401 mid-session.
    func handleUnauthorized() {
        errorMessage = "Your session expired. Please sign in again."
        signOut()
    }
}

extension AuthStore: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } ?? windows.first }
}
