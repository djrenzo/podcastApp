import Foundation
import Observation

struct ListeningProgressRecord: Codable, Identifiable, Equatable {
    var episodeId: String
    var podcastId: String
    var podcastName: String
    var title: String
    var imageUrl: String?
    var hasVideo: Bool
    var duration: Double
    var listenTime: Double
    var progress: Double
    var lastListenDatetime: Date
    var chapters: [AudiobookChapter] = []
    var isAudiobook = false
    var description: String?
    var publishDatetime: String?
    var isMarkedAsPlayed = false

    var id: String { episodeId }
}

@Observable
final class ListeningProgressStore: @unchecked Sendable {
    static let shared = ListeningProgressStore()

    private let key = "podimo_listening_progress"
    private let completedKey = "podimo_completed_episodes"
    private let notCompletedKey = "podimo_not_completed_episodes"
    private let minProgress = 0.02
    private let maxProgress = 0.95

    private(set) var records: [ListeningProgressRecord] = []
    /// Episodes finished locally. Kept separately (and durably) from `records`,
    /// since a finished episode is deliberately dropped from `records` (so it
    /// disappears from Keep Listening) but should still show as done wherever
    /// else the episode is listed — which the API's own `isMarkedAsPlayed`
    /// won't reflect, since this app never writes that flag back to the server.
    private(set) var completedEpisodeIds: Set<String> = []
    /// Episodes the user has explicitly marked *not* done. Needed as its own
    /// set (rather than just clearing local state) because the API's
    /// `isMarkedAsPlayed` can independently say an episode is finished, and
    /// this app never writes that flag back — so without a local override
    /// forcing "unplayed", a "mark as not done" on such an episode would have
    /// no visible effect.
    private(set) var notCompletedEpisodeIds: Set<String> = []

    private init() {
        load()
        loadCompleted()
        loadNotCompleted()
    }

    var inProgress: [ListeningProgressRecord] {
        records
            .filter { $0.progress >= minProgress && $0.progress < maxProgress }
            .sorted { $0.lastListenDatetime > $1.lastListenDatetime }
    }

    func isCompleted(episodeId: String) -> Bool {
        completedEpisodeIds.contains(episodeId)
    }

    func isForcedNotCompleted(episodeId: String) -> Bool {
        notCompletedEpisodeIds.contains(episodeId)
    }

    /// Local data always takes precedence over the API — a locally-finished
    /// episode stays finished even if the API never got told (it's dropped
    /// from `records` once done, so that check has to come first or a stale
    /// "still in progress" API value would leak back through below), then an
    /// in-progress local record, then finally whatever the API last reported.
    func effectiveProgress(for episode: Episode) -> EpisodeProgress? {
        if isCompleted(episodeId: episode.id) {
            return EpisodeProgress(progress: 1.0, listenTime: episode.duration)
        }
        // An explicit "mark as not done" wins over both any lingering local
        // record and whatever the API reports, resetting the position to 0.
        if isForcedNotCompleted(episodeId: episode.id) {
            return EpisodeProgress(progress: 0, listenTime: 0)
        }
        if let record = records.first(where: { $0.episodeId == episode.id }) {
            return EpisodeProgress(progress: record.progress, listenTime: record.listenTime)
        }
        return episode.userProgress
    }

    func isWatched(_ episode: Episode) -> Bool {
        if isForcedNotCompleted(episodeId: episode.id) { return false }
        return episode.isMarkedAsPlayed || (effectiveProgress(for: episode)?.progress ?? 0) >= 0.95
    }

    func update(episode: Episode, currentTime: Double, duration: Double) {
        guard duration > 0, currentTime.isFinite, duration.isFinite else { return }
        let progress = min(max(currentTime / duration, 0), 1)
        guard progress < maxProgress else {
            markCompleted(episodeId: episode.id)
            remove(episodeId: episode.id)
            return
        }
        guard progress >= minProgress else { return }
        // Actively re-listening (e.g. restarted from the beginning) undoes a
        // prior completion mark — in either direction.
        unmarkCompleted(episodeId: episode.id)
        unmarkNotCompleted(episodeId: episode.id)
        let record = ListeningProgressRecord(
            episodeId: episode.id,
            podcastId: episode.podcastId,
            podcastName: episode.podcastName,
            title: episode.title,
            imageUrl: episode.imageUrl,
            hasVideo: episode.hasVideo,
            duration: duration,
            listenTime: currentTime,
            progress: progress,
            lastListenDatetime: Date(),
            chapters: episode.chapters,
            isAudiobook: episode.isAudiobook,
            description: episode.description,
            publishDatetime: episode.publishDatetime,
            isMarkedAsPlayed: episode.isMarkedAsPlayed
        )
        records.removeAll { $0.episodeId == episode.id }
        records.append(record)
        persist()
    }

