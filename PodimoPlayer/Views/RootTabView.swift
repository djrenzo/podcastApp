import SwiftUI
import AVKit

struct RootTabView: View {
    @State private var coordinator = PlaybackCoordinator.shared
    @State private var playback = PlaybackManager.shared
    @State private var showNowPlaying = false
    @State private var showVideoPlayer = false

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
                MiniPlayerBar(onTap: handleMiniPlayerTap)
                    .padding(.bottom, 49)
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .fullScreenCover(isPresented: $showVideoPlayer, onDismiss: {
            playback.collapseToAudioOnly()
        }) {
            VideoPlayerScreen()
        }
        .alert("Couldn't play episode", isPresented: .constant(coordinator.errorMessage != nil), actions: {
            Button("OK") { coordinator.errorMessage = nil }
        }, message: {
            Text(coordinator.errorMessage ?? "")
        })
    }

    private func handleMiniPlayerTap() {
        if playback.videoStreamURL != nil {
            playback.expandToVideo()
            showVideoPlayer = true
        } else {
            showNowPlaying = true
        }
    }
}

private struct VideoPlayerScreen: View {
    @State private var playback = PlaybackManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let player = playback.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .padding()
                        }
                    }
            }
        }
    }
}

#Preview {
    RootTabView()
}
