import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var region = "nl"
    @State private var podcasts: [Podcast] = []
    @State private var audiobooks: [Audiobook] = []
    @State private var externalPodcasts: [Podcast] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
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
                // Search-as-you-type: .task(id:) restarts (cancelling the
                // prior run) on every keystroke, so the sleep below debounces
                // — only a pause in typing lets a request actually fire.
                .task(id: [query, region]) {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        podcasts = []
                        audiobooks = []
                        externalPodcasts = []
                        hasSearched = false
                        errorMessage = nil
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search()
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
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 10) {
                Text("Region").font(.subheadline).foregroundStyle(.secondary)
                TextField("nl", text: $region)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(width: 60)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.podimoCard, in: RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
        }
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

    private func search() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, credentials.hasCredentials else { return }
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        errorMessage = nil
        hasSearched = true
        do {
            // Fired concurrently: the external search hits a different,
            // unauthenticated service, so it shouldn't wait on (or fail
            // alongside) the Podimo one.
            async let podimoResult = PodimoAPI.shared.search(query: trimmedQuery, region: trimmedRegion.isEmpty ? "nl" : trimmedRegion, limit: 10)
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
