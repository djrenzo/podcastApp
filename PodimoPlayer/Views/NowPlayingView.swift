import SwiftUI
import AVKit

struct NowPlayingView: View {
    @State private var playback = PlaybackManager.shared
    @State private var showChapters = false
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.podimoBackground.ignoresSafeArea())
        .sheet(isPresented: $showChapters) {
            AudiobookChaptersView()
        }
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
