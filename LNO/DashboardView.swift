import SwiftUI

/// Time window for the equity curve. Mirrors the web dashboard's period control
/// (7D/30D/90D/1Y/ALL); slices the already-fetched snapshot history client-side.
enum Period: String, CaseIterable, Identifiable {
    case d7 = "7D", d30 = "30D", d90 = "90D", y1 = "1Y", all = "ALL"
    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .d7: return 7
        case .d30: return 30
        case .d90: return 90
        case .y1: return 365
        case .all: return nil
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: PortfolioStore
    @Binding var showSettings: Bool
    @State private var period: Period = .d90

    var body: some View {
        ZStack {
            AppBackground()
            content
        }
        .lnoTopBar("Overview", auth: auth, showSettings: $showSettings)
        .refreshable { await store.refresh(auth: auth) }
    }

    @ViewBuilder private var content: some View {
        if store.loading && store.lastLoaded == nil {
            LoadingView()
        } else if let err = store.loadError, store.lastLoaded == nil {
            ErrorView(message: err) { Task { await store.refresh(auth: auth) } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    kpiGrid
                    equitySection
                    botAllocationSection
                    byBotSection
                    pnlCalendarSection
                    fundAllocationSection
                    fundsSummary
                    if let synced = store.live?.syncedDate {
                        Text("Synced \(Fmt.relative(synced))")
                            .font(.caption2).foregroundStyle(Theme.faintText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total equity").font(.subheadline).foregroundStyle(Theme.mutedText)
            Text(Fmt.usd(store.equity)).font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.navy).lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 8) {
                Text(Fmt.signedUSD(store.pnlDay)).fontWeight(.semibold)
                Text("(\(Fmt.pct(store.pnlDayPct)))")
            }
            .font(.subheadline).foregroundStyle(Theme.pnlColor(store.pnlDay))
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            KPITile(label: "Open P&L", value: Fmt.signedUSD(store.openPnl),
                    icon: "chart.line.uptrend.xyaxis", accent: Theme.pnlColor(store.openPnl),
                    sub: "\(store.openBots.count) open", subColor: Theme.mutedText)
            KPITile(label: "Exposure", value: Fmt.usd(store.exposure),
                    icon: "briefcase.fill", accent: Theme.blueAccent,
                    sub: "notional", subColor: Theme.mutedText)
            KPITile(label: "Funds", value: "\(store.funds.count)",
                    icon: "square.stack.3d.up.fill", accent: Theme.up,
                    sub: "\(store.openBots.count) positions", subColor: Theme.mutedText)
            KPITile(label: "Incidents", value: "\(store.ongoingIncidents)",
                    icon: store.hasOngoingIncident ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                    accent: store.hasOngoingIncident ? Theme.gold : Theme.up,
                    // Service-health status only (exchange API/data feed) — matches the web
                    // Live page's incident-status card, not portfolio performance breaches.
                    sub: store.hasOngoingIncident ? "Ongoing incident" : "Up and running",
                    subColor: store.hasOngoingIncident ? Theme.gold : Theme.up)
        }
    }

    /// Snapshots trimmed to the selected period (chart only — headline equity/P&L
    /// above always reflect the live/latest values regardless of this selector).
    private var periodSnapshots: [Snapshot] {
        guard let days = period.days else { return store.snapshots }
        return Array(store.snapshots.suffix(days))
    }

    @ViewBuilder private var equitySection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Equity curve").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    Spacer()
                }
                periodControl
                if periodSnapshots.count > 1 {
                    EquityChart(snapshots: periodSnapshots)
                } else {
                    Text("Not enough history yet.")
                        .font(.footnote).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        }
    }

    private var periodControl: some View {
        HStack(spacing: 6) {
            ForEach(Period.allCases) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { period = p }
                } label: {
                    Text(p.rawValue)
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(period == p ? Theme.gold : Theme.pageBG)
                        .foregroundStyle(period == p ? Theme.navy : Theme.mutedText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var fundsSummary: some View {
        if !store.fundGroups.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("By fund").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    ForEach(store.fundGroups) { g in
                        HStack {
                            FundDot(color: g.color)
                            Text(g.name).foregroundStyle(Theme.navy)
                            Text("· \(g.bots.count)").font(.caption).foregroundStyle(Theme.mutedText)
                            Spacer()
                            Text(Fmt.signedUSD(g.uPnl)).fontWeight(.semibold)
                                .foregroundStyle(Theme.pnlColor(g.uPnl))
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Bot allocation / By Bot (promoted — mirrors today's web restructuring:
    // per-individual-open-position detail now sits right after the equity curve,
    // paired with the PnL calendar; fund-level roll-up moves to the bottom below.)

    private static let fundPalette: [Color] = [
        Color(hex: 0xC9A24D), Color(hex: 0x3B82F6), Color(hex: 0x10B981), Color(hex: 0x8B5CF6),
        Color(hex: 0xF59E0B), Color(hex: 0xEF4444), Color(hex: 0xEC4899), Color(hex: 0x6366F1),
    ]
    private func paletteColor(_ i: Int) -> Color { Self.fundPalette[i % Self.fundPalette.count] }

    @ViewBuilder private var botAllocationSection: some View {
        let bots = store.openBotsByExposure
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bot Allocation").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if bots.isEmpty {
                    Text("No open exposure yet.").font(.footnote).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    VStack(spacing: 14) {
                        ZStack {
                            DonutChart(segments: bots.enumerated().map { i, b in
                                DonutSegment(value: abs(b.notional), color: paletteColor(i))
                            }, size: 130, thickness: 15)
                            VStack(spacing: 1) {
                                Text(Fmt.usd(store.exposure)).font(.system(.callout, design: .rounded)).fontWeight(.bold)
                                    .foregroundStyle(Theme.navy)
                                Text("exposure").font(.caption2).foregroundStyle(Theme.faintText)
                            }
                        }
                        VStack(spacing: 6) {
                            ForEach(Array(bots.prefix(8).enumerated()), id: \.element.id) { i, b in
                                HStack {
                                    Circle().fill(paletteColor(i)).frame(width: 8, height: 8)
                                    Text(b.symbol).font(.caption).foregroundStyle(Theme.mutedText)
                                    Spacer()
                                    Text(store.exposure > 0 ? Fmt.pct(abs(b.notional) / store.exposure * 100, decimals: 1) : "0.0%")
                                        .font(.caption).fontWeight(.medium).foregroundStyle(Theme.navy)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var byBotSection: some View {
        let bots = store.openBotsByExposure
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("By Bot").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if bots.isEmpty {
                    Text("No open positions.").font(.footnote).foregroundStyle(Theme.mutedText)
                } else {
                    VStack(spacing: 10) {
                        ForEach(bots.prefix(10)) { b in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(b.symbol).font(.system(.subheadline, design: .monospaced)).foregroundStyle(Theme.navy)
                                    SideBadge(isLong: b.isLong)
                                    Spacer()
                                    Text(Fmt.signedUSD(b.unrealizedPnl)).fontWeight(.semibold)
                                        .foregroundStyle(Theme.pnlColor(b.unrealizedPnl))
                                }
                                HStack {
                                    if let fid = b.fundId, let fund = store.funds.first(where: { $0.id == fid }) {
                                        FundBadge(name: fund.name, color: fund.color)
                                    } else {
                                        Text("Unassigned").font(.caption2).foregroundStyle(Theme.faintText)
                                    }
                                    Spacer()
                                    Text("\(Fmt.usd(abs(b.notional))) · \(b.leverage > 0 ? "\(Fmt.number(b.leverage))×" : "—")")
                                        .font(.caption2).foregroundStyle(Theme.mutedText)
                                }
                            }
                            if b.id != bots.prefix(10).last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - PnL calendar (GitHub-style daily heatmap; also feeds the PnL Calendar
    // widget via PortfolioStore.saveWidgetSnapshot()).

    @ViewBuilder private var pnlCalendarSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("PnL Calendar").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                    Spacer()
                    Text("daily").font(.caption2).foregroundStyle(Theme.faintText)
                }
                PnlCalendarView(days: store.pnlCalendar)
            }
        }
    }

    // MARK: - Fund allocation (demoted — supplementary roll-up below the bot-level view).

    @ViewBuilder private var fundAllocationSection: some View {
        let groups = store.fundGroups
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fund Allocation").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                if groups.isEmpty {
                    Text("No open exposure yet.").font(.footnote).foregroundStyle(Theme.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 100)
                } else {
                    let total = groups.reduce(0) { $0 + $1.notional }
                    VStack(spacing: 14) {
                        ZStack {
                            DonutChart(segments: groups.enumerated().map { i, g in
                                DonutSegment(value: g.notional, color: Color(hexString: g.color) ?? paletteColor(i))
                            }, size: 130, thickness: 15)
                            VStack(spacing: 1) {
                                Text(Fmt.usd(total)).font(.system(.callout, design: .rounded)).fontWeight(.bold)
                                    .foregroundStyle(Theme.navy)
                                Text("exposure").font(.caption2).foregroundStyle(Theme.faintText)
                            }
                        }
                        VStack(spacing: 6) {
                            ForEach(groups) { g in
                                HStack {
                                    FundDot(color: g.color, size: 8)
                                    Text(g.name).font(.caption).foregroundStyle(Theme.mutedText)
                                    Spacer()
                                    Text(total > 0 ? Fmt.pct(g.notional / total * 100, decimals: 1) : "0.0%")
                                        .font(.caption).fontWeight(.medium).foregroundStyle(Theme.navy)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
