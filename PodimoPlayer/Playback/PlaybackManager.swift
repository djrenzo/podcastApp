import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable
final class PlaybackManager: @unchecked Sendable {
    static let shared = PlaybackManager()

    private(set) var player: AVPlayer?
    private(set) var currentEpisode: Episode?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    /// The lighter, audio-only rendition a video episode always starts on.
    private(set) var audioURL: URL?
    /// The heavier video rendition, swapped in only when the full-screen
    /// player is opened. Nil for episodes with no video track at all.
    private(set) var videoStreamURL: URL?
    private(set) var isVideoActive = false

    var errorMessage: String?

    private var timeObserver: Any?
    private var lastProgressPersist: Date = .distantPast
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    private init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Starts playback of a new episode. Video episodes always start on the
    /// audio-only rendition; `expandToVideo()` swaps to `videoURL` once the
    /// user opens the full-screen player.
    func play(episode: Episode, audioURL: URL, videoURL: URL? = nil) {
        currentEpisode = episode
        self.audioURL = audioURL
        self.videoStreamURL = videoURL
        isVideoActive = false
        errorMessage = nil
        artwork = nil
        loadArtwork(for: episode)
        loadItem(url: audioURL, resumeTime: episode.resumeTime ?? 0, autoplay: true)
    }

    func expandToVideo() {
        guard let videoStreamURL, !isVideoActive else { return }
        isVideoActive = true
        loadItem(url: videoStreamURL, resumeTime: currentTime, autoplay: isPlaying)
    }

    func collapseToAudioOnly() {
        guard let audioURL, isVideoActive else { return }
        isVideoActive = false
        loadItem(url: audioURL, resumeTime: currentTime, autoplay: isPlaying)
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlayingInfo()
        persistProgressIfNeeded(force: true)
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    @objc private func handleDidFinish() {
        isPlaying = false
        if let currentEpisode {
            ListeningProgressStore.shared.remove(episodeId: currentEpisode.id)
        }
    }

    private func loadItem(url: URL, resumeTime: Double, autoplay: Bool) {
        removeObserver()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        observeTime()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: item)
        if resumeTime > 0 {
            newPlayer.seek(to: CMTime(seconds: resumeTime, preferredTimescale: 600))
        }
        if autoplay {
            newPlayer.play()
        }
        isPlaying = autoplay
        updateNowPlayingInfo()
    }

    private func loadArtwork(for episode: Episode) {
        artworkTask?.cancel()
        guard let imageUrlString = episode.imageUrl, let imageUrl = URL(string: imageUrlString) else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: imageUrl),
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentEpisode?.id == episode.id else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func observeTime() {
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let player = self.player else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if let seconds = player.currentItem?.duration.seconds, seconds.isFinite {
                self.duration = seconds
            }
            self.updateNowPlayingInfo(timeOnly: true)
            self.persistProgressIfNeeded()
        }
    }

    private func persistProgressIfNeeded(force: Bool = false) {
        guard let episode = currentEpisode, duration > 0 else { return }
        guard force || Date().timeIntervalSince(lastProgressPersist) >= 5 else { return }
        lastProgressPersist = Date()
        ListeningProgressStore.shared.update(episode: episode, currentTime: currentTime, duration: duration)
    }

    private func removeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        // Swapping items (audio <-> video) re-registers this on every call,
        // so drop any prior registration to avoid stacking observers.
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    // MPRemoteCommandCenter invokes these on its own background queue, not
    // necessarily the main thread/actor — hop explicitly rather than relying
    // on an implicit guarantee, which was crashing (dispatch_assert_queue trap
    // inside the Swift concurrency runtime when mutating state off-main).
    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.player?.play()
                self?.isPlaying = true
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                self?.player?.pause()
                self?.isPlaying = false
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let positionTime = event.positionTime
            DispatchQueue.main.async {
                self?.seek(to: positionTime)
            }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.seek(to: self.currentTime + 30)
            }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.seek(to: max(0, self.currentTime - 15))
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(timeOnly: Bool = false) {
        // Backstop: MPNowPlayingInfoCenter's setter is main-thread sensitive,
        // and this function is reachable from the remote-command handlers above.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateNowPlayingInfo(timeOnly: timeOnly) }
            return
        }
        guard let episode = currentEpisode else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        // Title is recomputed on every tick (not just timeOnly: false) so an
        // audiobook's title tracks which chapter is currently playing.
        info[MPMediaItemPropertyTitle] = nowPlayingTitle(for: episode)
        if !timeOnly {
            info[MPMediaItemPropertyArtist] = episode.podcastName
            // Set (or clear, while the new episode's artwork is still downloading)
            // on every non-timeOnly update so a previous episode's artwork can't linger.
            info[MPMediaItemPropertyArtwork] = artwork
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Podcast episodes: just the episode title (artist is the podcast name).
    /// Audiobooks: "<current chapter> • <book title>" (artist is the author).
    private func nowPlayingTitle(for episode: Episode) -> String {
        guard episode.isAudiobook, let chapter = episode.chapter(at: currentTime) else {
            return episode.title
        }
        return "\(chapter.title) • \(episode.title)"
    }
}
