import SwiftUI
import WidgetKit

/// Lock Screen (accessory) widget: open-position count + unrealized P&L at a glance,
/// without unlocking. Reads the same App Group snapshot as the Home Screen widgets —
/// no networking, no auth in the extension.
///
/// Accessory families render in a vibrant, effectively monochrome mode, so P&L sign is
/// conveyed by an explicit +/− (Fmt.signedUSD) and an arrow glyph rather than by color,
/// which the system would flatten anyway.
struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .environment(\.locale, LanguagePersistence.loadForWidget().locale)
        }
        .configurationDisplayName("Positions & P&L")
        .description("Open positions and unrealized P&L on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PortfolioEntry

    private var openCount: Int { entry.snapshot?.positions.count ?? 0 }
    private var openPnl: Double { entry.snapshot?.openPnl ?? 0 }
    private var hasData: Bool { entry.snapshot != nil }

    var body: some View {
        switch family {
        case .accessoryInline:
            // One line, system-styled — the only place an SF Symbol and text share a run.
            if hasData {
                Label {
                    Text("\(openCount) · \(Fmt.signedUSD(openPnl))")
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
            } else {
                Label("LNO", systemImage: "chart.line.uptrend.xyaxis")
            }

        case .accessoryCircular:
            // Count as the hero, P&L as the gauge label underneath the ring.
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(openCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("pos")
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .widgetLabel {
                Text(Fmt.signedUSD(openPnl))
            }

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text("LNO").font(.system(size: 12, weight: .semibold))
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                if hasData {
                    Text(Fmt.signedUSD(openPnl))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("\(openCount) open")
                        .font(.system(size: 11))
                } else {
                    Text("Open the app")
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
