import SwiftUI
import WidgetKit

/// Total portfolio equity + today's P&L — the same headline numbers as the
/// Overview tab.
struct GlobalEquityWidget: Widget {
    let kind = "GlobalEquityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            GlobalEquityView(entry: entry)
                .containerBackground(Theme.navy, for: .widget)
                .environment(\.locale, LanguagePersistence.loadForWidget().locale)
        }
        .configurationDisplayName("Global Equity")
        .description("Total portfolio equity and today's P&L.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GlobalEquityView: View {
    @Environment(\.widgetFamily) var family
    let entry: PortfolioEntry

    var body: some View {
        guard let s = entry.snapshot else { return AnyView(WidgetEmptyState()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    LNOLogo(showWordmark: false).frame(width: 20, height: 20)
                    Spacer()
                    Text("EQUITY").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedText)
                }
                Spacer(minLength: 0)
                Text(Fmt.usd(s.equity))
                    .font(.system(size: family == .systemSmall ? 22 : 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(spacing: 4) {
                    Text(Fmt.signedUSD(s.pnlDay)).fontWeight(.semibold)
                    Text("(\(Fmt.pct(s.pnlDayPct)))")
                }
                .font(.caption2).foregroundStyle(Theme.pnlColor(s.pnlDay))

                if family == .systemMedium {
                    Spacer(minLength: 0)
                    HStack {
                        widgetStat("Open P&L", Fmt.signedUSD(s.openPnl), Theme.pnlColor(s.openPnl))
                        Spacer()
                        widgetStat("Exposure", Fmt.usd(s.exposure), .white)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }

    private func widgetStat(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).textCase(.uppercase).font(.system(size: 9)).foregroundStyle(Theme.mutedText)
            Text(value).font(.caption).fontWeight(.semibold).foregroundStyle(color)
        }
    }
}
