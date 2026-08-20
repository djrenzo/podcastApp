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

    static let availableRates: [Float] = [1.0, 1.5, 2.0]
    private(set) var playbackRate: Float = 1.0

    var errorMessage: String?

    private var timeObserver: Any?
    private var lastProgressPersist: Date = .distantPast
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private let rateKey = "podimo_playback_rate"
    private var wasPlayingBeforeInterruption = false

    private init() {
        let storedRate = UserDefaults.standard.float(forKey: rateKey)
        playbackRate = Self.availableRates.contains(storedRate) ? storedRate : 1.0
        configureAudioSession()
        configureRemoteCommands()
    }

    /// Applies to audio, video, and audiobook playback alike — they're all
    /// just the one shared AVPlayer underneath.
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        UserDefaults.standard.set(rate, forKey: rateKey)
        if isPlaying {
            player?.rate = rate
        }
        updateNowPlayingInfo()
    }

    func cyclePlaybackRate() {
        let rates = Self.availableRates
        let currentIndex = rates.firstIndex(of: playbackRate) ?? 0
        setPlaybackRate(rates[(currentIndex + 1) % rates.count])
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    /// The system auto-pauses playback for things like a Siri notification
    /// readout over AirPods, but never auto-resumes it afterward — that part
    /// is on us. AVAudioSession can post this notification off the main
    /// thread, so hop explicitly rather than trusting the delivery thread
    /// (same reasoning as the MPRemoteCommandCenter handlers above).
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            DispatchQueue.main.async {
                self.wasPlayingBeforeInterruption = self.isPlaying
                self.isPlaying = false
            }
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
            let shouldResume = optionsValue.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            DispatchQueue.main.async {
                defer { self.wasPlayingBeforeInterruption = false }
                guard self.wasPlayingBeforeInterruption, shouldResume else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.player?.rate = self.playbackRate
                self.isPlaying = true
                self.updateNowPlayingInfo()
            }
        @unknown default:
            break
        }
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
        loadItem(url: videoStreamURL, resumeTime: currentTime, autoplay: isActuallyPlaying)
    }

    func collapseToAudioOnly() {
        guard let audioURL, isVideoActive else { return }
        isVideoActive = false
        loadItem(url: audioURL, resumeTime: currentTime, autoplay: isActuallyPlaying)
    }

    /// The full-screen video player uses AVKit's native controls, which pause/
    /// resume the AVPlayer directly without going through `togglePlayPause()` —
    /// so `isPlaying` can go stale while video is showing. Read the player's
    /// actual rate instead of trusting the cached flag when it matters (e.g.
    /// deciding whether to autoplay after swapping between audio and video).
    private var isActuallyPlaying: Bool {
        guard let player else { return false }
        return player.rate != 0 && player.error == nil
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Setting rate directly (rather than play(), which always resets
            // to 1.0) is how AVPlayer starts/resumes playback at a custom speed.
            player.rate = playbackRate
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
            newPlayer.rate = playbackRate
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
            // Built outside any MainActor context: MediaPlayer calls this
            // requestHandler from its own background queue whenever it wants
            // to render the artwork, and a closure formed inside `MainActor.run`
            // gets inferred as MainActor-isolated — tripping the same
            // dispatch_assert_queue crash as the remote-command handlers did.
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                guard let self, self.currentEpisode?.id == episode.id else { return }
                self.artwork = artwork
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
            // Keeps isPlaying accurate even when AVKit's native video controls
            // pause/resume the player directly, bypassing togglePlayPause().
            self.isPlaying = player.rate != 0
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
                guard let self else { return }
                self.player?.rate = self.playbackRate
                self.isPlaying = true
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
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
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
