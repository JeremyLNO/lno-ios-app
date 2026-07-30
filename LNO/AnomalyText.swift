import Foundation

/// Rebuilds an anomaly's sentence in the reader's language.
///
/// The server stores `summary` and `cause` in English — that is the fallback, and what an
/// email digest sends. Both clients (this app and the web dashboard) render them instead from
/// `code` + `evidence.variant` + the measured values, so a finding reads like the rest of the
/// app in all four languages. `variant` distinguishes wordings that differ in MEANING, not
/// just in numbers ("stopped trading" vs "trading twice as often"), so each gets its own
/// sentence rather than a template with a word swapped in.
///
/// When a detector ships without translations the lookup returns its own key, which is how we
/// detect the gap and fall back to the server's English rather than printing a raw key.
enum AnomalyText {

    /// Which evidence values feed each sentence, in the order the template consumes them.
    /// Kept next to the templates so adding a detector is one edit here plus four strings.
    private static let args: [String: [String]] = [
        "profit_factor_drop.losing":   ["baselinePF", "recentPF"],
        "profit_factor_drop.thinning": ["baselinePF", "recentPF"],
        "drawdown_rise.default":       ["recentDrawdown", "baselineDrawdown"],
        "loss_concentration.default":  ["symbol", "lossShare"],
        "long_short_drift.default":    ["weakSide", "longWinRate", "shortWinRate"],
        "trade_frequency.stopped":     ["windowDays", "baselinePerDay"],
        "trade_frequency.up":          ["changeAbs", "recentPerDay", "baselinePerDay"],
        "trade_frequency.down":        ["changeAbs", "recentPerDay", "baselinePerDay"],
        "expectation_missed.default":  ["strategy", "missedCount"],
        "exchange_latency.default":    ["exchange", "latencyMs"],
        "dormant_position.default":    ["symbol", "hoursIdle"],
        "slippage_rise.default":       ["baselineAvg", "recentAvg"],
        "unfilled_orders.default":     ["cancelledShare", "symbol"],
    ]

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), table: nil, bundle: .main, comment: "")
    }

    /// A key that resolves to itself means the string is missing from the catalog.
    private static func lookup(_ key: String) -> String? {
        let v = localized(key)
        return v == key ? nil : v
    }

    private static func render(_ template: String, _ anomaly: Anomaly) -> String {
        let names = args["\(anomaly.code).\(anomaly.variant)"] ?? []
        var out = template
        // Positional substitution, one placeholder at a time in declared order — the String
        // Catalog stores these with %@ markers so translators can reorder the sentence
        // around them without touching this code.
        for name in names {
            guard let range = out.range(of: "%@") else { break }
            out.replaceSubrange(range, with: anomaly.evidence[name]?.display ?? "—")
        }
        return out
    }

    static func summary(_ a: Anomaly) -> String {
        guard let t = lookup("anomaly.sum.\(a.code).\(a.variant)") else { return a.summary }
        return render(t, a)
    }

    static func cause(_ a: Anomaly) -> String {
        lookup("anomaly.cause.\(a.code).\(a.variant)") ?? a.cause
    }

    static func code(_ code: String) -> String {
        lookup("anomaly.code.\(code)") ?? code
    }

    static func severity(_ s: String) -> String {
        lookup("anomaly.sev.\(s)") ?? s.capitalized
    }
}
