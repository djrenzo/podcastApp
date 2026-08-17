import SwiftUI

struct DownloadsView: View {
    @State private var downloads = DownloadManager.shared
    @State private var coordinator = PlaybackCoordinator.shared

    /// Episodes currently downloading (or that just failed), sorted by title
    /// for a stable order — dictionary iteration order isn't guaranteed, and
    /// without sorting the row would jump around on every progress update.
    private var downloadingEntries: [(episode: Episode, state: DownloadState)] {
        downloads.downloadingEpisodes.values
            .compactMap { episode -> (Episode, DownloadState)? in
                switch downloads.state(for: episode.id) {
                case .downloading(let progress): return (episode, .downloading(progress))
                case .failed(let message): return (episode, .failed(message))
                default: return nil
                }
            }
            .sorted { $0.0.title < $1.0.title }
    }

    var body: some View {
        NavigationStack {
            Group {
                if downloads.records.isEmpty && downloadingEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        if !downloadingEntries.isEmpty {
                            Section("Downloading") {
                                ForEach(downloadingEntries, id: \.episode.id) { entry in
                                    downloadingRow(entry.episode, state: entry.state)
                                }
                            }
                        }
                        if !downloads.records.isEmpty {
                            Section(downloadingEntries.isEmpty ? "" : "Downloaded") {
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

    private func downloadingRow(_ episode: Episode, state: DownloadState) -> some View {
        HStack(spacing: 12) {
            RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(episode.podcastName).font(.caption).foregroundStyle(.secondary)
                switch state {
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .tint(Color.podimoPurple)
                case .failed(let message):
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(Color.podimoCoral)
                        .lineLimit(1)
                default:
                    EmptyView()
                }
            }
            Spacer()
            switch state {
            case .downloading(let progress):
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.podimoCoral)
            default:
                EmptyView()
            }
        }
    }

    private func play(_ record: DownloadRecord) {
        guard var episode = Episode(dict: [
            "id": record.episodeId,
            "podcastId": record.podcastId,
            "podcastName": record.podcastName,
            "title": record.title,
            "imageUrl": record.imageUrl as Any,
            "hasVideo": record.isVideo
        ]) else { return }
        episode.chapters = record.chapters
        episode.isAudiobook = record.isAudiobook
        let url = URL(fileURLWithPath: record.localPath)
        coordinator.playLocal(episode: episode, url: url)
    }
}
