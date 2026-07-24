import Foundation

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
