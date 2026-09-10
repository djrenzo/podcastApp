import SwiftUI
import AVKit

struct NowPlayingView: View {
    @State private var playback = PlaybackManager.shared
    @State private var showChapters = false
    @State private var showQueue = false
    @State private var navPath = NavigationPath()
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    /// Tracks the physical device orientation (not the interface orientation)
    /// so a video episode can be blown up to fill the screen the moment the
    /// phone is turned sideways, the way a full-screen video player behaves
    /// elsewhere. Seeded from the current orientation so a sheet opened while
    /// already rotated starts fullscreen instead of waiting for the next turn.
    @State private var isLandscape = UIDevice.current.orientation.isLandscape
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $navPath) {
            Group {
                if playback.isVideoActive, isLandscape, let player = playback.player {
                    fullscreenVideo(player: player)
                } else {
                    portraitContent
                }
            }
            .background(Color.podimoBackground.ignoresSafeArea())
            // The player screen itself has no nav bar (it's a drag-dismiss
            // sheet); pushed detail screens bring their own, so the (i) button
            // lands on the exact same PodcastDetailView / AudiobookDetailView,
            // back button and all, as opening it from the Library.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .navigationDestination(for: AudiobookLink.self) { link in
                AudiobookDetailView(audiobookId: link.id, previewTitle: link.title, previewImageUrl: link.imageUrl)
            }
            .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
            .onDisappear { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Face-up/-down/unknown aren't real interface orientations (e.g.
                // the phone laid flat on a table) — ignore those and keep
                // whatever the last valid reading was, rather than flipping back
                // out of fullscreen for no visible reason.
                let orientation = UIDevice.current.orientation
                guard orientation.isValidInterfaceOrientation else { return }
                isLandscape = orientation.isLandscape
            }
            .sheet(isPresented: $showChapters) {
                AudiobookChaptersView()
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
            }
        }
    }

    private func openDetail() {
        guard let episode = playback.currentEpisode else { return }
        if episode.isAudiobook {
            navPath.append(AudiobookLink(id: episode.id, title: episode.title, imageUrl: episode.imageUrl))
        } else if let podcast = minimalPodcast(for: episode) {
            navPath.append(podcast)
        }
    }

    /// The Now Playing episode only carries its podcast's denormalized
    /// id/name/image, not a full Podcast — reconstruct a minimal one.
    /// `Podcast.init?(dict:)` reads the image from a nested `images.coverImageUrl`.
    private func minimalPodcast(for episode: Episode) -> Podcast? {
        Podcast(dict: [
            "id": episode.podcastId,
            "title": episode.podcastName,
            "hasVideo": episode.hasVideo,
            "images": ["coverImageUrl": episode.imageUrl as Any]
        ])
    }

    private var portraitContent: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)

            if let episode = playback.currentEpisode {
                artworkOrVideo(for: episode)

                VStack(spacing: 6) {
                    Text(episode.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(2)
                    Text(episode.podcastName).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                progressSection

                if !episode.chapters.isEmpty {
                    chapterBar(for: episode)
                }

                HStack(spacing: 48) {
                    Button { playback.seek(to: max(0, playback.currentTime - 15)) } label: {
                        Image(systemName: "gobackward.15").font(.title)
                    }
                    Button { playback.togglePlayPause() } label: {
                        Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    Button { playback.seek(to: playback.currentTime + 30) } label: {
                        Image(systemName: "goforward.30").font(.title)
                    }
                }
                .foregroundStyle(Color.podimoInk)

                HStack(spacing: 24) {
                    sleepTimerButton
                    queueButton
                    markDoneButton
                    infoButton
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Fills the entire screen edge-to-edge with the video, replacing the
    /// whole player layout (artwork slot, transport controls, everything) —
    /// only reachable while a video rendition is actually active, so rotating
    /// back to portrait (or tapping to collapse to audio) always drops back
    /// into the normal layout above.
    private func fullscreenVideo(player: AVPlayer) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button {
                playback.collapseToAudioOnly()
            } label: {
                Image(systemName: "headphones")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(20)
        }
    }

    private var queueButton: some View {
        Button {
            showQueue = true
        } label: {
            Image(systemName: "list.bullet")
                .font(.subheadline)
                .foregroundStyle(Color.podimoPurple)
                .padding(10)
                .background(Color.podimoCard, in: Circle())
        }
    }

    /// Podcast episode: mark done + play the next queued episode.
    /// Audiobook: mark the current chapter done + jump to the next chapter.
    private var markDoneButton: some View {
        Button {
            playback.markCurrentDoneAndAdvance()
        } label: {
            Image(systemName: "checkmark")
                .font(.subheadline)
                .foregroundStyle(Color.podimoPurple)
                .padding(10)
                .background(Color.podimoCard, in: Circle())
        }
    }

    private var infoButton: some View {
        Button {
            openDetail()
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color.podimoPurple)
                .padding(10)
                .background(Color.podimoCard, in: Circle())
        }
    }

    private static let sleepTimerOptions = [5, 10, 15, 30, 45, 60]

    private var sleepTimerButton: some View {
        Menu {
            ForEach(Self.sleepTimerOptions, id: \.self) { minutes in
                Button {
                    playback.setSleepTimer(minutes: minutes)
                } label: {
                    Label("\(minutes) min", systemImage: "moon.zzz")
                }
            }
            if playback.sleepTimerRemaining != nil {
                Button(role: .destructive) {
                    playback.cancelSleepTimer()
                } label: {
                    Label("Cancel Timer", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "moon.zzz")
                if let remaining = playback.sleepTimerRemaining {
                    Text(sleepTimerLabel(remaining))
                        .font(.caption.monospacedDigit())
                }
            }
            .font(.subheadline)
            .foregroundStyle(playback.sleepTimerRemaining != nil ? Color.podimoPurple : Color.secondary)
            .padding(10)
            .background(Color.podimoCard, in: Capsule())
        }
    }

    private func sleepTimerLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Shows the video inline, in the same slot the artwork occupies for
    /// audio episodes, rather than a separate full-screen cover. Video
    /// episodes still start audio-only — tapping the toggle is what actually
    /// swaps in the (heavier) video rendition via PlaybackManager.
    @ViewBuilder
    private func artworkOrVideo(for episode: Episode) -> some View {
        ZStack(alignment: .topTrailing) {
            if playback.isVideoActive, let player = playback.player {
                VideoPlayer(player: player)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
            } else {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 28)
                    .frame(width: 260, height: 260)
            }
            if playback.videoStreamURL != nil {
                Button {
                    if playback.isVideoActive {
                        playback.collapseToAudioOnly()
                    } else {
                        playback.expandToVideo()
                    }
                } label: {
                    Image(systemName: playback.isVideoActive ? "headphones" : "video.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .padding(10)
            }
        }
        .shadow(color: Color.podimoPurple.opacity(0.3), radius: 24, y: 12)
    }

    private var progressSection: some View {
        VStack(spacing: 6) {
            // Seeking on every drag tick fights the periodic time observer
            // (which keeps overwriting currentTime from the actual, laggier
            // player position mid-seek), reading as a jumpy thumb instead of a
            // smooth glide. Track the finger locally while dragging and only
            // commit a single real seek once the gesture ends.
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : playback.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(playback.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        scrubTime = playback.currentTime
                        isScrubbing = true
                    } else {
                        playback.seek(to: scrubTime)
                        isScrubbing = false
                    }
                }
            )
            .tint(Color.podimoPurple)

            HStack {
                Text(format(isScrubbing ? scrubTime : playback.currentTime))
                Spacer()
                speedButton
                Spacer()
                Text(format(playback.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
    }

    /// Cycles 1x → 1.5x → 2x → 1x. Applies to whatever's currently loaded —
    /// audio episode, audiobook, or video — since they all share one AVPlayer.
    private var speedButton: some View {
        Button {
            playback.cyclePlaybackRate()
        } label: {
            Text(speedLabel(playback.playbackRate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.podimoPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.podimoCard, in: Capsule())
        }
    }

    private func speedLabel(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))x" : "\(rate)x"
    }

    private func chapterBar(for episode: Episode) -> some View {
        HStack(spacing: 12) {
            Button {
                jumpToAdjacentChapter(for: episode, forward: false)
            } label: {
                Image(systemName: "backward.end.fill")
                    .foregroundStyle(Color.podimoPurple)
            }

            Button {
                showChapters = true
            } label: {
                VStack(spacing: 2) {
                    Text(chapterSubtitle(for: episode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currentChapter(for: episode)?.title ?? "Chapters")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.podimoInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }

            Button {
                jumpToAdjacentChapter(for: episode, forward: true)
            } label: {
                Image(systemName: "forward.end.fill")
                    .foregroundStyle(Color.podimoPurple)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 32)
    }

    private func currentChapter(for episode: Episode) -> AudiobookChapter? {
        episode.chapter(at: playback.currentTime)
    }

    private func chapterSubtitle(for episode: Episode) -> String {
        guard let chapter = currentChapter(for: episode) else { return "\(episode.chapters.count) chapters" }
        return "Chapter \(chapter.sequence) of \(episode.chapters.count)"
    }

    private func jumpToAdjacentChapter(for episode: Episode, forward: Bool) {
        let chapters = episode.chapters.sorted { $0.sequence < $1.sequence }
        let currentSequence = currentChapter(for: episode)?.sequence
        guard let currentIndex = chapters.firstIndex(where: { $0.sequence == currentSequence }) else { return }
        let targetIndex = forward ? currentIndex + 1 : currentIndex - 1
        guard chapters.indices.contains(targetIndex) else { return }
        playback.seek(to: chapters[targetIndex].startTimestampInSeconds)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
