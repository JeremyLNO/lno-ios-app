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

    private var unreadCount: Int { readStore.unreadCount(in: store.alerts) }

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if unreadCount > 0 {
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
