import SwiftUI

/// Routes URL-based navigation (currently: tapping a fund on the Funds Equity
/// widget) to the right tab/screen. `lnocc://fund/<id>` switches to Positions and
/// asks it to scroll to that fund's card.
@MainActor
final class DeepLinkRouter: ObservableObject {
    enum Tab: Hashable { case overview, positions, prices, alerts }

    @Published var selectedTab: Tab = .overview
    @Published var scrollToFundID: String?

    func handle(_ url: URL) {
        guard url.scheme == Config.authCallbackScheme else { return }
        switch url.host {
        case "fund":
            let id = url.pathComponents.dropFirst().first
            selectedTab = .positions
            scrollToFundID = id
        default:
            break // "auth" (Google sign-in) is consumed by ASWebAuthenticationSession itself
        }
    }
}
