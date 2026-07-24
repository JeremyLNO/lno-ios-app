import SwiftUI
import WidgetKit

/// Service health at a glance — mirrors the web dashboard's System Status page.
/// Medium only (a small tile can't fit more than one or two checks legibly).
struct ServiceStatusWidget: Widget {
    let kind = "ServiceStatusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            ServiceStatusView(entry: entry)
                .containerBackground(Theme.navy, for: .widget)
                .environment(\.locale, LanguagePersistence.loadForWidget().locale)
        }
        .configurationDisplayName("Service Status")
        .description("Exchange sync, database, positions, alerting, funds and last sync.")
        .supportedFamilies([.systemMedium])
    }
}

private struct ServiceStatusView: View {
    let entry: PortfolioEntry

    var body: some View {
        guard let s = entry.snapshot else { return AnyView(WidgetEmptyState()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(dotColor(s.overallStatus)).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(s.overallStatus)).textCase(.uppercase)
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedText)
                }
                ForEach(s.serviceChecks) { c in
                    HStack(spacing: 6) {
                        Circle().fill(dotColor(for: c.state)).frame(width: 6, height: 6)
                        Text(LocalizedStringKey(c.label)).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Text(LocalizedStringKey(c.sub)).font(.system(size: 10)).foregroundStyle(Theme.mutedText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }

    private func dotColor(_ overall: String) -> Color {
        switch overall {
        case "Degraded": return Theme.down
        case "Partial Outage": return Theme.gold
        default: return Theme.up
        }
    }
    private func dotColor(for state: String) -> Color {
        switch state {
        case "ok": return Theme.up
        case "warn": return Theme.gold
        case "down": return Theme.down
        default: return Theme.mutedText
        }
    }
}
