import SwiftUI

struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var offset = 0
    @State private var hasMore = true

    private let pageSize = 50

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary).padding(.horizontal, 20)
                } else if isLoading && episodes.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(episodes) { episode in
                        EpisodeRow(episode: episode)
                            .padding(.horizontal, 20)
                            .onAppear {
                                if episode.id == episodes.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                    }
                    if isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .background(Color.podimoBackground)
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                RemoteArtwork(urlString: podcast.imageUrl, cornerRadius: 20)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(podcast.title).font(.title3.bold()).foregroundStyle(Color.podimoInk)
                    if let author = podcast.authorName {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let followers = podcast.followerCount {
                        Text("\(followers) followers").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let description = podcast.description, !description.isEmpty {
                Text(description).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .padding(20)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        offset = 0
        hasMore = true
        do {
            let page = try await PodimoAPI.shared.getEpisodes(podcastId: podcast.id, limit: pageSize, offset: 0)
            episodes = page
            offset = page.count
            hasMore = page.count == pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMore else { return }
        isLoadingMore = true
        do {
            let page = try await PodimoAPI.shared.getEpisodes(podcastId: podcast.id, limit: pageSize, offset: offset)
            let existingIds = Set(episodes.map(\.id))
            episodes.append(contentsOf: page.filter { !existingIds.contains($0.id) })
            offset += page.count
            hasMore = page.count == pageSize
        } catch {
            hasMore = false
        }
        isLoadingMore = false
    }
}
