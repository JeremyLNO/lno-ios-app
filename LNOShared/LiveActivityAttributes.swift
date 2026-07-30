import Foundation
import ActivityKit

/// The desk's open book, live on the Lock Screen and in the Dynamic Island.
///
/// Compiled into BOTH targets (LNOShared is globbed by gen_pbxproj.py): the app owns the
/// lifecycle, the widget extension owns the rendering, and this is the contract between
/// them. Keep it small — ActivityKit budgets the payload, and everything here has to be
/// derivable from what PortfolioStore already holds.
///
/// Deliberately NOT a second source of truth: every field is computed from the same
/// `bots`/`live` the Positions tab renders, in LiveActivityController.state(from:).
struct PositionsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var openCount: Int
        var longCount: Int
        var shortCount: Int
        var unrealizedPnl: Double
        /// Worst liquidation band across the open book: "ok" | "warn" | "danger".
        /// Mirrors Bot.liqLevel, so the badge can never disagree with the Positions tab.
        var risk: String
        /// Equity trail for the sparkline. Plain values, not normalised — the view scales
        /// them, so the app never has to guess the rendered size.
        var spark: [Double]
        var updatedAt: Date

        /// A position with no liquidation price reports no band; an empty book is "ok"
        /// rather than unknown — nothing is at risk when nothing is open.
        static func riskLabelKey(_ risk: String) -> String {
            switch risk {
            case "danger": return "Risk: critical"
            case "warn": return "Risk: watch"
            default: return "Risk: contained"
            }
        }
    }

    /// Static for the life of the activity — the account it belongs to, so a Lock Screen
    /// card can never be read as someone else's book after a re-login.
    var accountLabel: String
}
