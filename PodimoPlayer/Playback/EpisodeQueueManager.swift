import Foundation
import Observation

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
@Observable
final class EpisodeQueueManager: @unchecked Sendable {
    static let shared = EpisodeQueueManager()

    private(set) var manualQueue: [Episode] = []
    private(set) var autoplayQueue: [Episode] = []

    private init() {}

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
    /// episode play, per spec, rather than merged/appended.
    func setAutoplayQueue(_ episodes: [Episode]) {
        autoplayQueue = episodes
    }

    /// Manual queue takes priority. Removes whatever it returns, since
    /// calling this means that episode is about to start playing.
    func popNext() -> Episode? {
        if !manualQueue.isEmpty {
            return manualQueue.removeFirst()
        }
        if !autoplayQueue.isEmpty {
            return autoplayQueue.removeFirst()
        }
        return nil
    }
}
