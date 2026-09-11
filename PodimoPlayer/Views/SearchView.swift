import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var podcasts: [Podcast] = []
    @State private var audiobooks: [Audiobook] = []
    @State private var externalPodcasts: [Podcast] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    private let credentials = CredentialsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if credentials.hasCredentials {
                        searchFields
                    }
                    if !credentials.hasCredentials {
                        credentialsPrompt
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if hasSearched && podcasts.isEmpty && audiobooks.isEmpty && externalPodcasts.isEmpty {
                        Text("No results for \u{201C}\(query)\u{201D}.")
                            .foregroundStyle(.secondary)
                    } else if hasSearched {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
                // A plain Task kicked off from onChange, rather than
                // .task(id:) — .task is cancelled and *restarted* every time
                // this view disappears/reappears (e.g. pushing a
                // PodcastDetailView and coming back), which would otherwise
                // re-run the search — and its debounce sleep — on every trip
                // back from a result, flashing the loading state and
                // discarding what's already on screen.
                .onChange(of: query) { scheduleSearch() }
                .onAppear {
                    guard !hasSearched, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    scheduleSearch()
                }
            }
            .background(Color.podimoBackground)
            .navigationTitle("Search")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .navigationDestination(for: AudiobookLink.self) { link in
                AudiobookDetailView(audiobookId: link.id, previewTitle: link.title, previewImageUrl: link.imageUrl)
            }
        }
    }

    private var searchFields: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search podcasts and audiobooks", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 14))
    }

    private var credentialsPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "key.fill")
                .font(.title2)
                .foregroundStyle(.white)
            Text("Connect your Podimo account")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add your Cookie and Authorization token in Settings to search Podimo.")
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
            Button("Try again") { Task { await search() } }
                .buttonStyle(.borderedProminent)
                .tint(Color.podimoPurple)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 24))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !podcasts.isEmpty {
                CollapsibleGridSection(title: "Podcasts", items: podcasts, collapsedCount: 5, isLoading: false, emptyMessage: "No podcasts found.") { podcast in
                    NavigationLink(value: podcast) {
                        LibraryCardBody(imageUrl: podcast.imageUrl, title: podcast.title, subtitle: podcast.authorName ?? "", badge: podcast.hasVideo)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !audiobooks.isEmpty {
                CollapsibleGridSection(title: "Audiobooks", items: audiobooks, collapsedCount: 5, isLoading: false, emptyMessage: "No audiobooks found.") { book in
                    NavigationLink(value: AudiobookLink(id: book.id, title: book.title, imageUrl: book.imageUrl)) {
                        LibraryCardBody(imageUrl: book.imageUrl, title: book.title, subtitle: book.authors.joined(separator: ", "), badge: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !externalPodcasts.isEmpty {
                CollapsibleGridSection(title: "External", items: externalPodcasts, collapsedCount: 5, isLoading: false, emptyMessage: "No external podcasts found.") { podcast in
                    NavigationLink(value: podcast) {
                        LibraryCardBody(imageUrl: podcast.imageUrl, title: podcast.title, subtitle: podcast.authorName ?? "", badge: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Debounces search-as-you-type: cancels whatever's still pending from
    /// the last keystroke and starts a fresh 350ms-delayed one. Stored in
    /// @State (rather than a `.task`) so it isn't tied to this view's
    /// appear/disappear lifecycle.
    private func scheduleSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            podcasts = []
            audiobooks = []
            externalPodcasts = []
            hasSearched = false
            errorMessage = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, credentials.hasCredentials else { return }
        isLoading = true
        errorMessage = nil
        hasSearched = true
        do {
            // Fired concurrently: the external search hits a different,
            // unauthenticated service, so it shouldn't wait on (or fail
            // alongside) the Podimo one.
            async let podimoResult = PodimoAPI.shared.search(query: trimmedQuery, region: credentials.searchRegion, limit: 10)
            async let externalResult = ExternalPodcastAPI.shared.search(query: trimmedQuery)
            let result = try await podimoResult
            podcasts = result.podcasts
            audiobooks = result.audiobooks
            externalPodcasts = ((try? await externalResult) ?? []).map { Podcast(externalFeed: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
