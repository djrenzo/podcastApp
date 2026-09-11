import Foundation

/// Search result for a podcast sourced from an external, non-Podimo RSS feed
/// (via rss.com's public podcast-index search proxy).
struct ExternalFeedResult: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String
    let url: String
    let description: String?
    let author: String?
    let ownerName: String?
    let image: String?
    let artwork: String?
    let episodeCount: Int?
}

private struct ExternalFeedSearchResponse: Decodable {
    let feeds: [ExternalFeedResult]
}

enum ExternalPodcastError: LocalizedError {
    case badURL
    case http(Int)
    case badResponse
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid feed URL."
        case .http(let code): return "Request failed (HTTP \(code))."
        case .badResponse: return "The server returned an unexpected response."
        case .parsingFailed: return "Couldn't read that podcast's RSS feed."
        }
    }
}

struct ParsedRSSFeed {
    var title: String?
    var description: String?
    var imageUrl: String?
    var episodes: [Episode]
}

final class ExternalPodcastAPI: @unchecked Sendable {
    static let shared = ExternalPodcastAPI()

    private let searchEndpoint = URL(string: "https://apollo.rss.com/search/podcast-index/byterm")!
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:153.0) Gecko/20100101 Firefox/153.0"

    private init() {}

    func search(query: String) async throws -> [ExternalFeedResult] {
        var request = URLRequest(url: searchEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://rss.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://rss.com", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONEncoder().encode(["q": query])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExternalPodcastError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(ExternalFeedSearchResponse.self, from: data)
        return decoded.feeds
    }

    func fetchEpisodes(feedURL: String) async throws -> ParsedRSSFeed {
        guard let url = URL(string: feedURL) else { throw ExternalPodcastError.badURL }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ExternalPodcastError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try RSSFeedParser().parse(data: data, feedURL: feedURL)
    }
}

/// Minimal RSS 2.0 / iTunes-namespace feed parser, just enough to populate
/// the same `Episode` model the Podimo API produces so downstream views
/// (PodcastDetailView, EpisodeRow, playback, downloads) need no branching.
private final class RSSFeedParser: NSObject, XMLParserDelegate {
    private var feedTitle: String?
    private var feedDescription: String?
    private var feedImageUrl: String?
    private var items: [[String: String]] = []

    private var currentText = ""
    private var currentItem: [String: String] = [:]
    private var inItem = false

    private static let rfc822Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    func parse(data: Data, feedURL: String) throws -> ParsedRSSFeed {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw ExternalPodcastError.parsingFailed }
        let episodes = items.enumerated().map { index, dict in
            makeEpisode(from: dict, index: index, feedURL: feedURL, podcastTitle: feedTitle ?? "")
        }
        return ParsedRSSFeed(title: feedTitle, description: feedDescription, imageUrl: feedImageUrl, episodes: episodes)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""
        switch elementName {
        case "item":
            inItem = true
            currentItem = [:]
        case "enclosure":
            currentItem["enclosureUrl"] = attributeDict["url"]
        case "itunes:image", "image":
            guard let href = attributeDict["href"] else { break }
            if inItem {
                currentItem["imageUrl"] = href
            } else if feedImageUrl == nil {
                feedImageUrl = href
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""
        if inItem {
            switch elementName {
            case "title": currentItem["title"] = text
            case "description", "itunes:summary": currentItem["description"] = currentItem["description"] ?? text.strippingHTML
            case "pubDate": currentItem["pubDate"] = text
            case "guid": currentItem["guid"] = text
            case "itunes:duration": currentItem["duration"] = text
            case "item":
                inItem = false
                items.append(currentItem)
            default: break
            }
        } else {
            switch elementName {
            case "title": feedTitle = feedTitle ?? (text.isEmpty ? nil : text)
            case "description": feedDescription = feedDescription ?? (text.isEmpty ? nil : text.strippingHTML)
            default: break
            }
        }
    }

    private func parseDuration(_ text: String) -> Double? {
        if let seconds = Double(text) { return seconds }
        let parts = text.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    private func makeEpisode(from dict: [String: String], index: Int, feedURL: String, podcastTitle: String) -> Episode {
        let id = dict["guid"].flatMap { $0.isEmpty ? nil : $0 }
            ?? dict["enclosureUrl"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(feedURL)#\(index)"

        var publishDatetime: String?
        if let pubDateText = dict["pubDate"], let date = Self.rfc822Formatter.date(from: pubDateText) {
            publishDatetime = ISO8601DateFormatter().string(from: date)
        }

        var episodeDict: [String: Any] = [
            "id": id,
            "podcastId": feedURL,
            "podcastName": podcastTitle,
            "title": dict["title"] ?? "Untitled Episode",
            "description": dict["description"] as Any,
            "publishDatetime": publishDatetime as Any,
            "imageUrl": dict["imageUrl"] as Any,
            "hasVideo": false,
            "isMarkedAsPlayed": false
        ]
        if let durationText = dict["duration"], let duration = parseDuration(durationText) {
            episodeDict["duration"] = duration
        }
        if let enclosureUrl = dict["enclosureUrl"] {
            episodeDict["externalAudioURL"] = enclosureUrl
        }
        // swiftlint:disable:next force_unwrap — "id" and "title" are always present above.
        return Episode(dict: episodeDict)!
    }
}
