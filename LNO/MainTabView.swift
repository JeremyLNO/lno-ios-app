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

    /// Tab-level gating mirrors the web's MAIN_NAV perm-per-page (ui.tsx) exactly:
    /// Positions needs view_trades, Prices needs view_activity (same perm as the web's
    /// Activity/Prices pages), Realtime needs view_realtime. Overview and Alerts have no
    /// gate on the web (MyEquityPage and the alerts GET endpoint are both auth-only) —
    /// their gated *sub-sections* (PnL Calendar, "Mark all as read") are gated in place.
    private var canPositions: Bool { auth.user?.can("view_trades") ?? false }
    private var canPrices: Bool { auth.user?.can("view_activity") ?? false }
    private var canRealtime: Bool { auth.user?.can("view_realtime") ?? false }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack { DashboardView(showSettings: $showSettings) }
                .tabItem { Label("Overview", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(DeepLinkRouter.Tab.overview)

            if canPositions {
                NavigationStack { PositionsView(showSettings: $showSettings) }
                    .tabItem { Label("Positions", systemImage: "list.bullet.rectangle") }
                    .tag(DeepLinkRouter.Tab.positions)
            }

            if canPrices {
                NavigationStack { PricesView(showSettings: $showSettings) }
                    .tabItem { Label("Prices", systemImage: "bitcoinsign.circle") }
                    .tag(DeepLinkRouter.Tab.prices)
            }

            if canRealtime {
                NavigationStack { RealtimeView(showSettings: $showSettings) }
                    .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(DeepLinkRouter.Tab.realtime)
            }

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
        .onChange(of: router.selectedTab) { _, tab in
            // A tab can vanish out from under the user (rare: perms refreshed mid-session).
            // Bounce back to Overview rather than showing a TabView with a dangling selection.
            let stillVisible = (tab == .overview) || (tab == .alerts)
                || (tab == .positions && canPositions) || (tab == .prices && canPrices) || (tab == .realtime && canRealtime)
            if !stillVisible { router.selectedTab = .overview }
        }
    }
}
