import SwiftUI

/// One day's PnL derived from two consecutive equity snapshots — mirrors the web
/// dashboard's `PnlCalendar` day objects (src/ui.tsx). Shared between the app
/// (PortfolioStore/DashboardView) and the widget extension (WidgetSnapshot), so
/// both render identical calendar cells from the same data.
struct PnlCalendarDay: Codable, Identifiable, Equatable {
    var id: String { day }
    var day: String     // "YYYY-MM-DD"
    var pnl: Double
    var pct: Double?    // pnl as % of the prior day's equity; nil if prior equity was 0

    /// Builds the day-over-day series from an ascending (oldest-first) list of
    /// (day, equity) pairs — same math as the web's PnlCalendar: pnl = today - prev,
    /// pct = pnl / prev * 100.
    static func series(fromEquityByDay pairs: [(day: String, equity: Double)]) -> [PnlCalendarDay] {
        guard pairs.count > 1 else { return [] }
        var out: [PnlCalendarDay] = []
        for i in 1..<pairs.count {
            let prev = pairs[i - 1].equity
            let pnl = pairs[i].equity - prev
            out.append(PnlCalendarDay(day: pairs[i].day, pnl: pnl, pct: prev != 0 ? pnl / prev * 100 : nil))
        }
        return out
    }
}

/// Shared cell-color scale for the GitHub-style heatmaps — intensity is |pct| clamped
/// at 5% (past which it just reads as "very green/red") rather than scaled to the
/// single largest value in the set, so one outlier day doesn't wash out every other
/// cell. Mirrors the web's `pctHeatColor()` (src/ui.tsx) exactly.
enum PnlHeat {
    static func color(_ pct: Double?) -> Color {
        guard let pct else { return Color(hex: 0xF1F5F9) } // slate-100, "no data"
        let f = 0.18 + min(abs(pct) / 5, 1) * 0.82
        return pct >= 0 ? Theme.up.opacity(f) : Theme.down.opacity(f)
    }
}

/// GitHub-style daily-PnL calendar: columns = weeks, rows = Mon..Sun, most recent
/// week last. Mirrors the web's `PnlCalendar` component layout.
struct PnlCalendarView: View {
    let days: [PnlCalendarDay]
    var cellSize: CGFloat = 11
    var spacing: CGFloat = 3
    var showLegend: Bool = true

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Mon=0 ... Sun=6 for a given "YYYY-MM-DD" day string.
    private func weekday(_ day: String) -> Int {
        guard let d = Self.isoDay.date(from: day) else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wd = cal.component(.weekday, from: d) // 1=Sun...7=Sat
        return (wd + 5) % 7 // Mon=0...Sun=6
    }

    private var columns: [[PnlCalendarDay?]] {
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
        if days.count < 2 {
            Text("No data").font(.footnote).foregroundStyle(Theme.faintText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Measures its own width and picks however many columns of `cellSize` fit,
                // keeping the most recent weeks — always fills the available width edge-to-edge
                // instead of overflowing into a horizontal scroll. Mirrors the widget's approach.
                GeometryReader { geo in
                    let allCols = columns
                    let fittingColumns = max(1, Int((geo.size.width + spacing) / (cellSize + spacing)))
                    // Pad with blank columns on the left when there isn't enough real history
                    // to fill the measured width, instead of leaving a gap.
                    let pad = [[PnlCalendarDay?]](repeating: Array(repeating: nil, count: 7), count: max(0, fittingColumns - allCols.count))
                    let visible = (pad + allCols).suffix(fittingColumns)
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, col in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { ri in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(PnlHeat.color(col[ri]?.pct))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: cellSize * 7 + spacing * 6)
                if showLegend { legend }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("loss").font(.system(size: 9)).foregroundStyle(Theme.faintText)
            RoundedRectangle(cornerRadius: 2).fill(Theme.down.opacity(0.9)).frame(width: cellSize, height: cellSize)
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF1F5F9)).frame(width: cellSize, height: cellSize)
            RoundedRectangle(cornerRadius: 2).fill(Theme.up.opacity(0.9)).frame(width: cellSize, height: cellSize)
            Text("gain").font(.system(size: 9)).foregroundStyle(Theme.faintText)
        }
    }
}

/// GitHub-style heatmap where each cell is one CLOSED position (not a day), colored by its
/// realized PnL % — chronological, oldest first. Mirrors the web's `PositionsHeatmap`
/// (src/ui.tsx) layout and the same width-fill+padding behavior as `PnlCalendarView` above.
struct PositionsHeatmapView: View {
    /// Realized PnL % of each closed position, oldest first — kept as plain `Double?` (not
    /// `Bot`) so this shared file compiles into the widget target too, which has no `Bot` type.
    let realizedPcts: [Double?]
    var cellSize: CGFloat = 11
    var spacing: CGFloat = 3
    var showLegend: Bool = true

    private var columns: [[Double?]] {
        var cols: [[Double?]] = []
        var col: [Double?] = []
        for p in realizedPcts {
            col.append(p)
            if col.count == 7 { cols.append(col); col = [] }
        }
        if !col.isEmpty {
            while col.count < 7 { col.append(nil) }
            cols.append(col)
        }
        return cols
    }

    var body: some View {
        if realizedPcts.isEmpty {
            Text("No data").font(.footnote).foregroundStyle(Theme.faintText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    let allCols = columns
                    let fittingColumns = max(1, Int((geo.size.width + spacing) / (cellSize + spacing)))
                    let pad = [[Double?]](repeating: Array(repeating: nil, count: 7), count: max(0, fittingColumns - allCols.count))
                    let visible = (pad + allCols).suffix(fittingColumns)
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, col in
                            VStack(spacing: spacing) {
                                ForEach(0..<7, id: \.self) { ri in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(PnlHeat.color(col[ri]))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: cellSize * 7 + spacing * 6)
                if showLegend {
                    HStack(spacing: 6) {
                        Text("loss").font(.system(size: 9)).foregroundStyle(Theme.faintText)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.down.opacity(0.9)).frame(width: cellSize, height: cellSize)
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF1F5F9)).frame(width: cellSize, height: cellSize)
                        RoundedRectangle(cornerRadius: 2).fill(Theme.up.opacity(0.9)).frame(width: cellSize, height: cellSize)
                        Text("gain").font(.system(size: 9)).foregroundStyle(Theme.faintText)
                    }
                }
            }
        }
    }
}
