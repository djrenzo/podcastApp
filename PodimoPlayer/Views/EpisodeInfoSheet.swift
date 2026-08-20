import SwiftUI

struct EpisodeInfoSheet: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        infoRow(label: "Podcast", value: episode.podcastName)
                        if let date = episode.publishedDate {
                            infoRow(label: "Published", value: date.formatted(date: .long, time: .shortened))
                        }
                        if !episode.formattedDuration.isEmpty {
                            infoRow(label: "Duration", value: episode.formattedDuration)
                        }
                        if let progress = episode.userProgress?.progress, progress > 0 {
                            infoRow(label: "Progress", value: progressText(progress: progress, listenTime: episode.userProgress?.listenTime))
                        }
                        infoRow(label: "Marked as Played", value: episode.isMarkedAsPlayed ? "Yes" : "No")
                        infoRow(label: "Video", value: episode.hasVideo ? "Yes" : "No")
                        if !episode.chapters.isEmpty {
                            infoRow(label: "Chapters", value: "\(episode.chapters.count)")
                        }
                    }
                    if let description = episode.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(description.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.body)
                                .foregroundStyle(Color.podimoInk)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.podimoBackground)
            .navigationTitle("Episode Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 12)
                .frame(width: 64, height: 64)
            Text(episode.title)
                .font(.headline)
                .foregroundStyle(Color.podimoInk)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.podimoInk)
                .multilineTextAlignment(.trailing)
        }
    }

    private func progressText(progress: Double, listenTime: Double?) -> String {
        let percentage = "\(Int(min(max(progress, 0), 1) * 100))%"
        guard let listenTime, listenTime > 0 else { return percentage }
        let minutes = Int(listenTime) / 60
        return "\(percentage) \u{2022} \(minutes) min listened"
    }
}
