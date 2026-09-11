import Foundation
import Observation

/// A podcast added to the local, non-Podimo "External" library — feeds
/// discovered via `ExternalPodcastAPI` search and followed locally, since
/// there's no Podimo account concept for them to be added to server-side.
struct ExternalLibraryEntry: Codable, Identifiable, Equatable {
    var feedURL: String
    var title: String
    var authorName: String?
    var description: String?
    var imageUrl: String?
    var addedDate: Date

    var id: String { feedURL }
}

@Observable
final class ExternalLibraryStore: @unchecked Sendable {
    static let shared = ExternalLibraryStore()

    private let key = "podimo_external_library"

    private(set) var entries: [ExternalLibraryEntry] = []

    private init() {
        load()
    }

    func isInLibrary(feedURL: String) -> Bool {
        entries.contains { $0.feedURL == feedURL }
    }

    func add(_ entry: ExternalLibraryEntry) {
        guard !isInLibrary(feedURL: entry.feedURL) else { return }
        entries.append(entry)
        persist()
    }

    func remove(feedURL: String) {
        guard entries.contains(where: { $0.feedURL == feedURL }) else { return }
        entries.removeAll { $0.feedURL == feedURL }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ExternalLibraryEntry].self, from: data) {
            entries = decoded
        }
    }
}
