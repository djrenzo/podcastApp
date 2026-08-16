import AVFoundation
import MediaPlayer
import Observation

@Observable
final class PlaybackManager: @unchecked Sendable {
    static let shared = PlaybackManager()

    private(set) var player: AVPlayer?
    private(set) var currentEpisode: Episode?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var errorMessage: String?

    private var timeObserver: Any?

    private init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(url: URL, episode: Episode) {
        currentEpisode = episode
        errorMessage = nil
        removeObserver()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        observeTime()
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: item)
        newPlayer.play()
        isPlaying = true
        updateNowPlayingInfo()
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
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    @objc private func handleDidFinish() {
        isPlaying = false
    }

    private func observeTime() {
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, let player = self.player else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if let seconds = player.currentItem?.duration.seconds, seconds.isFinite {
                self.duration = seconds
            }
            self.updateNowPlayingInfo(timeOnly: true)
        }
    }

    private func removeObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.isPlaying = true
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.isPlaying = false
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: self.currentTime + 30)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: max(0, self.currentTime - 15))
            return .success
        }
    }

    private func updateNowPlayingInfo(timeOnly: Bool = false) {
        guard let episode = currentEpisode else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        if !timeOnly {
            info[MPMediaItemPropertyTitle] = episode.title
            info[MPMediaItemPropertyArtist] = episode.podcastName
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
