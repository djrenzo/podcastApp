import SwiftUI

struct NowPlayingView: View {
    @State private var playback = PlaybackManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)

            if let episode = playback.currentEpisode {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 28)
                    .frame(width: 260, height: 260)
                    .shadow(color: Color.podimoPurple.opacity(0.3), radius: 24, y: 12)

                VStack(spacing: 6) {
                    Text(episode.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(2)
                    Text(episode.podcastName).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                progressSection

                HStack(spacing: 48) {
                    Button { playback.seek(to: max(0, playback.currentTime - 15)) } label: {
                        Image(systemName: "gobackward.15").font(.title)
                    }
                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { playback.seek(to: playback.currentTime + 30) } label: {
                        Image(systemName: "goforward.30").font(.title)
                    }
                }
                .foregroundStyle(Color.podimoInk)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.podimoBackground.ignoresSafeArea())
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { playback.currentTime },
                set: { playback.seek(to: $0) }
            ), in: 0...max(playback.duration, 1))
            .tint(Color.podimoPurple)

            HStack {
                Text(format(playback.currentTime))
                Spacer()
                Text(format(playback.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
