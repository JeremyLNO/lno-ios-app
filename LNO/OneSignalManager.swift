import Foundation
import OneSignalFramework
import OneSignalLiveActivities
import ActivityKit

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

    /// Requests the system push-permission prompt — but only when permission is
    /// still undetermined. If it was already denied in a previous run, the OS won't
    /// re-show its own dialog; `fallbackToSettings: true` would make the OneSignal
    /// SDK present its *own* UIKit alert directing the user to Settings instead.
    /// That app-presented alert collides with SwiftUI still tearing down the "Got
    /// it" alert it was triggered from (UIKit only supports one active presentation
    /// transaction per window) and can leave the window's presentation state
    /// wedged, silently swallowing all further touches — reproduced reliably in
    /// the Simulator. Since this call site only ever fires from a one-time,
    /// low-stakes informational alert, the simplest correct fix is to skip it
    /// entirely once the user has already made a choice, rather than trying to
    /// win a timing race against SwiftUI's own alert dismissal.
    func requestPushPermission() {
        guard OneSignal.Notifications.permissionNative == .notDetermined else { return }
        OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
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

    // MARK: - Live Activities
    //
    // OneSignal's `enter`/`exit` take a raw ActivityKit push token, so the activity's
    // attributes stay a plain `ActivityAttributes` and never have to conform to
    // `OneSignalLiveActivityAttributes`. That matters here: the attributes live in
    // LNOShared, which is compiled into the WIDGET EXTENSION too — and the extension does
    // not link OneSignal. Conforming would break that target outright.

    /// Register a running activity's update token so the server can push new content to it.
    /// `activityId` is the handle the backend addresses; one shared id means one REST call
    /// updates every admin's card.
    func liveActivityEnter(id: String, token: String) {
        OneSignal.LiveActivities.enter(id, withToken: token)
    }

    func liveActivityExit(id: String) {
        OneSignal.LiveActivities.exit(id)
    }

    /// Push-to-start token (iOS 17.2+): lets the server CREATE the card on a device where
    /// the app isn't running at all.
    ///
    /// Called on the concrete manager, not through `OneSignal.LiveActivities`: that property
    /// is typed as the `OSLiveActivities` PROTOCOL metatype, and the generic overload lives in
    /// an extension on it that a protocol existential cannot dispatch. `enter`/`exit` above are
    /// @objc protocol members, which is why they resolve the normal way.
    @available(iOS 17.2, *)
    func setPushToStartToken<T: ActivityAttributes>(_ type: T.Type, token: String) {
        OneSignalLiveActivitiesManagerImpl.setPushToStartToken(type, withToken: token)
    }
}

extension OneSignalManager: OSPushSubscriptionObserver {
    func onPushSubscriptionDidChange(state: OSPushSubscriptionChangedState) {
        evaluate(state.current.id)
    }
}
