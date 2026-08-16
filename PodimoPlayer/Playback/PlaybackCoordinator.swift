import Foundation
import Observation

@Observable
final class PlaybackCoordinator: @unchecked Sendable {
    static let shared = PlaybackCoordinator()

    var videoURL: URL?
    var audioOnlyURL: URL?
    var videoEpisode: Episode?
    var isResolving = false
    var errorMessage: String?

    private init() {}

    func play(episode: Episode) {
        errorMessage = nil
        if let record = DownloadManager.shared.record(for: episode.id) {
            let url = URL(fileURLWithPath: record.localPath)
            route(url: url, episode: episode, audioOnlyURL: nil)
            return
        }

        isResolving = true
        Task {
            do {
                let urlString = try await PodimoAPI.shared.getEpisodeURL(podcastId: episode.podcastId, episodeId: episode.id)
                guard let url = URL(string: urlString) else { throw PodimoError.badResponse }
                var audioOnlyURL: URL?
                var videoURL = url
                if episode.hasVideo, let variants = try? await HLSVariantResolver.resolveVariants(masterURL: url) {
                    videoURL = variants.videoURL ?? url
                    audioOnlyURL = variants.audioURL
                }
                await MainActor.run {
                    self.isResolving = false
                    self.route(url: videoURL, episode: episode, audioOnlyURL: audioOnlyURL)
                }
            } catch {
                await MainActor.run {
                    self.isResolving = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func route(url: URL, episode: Episode, audioOnlyURL: URL?) {
        if episode.hasVideo {
            videoEpisode = episode
            self.audioOnlyURL = audioOnlyURL
            videoURL = url
        } else {
            PlaybackManager.shared.play(url: url, episode: episode)
        }
    }
}
