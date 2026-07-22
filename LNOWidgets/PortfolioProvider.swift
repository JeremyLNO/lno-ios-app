import SwiftUI
import WidgetKit

/// Shared timeline entry + provider for all four LNO widgets — each widget just
/// picks which fields of the snapshot to render. No networking here: the widget
/// extension only ever reads what the main app last wrote to the App Group.
struct PortfolioEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry {
        PortfolioEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) {
        completion(PortfolioEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        let entry = PortfolioEntry(date: Date(), snapshot: WidgetSnapshot.load())
        // The app pushes a reload after every refresh (foreground) or 15s/15min
        // background poll; this is just a backstop so the widget doesn't go stale
        // if the app hasn't been opened in a while.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// Shown in all four widgets when no snapshot has been saved yet (never opened
/// the app / not signed in).
struct WidgetEmptyState: View {
    var text = "Open LNO Control Center to load your portfolio."
    var body: some View {
        VStack(spacing: 6) {
            LNOLogo(showWordmark: false).frame(width: 28, height: 28)
            Text(text)
                .font(.caption2).foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}
