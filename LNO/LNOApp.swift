import SwiftUI

@main
struct LNOApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var router = DeepLinkRouter()
    @StateObject private var languageStore = LanguageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(router)
                .environmentObject(languageStore)
                // The officially-supported way to make a String Catalog respect an
                // in-app language choice instead of the device's system Settings ▸
                // Language: override the `\.locale` environment value for the whole
                // hierarchy. `Text`/`LocalizedStringKey` resolution consults this
                // before falling back to the device locale, so this takes effect
                // immediately, with no relaunch.
                .environment(\.locale, languageStore.lang.locale)
                .onChange(of: auth.user) { _, user in
                    languageStore.syncFromServer(user)
                }
                .preferredColorScheme(.light)
                .tint(Theme.gold)
                .onOpenURL { router.handle($0) }
                .task {
                    guard auth.phase == .loading else { return }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-demo") {
                        auth.enterDemoMode()
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("-demo-locked") {
                        await auth.enterLockedDemoMode()
                        return
                    }
                    #endif
                    await auth.bootstrap()
                }
        }
    }
}

/// Switches between the loading splash, the login screen, and the signed-in tabs.
struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var oneSignal = OneSignalManager.shared
    @StateObject private var network = NetworkMonitor.shared
    @State private var showIntegrationAlert = false
    @AppStorage("hasRequestedPushPermission") private var hasRequestedPushPermission = false

    var body: some View {
        ZStack(alignment: .top) {
            switch auth.phase {
            case .loading:
                AuthBackground()
                VStack(spacing: 20) {
                    LNOLogo().frame(width: 200, height: 200 * (190.6 / 824))
                    ProgressView().tint(Theme.gold)
                }
            case .signedOut:
                LoginView()
            case .locked:
                LockScreenView()
            case .signedIn:
                MainTabView()
            }
            if !network.isConnected {
                OfflineBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut, value: auth.phase)
        .animation(.easeInOut, value: network.isConnected)
        .task { oneSignal.initialize(appId: Config.oneSignalAppID) }
        // Real, user-facing permission ask: fires once, the first time a session
        // reaches .signedIn — independent of the OneSignal debug alert below, so a
        // stale "already shown" flag from earlier dev testing can never suppress it.
        .onChange(of: auth.phase) { _, phase in
            guard phase == .signedIn, !hasRequestedPushPermission else { return }
            hasRequestedPushPermission = true
            oneSignal.requestPushPermission()
        }
        #if DEBUG
        .onChange(of: oneSignal.didRegister) { _, registered in
            if registered { showIntegrationAlert = true }
        }
        .alert("Your OneSignal SDK integration is complete!", isPresented: $showIntegrationAlert) {
            Button("Got it") {
                oneSignal.markIntegrationAlertShown()
            }
        } message: {
            Text("This is a DEBUG-only diagnostic confirming the SDK registered with OneSignal.")
        }
        #endif
    }
}
