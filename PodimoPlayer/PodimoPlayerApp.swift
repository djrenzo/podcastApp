import SwiftUI

@main
struct PodimoPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        CrashReporter.install()
        CrashReporter.consumePendingCrash()
        // Force this to initialize now rather than whenever some view first
        // touches it — it reconnects to any background download sessions in
        // its init, and that needs to happen as early as possible so a
        // relaunch triggered by handleEventsForBackgroundURLSession doesn't
        // miss the window to pick them back up.
        _ = DownloadManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(nil)
        }
    }
}
