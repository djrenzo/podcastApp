import SwiftUI

struct RemoteArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient.podimoBrand)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    // .id(url) forces a fresh AsyncImage (and thus a retry) if a prior
                    // attempt for this exact URL failed — otherwise a one-off network
                    // hiccup leaves it permanently blank until the view is torn down
                    // and rebuilt (e.g. an app relaunch), since nothing else prompts
                    // AsyncImage to try again.
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .failure:
                            Image(systemName: "waveform")
                                .foregroundStyle(.white.opacity(0.7))
                        @unknown default:
                            Image(systemName: "waveform")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .id(url)
                } else {
                    Image(systemName: "waveform")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
