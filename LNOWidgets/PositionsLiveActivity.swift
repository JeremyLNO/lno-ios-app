import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen / Dynamic Island presentation of the open book.
///
/// Unlike the accessory widgets, a Live Activity draws on its OWN dark surface rather than
/// in the system's vibrant monochrome mode — so here P&L really is green or red, and the
/// colour carries meaning instead of being flattened away.
struct PositionsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PositionsActivityAttributes.self) { context in
            LiveCard(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .environment(\.locale, LanguagePersistence.loadForWidget().locale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(context.state.openCount)").font(.title2.bold()).foregroundStyle(.white)
                        Text(L("open")).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.signedUSD(context.state.unrealizedPnl, decimals: 2))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(pnlTint(context.state.unrealizedPnl))
                        Text(L("Unrealized P&L")).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SideRow(state: context.state, compact: true)
                }
            } compactLeading: {
                Text("\(context.state.openCount)").font(.caption.bold()).foregroundStyle(.white)
            } compactTrailing: {
                Text(Fmt.signedUSD(context.state.unrealizedPnl))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(pnlTint(context.state.unrealizedPnl))
            } minimal: {
                // One glyph's worth of room: the sign is the only thing that fits, and it is
                // also the only thing worth knowing at a glance.
                Image(systemName: context.state.unrealizedPnl >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .foregroundStyle(pnlTint(context.state.unrealizedPnl))
            }
            .widgetURL(URL(string: "\(Config.authCallbackScheme)://tab/positions"))
        }
    }
}

private func pnlTint(_ v: Double) -> Color { v >= 0 ? Theme.up : Theme.down }

/// A Live Activity does NOT honour `.environment(\.locale, …)` for string lookup the way an
/// ordinary widget does (see LanguagePersistence.bundleForWidget) — every visible string here
/// therefore goes through an explicit bundle lookup instead of a LocalizedStringKey.
private func L(_ key: String) -> String { LanguagePersistence.widgetString(key) }

private struct LiveCard: View {
    let state: PositionsActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Count and its noun share a baseline: the number is the headline, the
                    // word is context, so they are one sentence rather than two elements.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(state.openCount)").font(.title.bold()).foregroundStyle(.white)
                        Text(L("open positions")).font(.headline).foregroundStyle(.white.opacity(0.85))
                    }
                    Text(L("Unrealized P&L")).font(.caption).foregroundStyle(.white.opacity(0.55))
                    Text(Fmt.signedUSD(state.unrealizedPnl, decimals: 2))
                        .font(.system(size: 28, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(pnlTint(state.unrealizedPnl))
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
                Spacer(minLength: 0)
                LiveSparkline(values: state.spark, tint: pnlTint(state.unrealizedPnl))
                    .frame(width: 96, height: 62)
            }
            Divider().overlay(Color.white.opacity(0.15))
            SideRow(state: state, compact: false)
        }
    }
}

private struct SideRow: View {
    let state: PositionsActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 14 : 0) {
            leg(icon: "arrow.up.right", tint: Theme.up, count: state.longCount, label: L("long"))
            if !compact { Spacer(minLength: 8) }
            leg(icon: "arrow.down.right", tint: Theme.down, count: state.shortCount, label: L("short"))
            if !compact { Spacer(minLength: 8) }
            Label {
                Text(L(PositionsActivityAttributes.ContentState.riskLabelKey(state.risk)))
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
            } icon: {
                Image(systemName: riskSymbol).foregroundStyle(riskTint)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private func leg(icon: String, tint: Color, count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.footnote.bold()).foregroundStyle(tint)
            Text("\(count)").font(.footnote.bold().monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.footnote).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var riskSymbol: String {
        switch state.risk {
        case "danger": return "exclamationmark.shield.fill"
        case "warn":   return "shield.lefthalf.filled"
        default:       return "checkmark.shield"
        }
    }
    private var riskTint: Color {
        switch state.risk {
        case "danger": return Theme.down
        case "warn":   return Theme.warn
        default:       return Theme.gold
        }
    }
}

/// Equity trail. Flat or single-point series still draw a line rather than collapsing to
/// the top edge — a straight line reads as "no movement", an empty box reads as "broken".
private struct LiveSparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = values.count >= 2 ? values : [values.first ?? 0, values.first ?? 0]
            let lo = pts.min() ?? 0, hi = pts.max() ?? 0
            let span = hi - lo
            let x: (Int) -> CGFloat = { i in CGFloat(i) / CGFloat(pts.count - 1) * geo.size.width }
            let y: (Double) -> CGFloat = { v in
                span > 0 ? (1 - CGFloat((v - lo) / span)) * geo.size.height : geo.size.height / 2
            }
            let line = Path { p in
                for (i, v) in pts.enumerated() {
                    let pt = CGPoint(x: x(i), y: y(v))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            ZStack {
                line.stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.addPath(line)
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Circle().fill(tint).frame(width: 6, height: 6)
                    .position(x: x(pts.count - 1), y: y(pts.last ?? 0))
            }
        }
    }
}
