import SwiftUI
import WidgetKit

/// Loads and holds the read-only portfolio data shared across tabs, and derives the
/// same KPIs the web dashboard computes client-side from bots + funds + live + snapshots.
@MainActor
final class PortfolioStore: ObservableObject {
    @Published var bots: [Bot] = []
    @Published var funds: [Fund] = []
    @Published var live: LiveEquity?
    @Published var snapshots: [Snapshot] = []
    @Published var alerts: [Alert] = []
    @Published var anomalies: [Anomaly] = []
    @Published var milestones: [Milestone] = []
    /// Live measurements per scope/metric, as the server computed them — the app does NOT
    /// recompute a milestone's progress, or the bar could disagree with the award.
    @Published var milestoneMeasured: [String: [String: Double]] = [:]

    @Published var loading = false
    @Published var loadError: String?
    @Published var lastLoaded: Date?

    var openBots: [Bot] { bots.filter { $0.isOpen } }
    /// Closed positions, oldest first — matches the web's PositionsHeatmap ordering
    /// (`lastChanged||lastSeen`), so the two render identical grids.
    var closedBots: [Bot] {
        bots.filter { $0.isClosed }.sorted {
            (Fmt.date($0.lastChanged ?? $0.lastSeen) ?? .distantPast) < (Fmt.date($1.lastChanged ?? $1.lastSeen) ?? .distantPast)
        }
    }

    // Derived KPIs (mirror api/_lib/portfolio.js buildPortfolio).
    var equity: Double { live?.equity ?? 0 }
    var openPnl: Double { openBots.reduce(0) { $0 + $1.unrealizedPnl } }
    var exposure: Double { openBots.reduce(0) { $0 + $1.notional } }
    var lastSnapshotEquity: Double { snapshots.last?.equity ?? equity }
    var pnlDay: Double { equity - lastSnapshotEquity }
    var pnlDayPct: Double { lastSnapshotEquity != 0 ? pnlDay / lastSnapshotEquity * 100 : 0 }

    func milestoneProgress(_ m: Milestone) -> Double { milestoneMeasured[m.scope]?[m.metric] ?? 0 }

    var pendingAlerts: Int { alerts.filter { !$0.isAcked }.count }
    // Real-time incident status (Overview) counts service-health alerts only (api_error) —
    // not portfolio performance breaches (drawdown/PnL), which are a different alert type.
    var ongoingIncidents: Int { alerts.filter { $0.isIncident && !$0.isAcked }.count }
    var hasOngoingIncident: Bool { ongoingIncidents > 0 }
    /// Unresolved findings, criticals first — the count the Alerts tab badges on.
    var openAnomalies: [Anomaly] { anomalies.filter { !$0.isResolved } }
    var criticalAnomalies: Int { openAnomalies.filter(\.isCritical).count }

    /// Day-over-day PnL% series for the GitHub-style calendar heatmap — mirrors the
    /// web dashboard's `PnlCalendar` derivation from the same snapshot history.
    var pnlCalendar: [PnlCalendarDay] {
        PnlCalendarDay.series(fromEquityByDay: snapshots.map { ($0.day, $0.equity) })
    }

    /// Bot-level (per open position) allocation — the "Bot Allocation" donut + "By
    /// Bot" table now promoted above the fund-level roll-up, matching the web's
    /// today's restructuring. Sorted largest exposure first, same as the widget's
    /// position ordering.
    var openBotsByExposure: [Bot] { openBots.sorted { abs($0.notional) > abs($1.notional) } }

