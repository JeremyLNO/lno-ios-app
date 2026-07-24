import SwiftUI

struct PricesView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @Binding var showSettings: Bool
    @State private var tickers: [String: BinanceTicker] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var order: [String] = []

    private static let orderKey = "lno_price_order"
    /// Ticker refresh cadence — matches the web dashboard's live price polling.
    private static let pollInterval: UInt64 = 5_000_000_000

    /// Unique traded symbols (Binance USDⓈ-M) with at least one operational
    /// (open) bot — matches the web dashboard's Prices page.
    private var symbols: [String] {
        Array(Set(store.openBots.map { $0.symbol })).sorted()
    }

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Prices", auth: auth, showSettings: $showSettings)
        .task(id: symbols) {
            syncOrder()
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder private var content: some View {
        if symbols.isEmpty {
            EmptyStateView(icon: "bitcoinsign.circle", title: "No traded assets",
                           subtitle: "Prices track the assets in your open positions.")
        } else if loading && tickers.isEmpty {
            LoadingView()
        } else if let error, tickers.isEmpty {
            ErrorView(message: LocalizedStringKey(error)) { Task { await load() } }
        } else {
            List {
                ForEach(order, id: \.self) { sym in
                    priceRow(sym, ticker: tickers[sym])
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSpacing(12)
            .environment(\.editMode, .constant(.active))
        }
    }

    private func priceRow(_ symbol: String, ticker: BinanceTicker?) -> some View {
        let base = symbol.replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USDC", with: "")
        return HStack {
            ZStack {
                Circle().fill(Theme.navy).frame(width: 36, height: 36)
                Text(String(base.prefix(3))).font(.system(size: 11)).fontWeight(.bold).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(base).font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                Text(symbol).font(.caption2).foregroundStyle(Theme.faintText)
            }
            Spacer()
            if let t = ticker {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Fmt.price(t.price)).font(.system(.body, design: .rounded)).fontWeight(.bold)
                        .foregroundStyle(Theme.navy)
                    changeBadge(t.changePct)
                }
            } else {
                ProgressView().tint(Theme.gold)
            }
        }
        .padding(16)
        .background(Theme.cardBG)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func changeBadge(_ pct: Double) -> some View {
        let up = pct >= 0
        return HStack(spacing: 2) {
            Image(systemName: up ? "triangle.fill" : "triangle.fill")
                .font(.system(size: 6)).rotationEffect(.degrees(up ? 0 : 180))
            Text(Fmt.pct(pct))
        }
        .font(.caption2).fontWeight(.semibold)
        .foregroundStyle(up ? Theme.up : Theme.down)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background((up ? Theme.up : Theme.down).opacity(0.1))
        .clipShape(Capsule())
    }

    /// Merges the persisted custom order with the current symbol set: keeps known
    /// symbols in their saved order, appends new ones, drops symbols no longer held.
    private func syncOrder() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.orderKey) ?? []
        var next = saved.filter { symbols.contains($0) }
        for s in symbols where !next.contains(s) { next.append(s) }
        if next != order {
            order = next
            UserDefaults.standard.set(order, forKey: Self.orderKey)
        }
    }

    private func move(from: IndexSet, to: Int) {
        order.move(fromOffsets: from, toOffset: to)
        UserDefaults.standard.set(order, forKey: Self.orderKey)
    }

    /// On the first load (no tickers yet) a failure shows the full-screen error
    /// state. On later background polls, a dropped request just keeps the last
    /// known prices on screen instead of flashing an error over live data.
    private func load() async {
        guard !symbols.isEmpty else { return }
        let hadData = !tickers.isEmpty
        if !hadData { loading = true }
        defer { loading = false }
        do {
            let fresh = try await APIClient.tickers(symbols: symbols)
            if !fresh.isEmpty { tickers = fresh; error = nil }
            else if !hadData { error = "Could not load prices." }
        } catch {
            if !hadData { self.error = "Could not load prices." }
        }
    }
}
