import Foundation

enum PodimoError: LocalizedError {
    case missingCredentials
    case badResponse
    case http(Int)
    case graphQL(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Add your Podimo cookie and auth token in Settings first."
        case .badResponse: return "The server returned an unexpected response."
        case .http(let code): return "Request failed with status \(code)."
        case .graphQL(let message): return message
        }
    }
}

final class PodimoAPI: @unchecked Sendable {
    static let shared = PodimoAPI()
    private let endpoint = URL(string: "https://open.podimo.com/graphql")!

    private func perform(operationName: String, query: String, variables: [String: Any], extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let creds = CredentialsStore.shared
        guard creds.hasCredentials else { throw PodimoError.missingCredentials }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(creds.authToken, forHTTPHeaderField: "Authorization")
        request.setValue(creds.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://open.podimo.com", forHTTPHeaderField: "Origin")
        request.setValue("https://open.podimo.com/", forHTTPHeaderField: "Referer")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let bodyData = try JSONSerialization.data(withJSONObject: [
            "operationName": operationName, "variables": variables, "query": query
        ])
        request.httpBody = bodyData

        var logEntry = DebugLogEntry(
            operationName: operationName,
            requestURL: endpoint.absoluteString,
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: String(data: bodyData, encoding: .utf8) ?? ""
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            logEntry.statusCode = http?.statusCode
            logEntry.responseBody = String(data: data, encoding: .utf8)

            guard let http else {
                logEntry.errorDescription = "No HTTP response"
                DebugLogStore.shared.record(logEntry)
                throw PodimoError.badResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                logEntry.errorDescription = "HTTP \(http.statusCode)"
                DebugLogStore.shared.record(logEntry)
                throw PodimoError.http(http.statusCode)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logEntry.errorDescription = "Unparseable response body"
                DebugLogStore.shared.record(logEntry)
                throw PodimoError.badResponse
            }
            if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
                let message = first["message"] as? String ?? "Unknown GraphQL error"
                logEntry.errorDescription = message
                DebugLogStore.shared.record(logEntry)
                throw PodimoError.graphQL(message)
            }
            guard let result = json["data"] as? [String: Any] else {
                logEntry.errorDescription = "Missing data field"
                DebugLogStore.shared.record(logEntry)
                throw PodimoError.badResponse
            }
            DebugLogStore.shared.record(logEntry)
            return result
        } catch let error as PodimoError {
            throw error
        } catch {
            logEntry.errorDescription = error.localizedDescription
            DebugLogStore.shared.record(logEntry)
            throw error
        }
    }

    func getLibrary() async throws -> [LibraryEntry] {
        let data = try await perform(
            operationName: "LibrarySavedItemsResultsQuery",
            query: GraphQLQueries.library,
            variables: ["podcastsSorting": "DATE_FOLLOWED"]
        )
        let podcasts = data["podcastsFollowed"] as? [[String: Any]] ?? []
        let audiobooks = data["audiobooksUserLibrary"] as? [[String: Any]] ?? []
        let podcastEntries = podcasts.compactMap { Podcast(dict: $0) }.map { LibraryEntry.podcast($0) }
        let audiobookEntries = audiobooks.compactMap { Audiobook(dict: $0) }.map { LibraryEntry.audiobook($0) }
        return podcastEntries + audiobookEntries
    }

    func getEpisodes(podcastId: String, limit: Int = 50, offset: Int = 0) async throws -> [Episode] {
        let data = try await perform(operationName: "PodcastEpisodesResultsQuery", query: GraphQLQueries.episodes, variables: ["podcastId": podcastId, "limit": limit, "offset": offset, "sorting": "PUBLISHED_DESCENDING"])
        let list = data["podcastEpisodes"] as? [[String: Any]] ?? []
        return list.compactMap { Episode(dict: $0) }
    }

    func getEpisodesFollowed(limit: Int = 20) async throws -> [Episode] {
        let data = try await perform(operationName: "EpisodesFollowedResultsQuery", query: GraphQLQueries.followed, variables: ["limit": limit])
        let list = data["podcastEpisodesFollowed"] as? [[String: Any]] ?? []
        return list.compactMap { Episode(dict: $0) }
    }

    func getAudiobookChannel(audiobookId: String, limit: Int = 10, offset: Int = 0) async throws -> (audiobook: AudiobookDetail, youMightAlsoLike: [AudiobookSummary]) {
        let data = try await perform(operationName: "AudiobookChannelQuery", query: GraphQLQueries.audiobookChannel, variables: ["audiobookId": audiobookId, "limit": limit, "offset": offset], extraHeaders: ["user-os": "ios"])
        guard let audiobookDict = data["audiobook"] as? [String: Any], let audiobook = AudiobookDetail(dict: audiobookDict) else {
            throw PodimoError.badResponse
        }
        let relatedList = data["youMightAlsoLikeData"] as? [[String: Any]] ?? []
        let related = relatedList.compactMap { AudiobookSummary(dict: $0) }
        return (audiobook, related)
    }

    func getEpisodeURL(podcastId: String, episodeId: String) async throws -> String {
        let data = try await perform(operationName: "PlaybackByPodcastEpisodeQuery", query: GraphQLQueries.mediaURL, variables: ["podcastId": podcastId, "episodeId": episodeId])
        guard let playback = data["playbackByPodcastEpisode"] as? [String: Any],
              let track = playback["track"] as? [String: Any],
              let url = track["url"] as? String else {
            throw PodimoError.badResponse
        }
        return url
    }
}
