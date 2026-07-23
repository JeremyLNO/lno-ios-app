import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: DeepLinkRouter
    @StateObject private var store = PortfolioStore()
    @StateObject private var alertReadStore = AlertReadStore()
    @State private var showSettings = false

    /// How often positions/mark-prices refresh in the background, matching the
    /// web dashboard's live-data cadence for bots/equity (funds/snapshots change
    /// rarely and stay on pull-to-refresh only).
    private static let pollInterval: UInt64 = 15_000_000_000

    /// Matches the web's mobile bottom nav: white bg, gold for the active tab,
    /// slate-500 for inactive ones (`MobileNav` in ui.tsx).
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Theme.gold)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.gold)]
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Theme.mutedText)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.mutedText)]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView(showSettings: $showSettings) }
                .tabItem { Label("Overview", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(DeepLinkRouter.Tab.overview)

            NavigationStack { PositionsView(showSettings: $showSettings) }
                .tabItem { Label("Positions", systemImage: "list.bullet.rectangle") }
                .tag(DeepLinkRouter.Tab.positions)

            NavigationStack { PricesView(showSettings: $showSettings) }
                .tabItem { Label("Prices", systemImage: "bitcoinsign.circle") }
                .tag(DeepLinkRouter.Tab.prices)

            NavigationStack { AlertsView(showSettings: $showSettings) }
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(DeepLinkRouter.Tab.alerts)
                .badge(alertReadStore.unreadCount(in: store.alerts))
        }
        .environmentObject(store)
        .environmentObject(alertReadStore)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            await store.refresh(auth: auth)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollInterval)
                if Task.isCancelled { break }
                await store.refreshPositionsOnly(auth: auth)
            }
        }
    }
}
