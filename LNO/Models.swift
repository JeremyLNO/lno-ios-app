import Foundation
import SwiftUI

// Codable models mirroring the LNO Control Center API responses. Extra JSON keys
// are ignored automatically; only fields the read-only client needs are declared.

struct User: Codable, Identifiable, Equatable {
    let id: String
    let email: String
    var firstName: String = ""
    var lastName: String = ""
    let role: String
    var permissions: [String] = []
    var phone: String = ""
    var notify: Bool = false
    var authProvider: String = "password"
    /// Same `data:image/…;base64,…` string the web dashboard stores (ProfilePage's
    /// upload writes a FileReader data URL straight to this column) — decoded for
    /// display by `AvatarView`, never re-encoded by this read-only client.
    var avatar: String? = nil
    /// Nullable — the web dashboard's `users.language` column. `nil` means the
    /// user has never explicitly picked a language on either client; once set
    /// here it's the shared default the web and iOS app both sync to (see
    /// `LanguageStore.syncFromServer`).
    var language: String? = nil

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
    /// Mirrors the web dashboard's `hasPerm()` (src/ui.tsx) exactly: admin always passes,
    /// and a caller can ask about any-of a set of permissions (matching hasPerm's array overload).
    func can(_ perm: String) -> Bool { role == "admin" || permissions.contains(perm) }
    func can(anyOf perms: [String]) -> Bool { role == "admin" || perms.contains { permissions.contains($0) } }
    var isAdmin: Bool { role == "admin" }
}

struct AuthResponse: Codable { let token: String; let user: User }
struct MeResponse: Codable { let user: User }
struct APIError: Codable { let error: String }

// MARK: - Positions (bots) + live equity

struct Bot: Codable, Identifiable, Equatable {
    let id: String
    let exchange: String
    let symbol: String
    var fundId: String?
    let side: String
    let qty: Double
    let entry: Double
    let mark: Double
    let unrealizedPnl: Double
    let notional: Double
    let leverage: Double
    let status: String
    var firstSeen: String?
    var lastSeen: String?
    var liquidationPrice: Double? = nil
    var initialMargin: Double? = nil
    var lastChanged: String? = nil

    var isClosed: Bool { status == "closed" }
    /// Realized return on the margin committed to a closed position — mirrors the web's
    /// PositionsHeatmap cell coloring exactly (base = initialMargin, falling back to
    /// |notional| when margin wasn't recorded).
    var realizedPct: Double? {
        let base = initialMargin ?? (notional != 0 ? abs(notional) : nil)
        guard let base, base != 0 else { return nil }
        return unrealizedPnl / base * 100
    }

    var isOpen: Bool { status == "open" }
    var isLong: Bool { side.lowercased() == "long" || side.lowercased() == "buy" }
    /// % move from mark to liquidation price, and a severity band — mirrors the
    /// web's `liqInfo()` (src/ui.tsx) exactly, including its thresholds.
    var liqDistancePct: Double? {
        guard let liquidationPrice, mark != 0 else { return nil }
        return abs(mark - liquidationPrice) / mark * 100
    }
    enum LiqLevel { case danger, warn, ok }
    var liqLevel: LiqLevel? {
        guard let pct = liqDistancePct else { return nil }
        return pct < 10 ? .danger : (pct < 25 ? .warn : .ok)
    }
    /// Base asset for price lookups, e.g. "BTCUSDT" -> "BTC".
    var baseAsset: String {
        for q in ["USDT", "USDC", "BUSD", "USD"] where symbol.hasSuffix(q) {
            return String(symbol.dropLast(q.count))
        }
        return symbol
    }
}

struct LiveEquity: Codable, Equatable {
    var equity: Double = 0
    var positions: Int?
    /// Count of currently-connected exchange accounts (NOT a bool — the backend
    /// sends a number here; api/_lib/sync.js's `live` cache).
    var connected: Int?
    var syncedAt: Double?  // ms epoch

    var syncedDate: Date? { syncedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
}

struct BotsResponse: Codable { let bots: [Bot]; let live: LiveEquity? }

// MARK: - Funds

struct Fund: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let color: String
    var sort: Int = 0
    var botCount: Int = 0
    var openCount: Int = 0
}
struct FundsResponse: Codable { let funds: [Fund] }

// MARK: - Equity snapshots

