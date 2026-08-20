import SwiftUI

enum EpisodeWatchFilter: String, CaseIterable {
    case all = "All Episodes"
    case unwatched = "Only Unwatched"
}

enum EpisodeSortOrder: String {
    case descending = "PUBLISHED_DESCENDING"
    case ascending = "PUBLISHED_ASCENDING"

    var toggled: EpisodeSortOrder {
        self == .descending ? .ascending : .descending
    }

    var label: String {
        self == .descending ? "Newest First" : "Oldest First"
    }

    var icon: String {
        self == .descending ? "arrow.down" : "arrow.up"
    }
}

struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var offset = 0
    @State private var hasMore = true
    @State private var sortOrder: EpisodeSortOrder = .descending
    @State private var watchFilter: EpisodeWatchFilter = .all
    @State private var progressStore = ListeningProgressStore.shared
    @State private var showFullDescription = false

    private let pageSize = 50
    private var sortOrderKey: String { "podimo_episode_sort_\(podcast.id)" }

    /// Filtered client-side — the episode list API has no "unwatched" filter
    /// of its own, and "watched" already depends on merging local progress
    /// data on top of whatever the API reports (see ListeningProgressStore).
    private var filteredEpisodes: [Episode] {
        switch watchFilter {
        case .all: return episodes
        case .unwatched: return episodes.filter { !progressStore.isWatched($0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if !episodes.isEmpty {
                    filterPicker
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary).padding(.horizontal, 20)
                } else if isLoading && episodes.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    ForEach(filteredEpisodes) { episode in
                        EpisodeRow(episode: episode)
                            .padding(.horizontal, 20)
                            .onAppear {
                                if episode.id == filteredEpisodes.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                    }
                    if isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    if filteredEpisodes.isEmpty && !episodes.isEmpty {
                        Text("No unwatched episodes.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .background(Color.podimoBackground)
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadSortOrder()
            await load()
        }
        .sheet(isPresented: $showFullDescription) {
            NavigationStack {
                ScrollView {
                    Text(podcast.description ?? "")
                        .font(.body)
                        .foregroundStyle(Color.podimoInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .background(Color.podimoBackground)
                .navigationTitle(podcast.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFullDescription = false }
                    }
                }
            }
        }
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
            metaChips
            if let description = podcast.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .contentShape(Rectangle())
                    .onTapGesture { showFullDescription = true }
            }
        }
        .padding(20)
    }

    private var metaChips: some View {
        HStack(spacing: 8) {
            if podcast.isFollowing == true {
                metaChip(icon: "checkmark", text: "Following")
            }
            if !episodes.isEmpty {
                metaChip(icon: "list.bullet", text: "\(episodes.count)\(hasMore ? "+" : "") episodes")
            }
            Spacer()
            sortButton
        }
    }

    private var filterPicker: some View {
        Picker("Filter", selection: $watchFilter) {
            ForEach(EpisodeWatchFilter.allCases, id: \.self) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var sortButton: some View {
        Button {
            sortOrder = sortOrder.toggled
            saveSortOrder()
            Task { await load() }
        } label: {
            Label(sortOrder.label, systemImage: sortOrder.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.podimoPurple)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.podimoPurple.opacity(0.12), in: Capsule())
        }
        .disabled(isLoading)
    }

    private func metaChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.podimoPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.podimoPurple.opacity(0.12), in: Capsule())
    }

    private func loadSortOrder() {
        if let raw = UserDefaults.standard.string(forKey: sortOrderKey), let order = EpisodeSortOrder(rawValue: raw) {
            sortOrder = order
        }
    }

    private func saveSortOrder() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: sortOrderKey)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        offset = 0
        hasMore = true
        do {
            let page = try await PodimoAPI.shared.getEpisodes(podcastId: podcast.id, limit: pageSize, offset: 0, sorting: sortOrder.rawValue)
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
            let page = try await PodimoAPI.shared.getEpisodes(podcastId: podcast.id, limit: pageSize, offset: offset, sorting: sortOrder.rawValue)
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
