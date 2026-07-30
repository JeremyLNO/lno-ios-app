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
/// No push updates: the app refreshes the activity while it is running, and iOS keeps the
/// last state on screen afterwards. That means the card can go stale between launches,
/// which is why `updatedAt` travels with the state — see LiveActivityController.sync.
@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()
    private init() {
        enabled = UserDefaults.standard.object(forKey: Self.prefKey) as? Bool ?? true
        // An activity OUTLIVES the app process. Adopt whatever is already on the Lock Screen
        // instead of requesting a second one — otherwise every relaunch stacks another card,
        // and the top one is whichever the system feels like, i.e. possibly the stalest.
        activity = Activity<PositionsActivityAttributes>.activities.first
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

        let state = Self.state(from: store)
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60))) }
        } else {
            let attrs = PositionsActivityAttributes(accountLabel: user.email)
            activity = try? Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60)),
                pushType: nil
            )
        }
    }

    func end() async {
        guard let a = activity else { return }
        activity = nil
        await a.end(nil, dismissalPolicy: .immediate)
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
            updatedAt: Date()
        )
    }
}
