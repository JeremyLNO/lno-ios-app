import SwiftUI

/// Minimal donut chart for allocation breakdowns (bot/fund exposure) — mirrors the
/// web's `Donut` component (src/ui.tsx): a ring of colored arcs sized by value, with
/// an optional centered label. No legend here — callers render their own rows below
/// it (see DashboardView's botAllocation/fundAllocation sections).
struct DonutSegment: Identifiable {
    let id = UUID()
    let value: Double
    let color: Color
}

struct DonutChart: View {
    let segments: [DonutSegment]
    var size: CGFloat = 140
    var thickness: CGFloat = 16

    private var total: Double { segments.reduce(0) { $0 + $1.value } }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: thickness)
            if total > 0 {
                ForEach(Array(segments.enumerated()), id: \.element.id) { _, seg in
                    let start = fraction(before: seg)
                    let end = start + seg.value / total
                    Circle()
                        .trim(from: start, to: max(start, end - 0.002)) // tiny gap between slices
                        .stroke(seg.color, style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func fraction(before seg: DonutSegment) -> Double {
        guard total > 0 else { return 0 }
        var acc = 0.0
        for s in segments {
            if s.id == seg.id { break }
            acc += s.value / total
        }
        return acc
    }
}
