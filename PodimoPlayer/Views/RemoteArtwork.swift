import SwiftUI

// NSCache is documented by Apple as thread-safe for concurrent access, so this
// is safe despite not being provably Sendable to the compiler.
private nonisolated(unsafe) let artworkCache = NSCache<NSString, UIImage>()

struct RemoteArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

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
                await load()
            }
    }

    private func load() async {
        guard let urlString, let url = URL(string: urlString) else {
            image = nil
            return
        }
        let cacheKey = urlString as NSString
        if let cached = artworkCache.object(forKey: cacheKey) {
            image = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = UIImage(data: data) else {
            return
        }
        guard urlString == self.urlString else { return }
        artworkCache.setObject(loaded, forKey: cacheKey)
        image = loaded
    }
}
