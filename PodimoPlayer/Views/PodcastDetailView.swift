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
    @State private var isFollowing = false
    @State private var isTogglingFollow = false
    @State private var externalLibrary = ExternalLibraryStore.shared
    /// Backfilled when `podcast` was reconstructed from just an episode's
    /// denormalized fields (Now Playing's info button, Keep Listening's
    /// "Podcast" action) and so is missing its author/description.
    @State private var resolvedPodcast: Podcast?

    private let pageSize = 50
    private var sortOrderKey: String { "podimo_episode_sort_\(podcast.id)" }

    private var displayAuthor: String? { resolvedPodcast?.authorName ?? podcast.authorName }
    private var displayDescription: String? { resolvedPodcast?.description ?? podcast.description }

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
                        EpisodeRow(episode: episode, podcastEpisodesContext: episodes)
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
            if let feedURL = podcast.externalFeedURL {
                isFollowing = externalLibrary.isInLibrary(feedURL: feedURL)
            } else {
                isFollowing = podcast.isFollowing ?? false
            }
            await load()
            if podcast.externalFeedURL == nil {
                await refreshFollowState()
                if podcast.authorName == nil || podcast.description == nil {
                    resolvedPodcast = try? await PodimoAPI.shared.getPodcast(podcastId: podcast.id)
                }
            }
        }
        .sheet(isPresented: $showFullDescription) {
            NavigationStack {
                ScrollView {
                    Text(displayDescription ?? "")
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
                    if let author = displayAuthor {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let followers = podcast.followerCount {
                        Text("\(followers) followers").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            followButton
            metaChips
            if let description = displayDescription, !description.isEmpty {
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

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            Label(
                isFollowing ? "Remove from Library" : "Add to Library",
                systemImage: isFollowing ? "checkmark.circle.fill" : "plus.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.podimoPurple)
        .disabled(isTogglingFollow)
    }

    private var metaChips: some View {
        HStack(spacing: 8) {
            if !episodes.isEmpty {
                metaChip(icon: "list.bullet", text: "\(episodes.count)\(hasMore ? "+" : "") episodes")
            }
            Spacer()
            sortButton
        }
    }

    /// Optimistically flips the local state so the button responds instantly,
    /// then reconciles with (or reverts to) whatever the server confirms.
    /// External podcasts have no server to reconcile with — they're just
    /// added to or removed from the local External library directly.
    private func toggleFollow() {
        guard !isTogglingFollow else { return }
        let target = !isFollowing
        if let feedURL = podcast.externalFeedURL {
            isFollowing = target
            if target {
                externalLibrary.add(ExternalLibraryEntry(
                    feedURL: feedURL,
                    title: podcast.title,
                    authorName: podcast.authorName,
                    description: podcast.description,
                    imageUrl: podcast.imageUrl,
                    addedDate: Date()
                ))
            } else {
                externalLibrary.remove(feedURL: feedURL)
            }
            return
        }
        isFollowing = target
        isTogglingFollow = true
        Task {
            do {
                let confirmed = try await PodimoAPI.shared.setPodcastFollowed(podcastId: podcast.id, follow: target)
                await MainActor.run {
                    isFollowing = confirmed
                    isTogglingFollow = false
                }
            } catch {
                await MainActor.run {
                    isFollowing = !target
                    isTogglingFollow = false
                }
            }
        }
    }

    private func refreshFollowState() async {
        guard !isTogglingFollow else { return }
        if let state = try? await PodimoAPI.shared.getPodcastFollowState(podcastId: podcast.id) {
            isFollowing = state
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
            if let feedURL = podcast.externalFeedURL {
                // The whole feed comes back in one request — there's no
                // server-side sort/paging to ask for, so just reverse
                // locally for "oldest first".
                let feed = try await ExternalPodcastAPI.shared.fetchEpisodes(feedURL: feedURL)
                episodes = sortOrder == .ascending ? Array(feed.episodes.reversed()) : feed.episodes
                hasMore = false
                if podcast.authorName == nil || podcast.description == nil {
                    var backfilled = podcast
                    backfilled.authorName = feed.author
                    backfilled.description = feed.description
                    resolvedPodcast = backfilled
                }
            } else {
                let page = try await PodimoAPI.shared.getEpisodes(podcastId: podcast.id, limit: pageSize, offset: 0, sorting: sortOrder.rawValue)
                episodes = page
                offset = page.count
                hasMore = page.count == pageSize
            }
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
