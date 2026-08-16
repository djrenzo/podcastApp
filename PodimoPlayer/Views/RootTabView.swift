import SwiftUI
import AVKit

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
                MiniPlayerBar(showNowPlaying: $showNowPlaying)
                    .padding(.bottom, 49)
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .fullScreenCover(item: $coordinator.videoURL, onDismiss: {
            coordinator.videoURL = nil
            coordinator.videoEpisode = nil
        }) { url in
            VideoPlayerScreen(url: url)
        }
        .alert("Couldn't play episode", isPresented: .constant(coordinator.errorMessage != nil), actions: {
            Button("OK") { coordinator.errorMessage = nil }
        }, message: {
            Text(coordinator.errorMessage ?? "")
        })
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct VideoPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
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

#Preview {
    RootTabView()
}