import Foundation

enum APIClientError: LocalizedError {
    case unauthorized
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .server(let m): return m
        case .network(let m): return m
        }
    }
}

/// Thin async client over the LNO Control Center API. Stateless: the JWT is passed
/// in per call. A 401 with a token surfaces as `.unauthorized` so the UI can log out.
struct APIClient {
    var token: String?

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = []) async throws -> Data {
        var comps = URLComponents(url: Config.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIClientError.network("No response") }
            if http.statusCode == 401 { throw APIClientError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Request failed (\(http.statusCode))"
                throw APIClientError.server(msg)
            }
            return data
        } catch let e as APIClientError {
            throw e
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIClientError.server("Unexpected data from server") }
    }

    // MARK: - Auth

    static func loginGoogle(idToken: String) async throws -> AuthResponse {
        try await postAuth(["action": "google", "credential": idToken])
    }
    // Shareholder sign-in, step 1: ask for a 6-digit emailed code. Server always
    // replies 200 {ok:true} (no account-existence leak) except for @lno.company
    // addresses, which are Google-only and get a 400 back with that explanation.
    static func requestOtp(email: String) async throws {
        _ = try await postAuthRequest(["action": "requestOtp", "email": email])
    }
    // Shareholder sign-in, step 2: email + code -> token.
    static func verifyOtp(email: String, code: String) async throws -> AuthResponse {
        try await postAuth(["action": "verifyOtp", "email": email, "code": code])
    }
    private static func postAuth(_ body: [String: String]) async throws -> AuthResponse {
        let data = try await postAuthRequest(body)
        do {
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            throw APIClientError.server("Unexpected response from server")
        }
    }
    private static func postAuthRequest(_ body: [String: String]) async throws -> Data {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent("auth"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "Sign-in failed"
                throw APIClientError.server(msg)
            }
            return data
        } catch let e as APIClientError {
            throw e
        } catch {
            throw APIClientError.network(error.localizedDescription)
        }
    }

    func me() async throws -> User { try decode(MeResponse.self, from: await request("auth")).user }

    // MARK: - Data (read-only)

    func bots() async throws -> BotsResponse { try decode(BotsResponse.self, from: await request("bots")) }
    func funds() async throws -> [Fund] { try decode(FundsResponse.self, from: await request("funds")).funds }
    func snapshots(limit: Int = 365) async throws -> [Snapshot] {
        try decode(SnapshotsResponse.self, from: await request("snapshots", query: [.init(name: "limit", value: String(limit))])).snapshots
    }
    func alerts(type: String? = nil, limit: Int = 30) async throws -> [Alert] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let type { query.append(.init(name: "type", value: type)) }
        return try decode(AlertsResponse.self, from: await request("alerts", query: query)).alerts
    }
    func fills() async throws -> [Fill] {
        try decode(FillsResponse.self, from: await request("bots", query: [.init(name: "fills", value: "1")])).fills
    }
    /// Admin-only in practice (the Realtime page's Exchange Connectivity card is
    /// role==='admin'-gated on the web, not just view_exchanges) — the endpoint itself
    /// also serves a stripped read-only view to view_exchanges holders, unused here.
    func exchanges() async throws -> [ExchangeStatus] {
        try decode(ExchangesResponse.self, from: await request("exchanges")).exchanges
    }

    // MARK: - Public market data (no auth)

    static func tickers(symbols: [String]) async throws -> [String: BinanceTicker] {
        var out: [String: BinanceTicker] = [:]
        try await withThrowingTaskGroup(of: BinanceTicker?.self) { group in
            for sym in Set(symbols) {
                group.addTask {
                    var comps = URLComponents(url: Config.binanceFapi.appendingPathComponent("fapi/v1/ticker/24hr"), resolvingAgainstBaseURL: false)!
                    comps.queryItems = [.init(name: "symbol", value: sym)]
                    var req = URLRequest(url: comps.url!)
                    req.timeoutInterval = 12
                    guard let (data, resp) = try? await URLSession.shared.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200,
                          let t = try? JSONDecoder().decode(BinanceTicker.self, from: data) else { return nil }
                    return t
                }
            }
            for try await t in group { if let t { out[t.symbol] = t } }
        }
        return out
    }

    /// Fear & Greed index — same public endpoint as the web's Prices page sentiment widget.
    static func fearGreed() async throws -> (value: Int, label: String) {
        struct Resp: Decodable { struct Item: Decodable { let value: String; let value_classification: String }; let data: [Item] }
        var req = URLRequest(url: URL(string: "https://api.alternative.me/fng/?limit=1")!)
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = try JSONDecoder().decode(Resp.self, from: data)
        guard let item = r.data.first else { throw APIClientError.network("No data") }
        return (Int(item.value) ?? 0, item.value_classification)
    }

    /// BTC/ETH market-cap dominance % — same public CoinGecko endpoint as the web.
    static func marketDominance() async throws -> (btc: Double, eth: Double) {
        struct Resp: Decodable { struct D: Decodable { let market_cap_percentage: [String: Double] }; let data: D }
        var req = URLRequest(url: URL(string: "https://api.coingecko.com/api/v3/global")!)
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return (r.data.market_cap_percentage["btc"] ?? 0, r.data.market_cap_percentage["eth"] ?? 0)
    }
}
