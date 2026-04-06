import Foundation

struct PhotoItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    var title: String
    let date: Date
    let imageFileName: String
    let thumbnailFileName: String

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: date)
    }

    var imageURL: URL {
        PhotoLibraryStore.imageURL(for: imageFileName)
    }

    var thumbnailURL: URL {
        PhotoLibraryStore.thumbnailURL(for: thumbnailFileName)
    }
}

struct GalleryState {
    var photos: [PhotoItem] = []
    var selectedPhoto: PhotoItem?
    var isLoading = false
}
