import Foundation

enum HLSVariantResolver {
    struct VariantSet {
        var videoURL: URL?
        var audioURL: URL?
    }

    /// Fetches an HLS master playlist and picks out the "medium" video and
    /// audio-only renditions (e.g. `stream_video_medium/`, `stream_audio_medium/`),
    /// resolving their relative URIs (with their own signed query params) against
    /// the master playlist's URL.
    static func resolveVariants(masterURL: URL) async throws -> VariantSet {
        let (data, _) = try await URLSession.shared.data(from: masterURL)
        guard let text = String(data: data, encoding: .utf8) else { throw PodimoError.badResponse }

        var videoURL: URL?
        var audioURL: URL?

        let lines = text.components(separatedBy: .newlines)
        var index = 0
        while index < lines.count {
            guard lines[index].hasPrefix("#EXT-X-STREAM-INF") else {
                index += 1
                continue
            }
            var uriIndex = index + 1
            while uriIndex < lines.count && lines[uriIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                uriIndex += 1
            }
            defer { index = uriIndex + 1 }
            guard uriIndex < lines.count else { continue }
            let uri = lines[uriIndex].trimmingCharacters(in: .whitespaces)
            guard let resolved = URL(string: uri, relativeTo: masterURL)?.absoluteURL else { continue }
            if uri.contains("stream_video_medium") {
                videoURL = resolved
            } else if uri.contains("stream_audio_medium") {
                audioURL = resolved
            }
        }

        return VariantSet(videoURL: videoURL, audioURL: audioURL)
    }
}
