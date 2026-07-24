import SwiftUI

struct PositionsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @EnvironmentObject var router: DeepLinkRouter
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Positions", auth: auth, showSettings: $showSettings)
        .refreshable { await store.refresh(auth: auth) }
    }

    @ViewBuilder private var content: some View {
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
