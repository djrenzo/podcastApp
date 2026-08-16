import Foundation

struct EpisodeProgress: Equatable {
    var progress: Double?
    var listenTime: Double?
}

struct AudiobookChapter: Identifiable, Equatable, Hashable, Codable {
    let sequence: Int
    let title: String
    let duration: Double
    let startTimestampInSeconds: Double

    var id: Int { sequence }
    var endTimestampInSeconds: Double { startTimestampInSeconds + duration }

    init?(dict: [String: Any]) {
        guard let sequence = dict["sequence"] as? Int,
              let title = dict["title"] as? String,
              let duration = dict["duration"] as? Double,
              let start = dict["startTimestampInSeconds"] as? Double else { return nil }
        self.sequence = sequence
        self.title = title
        self.duration = duration
        self.startTimestampInSeconds = start
    }
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
    var chapters: [AudiobookChapter] = []
    /// Audiobooks are represented as an Episode too (podcastName doubles as
    /// the author string); this distinguishes how playback UI should label them.
    var isAudiobook = false

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

    /// Where playback should resume, or nil if there's nothing worth resuming
    /// (barely started, or already finished).
    var resumeTime: Double? {
        guard let listenTime = userProgress?.listenTime, listenTime > 5 else { return nil }
        if let progress = userProgress?.progress, progress >= 0.95 { return nil }
        if let duration, duration > 0, listenTime / duration >= 0.95 { return nil }
        return listenTime
    }

    func chapter(at time: Double) -> AudiobookChapter? {
        chapters.last { $0.startTimestampInSeconds <= time }
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

/// Lightweight navigation target: enough to push an AudiobookDetailView and show
/// something immediately, whether the tap came from the library grid or a
/// "You might also like" tile (which carry different, smaller fragments).
struct AudiobookLink: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let imageUrl: String?
}

struct AudiobookUserProgress: Equatable {
    var listenTime: Double?
    var lastListenDatetime: String?
}

struct AudiobookRatingSummary: Equatable {
    var totalVoteCount: Double
    var upVoteCount: Double

    var likedPercentage: Int? {
        guard totalVoteCount > 0 else { return nil }
        return Int((upVoteCount / totalVoteCount * 100).rounded())
    }
}

struct AudiobookDetail: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let authorNames: [String]
    let narratorNames: [String]
    let publisherName: String?
    let yearOfBookPublication: String?
    let language: String?
    let isAddedToLibrary: Bool
    let userProgress: AudiobookUserProgress?
    let rating: AudiobookRatingSummary?
    let imageUrl: String?
    let duration: Double?
    let audioUrl: String?
    let hlsUrl: String?
    let isAvailableForStreaming: Bool

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.description = dict["description"] as? String
        self.authorNames = dict["authorNames"] as? [String] ?? []
        self.narratorNames = dict["narratorNames"] as? [String] ?? []
        self.publisherName = dict["publisherName"] as? String
        self.yearOfBookPublication = dict["yearOfBookPublication"] as? String
        self.language = (dict["language"] as? [String: Any])?["localisedLanguage"] as? String

        let userState = dict["userState"] as? [String: Any]
        self.isAddedToLibrary = userState?["isAddedToLibrary"] as? Bool ?? false
        if let progressDict = userState?["userProgress"] as? [String: Any] {
            self.userProgress = AudiobookUserProgress(
                listenTime: progressDict["listenTime"] as? Double,
                lastListenDatetime: progressDict["lastListenDatetime"] as? String
            )
        } else {
            self.userProgress = nil
        }

        if let ratingDict = dict["rating"] as? [String: Any],
           let total = ratingDict["totalVoteCount"] as? Double,
           let up = ratingDict["upVoteCount"] as? Double {
            self.rating = AudiobookRatingSummary(totalVoteCount: total, upVoteCount: up)
        } else {
            self.rating = nil
        }

        self.imageUrl = (dict["coverImage"] as? [String: Any])?["url"] as? String

        let audio = dict["audio"] as? [String: Any]
        self.duration = audio?["duration"] as? Double
        self.audioUrl = audio?["url"] as? String
        self.hlsUrl = audio?["hlsUrl"] as? String

        self.isAvailableForStreaming = (dict["streamMeta"] as? [String: Any])?["isAvailableForStreaming"] as? Bool ?? true
    }

    var playableURLString: String? {
        hlsUrl ?? audioUrl
    }
}

struct AudiobookSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let authorNames: [String]
    let imageUrl: String?

    init?(dict: [String: Any]) {
        guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.description = dict["description"] as? String
        self.authorNames = dict["authorNames"] as? [String] ?? []
        self.imageUrl = (dict["coverImage"] as? [String: Any])?["url"] as? String
    }
}
