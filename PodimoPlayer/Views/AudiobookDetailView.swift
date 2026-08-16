import SwiftUI

struct AudiobookDetailView: View {
    let audiobookId: String
    let previewTitle: String
    let previewImageUrl: String?

    @State private var detail: AudiobookDetail?
    @State private var relatedBooks: [AudiobookSummary] = []
    @State private var chapters: [AudiobookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playback = PlaybackManager.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary).padding(.horizontal, 20)
                } else if isLoading && detail == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    if let description = detail?.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    }
                    if !relatedBooks.isEmpty {
                        relatedSection
                    }
                }
            }
            .padding(.bottom, 120)
        }
        .background(Color.podimoBackground)
        .navigationTitle(previewTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                RemoteArtwork(urlString: detail?.imageUrl ?? previewImageUrl, cornerRadius: 20)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail?.title ?? previewTitle).font(.title3.bold()).foregroundStyle(Color.podimoInk)
                    if let detail, !detail.authorNames.isEmpty {
                        Text(detail.authorNames.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let detail, !detail.narratorNames.isEmpty, detail.narratorNames != detail.authorNames {
                        Text("Narrated by \(detail.narratorNames.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let detail {
                        Text(metaLine(for: detail)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let detail {
                Button {
                    play(detail)
                } label: {
                    Label(isCurrentlyPlaying(detail) ? "Playing" : "Play", systemImage: isCurrentlyPlaying(detail) ? "waveform" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.podimoPurple)
                .disabled(detail.playableURLString == nil)
            }
        }
        .padding(20)
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You might also like")
                .font(.title3.bold())
                .foregroundStyle(Color.podimoInk)
                .padding(.horizontal, 20)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(relatedBooks) { book in
                    NavigationLink(value: AudiobookLink(id: book.id, title: book.title, imageUrl: book.imageUrl)) {
                        VStack(alignment: .leading, spacing: 8) {
                            RemoteArtwork(urlString: book.imageUrl, cornerRadius: 16)
                                .aspectRatio(1, contentMode: .fit)
                            Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(Color.podimoInk)
                            if !book.authorNames.isEmpty {
                                Text(book.authorNames.joined(separator: ", ")).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func metaLine(for detail: AudiobookDetail) -> String {
        var parts: [String] = []
        if let year = detail.yearOfBookPublication { parts.append(year) }
        if let language = detail.language { parts.append(language) }
        if let duration = detail.duration, duration > 0 { parts.append(formattedDuration(duration)) }
        if let percentage = detail.rating?.likedPercentage { parts.append("\(percentage)% liked") }
        if !chapters.isEmpty { parts.append("\(chapters.count) chapters") }
        return parts.joined(separator: " • ")
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private func isCurrentlyPlaying(_ detail: AudiobookDetail) -> Bool {
        playback.currentEpisode?.id == detail.id && playback.isPlaying
    }

    private func play(_ detail: AudiobookDetail) {
        guard let urlString = detail.playableURLString, let url = URL(string: urlString) else { return }
        guard var episode = Episode(dict: [
            "id": detail.id,
            "podcastId": detail.id,
            "podcastName": detail.authorNames.joined(separator: ", "),
            "title": detail.title,
            "imageUrl": detail.imageUrl as Any,
            "hasVideo": false,
            "duration": detail.duration as Any,
            "userProgress": ["listenTime": detail.userProgress?.listenTime as Any]
        ]) else { return }
        episode.chapters = chapters
        episode.isAudiobook = true
        PlaybackManager.shared.play(episode: episode, audioURL: url)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let channelTask = PodimoAPI.shared.getAudiobookChannel(audiobookId: audiobookId)
            async let chaptersTask = PodimoAPI.shared.getAudiobookChapters(audiobookId: audiobookId)
            let result = try await channelTask
            detail = result.audiobook
            relatedBooks = result.youMightAlsoLike
            chapters = (try? await chaptersTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