    /// Open positions grouped by fund, plus an "Unassigned" bucket, ordered by fund sort.
    struct FundGroup: Identifiable {
        let id: String
        let name: String
        let color: String
        var bots: [Bot]
        var uPnl: Double { bots.reduce(0) { $0 + $1.unrealizedPnl } }
        var notional: Double { bots.reduce(0) { $0 + $1.notional } }
        /// Fund names come from the server and shouldn't be run through the localization
        /// catalog — except the synthetic "__unassigned" bucket, whose "Unassigned" label
        /// is one of ours and should translate like any other UI string.
        var displayName: LocalizedStringKey { id == "__unassigned" ? "Unassigned" : LocalizedStringKey(name) }
    }
    var fundGroups: [FundGroup] {
        var groups: [FundGroup] = funds
            .sorted { ($0.sort, $0.name) < ($1.sort, $1.name) }
            .map { FundGroup(id: $0.id, name: $0.name, color: $0.color, bots: []) }
        let index = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1.id, $0) })
        var unassigned: [Bot] = []
        for b in openBots {
            if let fid = b.fundId, let i = index[fid] { groups[i].bots.append(b) }
            else { unassigned.append(b) }
        }
        if !unassigned.isEmpty {
            groups.append(FundGroup(id: "__unassigned", name: "Unassigned", color: "#64748B", bots: unassigned))
        }
        return groups.filter { !$0.bots.isEmpty }
    }

    // MARK: - Service status (mirrors the web dashboard's StatusPage.tsx — derived
    // client-side from data already fetched for other purposes, no dedicated
    // health endpoint exists server-side).

    struct ServiceCheck: Identifiable {
        enum State: String { case ok, warn, down, neutral }
        var id: String { label }
        let label: String
        let state: State
        let sub: String
    }

    var serviceChecks: [ServiceCheck] {
        var checks: [ServiceCheck] = []

        if let connected = live?.connected {
            checks.append(ServiceCheck(
                label: "Exchange Sync", state: connected > 0 ? .ok : .down,
                sub: connected > 0 ? "\(connected) exchange\(connected == 1 ? "" : "s") connected" : "No exchange connected"))
        } else {
            checks.append(ServiceCheck(label: "Exchange Sync", state: .neutral, sub: "No sync data yet"))
        }

        if !snapshots.isEmpty {
            checks.append(ServiceCheck(label: "Database", state: .ok,
                                        sub: "\(snapshots.count) day\(snapshots.count == 1 ? "" : "s") of history"))
        } else if loadError != nil {
            checks.append(ServiceCheck(label: "Database", state: .down, sub: "Could not reach snapshots"))
        } else {
            checks.append(ServiceCheck(label: "Database", state: .neutral, sub: "No history yet"))
        }

        checks.append(ServiceCheck(
            label: "Positions", state: openBots.isEmpty ? .neutral : .ok,
            sub: openBots.isEmpty ? "No open positions" : "\(openBots.count) open position\(openBots.count == 1 ? "" : "s")"))

        checks.append(ServiceCheck(
            label: "Alerting", state: .ok,
            sub: pendingAlerts == 0 ? "No pending alerts" : "\(pendingAlerts) pending"))

        checks.append(ServiceCheck(
            label: "Funds", state: funds.isEmpty ? .neutral : .ok,
            sub: funds.isEmpty ? "No funds configured" : "\(funds.count) fund\(funds.count == 1 ? "" : "s")"))

        if let synced = live?.syncedDate {
            let age = Date().timeIntervalSince(synced)
            let state: ServiceCheck.State = age < 300 ? .ok : (age < 1800 ? .warn : .down)
            checks.append(ServiceCheck(label: "Last Sync", state: state, sub: "\(Fmt.relative(synced))"))
        } else {
            checks.append(ServiceCheck(label: "Last Sync", state: .neutral, sub: "Never synced"))
        }

        return checks
    }

    var overallStatusLabel: String {
        if serviceChecks.contains(where: { $0.state == .down }) { return "Degraded" }
        if serviceChecks.contains(where: { $0.state == .warn }) { return "Partial Outage" }
        return "All Operational"
    }

    // MARK: - Loading

    func refresh(auth: AuthStore) async {
        if auth.isDemo {
            loading = true; defer { loading = false }
            bots = MockData.bots
            live = MockData.live
            funds = MockData.funds
            snapshots = MockData.snapshots
            alerts = MockData.alerts
            anomalies = MockData.anomalies
            milestones = MockData.milestones
            milestoneMeasured = MockData.milestoneMeasured
            loadError = nil
            lastLoaded = Date()
            saveWidgetSnapshot()
            LiveActivityController.shared.sync(store: self, auth: auth)
            return
        }
        loading = true; loadError = nil; defer { loading = false }
        let c = auth.client
        do {
            async let b = c.bots()
            async let f = c.funds()
            async let s = c.snapshots()
            async let a = c.alerts()
            // Anomalies need view_trades; a shareholder simply gets none rather than a 403
            // that would fail the whole refresh, so the call is optional and swallowed.
            async let an = c.anomaliesOrEmpty()
            // Same treatment as anomalies: a role without view_milestones simply gets none,
            // rather than a 403 that would fail the whole refresh.
            async let ms = c.milestonesOrEmpty()
            let (botsRes, fundsRes, snapsRes, alertsRes, anomaliesRes, milestonesRes) = try await (b, f, s, a, an, ms)
            bots = botsRes.bots
            live = botsRes.live
            funds = fundsRes
            snapshots = snapsRes
            alerts = alertsRes
            anomalies = anomaliesRes
            milestones = milestonesRes?.milestones ?? []
            milestoneMeasured = milestonesRes?.measured ?? [:]
            lastLoaded = Date()
            saveWidgetSnapshot()
            LiveActivityController.shared.sync(store: self, auth: auth)
        } catch APIClientError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "Could not load data"
        }
    }

    /// Publishes the current portfolio state to the shared App Group container for
    /// the widget extension, and asks the system to redraw them right away.
    private func saveWidgetSnapshot() {
        let fundNames = Dictionary(uniqueKeysWithValues: funds.map { ($0.id, $0.name) })
        let snapshot = WidgetSnapshot(
            equity: equity, pnlDay: pnlDay, pnlDayPct: pnlDayPct, openPnl: openPnl, exposure: exposure,
            funds: fundGroups.map { .init(id: $0.id, name: $0.name, color: $0.color, uPnl: $0.uPnl, positionCount: $0.bots.count) },
            positions: openBots.sorted { abs($0.notional) > abs($1.notional) }.prefix(10).map { b in
                .init(id: b.id, botLabel: b.exchange.capitalized,
                      fundName: b.fundId.flatMap { fundNames[$0] } ?? "Unassigned",
                      asset: b.baseAsset, side: b.side, unrealizedPnl: b.unrealizedPnl, notional: b.notional,
                      pnlPct: b.notional != 0 ? b.unrealizedPnl / b.notional * 100 : 0)
            },
            serviceChecks: serviceChecks.map { .init(label: $0.label, state: $0.state.rawValue, sub: $0.sub) },
            overallStatus: overallStatusLabel,
            calendar: Array(pnlCalendar.suffix(126)), // ~18 weeks — plenty for a medium widget
            updatedAt: Date()
        )
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Lightweight background refresh of positions + live equity only (funds and
    /// the daily snapshot history barely change, so they stay on pull-to-refresh).
    /// Silent on failure — a dropped background poll shouldn't flash an error
    /// screen over data the user is already looking at; the app-wide offline
    /// banner (NetworkMonitor) already communicates connectivity problems.
    func refreshPositionsOnly(auth: AuthStore) async {
        if auth.isDemo { return }
        do {
            async let botsRes = auth.client.bots()
            // Alerts ride along on the same lightweight poll so the Overview
            // incident indicator reflects service-health changes in near-real-time.
            async let alertsRes = auth.client.alerts()
            let (b, a) = try await (botsRes, alertsRes)
            bots = b.bots
            live = b.live
            alerts = a
            lastLoaded = Date()
            saveWidgetSnapshot()
            // The background poll is what keeps the Lock Screen card honest between manual
            // refreshes — without it the activity would freeze at whatever the last pull saw.
            LiveActivityController.shared.sync(store: self, auth: auth)
        } catch APIClientError.unauthorized {
            auth.handleUnauthorized()
        } catch {
            // transient/offline — keep showing the last known good data
        }
    }
}
