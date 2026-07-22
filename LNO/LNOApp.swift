import SwiftUI

@main
struct LNOApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var router = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(router)
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
        .onChange(of: oneSignal.didRegister) { _, registered in
            if registered { showIntegrationAlert = true }
        }
        .alert("Your OneSignal SDK integration is complete!", isPresented: $showIntegrationAlert) {
            Button("Got it") {
                // Persist *here*, on actual acknowledgement, not the moment the alert
                // is requested — marking it shown any earlier risks the flag being
                // set (e.g. if the process dies right after `didRegister` flips) even
                // though the user never actually saw/dismissed the alert, which would
                // silently suppress it forever on the next launch.
                oneSignal.markIntegrationAlertShown()
                oneSignal.requestPushPermission()
            }
        } message: {
            Text("You can now send Push Notifications & In-App Messages through OneSignal. Tap below to enable push notifications.")
        }
    }
}