struct Snapshot: Codable, Identifiable, Equatable {
    let day: String      // "YYYY-MM-DD"
    let equity: Double
    let pnlDay: Double
    var id: String { day }
}
struct SnapshotsResponse: Codable { let snapshots: [Snapshot] }

// MARK: - Alerts

struct Alert: Codable, Identifiable, Equatable {
    let id: Int
    let type: String?
    let code: String?
    let summary: String
    let createdAt: String?
    let ackedAt: String?
    let ackedBy: String?

    var isAcked: Bool { ackedAt != nil }
    var date: Date? { Fmt.date(createdAt) }
    // "Incident" = a service-health problem (exchange API / data feed), not a portfolio
    // performance threshold breach (drawdown/PnL) — those are a different alert type,
    // shown in the full alerts list but not counted as an incident.
    var isIncident: Bool { type == "api_error" }
}
struct AlertsResponse: Codable { let alerts: [Alert] }

// MARK: - Public Binance market data (Prices tab)

struct BinanceTicker: Codable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    var highPrice: String = "0"
    var lowPrice: String = "0"
    var quoteVolume: String = "0"
    var price: Double { Double(lastPrice) ?? 0 }
    var changePct: Double { Double(priceChangePercent) ?? 0 }
    var high: Double { Double(highPrice) ?? 0 }
    var low: Double { Double(lowPrice) ?? 0 }
    var volume: Double { Double(quoteVolume) ?? 0 }
}

// MARK: - Realtime tab

struct Fill: Codable, Identifiable, Equatable {
    let symbol: String
    let side: String
    let qty: Double
    let price: Double
    let realizedPnl: Double
    let commission: Double
    let occurredAt: String?

    var id: String { "\(symbol)-\(occurredAt ?? "")-\(price)-\(qty)" }
    var isBuy: Bool { side.lowercased() == "buy" || side.lowercased() == "long" }
    var date: Date? { Fmt.date(occurredAt) }
}
struct FillsResponse: Codable { let fills: [Fill] }

struct ExchangeStatus: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let label: String?
    var status: String? = nil       // admin-only field; nil for the read-only wallet view
    var latencyMs: Int? = nil

    var displayLabel: String { (label?.isEmpty == false ? label! : name) }
    var isConnected: Bool { status == "connected" || status == "ok" }
}
struct ExchangesResponse: Codable { let exchanges: [ExchangeStatus] }

// MARK: - Anomalies

/// A detected behavioural anomaly (api/_lib/anomalies.js). Distinct from `Alert`: an alert is
/// a threshold crossed right now, an anomaly is a PATTERN in how a bot is behaving.
///
/// `summary`/`cause` arrive from the server in English — they are the stored fallback and what
/// an email digest would send. Like the web client, this app rebuilds the sentence in the
/// reader's language from `code` + `evidence.variant`, falling back to the server text when a
/// detector has shipped without translations.
struct Anomaly: Codable, Identifiable, Equatable {
    let id: Int
    let code: String
    let scope: String
    let severity: String
    let summary: String
    let cause: String
    let evidence: [String: EvidenceValue]
    let detectedAt: String?
    let resolvedAt: String?
    let ackedAt: String?
    let ackedBy: String?

    var isCritical: Bool { severity == "critical" }
    var isResolved: Bool { resolvedAt != nil }
    var date: Date? { Fmt.date(detectedAt) }
    var variant: String { evidence["variant"]?.stringValue ?? "default" }

    /// "bot:binance:BTCUSDT" -> "binance:BTCUSDT"; "portfolio" and "strategy:x" get their own
    /// wording. Scope is stored machine-readable so detectors can dedupe on it; only the
    /// display is humanised.
    var scopeLabel: String {
        let parts = scope.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return scope == "portfolio" ? "" : scope }
        return parts[1]
    }
}

/// Evidence values are whatever the detector measured — a number, a string, or a small list.
/// Decoded permissively so a new detector shipping an unfamiliar shape cannot break the screen.
enum EvidenceValue: Codable, Equatable {
    case number(Double), text(String), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .other }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .text(let s): try c.encode(s)
        case .other: try c.encodeNil()
        }
    }
    var stringValue: String? { if case .text(let s) = self { return s }; return nil }
    var display: String {
        switch self {
        case .number(let d): return d == d.rounded() && abs(d) < 1e9 ? String(Int(d)) : String(format: "%.2f", d)
        case .text(let s): return s
        case .other: return "—"
        }
    }
}
struct AnomaliesResponse: Codable { let entries: [Anomaly]; let total: Int }

