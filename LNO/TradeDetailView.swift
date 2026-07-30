import SwiftUI

/// One completed round trip, in full — the phone version of the web's position page.
///
/// A round trip is not the same thing as the `Bot` rows on the Positions screen above it:
/// those show where each (exchange, symbol) pair stands right now, this shows what was
/// actually done and what it cost. Fetched on demand rather than with the list, because the
/// server pays a klines call for MAE/MFE and that is not worth doing 50 times for a scroll.
struct TradeDetailView: View {
    @EnvironmentObject var auth: AuthStore
    let trade: ClosedTrade

    @State private var detail: TradeDetail?
    @State private var error: String?

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .navigationTitle("\(trade.symbol) \(trade.direction)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        if auth.isDemo { detail = MockData.tradeDetail(for: trade); return }
        do { detail = try await auth.client.tradeDetail(id: trade.id) }
        catch APIClientError.unauthorized { auth.handleUnauthorized() }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Could not load data" }
    }

    @ViewBuilder private var content: some View {
        if let error { ErrorView(message: LocalizedStringKey(error)) { Task { await load() } } }
        else if let d = detail { loaded(d) }
        else { LoadingView() }
    }

    private func loaded(_ d: TradeDetail) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                resultCard(d)
                executionCard(d)
                if !d.orders.isEmpty { ordersCard(d) }
                if !d.fills.isEmpty { fillsCard(d) }
            }
            .padding(16)
        }
    }

    // MARK: - Cards

    private func resultCard(_ d: TradeDetail) -> some View {
        Card {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("Net PnL", Fmt.signedUSD(d.netPnl), tone: d.netPnl)
                    metric("Gross PnL", Fmt.signedUSD(d.grossPnl), tone: d.grossPnl)
                    metric("Fees", Fmt.usd(d.commission), tone: -1)
                    metric("Funding", Fmt.signedUSD(d.funding), tone: d.funding)
                    // Nulls stay "—". A metric the desk has not instrumented must never
                    // render as a measured zero.
                    metric("MAE", d.mae.map { Fmt.signedUSD($0) } ?? "—", tone: -1)
                    metric("MFE", d.mfe.map { Fmt.signedUSD($0) } ?? "—", tone: 1)
                    // Slippage is a COST: positive means the fills came in worse than asked,
                    // so it is shown negated to read like every other PnL figure on screen.
                    metric("Slippage", d.slippage.map { Fmt.signedUSD(-$0) } ?? "—", tone: d.slippage.map { -$0 } ?? 0)
                    metric("R", d.rMultiple.map { String(format: "%.2fR", $0) } ?? "—", tone: d.rMultiple ?? 0)
                }
            }
        }
    }

    private func metric(_ label: LocalizedStringKey, _ value: String, tone: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.mutedText)
            Text(value)
                .font(.system(.subheadline, design: .monospaced)).fontWeight(.semibold)
                .foregroundStyle(value == "—" ? Theme.faintText : (tone >= 0 ? Theme.up : Theme.down))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func executionCard(_ d: TradeDetail) -> some View {
        Card {
            VStack(spacing: 0) {
                row("Average entry", d.entryPrice.map(Fmt.price) ?? "—")
                row("Average exit", d.exitPrice.map(Fmt.price) ?? "—")
                row("Notional", d.notional.map { Fmt.usd($0) } ?? "—")
                row("Duration", d.durationS.map { Fmt.duration(seconds: $0) } ?? "—")
                if let lev = d.leverage, lev > 0 { row("Leverage", "\(Int(lev))x") }
            }
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Theme.mutedText)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.navy)
        }
        .padding(.vertical, 5)
    }

    /// What was asked for, including what never filled — the half of the story the fill
    /// stream cannot tell.
    private func ordersCard(_ d: TradeDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Orders").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                ForEach(d.orders) { o in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(o.side).font(.caption2).fontWeight(.bold)
                                .foregroundStyle(o.isBuy ? Theme.up : Theme.down)
                            Text(o.type).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.mutedText)
                            Text(o.status).font(.caption2).foregroundStyle(Theme.faintText)
                            Spacer()
                            if let s = o.slippage {
                                Text(Fmt.signedUSD(-s)).font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(s > 0 ? Theme.down : Theme.up)
                            }
                        }
                        HStack(spacing: 6) {
                            Text("Asked").font(.caption2).foregroundStyle(Theme.faintText)
                            Text(o.intendedPrice.map(Fmt.price) ?? String(localized: "at market"))
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.mutedText)
                            Text("Got").font(.caption2).foregroundStyle(Theme.faintText)
                            Text(o.avgPrice.map(Fmt.price) ?? "—")
                                .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.mutedText)
                        }
                    }
                    .opacity(o.unfilled ? 0.5 : 1)
                    if o.id != d.orders.last?.id { Divider() }
                }
            }
        }
    }

    private func fillsCard(_ d: TradeDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Executions").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                ForEach(d.fills) { f in
                    HStack(spacing: 6) {
                        Text(f.side).font(.caption2).fontWeight(.bold)
                            .foregroundStyle(f.isBuy ? Theme.up : Theme.down)
                        Text(Fmt.number(f.qty, decimals: f.qty < 1 ? 4 : 2))
                            .font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.mutedText)
                        Text("@").font(.caption2).foregroundStyle(Theme.faintText)
                        Text(Fmt.price(f.price)).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.navy)
                        Spacer()
                        if f.realizedPnl != 0 {
                            Text(Fmt.signedUSD(f.realizedPnl)).font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(f.realizedPnl >= 0 ? Theme.up : Theme.down)
                        }
                    }
                }
            }
        }
    }
}
