import Foundation

struct EpisodeProgress: Equatable {
    var progress: Double?
    var listenTime: Double?
}

struct Episode: Identifiable, Equatable {
    let id: String
    let podcastId: String
    let podcastName: String
    let title: String
    let description: String?
    let publishDatetime: String?
    let imageUrl: String?
    let duration: Double?
    let isMarkedAsPlayed: Bool
    let hasVideo: Bool
    var userProgress: EpisodeProgress?

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.podcastId = dict["podcastId"] as? String ?? ""
        self.podcastName = dict["podcastName"] as? String ?? ""
        self.description = dict["description"] as? String
        self.publishDatetime = dict["publishDatetime"] as? String
        self.duration = dict["duration"] as? Double
        self.isMarkedAsPlayed = dict["isMarkedAsPlayed"] as? Bool ?? false
        self.hasVideo = dict["hasVideo"] as? Bool ?? false
        if let direct = dict["imageUrl"] as? String {
            self.imageUrl = direct
        } else if let image = dict["image"] as? [String: Any] {
            self.imageUrl = image["url"] as? String
        } else {
            self.imageUrl = nil
        }
        if let progressDict = dict["userProgress"] as? [String: Any] {
            self.userProgress = EpisodeProgress(
                progress: progressDict["progress"] as? Double,
                listenTime: progressDict["listenTime"] as? Double
            )
        } else {
            self.userProgress = nil
        }
    }

    var publishedDate: Date? {
        guard let publishDatetime else { return nil }
        return ISO8601DateFormatter().date(from: publishDatetime)
    }

    var formattedDuration: String {
        guard let duration, duration > 0 else { return "" }
        let minutes = Int(duration) / 60
        return "\(minutes) min"
    }
}

struct Podcast: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let authorName: String?
    let description: String?
    let imageUrl: String?
    let hasVideo: Bool
    let followerCount: Int?
    let isFollowing: Bool?
    let newEpisodes: Int?

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.authorName = dict["authorName"] as? String
        self.description = dict["description"] as? String
        self.hasVideo = dict["hasVideo"] as? Bool ?? false
        self.followerCount = dict["followerCount"] as? Int
        if let images = dict["images"] as? [String: Any] {
            self.imageUrl = images["coverImageUrl"] as? String
        } else {
            self.imageUrl = nil
        }
        if let stats = dict["userStats"] as? [String: Any] {
            self.isFollowing = stats["isFollowing"] as? Bool
            self.newEpisodes = stats["newEpisodes"] as? Int
        } else {
            self.isFollowing = nil
            self.newEpisodes = nil
        }
    }
}

struct Audiobook: Identifiable, Equatable {
    let id: String
    let title: String
    let authors: [String]
    let description: String?
    let imageUrl: String?
    let duration: Double?
    let audioUrl: String?
    let hlsUrl: String?
    let isMarkedAsPlayed: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.description = dict["description"] as? String
        let authorsArray = dict["authors"] as? [[String: Any]] ?? []
        self.authors = authorsArray.compactMap { $0["name"] as? String }
        if let cover = dict["coverImage"] as? [String: Any] {
            self.imageUrl = cover["url"] as? String
        } else {
            self.imageUrl = nil
        }
        let audio = dict["audio"] as? [String: Any]
        self.duration = audio?["duration"] as? Double
        self.audioUrl = audio?["url"] as? String
        self.hlsUrl = audio?["hlsUrl"] as? String
        let userState = dict["userState"] as? [String: Any]
        self.isMarkedAsPlayed = userState?["isMarkedAsPlayed"] as? Bool ?? false
    }
}

enum LibraryEntry: Identifiable, Equatable {
    case podcast(Podcast)
    case audiobook(Audiobook)

    var id: String {
        switch self {
        case .podcast(let p): return "podcast_\(p.id)"
        case .audiobook(let a): return "audiobook_\(a.id)"
        }
    }
}
