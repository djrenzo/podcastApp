import Foundation
import AVFoundation
import Observation

struct DownloadRecord: Codable, Identifiable, Equatable {
    var episodeId: String
    var podcastId: String
    var title: String
    var podcastName: String
    var imageUrl: String?
    var isVideo: Bool
    var localPath: String
    var isAudiobook = false
    var chapters: [AudiobookChapter] = []

    var id: String { episodeId }
}

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(Double)
    case completed
    case failed(String)
}

@Observable
final class DownloadManager: NSObject, @unchecked Sendable {
    static let shared = DownloadManager()

    private(set) var states: [String: DownloadState] = [:]
    private(set) var records: [DownloadRecord] = []
    /// Metadata for downloads that are currently in flight (or just failed),
    /// keyed by episode id — `states`/`records` alone don't carry enough to
    /// render a row (title, artwork, ...) for something not finished yet.
    private(set) var downloadingEpisodes: [String: Episode] = [:]

    private let recordsKey = "podimo_downloads"
    @ObservationIgnored private let plainSession = URLSession(configuration: .default)
    @ObservationIgnored private lazy var assetSession: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.superapp.podimoplayer.hlsdownload")
        return AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }()

    @ObservationIgnored private var progressObservers: [String: NSKeyValueObservation] = [:]
    @ObservationIgnored private var assetTaskEpisodes: [Int: (Episode, Bool)] = [:]

    private override init() {
        super.init()
        loadRecords()
    }

    func record(for episodeId: String) -> DownloadRecord? {
        records.first { $0.episodeId == episodeId }
    }

    func state(for episodeId: String) -> DownloadState {
        if record(for: episodeId) != nil { return .completed }
        return states[episodeId] ?? .notDownloaded
    }

    func startDownload(episode: Episode, mediaURLString: String) {
        guard let url = URL(string: mediaURLString) else { return }
        let isHLS = url.pathExtension.lowercased() == "m3u8" || mediaURLString.contains(".m3u8")
        states[episode.id] = .downloading(0)
        downloadingEpisodes[episode.id] = episode
        if isHLS {
            startHLSDownload(episode: episode, url: url)
        } else {
            startPlainDownload(episode: episode, url: url)
        }
    }

    func deleteDownload(episodeId: String) {
        guard let record = record(for: episodeId) else { return }
        try? FileManager.default.removeItem(atPath: record.localPath)
        records.removeAll { $0.episodeId == episodeId }
        states[episodeId] = .notDownloaded
        downloadingEpisodes[episodeId] = nil
        persistRecords()
    }

    // MARK: Plain file download (mp3 / mp4)

    private func startPlainDownload(episode: Episode, url: URL) {
        let task = plainSession.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self else { return }
            Task { @MainActor in
                self.finishPlainDownload(episode: episode, url: url, tempURL: tempURL, error: error)
            }
        }
        progressObservers[episode.id] = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            Task { @MainActor in
                self?.states[episode.id] = .downloading(progress.fractionCompleted)
            }
        }
        task.resume()
    }

    @MainActor
    private func finishPlainDownload(episode: Episode, url: URL, tempURL: URL?, error: Error?) {
        progressObservers[episode.id] = nil
        guard let tempURL, error == nil else {
            states[episode.id] = .failed(error?.localizedDescription ?? "Download failed")
            return
        }
        do {
            let ext = url.pathExtension.isEmpty ? (episode.hasVideo ? "mp4" : "mp3") : url.pathExtension
            let destination = documentsDownloadsDirectory().appendingPathComponent("\(episode.id).\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let record = DownloadRecord(episodeId: episode.id, podcastId: episode.podcastId, title: episode.title, podcastName: episode.podcastName, imageUrl: episode.imageUrl, isVideo: episode.hasVideo, localPath: destination.path, isAudiobook: episode.isAudiobook, chapters: episode.chapters)
            records.removeAll { $0.episodeId == episode.id }
            records.append(record)
            states[episode.id] = .completed
            downloadingEpisodes[episode.id] = nil
            persistRecords()
        } catch {
            states[episode.id] = .failed(error.localizedDescription)
        }
    }

    // MARK: HLS asset download

    private func startHLSDownload(episode: Episode, url: URL) {
        let asset = AVURLAsset(url: url)
        guard let task = assetSession.makeAssetDownloadTask(asset: asset, assetTitle: episode.title, assetArtworkData: nil) else {
            states[episode.id] = .failed("Unable to start HLS download")
            return
        }
        assetTaskEpisodes[task.taskIdentifier] = (episode, true)
        task.resume()
    }

    private func documentsDownloadsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func persistRecords() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    private func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = decoded
        }
    }
}

extension DownloadManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let (episode, _) = assetTaskEpisodes[assetDownloadTask.taskIdentifier] else { return }
        var loaded: Double = 0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        let total = timeRangeExpectedToLoad.duration.seconds
        let fraction = total > 0 ? loaded / total : 0
        Task { @MainActor in
            self.states[episode.id] = .downloading(min(max(fraction, 0), 1))
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (episode, _) = assetTaskEpisodes[assetDownloadTask.taskIdentifier] else { return }
        Task { @MainActor in
            let record = DownloadRecord(episodeId: episode.id, podcastId: episode.podcastId, title: episode.title, podcastName: episode.podcastName, imageUrl: episode.imageUrl, isVideo: episode.hasVideo, localPath: location.path, isAudiobook: episode.isAudiobook, chapters: episode.chapters)
            self.records.removeAll { $0.episodeId == episode.id }
            self.records.append(record)
            self.states[episode.id] = .completed
            self.downloadingEpisodes[episode.id] = nil
            self.persistRecords()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (episode, _) = assetTaskEpisodes[task.taskIdentifier] else { return }
        assetTaskEpisodes[task.taskIdentifier] = nil
        guard let error else { return }
        Task { @MainActor in
            if self.record(for: episode.id) == nil {
                self.states[episode.id] = .failed(error.localizedDescription)
            }
        }
    }
}
