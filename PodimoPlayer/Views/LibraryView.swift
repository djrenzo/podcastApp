import SwiftUI

struct LibraryView: View {
    @State private var entries: [LibraryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var progressStore = ListeningProgressStore.shared
    @State private var keepListeningExpanded = false
    private let credentials = CredentialsStore.shared

    private var podcasts: [Podcast] {
        entries.compactMap { if case .podcast(let podcast) = $0 { return podcast }; return nil }
    }

    private var audiobooks: [Audiobook] {
        entries.compactMap { if case .audiobook(let book) = $0 { return book }; return nil }
    }

    private var keepListeningRecords: [ListeningProgressRecord] {
        Array(progressStore.inProgress.prefix(10))
    }

    private var visibleKeepListeningRecords: [ListeningProgressRecord] {
        keepListeningExpanded ? keepListeningRecords : Array(keepListeningRecords.prefix(5))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    if !credentials.hasCredentials {
                        credentialsPrompt
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else {
                        if !keepListeningRecords.isEmpty {
                            keepListeningSection
                        }
                        librarySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Color.podimoBackground)
            .navigationTitle("Library")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .navigationDestination(for: AudiobookLink.self) { link in
                AudiobookDetailView(audiobookId: link.id, previewTitle: link.title, previewImageUrl: link.imageUrl)
            }
            .task { await loadIfNeeded() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Good listening")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.podimoInk)
            Text("Your podcasts and audiobooks, in one place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var credentialsPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.white)
            Text("Connect your Podimo account")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add your Cookie and Authorization token in Settings to load your Library.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.podimoBrand, in: RoundedRectangle(cornerRadius: 24))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.podimoPurple)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 24))
    }

    private var keepListeningSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Keep Listening", subtitle: "\(keepListeningRecords.count) in progress")
            ForEach(visibleKeepListeningRecords) { record in
                if let episode = episode(from: record) {
                    EpisodeRow(episode: episode)
                }
            }
            if keepListeningRecords.count > 5 {
                ExpandButton(isExpanded: keepListeningExpanded, collapsedLabel: "Show 10", expandedLabel: "Show fewer") {
                    keepListeningExpanded.toggle()
                }
            }
        }
    }

    private func episode(from record: ListeningProgressRecord) -> Episode? {
        guard var episode = Episode(dict: [
            "id": record.episodeId,
            "podcastId": record.podcastId,
            "podcastName": record.podcastName,
            "title": record.title,
            "imageUrl": record.imageUrl as Any,
            "hasVideo": record.hasVideo,
            "duration": record.duration,
            "userProgress": ["progress": record.progress, "listenTime": record.listenTime]
        ]) else { return nil }
        episode.chapters = record.chapters
        episode.isAudiobook = record.isAudiobook
        return episode
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 28) {
            CollapsibleGridSection(title: "Podcasts", items: podcasts, collapsedCount: 6, isLoading: isLoading && entries.isEmpty, emptyMessage: "No podcasts in your library yet.") { podcast in
                NavigationLink(value: podcast) {
                    LibraryCardBody(imageUrl: podcast.imageUrl, title: podcast.title, subtitle: podcast.authorName ?? "", badge: podcast.hasVideo)
                }
                .buttonStyle(.plain)
            }
            CollapsibleGridSection(title: "Audiobooks", items: audiobooks, collapsedCount: 6, isLoading: isLoading && entries.isEmpty, emptyMessage: "No audiobooks in your library yet.") { book in
                NavigationLink(value: AudiobookLink(id: book.id, title: book.title, imageUrl: book.imageUrl)) {
                    LibraryCardBody(imageUrl: book.imageUrl, title: book.title, subtitle: book.authors.joined(separator: ", "), badge: false)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadIfNeeded() async {
        guard entries.isEmpty, credentials.hasCredentials else { return }
        await load()
    }

    private func load() async {
        guard credentials.hasCredentials else { return }
        isLoading = true
        errorMessage = nil
        do {
            entries = try await PodimoAPI.shared.getLibrary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold()).foregroundStyle(Color.podimoInk)
            Spacer()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ExpandButton: View {
    let isExpanded: Bool
    let collapsedLabel: String
    let expandedLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation { action() }
        } label: {
            Text(isExpanded ? expandedLabel : collapsedLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.podimoPurple)
        }
    }
}

struct CollapsibleGridSection<Item: Identifiable, ItemView: View>: View {
    let title: String
    let items: [Item]
    let collapsedCount: Int
    let isLoading: Bool
    let emptyMessage: String
    @ViewBuilder let itemView: (Item) -> ItemView
    @State private var expanded = false

    private var visibleItems: [Item] {
        expanded ? items : Array(items.prefix(collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: "\(items.count)")
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(visibleItems) { item in
                        itemView(item)
                    }
                }
                if items.count > collapsedCount {
                    ExpandButton(isExpanded: expanded, collapsedLabel: "Show all (\(items.count))", expandedLabel: "Show fewer") {
                        expanded.toggle()
                    }
                }
            }
        }
    }
}

struct LibraryCardBody: View {
    let imageUrl: String?
    let title: String
    let subtitle: String
    let badge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RemoteArtwork(urlString: imageUrl, cornerRadius: 16)
                    .aspectRatio(1, contentMode: .fit)
                if badge {
                    Image(systemName: "play.rectangle.fill")
                        .font(.caption)
                        .padding(6)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Color.podimoInk)
            Text(subtitle).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        }
    }
}
