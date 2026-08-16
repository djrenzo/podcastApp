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
            coordinator.audioOnlyURL = nil
        }) { url in
            VideoPlayerScreen(videoURL: url, audioOnlyURL: coordinator.audioOnlyURL, episode: coordinator.videoEpisode)
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
    let videoURL: URL
    let audioOnlyURL: URL?
    let episode: Episode?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var timeObserver: Any?
    @State private var isAudioOnly = false

    init(videoURL: URL, audioOnlyURL: URL?, episode: Episode?) {
        self.videoURL = videoURL
        self.audioOnlyURL = audioOnlyURL
        self.episode = episode
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    if audioOnlyURL != nil {
                        Button(action: toggleAudioOnly) {
                            Image(systemName: isAudioOnly ? "video.fill" : "headphones")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                    }
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                }
                .padding()
            }
            .onAppear {
                timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { _ in
                    persistProgress()
                }
            }
            .onDisappear {
                persistProgress()
                if let timeObserver { player.removeTimeObserver(timeObserver) }
                timeObserver = nil
            }
    }

    private func toggleAudioOnly() {
        guard let audioOnlyURL else { return }
        let targetURL = isAudioOnly ? videoURL : audioOnlyURL
        let resumeTime = player.currentTime()
        let wasPlaying = player.timeControlStatus != .paused
        player.replaceCurrentItem(with: AVPlayerItem(url: targetURL))
        player.seek(to: resumeTime)
        if wasPlaying { player.play() }
        isAudioOnly.toggle()
    }

    private func persistProgress() {
        guard let episode else { return }
        let currentTime = player.currentTime().seconds
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite, currentTime.isFinite else { return }
        ListeningProgressStore.shared.update(episode: episode, currentTime: currentTime, duration: duration)
    }
}

#Preview {
    RootTabView()
}