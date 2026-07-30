import Foundation
import ActivityKit
import SwiftUI

/// Owns the Live Activity lifecycle: start it when an admin has an open book, update it on
/// every refresh, end it when the book empties or the session goes away.
///
/// ADMIN ONLY. A Live Activity is readable on a LOCKED phone, so it is the least private
/// surface this app has — the whole desk's exposure, visible to anyone who picks the device
/// up. Only admins get it, and only if they opt in; everyone else never starts one.
///
/// Updates arrive two ways: the app refreshes the activity directly while it is running,
/// and the server pushes through OneSignal (which fronts APNs) the rest of the time — so the
/// card no longer freezes at whatever the last foreground refresh saw.
@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    private init() {
        enabled = UserDefaults.standard.object(forKey: Self.prefKey) as? Bool ?? true
        // An activity OUTLIVES the app process. Adopt whatever is already on the Lock Screen
        // instead of requesting a second one — otherwise every relaunch stacks another card,
        // and the top one is whichever the system feels like, i.e. possibly the stalest.
        activity = Activity<PositionsActivityAttributes>.activities.first
        if let activity { observeToken(of: activity) }
        for extra in Activity<PositionsActivityAttributes>.activities.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static let prefKey = "lno_live_activity_enabled"
    private var activity: Activity<PositionsActivityAttributes>?

    /// Opt-in switch, admin-visible in Settings. Defaults ON so the feature is discoverable,
    /// but turning it off ends any running activity immediately rather than at next launch.
    @Published private(set) var enabled: Bool
    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.prefKey)
        if !on { Task { await end() } }
    }

    /// True only when the system will actually let us start one — Settings ▸ Face ID &
    /// Passcode ▸ Live Activities can be off system-wide, and then the toggle would be a lie.
    var systemAllows: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Called after every portfolio refresh. Starts, updates or ends as the state dictates —
    /// one entry point, so there is no path where a stale activity is left running.
    func sync(store: PortfolioStore, auth: AuthStore) {
        guard let user = auth.user, user.isAdmin, enabled, systemAllows else {
            Task { await end() }
            return
        }
        let open = store.openBots
        // Nothing open is not "zero positions" worth showing on a Lock Screen — it is
        // nothing to say. End the activity rather than pin an empty card there.
        guard !open.isEmpty else { Task { await end() }; return }

        registerPushToStart()
        let state = Self.state(from: store)
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60))) }
        } else {
            let attrs = PositionsActivityAttributes(accountLabel: user.email)
            // .token, not nil: ActivityKit then vends an update token, which OneSignal
            // forwards to APNs on the server's behalf — that is what keeps the card fresh
            // while the app is closed. Without it the card freezes at the last refresh.
            activity = try? Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60)),
                pushType: .token
            )
            if let activity { observeToken(of: activity) }
        }
    }

    func end() async {
        guard let a = activity else { return }
        activity = nil
        tokenTask?.cancel(); tokenTask = nil
        OneSignalManager.shared.liveActivityExit(id: Self.activityId)
        await a.end(nil, dismissalPolicy: .immediate)
    }

    /// One shared activity id for the whole desk: the server updates "positions" once and
    /// every admin's card follows, instead of the backend having to track a token per device.
    static let activityId = "positions"

    private var tokenTask: Task<Void, Never>?

    /// The update token is not available at request time — ActivityKit delivers it (and any
    /// later rotation) asynchronously, so this has to be an ongoing subscription rather than
    /// a one-shot read.
    private func observeToken(of activity: Activity<PositionsActivityAttributes>) {
        tokenTask?.cancel()
        tokenTask = Task {
            for await data in activity.pushTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                OneSignalManager.shared.liveActivityEnter(id: Self.activityId, token: hex)
            }
        }
    }

    /// Push-to-start: lets the server raise the card on a device where the app is not
    /// running. Registered once at sign-in; iOS 17.2+ only, and harmlessly absent below that.
    private var pushToStartRegistered = false
    func registerPushToStart() {
        guard #available(iOS 17.2, *), !pushToStartRegistered else { return }
        pushToStartRegistered = true
        Task {
            for await data in Activity<PositionsActivityAttributes>.pushToStartTokenUpdates {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                OneSignalManager.shared.setPushToStartToken(PositionsActivityAttributes.self, token: hex)
            }
        }
    }

    /// Every field derived from what the Positions tab already renders — no second
    /// calculation that could drift from it.
    private static func state(from store: PortfolioStore) -> PositionsActivityAttributes.ContentState {
        let open = store.openBots
        let worst: String = {
            if open.contains(where: { $0.liqLevel == .danger }) { return "danger" }
            if open.contains(where: { $0.liqLevel == .warn }) { return "warn" }
            return "ok"
        }()
        return .init(
            openCount: open.count,
            longCount: open.filter { $0.isLong }.count,
            shortCount: open.filter { !$0.isLong }.count,
            unrealizedPnl: store.openPnl,
            risk: worst,
            // The equity trail the Overview chart draws, trimmed to what a 96pt sparkline
            // can actually resolve.
            spark: Array(store.snapshots.suffix(30).map { $0.equity }),
            updatedAt: Date().timeIntervalSince1970
        )
    }
}
