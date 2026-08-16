import Foundation
import Observation

/// Tracks chapters a user has explicitly marked as done, independent of
/// playback position (which drives automatic completion instead).
@Observable
final class AudiobookChapterProgressStore: @unchecked Sendable {
    static let shared = AudiobookChapterProgressStore()

    private let key = "podimo_manual_completed_chapters"
    private(set) var completedByEpisode: [String: Set<Int>] = [:]

    private init() {
        load()
    }

    func isManuallyCompleted(episodeId: String, sequence: Int) -> Bool {
        completedByEpisode[episodeId]?.contains(sequence) ?? false
    }

    func toggle(episodeId: String, sequence: Int) {
        var sequences = completedByEpisode[episodeId] ?? []
        if sequences.contains(sequence) {
            sequences.remove(sequence)
        } else {
            sequences.insert(sequence)
        }
        completedByEpisode[episodeId] = sequences
        persist()
    }

    private func persist() {
        let encodable = completedByEpisode.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            completedByEpisode = decoded.mapValues { Set($0) }
        }
    }
}
