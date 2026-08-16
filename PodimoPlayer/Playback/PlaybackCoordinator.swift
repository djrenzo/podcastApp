import Foundation
import Observation

@Observable
final class PlaybackCoordinator: @unchecked Sendable {
    static let shared = PlaybackCoordinator()

    var isResolving = false
    var errorMessage: String?

    private init() {}

    /// Resolves and starts an episode from the network (or a local download,
    /// if there is one). Video episodes always start on the audio-only
    /// rendition — the full-screen video view expands into the video
    /// rendition on demand.
    func play(episode: Episode) {
        errorMessage = nil
        if let record = DownloadManager.shared.record(for: episode.id) {
            playLocal(episode: episode, url: URL(fileURLWithPath: record.localPath))
            return
        }

        isResolving = true
        Task {
            do {
                let urlString = try await PodimoAPI.shared.getEpisodeURL(podcastId: episode.podcastId, episodeId: episode.id)
                guard let url = URL(string: urlString) else { throw PodimoError.badResponse }
                var audioURL = url
                var videoURL: URL?
                if episode.hasVideo, let variants = try? await HLSVariantResolver.resolveVariants(masterURL: url) {
                    audioURL = variants.audioURL ?? url
                    videoURL = variants.videoURL ?? url
                }
                await MainActor.run {
                    self.isResolving = false
                    PlaybackManager.shared.play(episode: episode, audioURL: audioURL, videoURL: videoURL)
                }
            } catch {
                await MainActor.run {
                    self.isResolving = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Plays a downloaded file. Downloads are a single local asset, so there's
    /// no separate audio-only rendition to swap to — video episodes just play
    /// the same file whether shown full-screen or collapsed to the mini player.
    func playLocal(episode: Episode, url: URL) {
        errorMessage = nil
        PlaybackManager.shared.play(episode: episode, audioURL: url, videoURL: episode.hasVideo ? url : nil)
    }

    /// Audiobooks are represented as an Episode (for reuse in EpisodeRow /
    /// Keep Listening), but they don't have a podcast-episode media URL to
    /// resolve — `play(episode:)`'s query would just 404. They already have a
    /// direct, if short-lived, audio URL from the audiobook channel query instead.
    func playAudiobook(episode: Episode) {
        errorMessage = nil
        isResolving = true
        Task {
            do {
                let result = try await PodimoAPI.shared.getAudiobookChannel(audiobookId: episode.id)
                guard let urlString = result.audiobook.playableURLString, let url = URL(string: urlString) else {
                    throw PodimoError.badResponse
                }
                await MainActor.run {
                    self.isResolving = false
                    PlaybackManager.shared.play(episode: episode, audioURL: url)
                }
            } catch {
                await MainActor.run {
                    self.isResolving = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
