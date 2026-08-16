import SwiftUI

struct NowPlayingView: View {
    @State private var playback = PlaybackManager.shared
    @State private var showChapters = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)

            if let episode = playback.currentEpisode {
                RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 28)
                    .frame(width: 260, height: 260)
                    .shadow(color: Color.podimoPurple.opacity(0.3), radius: 24, y: 12)

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

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(
                get: { playback.currentTime },
                set: { playback.seek(to: $0) }
            ), in: 0...max(playback.duration, 1))
            .tint(Color.podimoPurple)

            HStack {
                Text(format(playback.currentTime))
                Spacer()
                Text(format(playback.duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
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
