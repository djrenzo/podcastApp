import Foundation
import AVFoundation
import Observation
import UserNotifications
import UIKit

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

/// Enough metadata to finish processing a download — build a DownloadRecord,
/// post a notification — even if the app process was fully terminated and
/// relaunched by iOS specifically to deliver a background session completion
/// event. In-memory-only state (what this used to rely on) doesn't survive
/// that; this gets persisted instead. Keyed by URLSessionTask.taskIdentifier,
/// which background sessions keep stable across relaunches for the same
/// in-flight transfer.
private struct PendingDownload: Codable {
    var episodeId: String
    var podcastId: String
    var title: String
    var podcastName: String
    var imageUrl: String?
    var isVideo: Bool
    var isAudiobook: Bool
    var chapters: [AudiobookChapter]

    init(episode: Episode) {
        episodeId = episode.id
        podcastId = episode.podcastId
        title = episode.title
        podcastName = episode.podcastName
        imageUrl = episode.imageUrl
        isVideo = episode.hasVideo
        isAudiobook = episode.isAudiobook
        chapters = episode.chapters
    }

    var asEpisode: Episode? {
        guard var episode = Episode(dict: [
            "id": episodeId,
            "podcastId": podcastId,
            "podcastName": podcastName,
            "title": title,
            "imageUrl": imageUrl as Any,
            "hasVideo": isVideo
        ]) else { return nil }
        episode.chapters = chapters
        episode.isAudiobook = isAudiobook
        return episode
    }
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
    private let pendingKey = "podimo_pending_downloads"

