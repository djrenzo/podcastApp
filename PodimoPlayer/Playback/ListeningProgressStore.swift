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

    var id: String { episodeId }
}

@Observable
final class ListeningProgressStore: @unchecked Sendable {
    static let shared = ListeningProgressStore()

    private let key = "podimo_listening_progress"
    private let completedKey = "podimo_completed_episodes"
    private let minProgress = 0.02
    private let maxProgress = 0.95

    private(set) var records: [ListeningProgressRecord] = []
    /// Episodes finished locally. Kept separately (and durably) from `records`,
    /// since a finished episode is deliberately dropped from `records` (so it
    /// disappears from Keep Listening) but should still show as done wherever
    /// else the episode is listed — which the API's own `isMarkedAsPlayed`
    /// won't reflect, since this app never writes that flag back to the server.
    private(set) var completedEpisodeIds: Set<String> = []

    private init() {
        load()
        loadCompleted()
    }

    var inProgress: [ListeningProgressRecord] {
        records
            .filter { $0.progress >= minProgress && $0.progress < maxProgress }
            .sorted { $0.lastListenDatetime > $1.lastListenDatetime }
    }

    func isCompleted(episodeId: String) -> Bool {
        completedEpisodeIds.contains(episodeId)
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
        if let record = records.first(where: { $0.episodeId == episode.id }) {
            return EpisodeProgress(progress: record.progress, listenTime: record.listenTime)
        }
        return episode.userProgress
    }

    func isWatched(_ episode: Episode) -> Bool {
        episode.isMarkedAsPlayed || (effectiveProgress(for: episode)?.progress ?? 0) >= 0.95
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
        // prior completion mark.
        unmarkCompleted(episodeId: episode.id)
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
            isAudiobook: episode.isAudiobook
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

    /// Explicit "mark as done" (e.g. a swipe action), rather than completion
    /// inferred from playback crossing the finish threshold.
    func markAsDone(episodeId: String) {
        markCompleted(episodeId: episodeId)
        remove(episodeId: episodeId)
    }

    private func markCompleted(episodeId: String) {
        guard !completedEpisodeIds.contains(episodeId) else { return }
        completedEpisodeIds.insert(episodeId)
        persistCompleted()
    }

    private func unmarkCompleted(episodeId: String) {
        guard completedEpisodeIds.contains(episodeId) else { return }
        completedEpisodeIds.remove(episodeId)
        persistCompleted()
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
}
