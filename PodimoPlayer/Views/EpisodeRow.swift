import SwiftUI

struct EpisodeRow: View {
    let episode: Episode
    @State private var downloads = DownloadManager.shared
    @State private var coordinator = PlaybackCoordinator.shared
    @State private var isResolvingDownloadURL = false

    private var downloadState: DownloadState { downloads.state(for: episode.id) }

    var body: some View {
        Button {
            coordinator.play(episode: episode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 12)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.podimoInk)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if episode.hasVideo {
                            Image(systemName: "video.fill").font(.caption2)
                        }
                        Text(metaLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let progress = episode.userProgress?.progress, progress > 0.02 {
                        ProgressView(value: min(progress, 1))
                            .tint(Color.podimoCoral)
                    }
                }

                Spacer(minLength: 4)
                downloadButton
            }
            .padding(12)
            .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var metaLine: String {
        var parts: [String] = []
        if !episode.formattedDuration.isEmpty { parts.append(episode.formattedDuration) }
        if let date = episode.publishedDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " Β· ")
    }

    @ViewBuilder
    private var downloadButton: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                startDownload()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(Color.podimoPurple)
            }
            .disabled(isResolvingDownloadURL)
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(Color.podimoPurple)
                .frame(width: 22, height: 22)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.podimoMint)
                .onTapGesture { downloads.deleteDownload(episodeId: episode.id) }
        case .failed:
            Button {
                startDownload()
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(Color.podimoCoral)
            }
        }
    }

    private func startDownload() {
        isResolvingDownloadURL = true
        Task {
            do {
                let urlString = try await PodimoAPI.shared.getEpisodeURL(podcastId: episode.podcastId, episodeId: episode.id)
                await MainActor.run {
                    downloads.startDownload(episode: episode, mediaURLString: urlString)
                    isResolvingDownloadURL = false
                }
            } catch {
                await MainActor.run { isResolvingDownloadURL = false }
            }
        }
    }
}
