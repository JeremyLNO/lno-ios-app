import SwiftUI
import WidgetKit

/// Current open positions — mirrors the Positions tab. Medium/Large only (a small
/// tile can't fit bot + fund + asset + P&L legibly).
struct PositionsWidget: Widget {
    let kind = "PositionsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            PositionsWidgetView(entry: entry)
                .containerBackground(Theme.navy, for: .widget)
        }
        .configurationDisplayName("Open Positions")
        .description("Your currently open positions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct PositionsWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PortfolioEntry

    var body: some View {
        guard let s = entry.snapshot, !s.positions.isEmpty else {
            return AnyView(WidgetEmptyState(text: "No open positions."))
        }
        let maxRows = family == .systemLarge ? 9 : 4
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("POSITIONS").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedText)
                ForEach(s.positions.prefix(maxRows)) { p in
                    positionRow(p)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }

    private func positionRow(_ p: WidgetSnapshot.PositionLine) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(p.asset).font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                    Text(p.side.uppercased()).font(.system(size: 8, weight: .bold))
                        .foregroundStyle(p.side.lowercased() == "long" ? Theme.up : Theme.down)
                }
                Text("\(p.botLabel) · \(p.fundName)")
                    .font(.system(size: 9)).foregroundStyle(Theme.mutedText).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.signedUSD(p.unrealizedPnl, decimals: 2)).font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Theme.pnlColor(p.unrealizedPnl))
                Text(Fmt.pct(p.pnlPct)).font(.system(size: 9)).foregroundStyle(Theme.pnlColor(p.pnlPct))
            }
        }
    }
}
