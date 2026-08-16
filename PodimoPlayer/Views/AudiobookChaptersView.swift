import SwiftUI

struct AudiobookChaptersView: View {
    @State private var playback = PlaybackManager.shared
    @State private var chapterStore = AudiobookChapterProgressStore.shared
    @Environment(\.dismiss) private var dismiss

    private var episode: Episode? { playback.currentEpisode }

    var body: some View {
        NavigationStack {
            List {
                if let episode {
                    ForEach(episode.chapters) { chapter in
                        chapterRow(chapter, episodeId: episode.id)
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.podimoBackground)
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func chapterRow(_ chapter: AudiobookChapter, episodeId: String) -> some View {
        let isCurrent = playback.currentEpisode?.chapter(at: playback.currentTime)?.sequence == chapter.sequence
        let isDone = isChapterCompleted(chapter, episodeId: episodeId)

        return HStack(spacing: 12) {
            Button {
                chapterStore.toggle(episodeId: episodeId, sequence: chapter.sequence)
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Color.podimoMint : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                playback.seek(to: chapter.startTimestampInSeconds)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.title)
                            .font(.subheadline.weight(isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? Color.podimoPurple : Color.podimoInk)
                        Text(formattedDuration(chapter.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isCurrent {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.podimoPurple)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.podimoCard)
    }

    private func isChapterCompleted(_ chapter: AudiobookChapter, episodeId: String) -> Bool {
        if chapterStore.isManuallyCompleted(episodeId: episodeId, sequence: chapter.sequence) {
            return true
        }
        guard playback.currentEpisode?.id == episodeId else { return false }
        return playback.currentTime >= chapter.endTimestampInSeconds - 1
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes) min"
    }
}
