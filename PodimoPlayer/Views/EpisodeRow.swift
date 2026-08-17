import SwiftUI

struct SwipeDoneAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void
}

struct EpisodeRow: View {
    let episode: Episode
    @State private var downloads = DownloadManager.shared
    @State private var coordinator = PlaybackCoordinator.shared
    @State private var progressStore = ListeningProgressStore.shared
    @State private var isResolvingDownloadURL = false

    private var downloadState: DownloadState { downloads.state(for: episode.id) }

    private var effectiveProgress: EpisodeProgress? {
        progressStore.effectiveProgress(for: episode)
    }

    private var playableEpisode: Episode {
        var updated = episode
        updated.userProgress = effectiveProgress
        return updated
    }

    private var isCompleted: Bool {
        progressStore.isWatched(episode)
    }

    /// For audiobooks (only ever shown here via Keep Listening), lead with
    /// the chapter last listened to — same "<chapter> • <book>" shape as the
    /// Now Playing title — falling back to just the book title if there's no
    /// chapter data or no listening position yet.
    private var titleText: String {
        guard episode.isAudiobook,
              let chapter = episode.chapter(at: effectiveProgress?.listenTime ?? 0) else {
            return episode.title
        }
        return "\(chapter.title) • \(episode.title)"
    }

    private var doneActions: [SwipeDoneAction] {
        guard episode.isAudiobook else {
            return [
                SwipeDoneAction(title: "Mark as Done", icon: "checkmark.circle.fill") {
                    ListeningProgressStore.shared.markAsDone(episodeId: episode.id)
                }
            ]
        }
        var actions: [SwipeDoneAction] = []
        if let chapter = episode.chapter(at: effectiveProgress?.listenTime ?? 0) {
            actions.append(SwipeDoneAction(title: "Mark Chapter as Done", icon: "checkmark") {
                markChapterDone(chapter)
            })
        }
        actions.append(SwipeDoneAction(title: "Mark Book as Done", icon: "checkmark.circle.fill") {
            ListeningProgressStore.shared.markAsDone(episodeId: episode.id)
        })
        return actions
    }

    /// Marks the chapter done and fast-forwards the saved resume position to
    /// the start of the next one, so next time this book is opened from Keep
    /// Listening it picks up right where the finished chapter left off — not
    /// wherever partway through it the listener happened to stop.
    /// If it was the last chapter, `update` naturally crosses the completion
    /// threshold and the whole book gets marked done instead.
    private func markChapterDone(_ chapter: AudiobookChapter) {
        AudiobookChapterProgressStore.shared.markCompleted(episodeId: episode.id, sequence: chapter.sequence)
        let sorted = episode.chapters.sorted { $0.sequence < $1.sequence }
        guard let index = sorted.firstIndex(where: { $0.sequence == chapter.sequence }),
              sorted.indices.contains(index + 1),
              let duration = episode.duration, duration > 0 else { return }
        let nextChapterStart = sorted[index + 1].startTimestampInSeconds
        ListeningProgressStore.shared.update(episode: episode, currentTime: nextChapterStart, duration: duration)
    }

    var body: some View {
        Button {
            if episode.isAudiobook {
                coordinator.playAudiobook(episode: playableEpisode)
            } else {
                coordinator.play(episode: playableEpisode)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 12)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
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
                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.podimoMint)
                        }
                    }
                    if let description = episode.description, !description.isEmpty {
                        Text(description.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !isCompleted, let progress = effectiveProgress?.progress, progress > 0.02 {
                        ProgressView(value: min(progress, 1))
                            .tint(Color.podimoCoral)
                    }
                }

                Spacer(minLength: 4)
                if !episode.isAudiobook {
                    downloadButton
                }
            }
            .padding(12)
            .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(doneActions) { action in
                Button {
                    action.action()
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !episode.formattedDuration.isEmpty { parts.append(episode.formattedDuration) }
        if let date = episode.publishedDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " • ")
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
