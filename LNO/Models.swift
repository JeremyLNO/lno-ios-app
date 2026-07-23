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

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
    func can(_ perm: String) -> Bool { permissions.contains(perm) }
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

    var isOpen: Bool { status == "open" }
    var isLong: Bool { side.lowercased() == "long" || side.lowercased() == "buy" }
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
    var price: Double { Double(lastPrice) ?? 0 }
    var changePct: Double { Double(priceChangePercent) ?? 0 }
}
