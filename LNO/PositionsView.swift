import SwiftUI

/// The closed round trips behind the open positions above. Loaded lazily and separately:
/// this list is history, not live state, so it must not ride on the 15-second position poll.
@MainActor
final class ClosedTradesStore: ObservableObject {
    @Published var trades: [ClosedTrade] = []
    @Published var loaded = false
    func load(auth: AuthStore) async {
        guard !loaded else { return }
        if auth.isDemo { trades = MockData.closedTrades; loaded = true; return }
        // A shareholder without view_trades simply gets nothing here rather than an error:
        // the section is additive, and the screen above it is the point.
        trades = (try? await auth.client.closedTrades(limit: 25).trades) ?? []
        loaded = true
    }
}

struct PositionsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @EnvironmentObject var router: DeepLinkRouter
    @Binding var showSettings: Bool
    @StateObject private var closed = ClosedTradesStore()

    /// Open positions and closed round trips answer different questions — "what am I
    /// holding" vs "what did we actually do" — and on a phone the second cannot live at the
    /// bottom of a scroll under N fund cards, where nobody would find it.
    private enum Scope: String, CaseIterable, Identifiable {
        case open, closed
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .open ? "Open" : "Closed trades" }
    }
    @State private var scope: Scope = {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "LNOTab") == "closed" { return .closed }
        #endif
        return .open
    }()

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Positions", auth: auth, showSettings: $showSettings)
        .refreshable { closed.loaded = false; await store.refresh(auth: auth); await closed.load(auth: auth) }
        .task { await closed.load(auth: auth) }
    }

    private func closedRow(_ t: ClosedTrade) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(t.symbol).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.navy)
                    SideBadge(isLong: t.isLong)
                }
                HStack(spacing: 6) {
                    Text(Fmt.relative(t.date)).font(.caption2).foregroundStyle(Theme.faintText)
                    if let d = t.durationS {
                        Text(Fmt.duration(seconds: d)).font(.caption2).foregroundStyle(Theme.faintText)
                    }
                    if let v = t.version {
                        Text(v).font(.caption2).foregroundStyle(Theme.gold)
                    }
                }
            }
            Spacer()
            Text(Fmt.signedUSD(t.netPnl))
                .font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                .foregroundStyle(t.netPnl >= 0 ? Theme.up : Theme.down)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.faintText)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if !(auth.user?.can("view_trades") ?? false) {
            DeniedView()
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8)
                if scope == .closed { closedContent } else { openContent }
            }
        }
    }

    @ViewBuilder private var closedContent: some View {
        if closed.trades.isEmpty {
            EmptyStateView(icon: "checkmark.circle", title: "No closed trade yet",
                           subtitle: "Round trips appear here once a position goes back to flat.")
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(closed.trades) { t in
                        NavigationLink { TradeDetailView(trade: t) } label: { closedRow(t) }
                            .buttonStyle(.plain)
                        if t.id != closed.trades.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder private var openContent: some View {
        if store.loading && store.lastLoaded == nil {
            LoadingView()
        } else if store.fundGroups.isEmpty {
            EmptyStateView(icon: "tray", title: "No open positions",
                           subtitle: "Positions appear here when funds are active.")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(store.fundGroups) { group in
                            fundCard(group).id(group.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: router.scrollToFundID) { _, fundID in
                    guard let fundID else { return }
                    withAnimation { proxy.scrollTo(fundID, anchor: .top) }
                    router.scrollToFundID = nil
                }
                .onAppear {
                    guard let fundID = router.scrollToFundID else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo(fundID, anchor: .top) }
                        router.scrollToFundID = nil
                    }
                }
            }
        }
    }

    private func fundCard(_ g: PortfolioStore.FundGroup) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FundDot(color: g.color, size: 12)
                    Text(g.displayName).font(.headline).foregroundStyle(Theme.navy)
                    Spacer()
                    Text(Fmt.signedUSD(g.uPnl)).fontWeight(.bold)
                        .foregroundStyle(Theme.pnlColor(g.uPnl))
                }
                Text("Exposure \(Fmt.usd(g.notional)) · \(g.bots.count) position\(g.bots.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Theme.mutedText)
                Divider().overlay(Theme.stroke)
                ForEach(g.bots.sorted { abs($0.notional) > abs($1.notional) }) { bot in
                    positionRow(bot)
                    if bot.id != g.bots.last?.id { Divider().overlay(Theme.stroke.opacity(0.5)) }
                }
            }
        }
    }

    private func positionRow(_ b: Bot) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(b.symbol).fontWeight(.semibold).foregroundStyle(Theme.navy)
                        SideBadge(isLong: b.isLong)
                    }
                    Text("\(b.exchange.uppercased()) · \(String(format: "%.0f×", b.leverage))")
                        .font(.caption2).foregroundStyle(Theme.mutedText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Fmt.signedUSD(b.unrealizedPnl, decimals: 2)).fontWeight(.semibold)
                        .foregroundStyle(Theme.pnlColor(b.unrealizedPnl))
                    Text(Fmt.usd(b.notional)).font(.caption2).foregroundStyle(Theme.mutedText)
                }
            }
            HStack {
                metric("Entry", Fmt.price(b.entry))
                Spacer()
                metric("Mark", Fmt.price(b.mark))
                Spacer()
                metric("Qty", String(format: "%g", b.qty))
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).textCase(.uppercase).font(.system(size: 9)).foregroundStyle(Theme.faintText)
            Text(value).font(.caption).foregroundStyle(Theme.navy.opacity(0.85))
        }
    }
}
