import SwiftUI

struct RemoteArtwork: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient.podimoBrand)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                } else {
                    Image(systemName: "waveform")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
