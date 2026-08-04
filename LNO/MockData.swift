import Foundation

/// Static, non-confidential sample data. Used by the DEBUG-only "Preview demo"
/// button for local testing, AND by the always-available App Review demo path
/// (Config.appReviewEmail) — so it must compile into Release too. Never contains
/// real LNO figures.
enum MockData {
    static let user = User(
        id: "demo", email: "demo@lno.company", firstName: "Alex", lastName: "Martin",
        role: "admin", permissions: ["view_activity", "view_trades", "view_reports"],
        phone: "", notify: true, authProvider: "google"
    )

    static let funds: [Fund] = [
        Fund(id: "f1", name: "Core Momentum", color: "#C9A24D", sort: 0, botCount: 3, openCount: 3),
        Fund(id: "f2", name: "Volatility Hedge", color: "#4285F4", sort: 1, botCount: 2, openCount: 2),
    ]

    static let bots: [Bot] = [
        Bot(id: "b1", exchange: "binance", symbol: "BTCUSDT", fundId: "f1", side: "long",
            qty: 0.42, entry: 61200, mark: 63840, unrealizedPnl: 1108.8, notional: 26812.8,
            leverage: 5, status: "open", firstSeen: nil, lastSeen: nil),
        Bot(id: "b2", exchange: "binance", symbol: "ETHUSDT", fundId: "f1", side: "long",
            qty: 6.1, entry: 3320, mark: 3465, unrealizedPnl: 884.5, notional: 21136.5,
            leverage: 4, status: "open", firstSeen: nil, lastSeen: nil),
        Bot(id: "b3", exchange: "bybit", symbol: "SOLUSDT", fundId: "f1", side: "short",
            qty: 180, entry: 168.4, mark: 171.9, unrealizedPnl: -630.0, notional: 30942.0,
            leverage: 3, status: "open", firstSeen: nil, lastSeen: nil),
        Bot(id: "b4", exchange: "okx", symbol: "MATICUSDT", fundId: "f2", side: "short",
            qty: 42000, entry: 0.612, mark: 0.589, unrealizedPnl: 966.0, notional: 24738.0,
            leverage: 3, status: "open", firstSeen: nil, lastSeen: nil),
        Bot(id: "b5", exchange: "binance", symbol: "AVAXUSDT", fundId: nil, side: "long",
            qty: 320, entry: 27.1, mark: 26.4, unrealizedPnl: -224.0, notional: 8448.0,
            leverage: 2, status: "open", firstSeen: nil, lastSeen: nil),
    ]

    static let live = LiveEquity(equity: 512_430, positions: 5, connected: 3,
                                  syncedAt: Date().timeIntervalSince1970 * 1000)

    static let snapshots: [Snapshot] = {
        let cal = Calendar(identifier: .gregorian)
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var out: [Snapshot] = []
        var equity = 468_000.0
        for i in stride(from: 29, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let drift = Double.random(in: -3200...5400)
            equity = max(420_000, equity + drift)
            out.append(Snapshot(day: df.string(from: day), equity: equity.rounded(), pnlDay: drift.rounded()))
        }
        return out
    }()

    static let milestones: [Milestone] = [
        Milestone(id: 1, scope: "monthly", metric: "equity_gain", threshold: 10_000, achievedAt: isoMinutesAgo(90), period: "2026-08"),
        Milestone(id: 2, scope: "monthly", metric: "equity_gain", threshold: 100_000, achievedAt: nil, period: nil),
        Milestone(id: 3, scope: "global", metric: "equity_level", threshold: 1_000_000, achievedAt: nil, period: nil),
    ]
    static let milestoneMeasured: [String: [String: Double]] = [
        "monthly": ["equity_gain": 28_450, "equity_pct": 12.4, "equity_level": 512_430, "position_pct": 6.2],
        "global": ["equity_gain": 112_430, "equity_pct": 28.1, "equity_level": 512_430, "position_pct": 6.2],
    ]

    static let alerts: [Alert] = [
        Alert(id: 1, type: "breach", code: "A2F9", summary: "Drawdown breach on Core Momentum: -4.2% intraday.",
              createdAt: isoMinutesAgo(35), ackedAt: nil, ackedBy: nil),
        Alert(id: 2, type: "api_error", code: "B71C", summary: "Binance API latency elevated (860ms avg over 5 min).",
              createdAt: isoMinutesAgo(210), ackedAt: isoMinutesAgo(180), ackedBy: "jeremy"),
        Alert(id: 3, type: "breach", code: "D0E4", summary: "Daily report generated and sent to shareholders.",
              createdAt: isoMinutesAgo(60 * 14), ackedAt: isoMinutesAgo(60 * 14), ackedBy: "system"),
    ]

