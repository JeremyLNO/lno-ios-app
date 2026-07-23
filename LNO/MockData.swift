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

    static let alerts: [Alert] = [
        Alert(id: 1, type: "breach", code: "A2F9", summary: "Drawdown breach on Core Momentum: -4.2% intraday.",
              createdAt: isoMinutesAgo(35), ackedAt: nil, ackedBy: nil),
        Alert(id: 2, type: "api_error", code: "B71C", summary: "Binance API latency elevated (860ms avg over 5 min).",
              createdAt: isoMinutesAgo(210), ackedAt: isoMinutesAgo(180), ackedBy: "jeremy"),
        Alert(id: 3, type: "breach", code: "D0E4", summary: "Daily report generated and sent to shareholders.",
              createdAt: isoMinutesAgo(60 * 14), ackedAt: isoMinutesAgo(60 * 14), ackedBy: "system"),
    ]

    private static func isoMinutesAgo(_ m: Int) -> String {
        let d = Date().addingTimeInterval(-Double(m) * 60)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
}