    /// Creates a nominal in-progress record for `episode` so it shows up in
    /// Keep Listening immediately, even though it hasn't actually started
    /// playing yet. Used when a queued-up episode takes over the Keep
    /// Listening slot of the one just marked done ahead of it (see
    /// EpisodeQueueManager.advance(past:)).
    func startTracking(_ episode: Episode) {
        guard !isWatched(episode) else { return }
        unmarkCompleted(episodeId: episode.id)
        let record = ListeningProgressRecord(
            episodeId: episode.id,
            podcastId: episode.podcastId,
            podcastName: episode.podcastName,
            title: episode.title,
            imageUrl: episode.imageUrl,
            hasVideo: episode.hasVideo,
            duration: episode.duration ?? 0,
            listenTime: 0,
            progress: minProgress,
            lastListenDatetime: Date(),
            chapters: episode.chapters,
            isAudiobook: episode.isAudiobook,
            description: episode.description,
            publishDatetime: episode.publishDatetime,
            isMarkedAsPlayed: episode.isMarkedAsPlayed
        )
        records.removeAll { $0.episodeId == episode.id }
        records.append(record)
        persist()
    }

    func remove(episodeId: String) {
        guard records.contains(where: { $0.episodeId == episodeId }) else { return }
        records.removeAll { $0.episodeId == episodeId }
        persist()
    }

    /// Explicit "mark as done" (e.g. a context-menu action), rather than
    /// completion inferred from playback crossing the finish threshold.
    func markAsDone(episodeId: String) {
        markCompleted(episodeId: episodeId)
        remove(episodeId: episodeId)
    }

    /// Explicit "mark as not done": clears the completed flag, forces the
    /// episode back to "unplayed" even against the API, and drops any saved
    /// resume position (removing it from Keep Listening in the process).
    func markAsNotDone(episodeId: String) {
        unmarkCompleted(episodeId: episodeId)
        markNotCompleted(episodeId: episodeId)
        remove(episodeId: episodeId)
    }

    private func markCompleted(episodeId: String) {
        unmarkNotCompleted(episodeId: episodeId)
        guard !completedEpisodeIds.contains(episodeId) else { return }
        completedEpisodeIds.insert(episodeId)
        persistCompleted()
    }

    private func unmarkCompleted(episodeId: String) {
        guard completedEpisodeIds.contains(episodeId) else { return }
        completedEpisodeIds.remove(episodeId)
        persistCompleted()
    }

    private func markNotCompleted(episodeId: String) {
        guard !notCompletedEpisodeIds.contains(episodeId) else { return }
        notCompletedEpisodeIds.insert(episodeId)
        persistNotCompleted()
    }

    private func unmarkNotCompleted(episodeId: String) {
        guard notCompletedEpisodeIds.contains(episodeId) else { return }
        notCompletedEpisodeIds.remove(episodeId)
        persistNotCompleted()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ListeningProgressRecord].self, from: data) {
            records = decoded
        }
    }

    private func persistCompleted() {
        UserDefaults.standard.set(Array(completedEpisodeIds), forKey: completedKey)
    }

    private func loadCompleted() {
        if let ids = UserDefaults.standard.array(forKey: completedKey) as? [String] {
            completedEpisodeIds = Set(ids)
        }
    }

    private func persistNotCompleted() {
        UserDefaults.standard.set(Array(notCompletedEpisodeIds), forKey: notCompletedKey)
    }

    private func loadNotCompleted() {
        if let ids = UserDefaults.standard.array(forKey: notCompletedKey) as? [String] {
            notCompletedEpisodeIds = Set(ids)
        }
    }
}
