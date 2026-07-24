import SwiftUI

/// Mirrors the web dashboard's Realtime/"Live" page (src/pages/RealtimePage.tsx):
/// an operations dashboard combining live open positions, a fills/trade log,
/// buy/sell order flow, service health and incident/exchange-connectivity
/// monitoring — gated by `view_realtime`, with Exchange Connectivity admin-only,
/// exactly like the web page.
struct RealtimeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @Binding var showSettings: Bool

    @State private var fills: [Fill] = []
    @State private var incidents: [Alert] = []
    @State private var exchanges: [ExchangeStatus] = []
    @State private var fundFilter: String? = nil // nil = All, "__unassigned" = Unassigned, else fund id
    @State private var detailBot: Bot?

    private static let pollInterval: UInt64 = 30_000_000_000

    private var canAdmin: Bool { auth.user?.isAdmin ?? false }

    private var filteredBots: [Bot] {
        guard let fundFilter else { return store.openBots }
        if fundFilter == "__unassigned" { return store.openBots.filter { $0.fundId == nil } }
        return store.openBots.filter { $0.fundId == fundFilter }
    }

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Live", auth: auth, showSettings: $showSettings)
        .task {
            while !Task.isCancelled {
                await loadAll()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
        .refreshable { await loadAll() }
        .sheet(item: $detailBot) { bot in PositionDetailSheet(bot: bot) }
    }

    @ViewBuilder private var content: some View {
        if !(auth.user?.can("view_realtime") ?? false) {
            DeniedView()
        } else if store.loading && store.lastLoaded == nil {
            LoadingView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.openBots.isEmpty { marketTicker }
                    fundFilterRow
                    kpiGrid
                    recentFillsCard
                    tradeStreamCard
                    orderFlowCard
                    openPositionsCard
                    serviceHealthCard
                    recentIncidentsCard
                    if canAdmin { exchangeConnectivityCard }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Market ticker strip

    private var marketTicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.openBots) { b in
                    HStack(spacing: 8) {
                        Text(b.baseAsset).font(.system(.caption, design: .monospaced)).fontWeight(.semibold).foregroundStyle(Theme.navy)
                        SideBadge(isLong: b.isLong)
                        Text(Fmt.signedUSD(b.unrealizedPnl)).font(.caption).fontWeight(.medium).foregroundStyle(Theme.pnlColor(b.unrealizedPnl))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.cardBG)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Fund filter

    private var fundFilterRow: some View {
        Menu {
            Button("All") { fundFilter = nil }
            Button("Unassigned") { fundFilter = "__unassigned" }
            ForEach(store.funds) { f in
                Button(f.name) { fundFilter = f.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(fundFilterLabel).font(.subheadline).fontWeight(.medium).foregroundStyle(Theme.navy)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.mutedText)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.cardBG)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var fundFilterLabel: String {
        guard let fundFilter else { return "All" }
        if fundFilter == "__unassigned" { return "Unassigned" }
        return store.funds.first { $0.id == fundFilter }?.name ?? "All"
    }

    // MARK: - KPI grid

    private var kpiGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                KPITile(label: "Total equity", value: Fmt.usd(store.equity), icon: "banknote")
                KPITile(label: "Open Positions", value: "\(store.openBots.count)", icon: "list.bullet.rectangle")
                KPITile(label: "Open P&L", value: Fmt.signedUSD(store.openPnl), icon: "chart.line.uptrend.xyaxis",
                        accent: store.openPnl >= 0 ? Theme.up : Theme.down)
                KPITile(label: "Exposure", value: Fmt.usd(store.exposure), icon: "scalemass")
            }
            incidentStatusRow
        }
    }

    private var incidentStatusRow: some View {
        HStack {
            Circle().fill(store.hasOngoingIncident ? Theme.down : Theme.up).frame(width: 8, height: 8)
            Text(store.hasOngoingIncident ? "Ongoing incident" : "Up and running")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(store.hasOngoingIncident ? Theme.down : Theme.up)
            Spacer()
        }
        .padding(12)
        .background(Theme.cardBG)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Fills

    private var recentFillsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Fills").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if fills.isEmpty {
                    Text("No data").font(.caption).foregroundStyle(Theme.faintText)
                } else {
                    ForEach(fills.prefix(15)) { f in
                        HStack {
                            Text(f.symbol).font(.system(.caption, design: .monospaced)).fontWeight(.semibold).foregroundStyle(Theme.navy)
                            Text(f.side.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(f.isBuy ? Theme.up : Theme.down)
                            Spacer()
                            Text(Fmt.number(f.qty, decimals: 3)).font(.caption2).foregroundStyle(Theme.mutedText)
                            Text(Fmt.price(f.price)).font(.caption2).foregroundStyle(Theme.mutedText)
                            Text(Fmt.relative(f.date)).font(.caption2).foregroundStyle(Theme.faintText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Trade Stream (same data, log-styled)

    private var tradeStreamCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Trade Stream").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    if !fills.isEmpty {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Theme.up).frame(width: 6, height: 6)
                            Text("streaming").font(.caption2).foregroundStyle(Theme.up)
                        }
                    }
                }
                if fills.isEmpty {
                    Text("No data").font(.caption).foregroundStyle(Theme.faintText)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fills.prefix(20)) { f in
                            Text("\(f.side.uppercased()) \(f.symbol) \(Fmt.number(f.qty, decimals: 3)) @ \(Fmt.price(f.price))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(f.isBuy ? Theme.up : Theme.down)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Order Flow donut

    private var orderFlowCard: some View {
        let buyQty = fills.filter { $0.isBuy }.reduce(0) { $0 + $1.qty }
        let sellQty = fills.filter { !$0.isBuy }.reduce(0) { $0 + $1.qty }
        let total = buyQty + sellQty
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Order Flow").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                HStack(spacing: 20) {
                    ZStack {
                        DonutChart(segments: [.init(value: buyQty, color: Theme.up), .init(value: sellQty, color: Theme.down)], size: 96, thickness: 12)
                        VStack(spacing: 0) {
                            Text(Fmt.number(buyQty - sellQty, decimals: 2)).font(.headline).foregroundStyle(Theme.navy)
                            Text("Net Flow").font(.caption2).foregroundStyle(Theme.mutedText)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) { Circle().fill(Theme.up).frame(width: 6, height: 6); Text("Buy \(Fmt.pct(total > 0 ? buyQty/total*100 : 0, decimals: 0))").font(.caption) }
                        HStack(spacing: 5) { Circle().fill(Theme.down).frame(width: 6, height: 6); Text("Sell \(Fmt.pct(total > 0 ? sellQty/total*100 : 0, decimals: 0))").font(.caption) }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Open Positions

    private var openPositionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Open Positions").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    if let connected = store.live?.connected, connected > 0 {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(Theme.up).frame(width: 6, height: 6)
                            Text("connected \(connected)").font(.caption2).foregroundStyle(Theme.up)
                        }
                    }
                }
                if filteredBots.isEmpty {
                    Text("No open positions.").font(.caption).foregroundStyle(Theme.faintText)
                } else {
                    ForEach(filteredBots.sorted { abs($0.notional) > abs($1.notional) }) { b in
                        Button { detailBot = b } label: { positionRow(b) }
                            .buttonStyle(.plain)
                        if b.id != filteredBots.last?.id { Divider().overlay(Theme.stroke.opacity(0.5)) }
                    }
                }
            }
        }
    }

    private func positionRow(_ b: Bot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.symbol).fontWeight(.semibold).foregroundStyle(Theme.navy)
                SideBadge(isLong: b.isLong)
                Spacer()
                Text(Fmt.signedUSD(b.unrealizedPnl, decimals: 2)).fontWeight(.semibold).foregroundStyle(Theme.pnlColor(b.unrealizedPnl))
            }
            HStack {
                miniMetric("Entry", Fmt.price(b.entry))
                Spacer()
                miniMetric("Mark", Fmt.price(b.mark))
                Spacer()
                miniMetric("Lev", "\(Fmt.number(b.leverage))×")
                Spacer()
                if let pct = b.liqDistancePct {
                    miniMetric("Liq Dist", Fmt.pct(pct, decimals: 1), color: liqColor(b.liqLevel))
                }
            }
            Text(b.exchange.capitalized).font(.caption2).foregroundStyle(Theme.faintText)
        }
        .padding(.vertical, 4)
    }

    private func miniMetric(_ label: LocalizedStringKey, _ value: String, color: Color = Theme.navy) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).textCase(.uppercase).font(.system(size: 8)).foregroundStyle(Theme.faintText)
            Text(value).font(.caption2).foregroundStyle(color.opacity(0.9))
        }
    }

    private func liqColor(_ level: Bot.LiqLevel?) -> Color {
        switch level {
        case .danger: return Theme.down
        case .warn: return Color(hex: 0xF59E0B)
        default: return Theme.mutedText
        }
    }

    // MARK: - Service Health (reuses PortfolioStore.serviceChecks, shared with the widget)

    private var serviceHealthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Service Status").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                ForEach(store.serviceChecks) { c in
                    HStack {
                        Circle().fill(dotColor(for: c.state)).frame(width: 7, height: 7)
                        Text(LocalizedStringKey(c.label)).font(.caption).foregroundStyle(Theme.navy)
                        Spacer()
                        Text(LocalizedStringKey(c.sub)).font(.caption2).foregroundStyle(Theme.mutedText)
                    }
                }
            }
        }
    }

    private func dotColor(for state: PortfolioStore.ServiceCheck.State) -> Color {
        switch state {
        case .ok: return Theme.up
        case .warn: return Color(hex: 0xF59E0B)
        case .down: return Theme.down
        case .neutral: return Theme.mutedText
        }
    }

    // MARK: - Recent Incidents

    private var recentIncidentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Incidents").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if incidents.isEmpty {
                    Text("No incidents").font(.caption).foregroundStyle(Theme.faintText)
                } else {
                    ForEach(incidents) { a in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(a.isAcked ? Theme.up : Theme.down).frame(width: 6, height: 6).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.summary).font(.caption).foregroundStyle(Theme.navy)
                                Text(Fmt.relative(a.date)).font(.caption2).foregroundStyle(Theme.faintText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Exchange Connectivity (admin-only, matches the web's role==='admin' gate)

    private var exchangeConnectivityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Exchange Connectivity").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if exchanges.isEmpty {
                    Text("No data").font(.caption).foregroundStyle(Theme.faintText)
                } else {
                    ForEach(exchanges) { e in
                        HStack {
                            Circle().fill(e.isConnected ? Theme.up : Theme.down).frame(width: 7, height: 7)
                            Text(e.displayLabel).font(.caption).foregroundStyle(Theme.navy)
                            Spacer()
                            if let ms = e.latencyMs {
                                Text("\(ms) ms").font(.caption2).foregroundStyle(ms > 1000 ? Color(hex: 0xF59E0B) : Theme.mutedText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        async let f = try? auth.client.fills()
        async let i = try? auth.client.alerts(type: "api_error", limit: 6)
        async let e = canAdmin ? (try? auth.client.exchanges()) : nil
        let (fResult, iResult, eResult) = await (f, i, e)
        if let fResult { fills = fResult }
        if let iResult { incidents = iResult }
        if let eResult { exchanges = eResult }
    }
}

/// Minimal position detail sheet — "View Details" on the web opens a richer overlay
/// (PositionDetailOverlay with a mini chart); this covers the same core fields in a
/// view-only, single-screen form factor appropriate for the app.
private struct PositionDetailSheet: View {
    let bot: Bot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Symbol", bot.symbol)
                    row("Side", bot.side.uppercased())
                    row("Exchange", bot.exchange.capitalized)
                }
                Section {
                    row("Entry", Fmt.price(bot.entry))
                    row("Mark", Fmt.price(bot.mark))
                    row("Quantity", Fmt.number(bot.qty, decimals: 4))
                    row("Leverage", "\(Fmt.number(bot.leverage))×")
                }
                Section {
                    row("Unrealized P&L", Fmt.signedUSD(bot.unrealizedPnl, decimals: 2))
                    row("Notional", Fmt.usd(bot.notional))
                    if let pct = bot.liqDistancePct {
                        row("Liq. Distance", Fmt.pct(pct, decimals: 1))
                    }
                }
            }
            .navigationTitle(bot.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.mutedText)
            Spacer()
            Text(value).fontWeight(.medium).foregroundStyle(Theme.navy)
        }
    }
}
