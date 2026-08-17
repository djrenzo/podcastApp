import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var region = "nl"
    @State private var podcasts: [Podcast] = []
    @State private var audiobooks: [Audiobook] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false
    private let credentials = CredentialsStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    if credentials.hasCredentials {
                        searchFields
                    }
                    if !credentials.hasCredentials {
                        credentialsPrompt
                    } else if let errorMessage {
                        errorCard(errorMessage)
                    } else if isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if hasSearched && podcasts.isEmpty && audiobooks.isEmpty {
                        Text("No results for \u{201C}\(query)\u{201D}.")
                            .foregroundStyle(.secondary)
                    } else if hasSearched {
                        resultsSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Color.podimoBackground)
            .navigationTitle("Search")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .navigationDestination(for: AudiobookLink.self) { link in
                AudiobookDetailView(audiobookId: link.id, previewTitle: link.title, previewImageUrl: link.imageUrl)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.podimoInk)
            Text("Find podcasts and audiobooks on Podimo.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 12)
    }

    private var searchFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search podcasts and audiobooks", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
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
                Button("Search") { Task { await search() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.podimoPurple)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            let result = try await PodimoAPI.shared.search(query: trimmedQuery, region: trimmedRegion.isEmpty ? "nl" : trimmedRegion, limit: 10)
            podcasts = result.podcasts
            audiobooks = result.audiobooks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
