import Foundation
import Observation

/// Lightweight Codable snapshot of a queued Episode, for persisting queue
/// state to UserDefaults — Episode itself isn't Codable (see PodimoModels),
/// so this mirrors the same "record" pattern used elsewhere in the app
/// (DownloadRecord, ListeningProgressRecord) and round-trips through
/// Episode(dict:).
private struct QueuedEpisodeRecord: Codable {
    var id: String
    var podcastId: String
    var podcastName: String
    var title: String
    var description: String?
    var publishDatetime: String?
    var imageUrl: String?
    var duration: Double?
    var isMarkedAsPlayed: Bool
    var hasVideo: Bool
    var chapters: [AudiobookChapter]

    init(episode: Episode) {
        id = episode.id
        podcastId = episode.podcastId
        podcastName = episode.podcastName
        title = episode.title
        description = episode.description
        publishDatetime = episode.publishDatetime
        imageUrl = episode.imageUrl
        duration = episode.duration
        isMarkedAsPlayed = episode.isMarkedAsPlayed
        hasVideo = episode.hasVideo
        chapters = episode.chapters
    }

    var asEpisode: Episode? {
        guard var episode = Episode(dict: [
            "id": id,
            "podcastId": podcastId,
            "podcastName": podcastName,
            "title": title,
            "description": description as Any,
            "publishDatetime": publishDatetime as Any,
            "imageUrl": imageUrl as Any,
            "duration": duration as Any,
            "isMarkedAsPlayed": isMarkedAsPlayed,
            "hasVideo": hasVideo
        ]) else { return nil }
        episode.chapters = chapters
        return episode
    }
}

/// Podcast episodes only (audiobooks are excluded by every call site that
/// feeds this). Two queues, checked in priority order when advancing:
///
/// - `manualQueue`: user-curated via "Add to Queue"; takes priority over the
///   autoplay queue, and is never persisted — it's meant to reset to empty
///   every app launch, not survive one.
/// - `autoplayQueue`: rebuilt from scratch every time a fresh podcast episode
///   is played from a context that knows the rest of that podcast's episode
///   list (see EpisodeRow) — "the next episodes in line", in whatever order
///   that list is currently sorted in.
///
/// The autoplay queue is additionally persisted per "owner" episode (the
/// episode it trails), so that:
/// - resuming an episode from Keep Listening — where that fresh episode-list
///   context isn't available — brings back the same "up next" queue it had
///   when it was originally played from the podcast view, and
/// - marking an in-progress episode done can hand off to whatever was next
///   in its queue, even without actually playing anything.
@Observable
final class EpisodeQueueManager: @unchecked Sendable {
    static let shared = EpisodeQueueManager()

    private(set) var manualQueue: [Episode] = []
    private(set) var autoplayQueue: [Episode] = []

    /// The episode `autoplayQueue` currently trails. Tracked so advancing
    /// through it (via `popNext()`) can keep re-saving the shrinking tail
    /// under whichever episode is now "in front" of it.
    private var currentOwnerId: String?

    private let storageKey = "podimo_autoplay_queues_by_owner"
    /// owner episode id -> the episodes queued up after it. Keyed by every
    /// episode that's ever been played with a known "next in line", not just
    /// whichever one is currently loaded — so Keep Listening can look up
    /// *any* in-progress episode's saved queue on demand.
    private var queuesByOwner: [String: [QueuedEpisodeRecord]] = [:]

    private init() {
        loadQueues()
    }

    func isInManualQueue(_ episodeId: String) -> Bool {
        manualQueue.contains { $0.id == episodeId }
    }

    func addToManualQueue(_ episode: Episode) {
        guard !isInManualQueue(episode.id) else { return }
        manualQueue.append(episode)
    }

    func removeFromManualQueue(episodeId: String) {
        manualQueue.removeAll { $0.id == episodeId }
    }

    func removeFromManualQueue(at offsets: IndexSet) {
        manualQueue.remove(atOffsets: offsets)
    }

    func clearManualQueue() {
        manualQueue.removeAll()
    }

    /// Replaces the autoplay queue outright — called on every fresh podcast
    /// episode play, per spec, rather than merged/appended. Persists it keyed
    /// to `owner` so it can be restored later via `restoreQueue(for:)`.
    func setAutoplayQueue(_ episodes: [Episode], owner: String) {
        autoplayQueue = episodes
        currentOwnerId = owner
        saveQueue(episodes, owner: owner)
    }

    /// Restores whatever queue was saved the last time `episodeId` was played
    /// with a known "next in line" — used when resuming an episode from Keep
    /// Listening, where the fresh podcast-episode-list context that normally
    /// builds the autoplay queue isn't available. Clears it (rather than
    /// leaving a stale queue in place) if nothing was ever saved for it.
    func restoreQueue(for episodeId: String) {
        autoplayQueue = queuesByOwner[episodeId]?.compactMap(\.asEpisode) ?? []
        currentOwnerId = episodeId
    }

    /// Manual queue takes priority. Removes whatever it returns, since
    /// calling this means that episode is about to start playing. Advancing
    /// the autoplay queue this way also shifts the saved "owner" forward to
    /// whatever's now playing, so its own remaining tail stays restorable.
    func popNext() -> Episode? {
        if !manualQueue.isEmpty {
            return manualQueue.removeFirst()
        }
        guard !autoplayQueue.isEmpty else { return nil }
        let next = autoplayQueue.removeFirst()
        setAutoplayQueue(autoplayQueue, owner: next.id)
        return next
    }

    /// Consumes and returns the episode saved as next-in-line after
    /// `episodeId`, without playing anything — used by "Mark as Done" in Keep
    /// Listening to hand that slot off to whatever was queued up behind it.
    /// Re-saves the remaining tail under the handed-off episode's own id, so
    /// it in turn stays restorable if that one gets resumed or marked done.
    func advance(past episodeId: String) -> Episode? {
        guard var queue = queuesByOwner[episodeId], !queue.isEmpty else { return nil }
        let nextRecord = queue.removeFirst()
        queuesByOwner[episodeId] = nil
        guard let next = nextRecord.asEpisode else {
            persistQueues()
            return nil
        }
        queuesByOwner[next.id] = queue.isEmpty ? nil : queue
        persistQueues()
        // Keep the in-memory queue (and QueueView, which reads it live) in
        // sync too, in case this is the queue actually loaded for playback.
        if currentOwnerId == episodeId {
            autoplayQueue = queue.compactMap(\.asEpisode)
            currentOwnerId = next.id
        }
        return next
    }

    private func saveQueue(_ episodes: [Episode], owner: String) {
        queuesByOwner[owner] = episodes.isEmpty ? nil : episodes.map(QueuedEpisodeRecord.init)
        persistQueues()
    }

    private func persistQueues() {
        if let data = try? JSONEncoder().encode(queuesByOwner) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadQueues() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [QueuedEpisodeRecord]].self, from: data) {
            queuesByOwner = decoded
        }
    }
}
