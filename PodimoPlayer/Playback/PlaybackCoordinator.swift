import Foundation
import Observation

@Observable
final class PlaybackCoordinator: @unchecked Sendable {
    static let shared = PlaybackCoordinator()

    var videoURL: URL?
    var videoEpisode: Episode?
    var isResolving = false
    var errorMessage: String?

    private init() {}

    func play(episode: Episode) {
        errorMessage = nil
        if let record = DownloadManager.shared.record(for: episode.id) {
            let url = URL(fileURLWithPath: record.localPath)
            route(url: url, episode: episode)
            return
        }

        isResolving = true
        Task {
            do {
                let urlString = try await PodimoAPI.shared.getEpisodeURL(podcastId: episode.podcastId, episodeId: episode.id)
                guard let url = URL(string: urlString) else { throw PodimoError.badResponse }
                await MainActor.run {
                    self.isResolving = false
                    self.route(url: url, episode: episode)
                }
            } catch {
                await MainActor.run {
                    self.isResolving = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func route(url: URL, episode: Episode) {
        if episode.hasVideo {
            videoEpisode = episode
            videoURL = url
        } else {
            PlaybackManager.shared.play(url: url, episode: episode)
        }
    }
}
