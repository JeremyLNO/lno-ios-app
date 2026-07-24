import SwiftUI

/// Design tokens mirroring the web dashboard exactly (tailwind.config.js +
/// ui.tsx). The web app is a LIGHT theme — cream page background, white cards,
/// navy/slate text — not dark navy as earlier iOS drafts assumed.
enum Theme {
    static let navy = Color(hex: 0x0B1F3A)       // primary brand / text / sidebar bg
    static let navy2 = Color(hex: 0x0F2A4D)      // navy hover/pressed state
    static let gold = Color(hex: 0xC9A24D)       // accent
    static let up = Color(hex: 0x10B981)         // success — positive P&L
    static let down = Color(hex: 0xEF4444)       // danger — negative P&L
    static let warn = Color(hex: 0xF59E0B)       // amber — paused/degraded
    static let blueAccent = Color(hex: 0x3B82F6) // exposure KPI accent

    static let pageBG = Color(hex: 0xF8F7F4)     // app background (cream)
    static let cardBG = Color.white
    static let stroke = Color(hex: 0xE2E8F0).opacity(0.8) // slate-200/80
    static let mutedText = Color(hex: 0x64748B)  // slate-500
    static let faintText = Color(hex: 0x94A3B8)  // slate-400
    static let navySoft = Color(hex: 0x13294D)   // dark-surface only (login/lock screens)

    /// Green for positive, red for negative, muted for zero.
    static func pnlColor(_ v: Double) -> Color {
        if v > 0 { return up }
        if v < 0 { return down }
        return mutedText
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
    /// Parse a "#RRGGBB" hex string from the API (fund colours).
    init?(hexString: String?) {
        guard var s = hexString else { return nil }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

/// Shared number/date formatting, matching the dashboard's fmtUSD/fmtSigned/fmtPrice.
enum Fmt {
    static func usd(_ v: Double, decimals: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = decimals
        f.maximumFractionDigits = decimals
        let n = f.string(from: NSNumber(value: v)) ?? "0"
        return "$\(n)"
    }
    static func signedUSD(_ v: Double, decimals: Int = 0) -> String {
        let sign = v > 0 ? "+" : (v < 0 ? "−" : "")
        return "\(sign)\(usd(abs(v), decimals: decimals))"
    }
    static func pct(_ v: Double, decimals: Int = 2) -> String {
        let sign = v > 0 ? "+" : (v < 0 ? "−" : "")
        return String(format: "\(sign)%.\(decimals)f%%", abs(v))
    }
    /// Plain (unsigned, unprefixed) number — used for e.g. leverage ("10×").
    static func number(_ v: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f", v)
    }
    /// Compact-formatted USD (e.g. $1.2M, $840K) — matches the web's volume/notional
    /// summaries (fmtCompactUSD in src/ui.tsx).
    static func compactUSD(_ v: Double) -> String {
        let av = abs(v)
        let sign = v < 0 ? "-" : ""
        if av >= 1_000_000_000 { return "\(sign)$\(number(av / 1_000_000_000, decimals: 2))B" }
        if av >= 1_000_000 { return "\(sign)$\(number(av / 1_000_000, decimals: 2))M" }
        if av >= 1_000 { return "\(sign)$\(number(av / 1_000, decimals: 1))K" }
        return "\(sign)\(usd(av))"
    }
    static func price(_ v: Double) -> String {
        let decimals: Int = v >= 1000 ? 1 : (v >= 1 ? 2 : (v >= 0.01 ? 4 : 6))
        return usd(v, decimals: decimals)
    }
    /// Parse an ISO-8601 / Postgres timestamp string leniently.
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        // Postgres "YYYY-MM-DD HH:MM:SS(.sss)" without a T
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
