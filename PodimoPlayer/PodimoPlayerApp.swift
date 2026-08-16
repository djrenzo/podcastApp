import SwiftUI

@main
struct PodimoPlayerApp: App {
    init() {
        CrashReporter.install()
        CrashReporter.consumePendingCrash()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(nil)
        }
    }
}
