import SwiftUI

struct MiniPlayerBar: View {
    let onTap: () -> Void
    @State private var playback = PlaybackManager.shared

    var body: some View {
        if let episode = playback.currentEpisode {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 10)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.white)
                        Text(episode.podcastName).font(.caption).lineLimit(1).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(LinearGradient.podimoBrand, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }
}
