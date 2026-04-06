import Foundation
import Combine

@MainActor
class GalleryViewModel: ObservableObject {
    @Published var state = GalleryState()

    func loadPhotos(_ photos: [PhotoItem]) {
        state.photos = photos
    }

    func selectPhoto(_ photo: PhotoItem) {
        state.selectedPhoto = photo
    }

    func updatePhotoTitle(_ photo: PhotoItem, title: String) {
        if let index = state.photos.firstIndex(where: { $0.id == photo.id }) {
            state.photos[index].title = title
        }
    }
}
