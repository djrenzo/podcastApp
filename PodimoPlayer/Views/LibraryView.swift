import SwiftUI

struct LibraryView: View {
    @State private var entries: [LibraryEntry] = []
    @State private var followed: [Episode] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let credentials = CredentialsStore.shared

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
                        if !followed.isEmpty {
                            followedSection
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

    private var followedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "New Episodes", subtitle: "\(followed.count) waiting for you")
            ForEach(followed) { episode in
                EpisodeRow(episode: episode)
            }
        }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your Library", subtitle: "\(entries.count) shows")
            if isLoading && entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
            } else if entries.isEmpty {
                Text("No shows in your library yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(entries) { entry in
                        LibraryEntryCard(entry: entry)
                    }
                }
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
            async let libraryTask = PodimoAPI.shared.getLibrary()
            async let followedTask = PodimoAPI.shared.getEpisodesFollowed(limit: 10)
            entries = try await libraryTask
            followed = try await followedTask
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SectionHeader: View {
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

private struct LibraryEntryCard: View {
    let entry: LibraryEntry

    var body: some View {
        switch entry {
        case .podcast(let podcast):
            NavigationLink(value: podcast) {
                cardBody(imageUrl: podcast.imageUrl, title: podcast.title, subtitle: podcast.authorName ?? "", badge: podcast.hasVideo)
            }
            .buttonStyle(.plain)
        case .audiobook(let book):
            cardBody(imageUrl: book.imageUrl, title: book.title, subtitle: book.authors.joined(separator: ", "), badge: false)
        }
    }

    private func cardBody(imageUrl: String?, title: String, subtitle: String, badge: Bool) -> some View {
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