import Foundation
import OneSignalFramework

/// Centralized wrapper around the OneSignal SDK — per OneSignal's integration
/// guidance, this is the ONLY file that calls OneSignal directly. Everything else
/// (SwiftUI views, AuthStore) goes through this.
///
/// Scope for now: SDK init + the one-time "integration complete" push-permission
/// prompt. Actually delivering LNO alerts as push notifications (tagging the user,
/// wiring the backend's notify.js to call the OneSignal REST API) is a follow-up —
/// this class doesn't call `login`/tag methods yet since nothing needs them.
final class OneSignalManager: NSObject, ObservableObject {
    static let shared = OneSignalManager()
    private override init() { super.init() }

    /// Persisted (not just in-memory) so the "integration complete" alert really is
    /// one-time-ever, not once-per-launch. Without this, `didRegister` re-latches
    /// true on every cold start once the SDK has a real subscription ID cached
    /// locally from a *previous* run — re-showing the alert on every relaunch and,
    /// worse, re-driving `requestPushPermission()` every time too.
    private static let hasShownAlertKey = "OneSignalManager.hasShownIntegrationAlert"

    /// True once the device has a real, server-assigned push subscription ID
    /// (not the SDK's `local-` placeholder) AND we haven't already shown the
    /// one-time verification alert in RootView on a previous launch.
    @Published private(set) var didRegister = false
    private var hasFiredRegistration = false
    private var didInitialize = false

    func initialize(appId: String) {
        guard !didInitialize, !appId.isEmpty else { return }
        didInitialize = true
        OneSignal.Debug.setLogLevel(.LL_WARN)
        OneSignal.initialize(appId, withLaunchOptions: nil)
        OneSignal.User.pushSubscription.addObserver(self)
        // The ID may already be server-assigned before the observer attaches.
        evaluate(OneSignal.User.pushSubscription.id)
    }

    /// Requests the system push-permission prompt. Deliberately dispatched to the
    /// next run-loop turn rather than called inline from a SwiftUI `.alert` button
    /// action: when permission was already denied in a previous run, the OS won't
    /// re-show its own dialog, so with `fallbackToSettings: true` the OneSignal SDK
    /// instead presents its *own* UIKit alert directing the user to Settings. Firing
    /// that presentation synchronously — before SwiftUI has finished tearing down
    /// its own alert's presentation — collides with the outgoing dismissal
    /// (UIKit only supports one active presentation transaction at a time) and can
    /// leave the window's presentation state wedged, silently swallowing all further
    /// touches. Yielding one run-loop turn lets SwiftUI's dismissal complete first.
    func requestPushPermission() {
        DispatchQueue.main.async {
            OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: true)
        }
    }

    private func evaluate(_ subscriptionId: String?) {
        guard let id = subscriptionId, !id.isEmpty, !id.hasPrefix("local-") else { return }
        guard !hasFiredRegistration else { return }
        hasFiredRegistration = true
        guard !UserDefaults.standard.bool(forKey: Self.hasShownAlertKey) else { return }
        DispatchQueue.main.async { [weak self] in self?.didRegister = true }
    }

    /// Called by RootView once it has actually presented the alert, so it never
    /// shows again on a future launch.
    func markIntegrationAlertShown() {
        UserDefaults.standard.set(true, forKey: Self.hasShownAlertKey)
    }
}

extension OneSignalManager: OSPushSubscriptionObserver {
    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        evaluate(state.current.id)
    }
}
