import Foundation
import Network
import Observation

/// Tracks basic internet reachability via NWPathMonitor, so views can offer a
/// reduced "offline" experience — e.g. Keep Listening falling back to only
/// what's actually downloaded — instead of just failing every request.
@Observable
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    /// Optimistically true until the first path update arrives, so the UI
    /// doesn't flash an "offline" state on launch before NWPathMonitor has
    /// had a chance to report anything.
    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.superapp.podimoplayer.networkmonitor")

    private init() {
        // NWPathMonitor invokes this on its own queue, not necessarily the
        // main thread/actor — hop explicitly before touching @Observable
        // state, same reasoning as every other system-callback handler here.
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }
}
