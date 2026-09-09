import SwiftUI

struct QueueView: View {
    @State private var queueManager = EpisodeQueueManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if queueManager.manualQueue.isEmpty && queueManager.autoplayQueue.isEmpty {
                    ContentUnavailableView(
                        "Queue is empty",
                        systemImage: "list.bullet",
                        description: Text("Add episodes to the queue, or play one from a podcast to queue up what comes after it.")
                    )
                } else {
                    List {
                        if !queueManager.manualQueue.isEmpty {
                            Section("Up Next") {
                                ForEach(queueManager.manualQueue) { episode in
                                    row(for: episode)
                                }
                                .onDelete { offsets in
                                    queueManager.removeFromManualQueue(at: offsets)
                                }
                            }
                        }
                        if !queueManager.autoplayQueue.isEmpty {
                            Section("Autoplay") {
                                ForEach(queueManager.autoplayQueue) { episode in
                                    row(for: episode)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.podimoBackground)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear Manual Queue", role: .destructive) {
                        queueManager.clearManualQueue()
                    }
                    .disabled(queueManager.manualQueue.isEmpty)
                }
            }
        }
    }

    private func row(for episode: Episode) -> some View {
        HStack(spacing: 12) {
            RemoteArtwork(urlString: episode.imageUrl, cornerRadius: 8)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(episode.podcastName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .listRowBackground(Color.podimoCard)
    }
}
