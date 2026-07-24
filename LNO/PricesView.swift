import SwiftUI

struct PricesView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @Binding var showSettings: Bool
    @State private var tickers: [String: BinanceTicker] = [:]
    @State private var loading = false
    @State private var error: String?
    @State private var order: [String] = []
    @State private var fearGreed: (value: Int, label: String)?
    @State private var dominance: (btc: Double, eth: Double)?

    private static let orderKey = "lno_price_order"
    /// Ticker refresh cadence — matches the web dashboard's live price polling.
    private static let pollInterval: UInt64 = 5_000_000_000
    /// Sentiment (Fear & Greed / dominance) cadence — matches the web's 60s poll.
    private static let sentimentPollInterval: UInt64 = 60_000_000_000

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
        .task {
            while !Task.isCancelled {
                await loadSentiment()
                try? await Task.sleep(nanoseconds: Self.sentimentPollInterval)
            }
        }
        .refreshable { await load(); await loadSentiment() }
    }

    @ViewBuilder private var content: some View {
        if !(auth.user?.can("view_activity") ?? false) {
            DeniedView()
        } else if symbols.isEmpty {
            EmptyStateView(icon: "bitcoinsign.circle", title: "No traded assets",
                           subtitle: "Prices track the assets in your open positions.")
        } else if loading && tickers.isEmpty {
            LoadingView()
        } else if let error, tickers.isEmpty {
            ErrorView(message: LocalizedStringKey(error)) { Task { await load() } }
        } else {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        kpiRow
                        sentimentCard
                        heatmapCard
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(order, id: \.self) { sym in
                        priceRow(sym, ticker: tickers[sym])
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                    .onMove(perform: move)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowSpacing(12)
            .environment(\.editMode, .constant(.active))
        }
    }

    // MARK: - KPI row (Active Markets / 24h Volume / Gainers / Losers)

    private var kpiRow: some View {
        let values = order.compactMap { tickers[$0] }
        let gainers = values.filter { $0.changePct >= 0 }.count
        let losers = values.count - gainers
        let totalVolume = values.reduce(0) { $0 + $1.volume }
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            KPITile(label: "Active Markets", value: "\(values.count)", icon: "bitcoinsign.circle")
            KPITile(label: "24h Volume", value: Fmt.compactUSD(totalVolume), icon: "chart.bar")
            KPITile(label: "Gainers", value: "\(gainers)", icon: "arrow.up.right", accent: Theme.up)
            KPITile(label: "Losers", value: "\(losers)", icon: "arrow.down.right", accent: Theme.down)
        }
    }

    // MARK: - Market Sentiment (Fear & Greed donut + BTC/ETH dominance)

    private func fearGreedColor(_ v: Int) -> Color {
        switch v {
        case ..<25: return Theme.down
        case 25..<45: return Color(hex: 0xF59E0B)
        case 45..<55: return Color(hex: 0xA3E635)
        default: return Theme.up
        }
    }

    private var sentimentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Market Sentiment").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                HStack(spacing: 20) {
                    if let fg = fearGreed {
                        ZStack {
                            DonutChart(segments: [
                                .init(value: Double(fg.value), color: fearGreedColor(fg.value)),
                                .init(value: Double(100 - fg.value), color: Theme.stroke),
                            ], size: 96, thickness: 10)
                            VStack(spacing: 0) {
                                Text("\(fg.value)").font(.title3).fontWeight(.bold).foregroundStyle(Theme.navy)
                                Text(fg.label).font(.caption2).foregroundStyle(Theme.mutedText)
                            }
                        }
                    } else {
                        ProgressView().tint(Theme.gold).frame(width: 96, height: 96)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        dominanceRow("BTC Dominance", dominance?.btc)
                        dominanceRow("ETH Dominance", dominance?.eth)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dominanceRow(_ label: LocalizedStringKey, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(Theme.mutedText)
            Text(pct.map { Fmt.pct($0) } ?? "—").font(.subheadline).fontWeight(.bold).foregroundStyle(Theme.navy)
        }
    }

    // MARK: - Heatmap (color intensity by |%change|, clamped ±5%, same scale as PnL heatmaps)

    private var heatmapCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Heatmap").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(order, id: \.self) { sym in
                        let t = tickers[sym]
                        let base = sym.replacingOccurrences(of: "USDT", with: "").replacingOccurrences(of: "USDC", with: "")
                        VStack(spacing: 2) {
                            Text(base).font(.caption2).fontWeight(.bold)
                            Text(t.map { Fmt.pct($0.changePct) } ?? "—").font(.caption2).fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(pctHeatColor(t?.changePct))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func pctHeatColor(_ pct: Double?) -> Color {
        guard let pct else { return Theme.stroke }
        let f = 0.35 + min(abs(pct) / 5, 1) * 0.65
        return (pct >= 0 ? Theme.up : Theme.down).opacity(f)
    }

    private func priceRow(_ symbol: String, ticker: BinanceTicker?) -> some View {
        let base = symbol.replacingOccurrences(of: "USDT", with: "")
            .replacingOccurrences(of: "USDC", with: "")
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
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
                if let t = ticker {
                    HStack {
                        metric("24h High", Fmt.price(t.high))
                        Spacer()
                        metric("24h Low", Fmt.price(t.low))
                        Spacer()
                        metric("Volume", Fmt.compactUSD(t.volume))
                    }
                }
            }
        }
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).textCase(.uppercase).font(.system(size: 9)).foregroundStyle(Theme.faintText)
            Text(value).font(.caption).foregroundStyle(Theme.navy.opacity(0.85))
        }
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

    private func loadSentiment() async {
        async let fg = try? APIClient.fearGreed()
        async let dom = try? APIClient.marketDominance()
        let (fgResult, domResult) = await (fg, dom)
        if let fgResult { fearGreed = fgResult }
        if let domResult { dominance = domResult }
    }
}
