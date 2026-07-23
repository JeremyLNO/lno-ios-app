import SwiftUI
import WidgetKit

/// GitHub-style daily PnL% heatmap — small shows the last ~7 weeks, medium the full
/// cached series (up to ~18 weeks, see PortfolioStore.saveWidgetSnapshot()). Uses the
/// same PnlCalendarDay/PnlCalendarView/PnlHeat as the Dashboard's PnL Calendar card
/// (LNOShared/PnlCalendar.swift), so the two always render identical colors.
struct PnlCalendarWidget: Widget {
    let kind = "PnlCalendarWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortfolioProvider()) { entry in
            PnlCalendarWidgetView(entry: entry)
                .containerBackground(Theme.navy, for: .widget)
        }
        .configurationDisplayName("PnL Calendar")
        .description("Daily P&L heatmap, GitHub-contributions style.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PnlCalendarWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: PortfolioEntry

    var body: some View {
        guard let s = entry.snapshot, s.calendar.count > 1 else {
            return AnyView(WidgetEmptyState(text: "Not enough history yet."))
        }
        // The heatmap itself measures the space it's given and fills it edge-to-edge
        // (always 7 rows, as many columns as fit) — no more guessing a day count per family.
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("PNL CALENDAR").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedText)
                PnlCalendarWidgetHeatmap(allDays: s.calendar, preferredCellSize: family == .systemSmall ? 7 : 9)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        )
    }
}

/// Widget-only rendering of the calendar grid (no legend, no ScrollView — widgets
/// can't scroll interactively) sharing the exact same weekday-bucketing and color
/// logic as the app's PnlCalendarView. Always 7 rows; measures its own width and
/// picks however many columns of `preferredCellSize` fit, then keeps that many of
/// the most recent weeks — so the grid fills the widget rather than leaving a gap
/// or clipping.
private struct PnlCalendarWidgetHeatmap: View {
    let allDays: [PnlCalendarDay]
    let preferredCellSize: CGFloat
    private let spacing: CGFloat = 2

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func weekday(_ day: String) -> Int {
        guard let d = Self.isoDay.date(from: day) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.component(.weekday, from: d)
        return (wd + 5) % 7
    }

    private func columns(for days: [PnlCalendarDay]) -> [[PnlCalendarDay?]] {
        guard let first = days.first else { return [] }
        var cols: [[PnlCalendarDay?]] = []
        var col: [PnlCalendarDay?] = Array(repeating: nil, count: weekday(first.day))
        for d in days {
            col.append(d)
            if col.count == 7 { cols.append(col); col = [] }
        }
        if !col.isEmpty {
            while col.count < 7 { col.append(nil) }
            cols.append(col)
        }
        return cols
    }

    var body: some View {
        GeometryReader { geo in
            let fittingColumns = max(1, Int((geo.size.width + spacing) / (preferredCellSize + spacing)))
            // +7 slack days so trimming to whole weeks (via the weekday offset above)
            // never leaves the grid a column short of what actually fits.
            let sliced = Array(allDays.suffix(fittingColumns * 7 + 7))
            let realCols = columns(for: sliced).suffix(fittingColumns)
            // Pad with blank columns on the left when there isn't enough real history to
            // fill the measured width, instead of leaving a gap.
            let pad = [[PnlCalendarDay?]](repeating: Array(repeating: nil, count: 7), count: max(0, fittingColumns - realCols.count))
            let cols = pad + realCols
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(cols.enumerated()), id: \.offset) { _, col in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { ri in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(PnlHeat.color(col[ri]?.pct))
                                .frame(width: preferredCellSize, height: preferredCellSize)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: preferredCellSize * 7 + spacing * 6)
    }
}