// MARK: - Milestones

/// One entry of the desk's scoreboard. `scope` is "monthly" (measured within the current
/// month, reachable again every month) or "global" (all-time, reached exactly once) — the app
/// only READS this; awarding and announcing happen server-side.
struct Milestone: Codable, Identifiable, Equatable {
    let id: Int
    let scope: String
    let metric: String
    let threshold: Double
    let achievedAt: String?
    let period: String?

    var isAchieved: Bool { achievedAt != nil }
    var date: Date? { Fmt.date(achievedAt) }

    /// A LocalizedStringKey, NOT a String built with NSLocalizedString: the latter resolves
    /// against the SYSTEM language, so the label stayed English while the rest of the card
    /// followed the in-app language choice (which travels through .environment(\.locale)).
    /// Interpolating a String yields the key "… %@ …", which is what the catalog is keyed by.
    /// Mirrors milestoneLabel() on the server.
    var label: LocalizedStringKey {
        let n = threshold
        // Space-grouped, like the web's labels — "+10 000 USDT" is readable where "+10000"
        // is a number you have to count.
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.groupingSeparator = " "; f.maximumFractionDigits = 0
        let num = f.string(from: NSNumber(value: n)) ?? Fmt.number(n)
        // The percent sign travels INSIDE the interpolated value: a literal '%' in the key
        // would have to be escaped consistently on both sides, and one mismatch silently
        // falls back to the untranslated key.
        let pctText = Fmt.number(n, decimals: n == n.rounded() ? 0 : 1) + "%"
        switch metric {
        case "equity_gain":  return "Equity +\(num) USDT"
        case "equity_pct":   return "Equity growth \(pctText)"
        case "equity_level": return "Equity reaches \(num) USDT"
        case "position_pct": return "A single position at +\(pctText)"
        default:             return LocalizedStringKey("\(metric) \(num)")
        }
    }
}

struct MilestonesResponse: Codable {
    let milestones: [Milestone]
    let measured: [String: [String: Double]]?
}

// MARK: - Closed round trips

/// One completed round trip, reconstructed server-side from real fills. Distinct from `Bot`,
/// which is the CURRENT state of an (exchange, symbol) pair: this is what was actually done.
struct ClosedTrade: Codable, Identifiable, Equatable {
    let id: String
    let symbol: String
    let direction: String
    let qty: Double
    let entryPrice: Double?
    let exitPrice: Double?
    let netPnl: Double
    let commission: Double
    let funding: Double
    let openedAt: String?
    let closedAt: String?
    let durationS: Int?
    let leverage: Double?
    let version: String?

    var isLong: Bool { direction == "LONG" }
    var date: Date? { Fmt.date(closedAt) }
}
struct ClosedTradesResponse: Codable { let trades: [ClosedTrade]; let total: Int }

struct TradeOrder: Codable, Identifiable, Equatable {
    let orderId: Int
    let side: String
    let type: String
    let status: String
    let intendedPrice: Double?
    let avgPrice: Double?
    let slippage: Double?
    let unfilled: Bool
    let placedAt: String?

    var id: Int { orderId }
    var isBuy: Bool { side == "BUY" }
}

struct TradeFill: Codable, Identifiable, Equatable {
    let tradeId: Int
    let side: String
    let qty: Double
    let price: Double
    let realizedPnl: Double
    let commission: Double
    let occurredAt: String?
    var id: Int { tradeId }
    var isBuy: Bool { side == "BUY" }
}

/// Everything known about one round trip — the audit view. Fields the desk has not
/// instrumented arrive as null and are shown as "—" rather than as a measured zero.
struct TradeDetail: Codable, Equatable {
    let id: String
    let symbol: String
    let direction: String
    let qty: Double
    let entryPrice: Double?
    let exitPrice: Double?
    let grossPnl: Double
    let commission: Double
    let funding: Double
    let netPnl: Double
    let openedAt: String?
    let closedAt: String?
    let durationS: Int?
    let leverage: Double?
    let notional: Double?
    let mae: Double?
    let mfe: Double?
    let slippage: Double?
    let rMultiple: Double?
    let unfilledOrders: Int?
    var orders: [TradeOrder] = []
    var fills: [TradeFill] = []

    var isLong: Bool { direction == "LONG" }
}
