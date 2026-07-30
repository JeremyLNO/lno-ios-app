import SwiftUI

/// Routes URL-based navigation (currently: tapping a fund on the Funds Equity
/// widget) to the right tab/screen. `lnocc://fund/<id>` switches to Positions and
/// asks it to scroll to that fund's card.
@MainActor
final class DeepLinkRouter: ObservableObject {
    enum Tab: Hashable { case overview, positions, prices, realtime, alerts }

    @Published var selectedTab: Tab = {
        #if DEBUG
        // Start on a given tab, for screenshotting and automated checks:
        //   xcrun simctl launch <device> company.lno.controlcenter -LNODemo YES -LNOTab alerts
        // A deep link would do the same, but iOS interposes an "Open in …?" confirmation that
        // a headless check cannot dismiss. DEBUG-only.
        switch UserDefaults.standard.string(forKey: "LNOTab") {
        case "positions", "closed", "detail": return .positions
        case "prices":    return .prices
        case "realtime":  return .realtime
        case "alerts", "anomalies": return .alerts
        default: break
        }
        #endif
        return .overview
    }()
    @Published var scrollToFundID: String?

    func handle(_ url: URL) {
        guard url.scheme == Config.authCallbackScheme else { return }
        switch url.host {
        // lnocc://tab/<overview|positions|prices|realtime|alerts> — lets a push notification
        // (or a test harness) open the screen it is about instead of always landing on
        // Overview and leaving the reader to find it.
        case "tab":
            switch url.pathComponents.dropFirst().first {
            case "positions": selectedTab = .positions
            case "prices":    selectedTab = .prices
            case "realtime":  selectedTab = .realtime
            case "alerts":    selectedTab = .alerts
            default:          selectedTab = .overview
            }
        case "fund":
            let id = url.pathComponents.dropFirst().first
            selectedTab = .positions
            scrollToFundID = id
        default:
            break // "auth" (Google sign-in) is consumed by ASWebAuthenticationSession itself
        }
    }
}
