import SwiftUI

struct DownloadsView: View {
    @State private var downloads = DownloadManager.shared
    @State private var coordinator = PlaybackCoordinator.shared

    var body: some View {
        NavigationStack {
            Group {
                if downloads.records.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(downloads.records) { record in
                            Button {
                                play(record)
                            } label: {
                                row(for: record)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    downloads.deleteDownload(episodeId: record.episodeId)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.podimoBackground)
            .navigationTitle("Downloads")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle").font(.system(size: 44)).foregroundStyle(Color.podimoPurple)
            Text("No downloads yet").font(.headline)
            Text("Download an episode from your Library to listen or watch offline.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.podimoBackground)
    }

    private func row(for record: DownloadRecord) -> some View {
        HStack(spacing: 12) {
            RemoteArtwork(urlString: record.imageUrl, cornerRadius: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(record.podcastName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: record.isVideo ? "video.fill" : "waveform")
                .foregroundStyle(.secondary)
        }
    }

    private func play(_ record: DownloadRecord) {
        let episode = Episode(dict: [
            "id": record.episodeId,
            "podcastId": record.podcastId,
            "podcastName": record.podcastName,
            "title": record.title,
            "imageUrl": record.imageUrl as Any,
            "hasVideo": record.isVideo
        ])
        guard let episode else { return }
        let url = URL(fileURLWithPath: record.localPath)
        if episode.hasVideo {
            coordinator.videoEpisode = episode
            coordinator.audioOnlyURL = nil
            coordinator.videoURL = url
        } else {
            PlaybackManager.shared.play(url: url, episode: episode)
        }
    }
}
