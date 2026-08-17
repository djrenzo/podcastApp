import UIKit

/// SwiftUI's App lifecycle has no hook for background URLSession events on
/// its own — this is required so iOS can wake (or relaunch) the app to
/// finish delivering a download's result after it completed while the app
/// was backgrounded or fully terminated.
final class AppDelegate: NSObject, UIApplicationDelegate {
    var backgroundSessionCompletionHandlers: [String: () -> Void] = [:]

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandlers[identifier] = completionHandler
    }
}
