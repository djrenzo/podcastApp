import SwiftUI
import CryptoKit
import ImageIO

// NSCache is documented by Apple as thread-safe for concurrent access, so this
// is safe despite not being provably Sendable to the compiler.
private nonisolated(unsafe) let artworkResultCache = NSCache<NSString, UIImage>()
private nonisolated(unsafe) let artworkContentCache = NSCache<NSString, UIImage>()

/// Loads, downsamples, and caches remote artwork so scrolling long episode
/// lists doesn't decode dozens of full-resolution images at once — and so
/// the same artwork (whether re-requested via the same URL, or a different
/// URL that happens to point at identical bytes, which podcasts commonly do
/// when episodes fall back to the show's own artwork) is only downloaded and
/// decoded once.
///
/// A plain class (rather than an actor) so `load(urlString:pixelSize:)` isn't
/// actor-isolated — an actor here would require UIImage (not Sendable) to
/// cross an isolation boundary on every call, which Swift 6 rejects at
/// compile time. `inFlight` is the only mutable state, guarded by a lock
/// instead.
private final class ArtworkLoader: @unchecked Sendable {
    static let shared = ArtworkLoader()

    private let lock = NSLock()
    /// De-dupes concurrent requests for the same cache key (e.g. many rows
    /// scrolling into view at once, all wanting the same not-yet-cached URL).
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func load(urlString: String, pixelSize: CGFloat?) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        let cacheKey = "\(urlString)|\(pixelSize.map { Int($0) } ?? 0)"

        if let cached = artworkResultCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        lock.lock()
        if let existing = inFlight[cacheKey] {
            lock.unlock()
            return await existing.value
        }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }

            let contentKey = "\(Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined())|\(pixelSize.map { Int($0) } ?? 0)" as NSString
            if let reused = artworkContentCache.object(forKey: contentKey) {
                artworkResultCache.setObject(reused, forKey: cacheKey as NSString)
                return reused
            }

            let image: UIImage?
            if let pixelSize {
                image = Self.downsample(data: data, toMaxPixelSize: pixelSize)
            } else {
                image = UIImage(data: data)
            }
            guard let image else { return nil }
            artworkResultCache.setObject(image, forKey: cacheKey as NSString)
            artworkContentCache.setObject(image, forKey: contentKey)
            return image
        }
        inFlight[cacheKey] = task
        lock.unlock()

        let result = await task.value
        lock.lock()
        inFlight[cacheKey] = nil
        lock.unlock()
        return result
    }

    /// Decodes directly at (approximately) the size it'll be displayed at,
    /// instead of decoding the source image at full resolution and letting
    /// SwiftUI scale it down every frame.
    private static func downsample(data: Data, toMaxPixelSize maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }
}

struct RemoteArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    /// The largest point size this artwork will actually be displayed at, if
    /// known — enables downsampled decoding. Leave nil for one-off, large
    /// displays (e.g. Now Playing) where decoding at full size is fine.
    var targetSize: CGFloat? = nil

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient.podimoBrand)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "waveform")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // Hand-rolled instead of AsyncImage: AsyncImage never retries a
            // failed load, and rows inside a LazyVStack (like Keep Listening)
            // only materialize their view body as they scroll near the
            // viewport — a one-off failure there just stays blank forever
            // with no further prompt to try again. .task(id:) reruns
            // whenever urlString changes *and* whenever this view reappears
            // (including a lazy row being recycled back into view), which
            // gives it a real retry path.
            .task(id: urlString) {
                guard let urlString else {
                    image = nil
                    return
                }
                let pixelSize = targetSize.map { $0 * displayScale }
                let loaded = await ArtworkLoader.shared.load(urlString: urlString, pixelSize: pixelSize)
                guard urlString == self.urlString else { return }
                image = loaded
            }
    }
}
