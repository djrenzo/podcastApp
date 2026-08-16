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
    private let minProgress = 0.02
    private let maxProgress = 0.95

    private(set) var records: [ListeningProgressRecord] = []

    private init() {
        load()
    }

    var inProgress: [ListeningProgressRecord] {
        records
            .filter { $0.progress >= minProgress && $0.progress < maxProgress }
            .sorted { $0.lastListenDatetime > $1.lastListenDatetime }
    }

    func update(episode: Episode, currentTime: Double, duration: Double) {
        guard duration > 0, currentTime.isFinite, duration.isFinite else { return }
        let progress = min(max(currentTime / duration, 0), 1)
        guard progress < maxProgress else {
            remove(episodeId: episode.id)
            return
        }
        guard progress >= minProgress else { return }
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
}
