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
        setCompleted(!isManuallyCompleted(episodeId: episodeId, sequence: sequence), episodeId: episodeId, sequence: sequence)
    }

    /// Explicit "mark as done" (e.g. a swipe action) — unlike `toggle`, this
    /// is idempotent rather than flipping an already-done chapter back off.
    func markCompleted(episodeId: String, sequence: Int) {
        setCompleted(true, episodeId: episodeId, sequence: sequence)
    }

    private func setCompleted(_ completed: Bool, episodeId: String, sequence: Int) {
        var sequences = completedByEpisode[episodeId] ?? []
        if completed {
            guard !sequences.contains(sequence) else { return }
            sequences.insert(sequence)
        } else {
            guard sequences.contains(sequence) else { return }
            sequences.remove(sequence)
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
