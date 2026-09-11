import UIKit

/// SwiftUI's App lifecycle has no hook for background URLSession events on
/// its own — this is required so iOS can wake (or relaunch) the app to
/// finish delivering a download's result after it completed while the app
/// was backgrounded or fully terminated.
final class AppDelegate: NSObject, UIApplicationDelegate {
    var backgroundSessionCompletionHandlers: [String: () -> Void] = [:]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Without this, MPRemoteCommandCenter's handlers can be registered
        // but the system never actually routes lock screen / Control Center
        // commands (or shows the Now Playing banner) to this process.
        application.beginReceivingRemoteControlEvents()
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandlers[identifier] = completionHandler
    }
}
