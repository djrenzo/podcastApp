import SwiftUI

struct SwipeDoneAction: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let action: () -> Void
}

struct EpisodeRow: View {
    let episode: Episode
    /// The full, currently-sorted episode list for this episode's podcast —
    /// passed only where that context is actually available (PodcastDetailView).
    /// Used solely to rebuild the autoplay queue ("the next episodes in line")
    /// when this episode is played; nil elsewhere (e.g. Keep Listening) just
    /// means the autoplay queue resets to empty instead, since there's no
    /// ordered list to draw "next" from there.
    var podcastEpisodesContext: [Episode]? = nil
    @State private var downloads = DownloadManager.shared
    @State private var coordinator = PlaybackCoordinator.shared
    @State private var progressStore = ListeningProgressStore.shared
    @State private var queueManager = EpisodeQueueManager.shared
    @State private var isResolvingDownloadURL = false
    @State private var showInfo = false
    /// Pushed onto the enclosing NavigationStack (not presented as a sheet),
    /// so "Information"/"Podcast" from a context menu land on the exact same
    /// screen — back button, further navigation (e.g. an audiobook's related
    /// books) and all — as tapping into it normally from the Library would.
    @State private var navigateToAudiobook: AudiobookLink?
    @State private var navigateToPodcast: Podcast?

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

    /// A minimal reconstruction of this episode's podcast, for the "Podcast"
    /// context menu action — Keep Listening only ever has the episode's own
    /// denormalized podcastId/podcastName/imageUrl on hand, not the full
    /// Podcast the API would otherwise return. `Podcast.init?(dict:)` reads
    /// the image from a nested `images.coverImageUrl`, not a top-level key.
    /// External episodes denormalize the feed URL into `podcastId` too, so
    /// that's carried over as `externalFeedURL` to keep this navigating to
    /// the same RSS-backed detail view rather than a broken Podimo lookup.
    private var minimalPodcast: Podcast? {
        guard var podcast = Podcast(dict: [
            "id": episode.podcastId,
            "title": episode.podcastName,
            "hasVideo": episode.hasVideo,
            "images": ["coverImageUrl": episode.imageUrl as Any]
        ]) else { return nil }
        if episode.externalAudioURLString != nil {
            podcast.externalFeedURL = episode.podcastId
        }
        return podcast
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
                    // If this episode had a saved "up next" (e.g. it was
                    // played from a podcast list, or resumed from here with
                    // one restored), hand its Keep Listening slot off to that
                    // next episode instead of just leaving it empty.
                    if let next = queueManager.advance(past: episode.id) {
                        ListeningProgressStore.shared.startTracking(next)
                    }
                },
                SwipeDoneAction(title: "Mark as Not Done", icon: "arrow.uturn.backward.circle") {
                    ListeningProgressStore.shared.markAsNotDone(episodeId: episode.id)
                }
            ]
        }
        var actions: [SwipeDoneAction] = []
        if let chapter = episode.chapter(at: effectiveProgress?.listenTime ?? 0) {
            actions.append(SwipeDoneAction(title: "Mark Chapter as Done", icon: "checkmark") {
                markChapterDone(chapter)
            })
            actions.append(SwipeDoneAction(title: "Mark Chapter as Not Done", icon: "arrow.uturn.backward") {
                markChapterNotDone(chapter)
            })
        }
        actions.append(SwipeDoneAction(title: "Mark Book as Done", icon: "checkmark.circle.fill") {
            ListeningProgressStore.shared.markAsDone(episodeId: episode.id)
        })
        actions.append(SwipeDoneAction(title: "Mark Book as Not Done", icon: "arrow.uturn.backward.circle") {
            ListeningProgressStore.shared.markAsNotDone(episodeId: episode.id)
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

    /// The inverse of `markChapterDone`: clears the chapter's completion mark
    /// and rewinds the saved resume position back to the start of that
    /// chapter, so it's queued up to be listened to again.
    private func markChapterNotDone(_ chapter: AudiobookChapter) {
        let store = ListeningProgressStore.shared
        store.markAsNotDone(episodeId: episode.id)
        AudiobookChapterProgressStore.shared.markNotCompleted(episodeId: episode.id, sequence: chapter.sequence)
        // For anything past the first chapter, restore a resume position at
        // that chapter's start; the first chapter just means "back to zero",
        // which markAsNotDone already handled.
        if chapter.startTimestampInSeconds >= 5, let duration = episode.duration, duration > 0 {
            store.update(episode: episode, currentTime: chapter.startTimestampInSeconds, duration: duration)
        }
    }

    var body: some View {
        Button {
            if episode.isAudiobook {
                coordinator.playAudiobook(episode: playableEpisode)
            } else {
                resetAutoplayQueue()
                coordinator.play(episode: playableEpisode)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 12, targetSize: 64)
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
            Button {
                if episode.isAudiobook {
                    navigateToAudiobook = AudiobookLink(id: episode.id, title: episode.title, imageUrl: episode.imageUrl)
                } else {
                    showInfo = true
                }
            } label: {
                Label("Information", systemImage: "info.circle")
            }
            if !episode.isAudiobook {
                Button {
                    navigateToPodcast = minimalPodcast
                } label: {
                    Label("Podcast", systemImage: "square.stack")
                }
                Button {
                    if queueManager.isInManualQueue(episode.id) {
                        queueManager.removeFromManualQueue(episodeId: episode.id)
                    } else {
                        queueManager.addToManualQueue(playableEpisode)
                    }
                } label: {
                    if queueManager.isInManualQueue(episode.id) {
                        Label("Remove from Queue", systemImage: "text.badge.minus")
                    } else {
                        Label("Add to Queue", systemImage: "text.badge.plus")
                    }
                }
            }
            ForEach(doneActions) { action in
                Button {
                    action.action()
                } label: {
                    Label(action.title, systemImage: action.icon)
                }
            }
        }
        // Podcast episodes have no standalone "page" elsewhere to match, so
        // this stays a modal info sheet. Audiobooks and podcasts do have one
        // (AudiobookDetailView / PodcastDetailView, both reachable by tapping
        // into the Library normally) — those push onto the enclosing
        // NavigationStack below instead, rather than reopening in a sheet.
        .sheet(isPresented: $showInfo) {
            EpisodeInfoSheet(episode: playableEpisode)
        }
        .navigationDestination(item: $navigateToAudiobook) { link in
            AudiobookDetailView(audiobookId: link.id, previewTitle: link.title, previewImageUrl: link.imageUrl)
        }
        .navigationDestination(item: $navigateToPodcast) { podcast in
            PodcastDetailView(podcast: podcast)
        }
    }

    /// "The autoplay queue is reset on every new episode play click" — rebuilt
    /// from whatever comes after this episode in the podcast's current list
    /// order. Where that list isn't available in this context (e.g. tapped
    /// from Keep Listening) fall back to restoring whatever queue was saved
    /// the last time this same episode was played with one, rather than just
    /// clearing it — so resuming an episode brings its "up next" back too.
    private func resetAutoplayQueue() {
        guard let context = podcastEpisodesContext,
              let index = context.firstIndex(where: { $0.id == episode.id }) else {
            queueManager.restoreQueue(for: episode.id)
            return
        }
        queueManager.setAutoplayQueue(Array(context[(index + 1)...]), owner: episode.id)
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
        // External episodes already carry a direct enclosure URL — there's
        // no Podimo episode ID to resolve one from.
        if let externalURLString = episode.externalAudioURLString {
            downloads.startDownload(episode: episode, mediaURLString: externalURLString)
            return
        }
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