    /// Sample findings for the demo/App Review session. Non-confidential and static, like
    /// everything else here — the point is that a reviewer sees a populated screen rather
    /// than an empty state that looks like a broken feature.
    static let anomalies: [Anomaly] = [
        Anomaly(id: 1, code: "profit_factor_drop", scope: "bot:binance:SOLUSDT", severity: "critical",
                summary: "Profit factor collapsed from 1.62 to 0.71",
                cause: "The recent window is losing money overall.",
                evidence: ["variant": .text("losing"), "baselinePF": .number(1.62), "recentPF": .number(0.71),
                           "dropPct": .number(56.2), "recentTrades": .number(19)],
                detectedAt: isoMinutesAgo(90), resolvedAt: nil, ackedAt: nil, ackedBy: nil),
        Anomaly(id: 2, code: "dormant_position", scope: "bot:binance:XRPUSDT", severity: "warning",
                summary: "XRPUSDT open and unchanged for 61h",
                cause: "The position has not moved in either direction for days while remaining exposed.",
                evidence: ["variant": .text("default"), "symbol": .text("XRPUSDT"), "hoursIdle": .number(61),
                           "thresholdHours": .number(48)],
                detectedAt: isoMinutesAgo(300), resolvedAt: nil, ackedAt: nil, ackedBy: nil),
        Anomaly(id: 3, code: "slippage_rise", scope: "bot:binance:ETHUSDT", severity: "warning",
                summary: "Slippage per trade rose from 1.10 to 2.40",
                cause: "Orders are executing further from their asked price than usual.",
                evidence: ["variant": .text("default"), "baselineAvg": .number(1.10), "recentAvg": .number(2.40),
                           "risePct": .number(118), "recentTrades": .number(23)],
                detectedAt: isoMinutesAgo(420), resolvedAt: nil, ackedAt: nil, ackedBy: nil),
    ]

    static let closedTrades: [ClosedTrade] = [
        ClosedTrade(id: "binance:BTCUSDT:9001", symbol: "BTCUSDT", direction: "LONG", qty: 0.4,
                    entryPrice: 59_820, exitPrice: 60_640, netPnl: 312.40, commission: 19.10, funding: -4.20,
                    openedAt: isoMinutesAgo(60 * 9), closedAt: isoMinutesAgo(60 * 6), durationS: 10_800,
                    leverage: 5, version: "v1.1"),
        ClosedTrade(id: "binance:ETHUSDT:9002", symbol: "ETHUSDT", direction: "SHORT", qty: 3,
                    entryPrice: 3_255, exitPrice: 3_291, netPnl: -118.60, commission: 8.40, funding: 1.10,
                    openedAt: isoMinutesAgo(60 * 26), closedAt: isoMinutesAgo(60 * 22), durationS: 14_400,
                    leverage: 10, version: "v1.1"),
        ClosedTrade(id: "binance:SOLUSDT:9003", symbol: "SOLUSDT", direction: "LONG", qty: 60,
                    entryPrice: 146.20, exitPrice: 149.05, netPnl: 158.90, commission: 7.05, funding: -0.80,
                    openedAt: isoMinutesAgo(60 * 50), closedAt: isoMinutesAgo(60 * 47), durationS: 10_800,
                    leverage: 5, version: "v1.0"),
    ]

    /// The audit view for whichever demo trade was tapped. Keyed by id so the numbers on the
    /// detail screen agree with the row that opened it.
    static func tradeDetail(for t: ClosedTrade) -> TradeDetail {
        TradeDetail(id: t.id, symbol: t.symbol, direction: t.direction, qty: t.qty,
                    entryPrice: t.entryPrice, exitPrice: t.exitPrice,
                    grossPnl: t.netPnl + t.commission - t.funding, commission: t.commission, funding: t.funding,
                    netPnl: t.netPnl, openedAt: t.openedAt, closedAt: t.closedAt, durationS: t.durationS,
                    leverage: t.leverage, notional: (t.entryPrice ?? 0) * t.qty,
                    mae: -abs(t.netPnl) * 1.4, mfe: abs(t.netPnl) * 1.9,
                    slippage: 2.35, rMultiple: t.netPnl / 420, unfilledOrders: 1,
                    orders: [
                        TradeOrder(orderId: 1, side: t.direction == "LONG" ? "BUY" : "SELL", type: "LIMIT", status: "FILLED",
                                   intendedPrice: t.entryPrice, avgPrice: (t.entryPrice ?? 0) * 1.0002,
                                   slippage: 1.20, unfilled: false, placedAt: t.openedAt),
                        TradeOrder(orderId: 2, side: t.direction == "LONG" ? "SELL" : "BUY", type: "STOP_MARKET", status: "CANCELED",
                                   intendedPrice: (t.entryPrice ?? 0) * 0.97, avgPrice: nil,
                                   slippage: nil, unfilled: true, placedAt: t.openedAt),
                        TradeOrder(orderId: 3, side: t.direction == "LONG" ? "SELL" : "BUY", type: "LIMIT", status: "FILLED",
                                   intendedPrice: t.exitPrice, avgPrice: (t.exitPrice ?? 0) * 0.9998,
                                   slippage: 1.15, unfilled: false, placedAt: t.closedAt),
                    ],
                    fills: [
                        TradeFill(tradeId: 1, side: t.direction == "LONG" ? "BUY" : "SELL", qty: t.qty,
                                  price: t.entryPrice ?? 0, realizedPnl: 0, commission: t.commission / 2, occurredAt: t.openedAt),
                        TradeFill(tradeId: 2, side: t.direction == "LONG" ? "SELL" : "BUY", qty: t.qty,
                                  price: t.exitPrice ?? 0, realizedPnl: t.netPnl + t.commission, commission: t.commission / 2, occurredAt: t.closedAt),
                    ])
    }

    private static func isoMinutesAgo(_ m: Int) -> String {
        let d = Date().addingTimeInterval(-Double(m) * 60)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}
