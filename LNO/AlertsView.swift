import SwiftUI

/// Tracks which alerts have been read on this device. Separate from the server's
/// admin-only acknowledgement (`Alert.ackedAt`) — this is purely a local "seen"
/// marker, since the app is view-only and never writes back to the API.
final class AlertReadStore: ObservableObject {
    @Published private(set) var readIDs: Set<Int>
    private static let key = "lno_read_alert_ids"

    init() {
        readIDs = Set(UserDefaults.standard.array(forKey: Self.key) as? [Int] ?? [])
    }
    func isRead(_ id: Int) -> Bool { readIDs.contains(id) }
    func markAllRead<S: Sequence>(_ ids: S) where S.Element == Int {
        readIDs.formUnion(ids)
        UserDefaults.standard.set(Array(readIDs), forKey: Self.key)
    }
    /// Count of alerts not yet marked read on this device — drives both the
    /// "Mark all as read" button and the Alerts tab badge.
    func unreadCount(in alerts: [Alert]) -> Int { alerts.filter { !isRead($0.id) }.count }
}

struct AlertsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @EnvironmentObject var readStore: AlertReadStore
    @Binding var showSettings: Bool

    private var unreadCount: Int { readStore.unreadCount(in: store.alerts) }

    /// Incidents and anomalies answer different questions — "is the service healthy" vs
    /// "is a bot behaving differently than it used to" — so they are two segments rather
    /// than one merged list that would bury the slow-moving findings under the loud ones.
    private enum Segment: String, CaseIterable, Identifiable {
        case incidents, anomalies
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .incidents ? "Incidents" : "Anomalies" }
    }
    @State private var segment: Segment = {
        #if DEBUG
        // Same DEBUG launch-argument hook the tab selection uses, so a headless screenshot
        // can land directly on the anomalies list. See DeepLinkRouter.selectedTab.
        if UserDefaults.standard.string(forKey: "LNOTab") == "anomalies" { return .anomalies }
        #endif
        return .incidents
    }()
    /// The segment is only worth showing to someone who can actually see anomalies.
    private var canSeeAnomalies: Bool { auth.user?.can("view_trades") ?? false }

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Alerts", auth: auth, showSettings: $showSettings)
        .toolbar {
            if unreadCount > 0 && segment == .incidents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all as read") {
                        readStore.markAllRead(store.alerts.map(\.id))
                    }
                    .font(.subheadline)
                }
            }
        }
        .refreshable { await store.refresh(auth: auth) }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            if canSeeAnomalies {
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if segment == .anomalies && canSeeAnomalies { anomalyContent } else { incidentContent }
        }
    }

    @ViewBuilder private var anomalyContent: some View {
        if store.loading && store.lastLoaded == nil {
            LoadingView()
        } else if store.openAnomalies.isEmpty {
            EmptyStateView(icon: "checkmark.seal", title: "No open anomaly",
                           subtitle: "Detectors compare the last two weeks against the six before them.")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.openAnomalies) { a in anomalyRow(a) }
                }
                .padding(16)
            }
        }
    }

    /// One finding: severity, what it is about, the rebuilt sentence, the likely cause, and
    /// the numbers that triggered it. The evidence is the point — a detector whose reasoning
    /// cannot be checked gets ignored after its first false positive.
    private func anomalyRow(_ a: Anomaly) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(AnomalyText.severity(a.severity))
                        .font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(a.isCritical ? Theme.down.opacity(0.12) : Color.orange.opacity(0.14))
                        .foregroundStyle(a.isCritical ? Theme.down : .orange)
                        .clipShape(Capsule())
                    Text(AnomalyText.code(a.code)).font(.caption2).foregroundStyle(Theme.faintText)
                    if !a.scopeLabel.isEmpty {
                        Text(a.scopeLabel).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.mutedText)
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.relative(a.date)).font(.caption2).foregroundStyle(Theme.faintText)
                }
                Text(AnomalyText.summary(a))
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AnomalyText.cause(a))
                    .font(.caption).foregroundStyle(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                let ev = a.evidence.filter { $0.key != "variant" }.sorted { $0.key < $1.key }
                if !ev.isEmpty {
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(ev, id: \.key) { k, v in
                            HStack {
                                Text(k).font(.caption2).foregroundStyle(Theme.faintText)
                                Spacer()
                                Text(v.display).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.navy)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var incidentContent: some View {
        if store.loading && store.lastLoaded == nil {
            LoadingView()
        } else if store.alerts.isEmpty {
            EmptyStateView(icon: "checkmark.seal", title: "No incidents",
                           subtitle: "Critical alerts and breaches show up here.")
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.alerts) { alert in
                        alertRow(alert)
                    }
                }
                .padding(16)
            }
        }
    }

    /// Mirrors the web header's alert-dropdown row exactly: a binary ack-state dot
    /// (green = acknowledged, red = not), summary text bold when unread, muted once
    /// read, and a meta row with the alert code, timestamp and ack info.
    private func alertRow(_ a: Alert) -> some View {
        let isUnread = !readStore.isRead(a.id)
        return Card {
            HStack(alignment: .top, spacing: 10) {
                Circle().fill(a.isAcked ? Theme.up : Theme.down).frame(width: 7, height: 7)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(a.summary)
                        .foregroundStyle(isUnread ? Theme.navy : Theme.mutedText)
                        .fontWeight(isUnread ? .medium : .regular)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if let code = a.code, !code.isEmpty {
                            Text(code).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.faintText)
                        }
                        Text(Fmt.relative(a.date)).font(.caption2).foregroundStyle(Theme.faintText)
                        Spacer()
                        if a.isAcked {
                            Text("✓ Acknowledged\(a.ackedBy.map { " · \($0)" } ?? "")")
                                .font(.caption2).foregroundStyle(Theme.up)
                        } else {
                            Text("Pending").font(.caption2).fontWeight(.semibold).foregroundStyle(Theme.down)
                        }
                    }
                }
                Spacer(minLength: 0)
                if isUnread {
                    Circle().fill(Theme.gold).frame(width: 6, height: 6).padding(.top, 5)
                }
            }
        }
    }
}
