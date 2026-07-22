import Foundation

/// Compact portfolio snapshot the main app writes after every refresh, and the
/// widget extension reads — via the shared App Group container. Keeps the widget
/// extension itself simple (no networking, no auth, no Keychain sharing needed);
/// it just renders whatever the app last saw. This file is compiled into BOTH the
/// app and widget targets (see gen_pbxproj.py SHARED_FILES).
struct WidgetSnapshot: Codable {
    struct FundLine: Codable, Identifiable {
        var id: String
        var name: String
        var color: String
        var uPnl: Double
        var positionCount: Int
    }
    struct PositionLine: Codable, Identifiable {
        var id: String
        var botLabel: String   // exchange, e.g. "Binance" — identifies which bot/account holds this position
        var fundName: String
        var asset: String      // base asset only, e.g. "BTC" (no USDT/USDC suffix)
        var side: String
        var unrealizedPnl: Double
        var notional: Double
        var pnlPct: Double
    }
    struct ServiceCheck: Codable, Identifiable {
        var id: String { label }
        var label: String
        var state: String // "ok" | "warn" | "down" | "neutral"
        var sub: String
    }

    var equity: Double
    var pnlDay: Double
    var pnlDayPct: Double
    var openPnl: Double
    var exposure: Double
    var funds: [FundLine]
    var positions: [PositionLine]
    var serviceChecks: [ServiceCheck]
    var overallStatus: String
    /// Recent day-over-day PnL% series for the PnL Calendar widget — see
    /// LNOShared/PnlCalendar.swift. A stale cached snapshot written before this field
    /// existed simply fails to decode once (WidgetSnapshot.load() returns nil, and
    /// affected widgets fall back to their empty state) until the app's next refresh
    /// overwrites it with the new shape.
    var calendar: [PnlCalendarDay] = []
    var updatedAt: Date

    static let appGroup = "group.company.lno.controlcenter"
    private static let key = "lno_widget_snapshot"

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
