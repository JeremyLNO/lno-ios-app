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
    func alerts() async throws -> [Alert] { try decode(AlertsResponse.self, from: await request("alerts")).alerts }

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
}