    // Both real background sessions now — a .default session's tasks get
    // suspended/cancelled once the app backgrounds, which was silently
    // breaking every plain (mp3/mp4) episode download the moment the app
    // left the foreground or the phone locked.
    @ObservationIgnored private lazy var plainSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.superapp.podimoplayer.plaindownload")
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    @ObservationIgnored private lazy var assetSession: AVAssetDownloadURLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.superapp.podimoplayer.hlsdownload")
        config.sessionSendsLaunchEvents = true
        return AVAssetDownloadURLSession(configuration: config, assetDownloadDelegate: self, delegateQueue: .main)
    }()

    @ObservationIgnored private var pendingDownloads: [Int: PendingDownload] = [:]

    private override init() {
        super.init()
        loadRecords()
        loadPending()
        UNUserNotificationCenter.current().delegate = self
        // Merely creating a session with the same background identifier
        // re-attaches it to whatever OS-managed transfers were already
        // running — this is what lets a relaunch pick back up.
        _ = plainSession
        _ = assetSession
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
        requestNotificationPermissionIfNeeded()
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

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyDownloadComplete(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = title
        content.sound = .default
        let request = UNNotificationRequest(identifier: "download-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: Plain file download (mp3 / mp4)

    private func startPlainDownload(episode: Episode, url: URL) {
        let task = plainSession.downloadTask(with: url)
        pendingDownloads[task.taskIdentifier] = PendingDownload(episode: episode)
        persistPending()
        task.resume()
    }

    // MARK: HLS asset download

    private func startHLSDownload(episode: Episode, url: URL) {
        let asset = AVURLAsset(url: url)
        guard let task = assetSession.makeAssetDownloadTask(asset: asset, assetTitle: episode.title, assetArtworkData: nil) else {
            states[episode.id] = .failed("Unable to start HLS download")
            return
        }
        pendingDownloads[task.taskIdentifier] = PendingDownload(episode: episode)
        persistPending()
        task.resume()
    }

    @MainActor
    private func finishDownload(taskIdentifier: Int, pending: PendingDownload, localPath: String) {
        let record = DownloadRecord(
            episodeId: pending.episodeId,
            podcastId: pending.podcastId,
            title: pending.title,
            podcastName: pending.podcastName,
            imageUrl: pending.imageUrl,
            isVideo: pending.isVideo,
            localPath: localPath,
            isAudiobook: pending.isAudiobook,
            chapters: pending.chapters
        )
        records.removeAll { $0.episodeId == pending.episodeId }
        records.append(record)
        states[pending.episodeId] = .completed
        downloadingEpisodes[pending.episodeId] = nil
        pendingDownloads[taskIdentifier] = nil
        persistRecords()
        persistPending()
        notifyDownloadComplete(title: pending.title)
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

    private func persistPending() {
        if let data = try? JSONEncoder().encode(pendingDownloads) {
            UserDefaults.standard.set(data, forKey: pendingKey)
        }
    }

    private func loadPending() {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let decoded = try? JSONDecoder().decode([Int: PendingDownload].self, from: data) else { return }
        pendingDownloads = decoded
        // Restores the "Downloading" section in the Downloads tab across a
        // fresh launch, for transfers that are still genuinely in progress
        // at the OS level even though this process only just started.
        for pending in decoded.values {
            if let episode = pending.asEpisode {
                downloadingEpisodes[pending.episodeId] = episode
            }
            states[pending.episodeId] = .downloading(0)
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let pending = pendingDownloads[downloadTask.taskIdentifier], totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.states[pending.episodeId] = .downloading(min(max(fraction, 0), 1))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let pending = pendingDownloads[downloadTask.taskIdentifier] else { return }
        // The file at `location` is deleted the moment this method returns,
        // so it has to be moved out synchronously here rather than off to a
        // later async hop.
        let urlExt = downloadTask.originalRequest?.url?.pathExtension ?? ""
        let ext = urlExt.isEmpty ? (pending.isVideo ? "mp4" : "mp3") : urlExt
        let destination = documentsDownloadsDirectory().appendingPathComponent("\(pending.episodeId).\(ext)")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            let taskId = downloadTask.taskIdentifier
            let path = destination.path
            Task { @MainActor in
                self.finishDownload(taskIdentifier: taskId, pending: pending, localPath: path)
            }
        } catch {
            let taskId = downloadTask.taskIdentifier
            let episodeId = pending.episodeId
            let message = error.localizedDescription
            Task { @MainActor in
                self.states[episodeId] = .failed(message)
                self.pendingDownloads[taskId] = nil
                self.persistPending()
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        Task { @MainActor in
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
                  let handler = appDelegate.backgroundSessionCompletionHandlers[identifier] else { return }
            appDelegate.backgroundSessionCompletionHandlers[identifier] = nil
            handler()
        }
    }
}

extension DownloadManager: AVAssetDownloadDelegate {
    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue], timeRangeExpectedToLoad: CMTimeRange) {
        guard let pending = pendingDownloads[assetDownloadTask.taskIdentifier] else { return }
        var loaded: Double = 0
        for value in loadedTimeRanges {
            loaded += value.timeRangeValue.duration.seconds
        }
        let total = timeRangeExpectedToLoad.duration.seconds
        let fraction = total > 0 ? loaded / total : 0
        Task { @MainActor in
            self.states[pending.episodeId] = .downloading(min(max(fraction, 0), 1))
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let pending = pendingDownloads[assetDownloadTask.taskIdentifier] else { return }
        let taskId = assetDownloadTask.taskIdentifier
        let path = location.path
        Task { @MainActor in
            self.finishDownload(taskIdentifier: taskId, pending: pending, localPath: path)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let pending = pendingDownloads[task.taskIdentifier] else { return }
        let taskId = task.taskIdentifier
        let episodeId = pending.episodeId
        let message = error.localizedDescription
        Task { @MainActor in
            // If it already succeeded, didFinishDownloadingTo already cleared
            // this entry — this is just the normal benign callback that
            // follows a success, not a real failure.
            guard self.pendingDownloads[taskId] != nil else { return }
            self.states[episodeId] = .failed(message)
            self.pendingDownloads[taskId] = nil
            self.persistPending()
        }
    }
}

extension DownloadManager: UNUserNotificationCenterDelegate {
    // Without this, a completion notification silently does nothing if the
    // app happens to be in the foreground when the download finishes (e.g.
    // the user is sitting on the Downloads tab watching the progress bar).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
