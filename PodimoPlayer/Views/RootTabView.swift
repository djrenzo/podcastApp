import SwiftUI

struct RootTabView: View {
    @State private var coordinator = PlaybackCoordinator.shared
    @State private var playback = PlaybackManager.shared
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "square.stack.fill") }
                DownloadsView()
                    .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            .tint(Color.podimoPurple)

            if playback.currentEpisode != nil {
                MiniPlayerBar(onTap: { showNowPlaying = true })
                    .padding(.bottom, 49)
            }
        }
        // A regular sheet (unlike fullScreenCover) supports swipe-to-dismiss,
        // and now hosts video inline instead of a separate full-screen cover —
        // collapse back to the audio-only rendition whenever it closes, however
        // that happens (swipe or otherwise).
        .sheet(isPresented: $showNowPlaying, onDismiss: {
            playback.collapseToAudioOnly()
        }) {
            NowPlayingView()
        }
        .alert("Couldn't play episode", isPresented: .constant(coordinator.errorMessage != nil), actions: {
            Button("OK") { coordinator.errorMessage = nil }
        }, message: {
            Text(coordinator.errorMessage ?? "")
        })
    }
}

#Preview {
    RootTabView()
}
