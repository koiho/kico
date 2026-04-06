import SwiftUI
import UIKit

struct DiskImageView<Placeholder: View>: View {
    let url: URL
    let maxPixelSize: CGFloat?
    let contentMode: ContentMode
    private let placeholder: Placeholder

    @State private var image: UIImage?

    init(
        url: URL,
        maxPixelSize: CGFloat? = nil,
        contentMode: ContentMode = .fit,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url.path) {
            await loadImage()
        }
        .onDisappear {
            image = nil
        }
    }

    @MainActor
    private func loadImage() async {
        let url = self.url
        let maxPixelSize = self.maxPixelSize
        let loadedImage = await Task.detached(priority: .userInitiated) {
            if let maxPixelSize {
                return StoredPhotoImageLoader.downsampledImage(at: url, maxPixelSize: maxPixelSize)
            }
            return StoredPhotoImageLoader.image(at: url)
        }.value
        image = loadedImage
    }
}
