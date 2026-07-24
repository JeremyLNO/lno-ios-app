import SwiftUI
import WidgetKit

/// Per-fund unrealized P&L — the "By fund" breakdown from Overview. Medium only
/// (a small tile can't fit more than one readable row); each fund row deep-links
/// into the app's Positions tab, scrolled to that fund.
struct FundsEquityWidget: Widget {
    let kind = "FundsEquityWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            FundsEquityView(entry: entry)
                .containerBackground(Theme.navy, for: .widget)
                .environment(\.locale, LanguagePersistence.loadForWidget().locale)
        }
        .configurationDisplayName("Funds Equity")
        .description("Unrealized P&L for each fund. Tap a fund to open it in the app.")
        .supportedFamilies([.systemMedium])
    }
}

private struct FundsEquityView: View {
    let entry: PortfolioEntry

    var body: some View {
        guard let s = entry.snapshot, !s.funds.isEmpty else {
            return AnyView(WidgetEmptyState(text: "No funds yet."))
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("FUNDS").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedText)
                ForEach(s.funds.prefix(5)) { f in
                    Link(destination: URL(string: "\(Config.authCallbackScheme)://fund/\(f.id)")!) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hexString: f.color) ?? Theme.gold).frame(width: 7, height: 7)
                            Text(f.displayName).font(.caption).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text(Fmt.signedUSD(f.uPnl)).font(.caption).fontWeight(.semibold)
                                .foregroundStyle(Theme.pnlColor(f.uPnl))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.mutedText)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }
}
