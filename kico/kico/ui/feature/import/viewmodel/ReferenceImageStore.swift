import Combine
import SwiftUI
import UIKit

struct ReferenceImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

@MainActor
final class ReferenceImageStore: ObservableObject {
    @Published private(set) var recentImages: [ReferenceImageItem] = []
    @Published private(set) var selectedImageID: ReferenceImageItem.ID?

    var selectedImage: UIImage? {
        recentImages.first(where: { $0.id == selectedImageID })?.image
    }

    func addImportedImage(_ image: UIImage) {
        let item = ReferenceImageItem(image: normalizeOrientation(of: image))
        recentImages.removeAll { existing in
            existing.image.pngData() == item.image.pngData()
        }
        recentImages.insert(item, at: 0)
        selectedImageID = item.id
    }

    func select(_ item: ReferenceImageItem) {
        selectedImageID = item.id
    }

    private func normalizeOrientation(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
