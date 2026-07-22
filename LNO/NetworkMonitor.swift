import SwiftUI
import Network

/// Watches device connectivity (Wi-Fi/cellular reachability, not API health) so
/// the app can show a clear "offline" banner instead of silently failing fetches.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "company.lno.controlcenter.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.isConnected = connected }
        }
        monitor.start(queue: queue)
    }
}

/// Slim banner shown across the whole app while the device has no connectivity.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("No Internet Connection").fontWeight(.semibold)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.down)
    }
}
