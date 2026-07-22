import Foundation

/// Central configuration. The app is a read-only client of the LNO Control Center
/// backend (same database, same API as https://cc.lno.company).
enum Config {
    /// Base URL of the Vercel serverless API. All endpoints hang off this.
    static let apiBase = URL(string: "https://cc.lno.company/api")!

    /// The web dashboard's own origin. Google sign-in reuses this exact login page
    /// (real GIS button, already-authorized JS origin, zero extra Google Cloud
    /// config) inside an ASWebAuthenticationSession — see AuthStore.signInWithGoogle.
    static let webBase = URL(string: "https://cc.lno.company")!

    /// Public Binance USDⓈ-M Futures market data (no key). Used by the Prices tab,
    /// mirroring how the web dashboard fetches public prices client-side.
    static let binanceFapi = URL(string: "https://fapi.binance.com")!

    /// Custom URL scheme this app registers (CFBundleURLTypes in Info.plist). The
    /// web login page redirects here with ?token=<jwt> once sign-in succeeds inside
    /// the ASWebAuthenticationSession — see main.tsx's `mobileHandoff`.
    static let authCallbackScheme = "lnocc"

    /// OneSignal app ID for push notifications.
    static let oneSignalAppID = "403e4ce4-2e4a-47ed-a938-77639eac3c9c"
    static var pushConfigured: Bool { !oneSignalAppID.isEmpty }
}
