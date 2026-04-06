import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct SavedPhotoArtifact: Sendable {
    let item: PhotoItem
    let thumbnailData: Data
}

enum PhotoLibraryStoreError: LocalizedError {
    case directoryCreationFailed(String)
    case imageEncodingFailed
    case thumbnailEncodingFailed
    case indexLoadFailed
    case indexSaveFailed

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "创建照片目录失败: \(path)"
        case .imageEncodingFailed:
            return "成片编码失败"
        case .thumbnailEncodingFailed:
            return "缩略图编码失败"
        case .indexLoadFailed:
            return "照片索引读取失败"
        case .indexSaveFailed:
            return "照片索引写入失败"
        }
    }
}

actor PhotoLibraryStore {
    nonisolated(unsafe) private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedPhotos: [PhotoItem] = []
    private var hasLoadedIndex = false
    private var directoriesPrepared = false

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadPhotos() throws -> [PhotoItem] {
        try ensureDirectories()

        if hasLoadedIndex {
            return cachedPhotos
        }

        let indexURL = Self.indexURL()
        guard fileManager.fileExists(atPath: indexURL.path) else {
            cachedPhotos = []
            hasLoadedIndex = true
            return []
        }

        guard let data = try? Data(contentsOf: indexURL) else {
            throw PhotoLibraryStoreError.indexLoadFailed
        }

        let items = try decoder.decode([PhotoItem].self, from: data).sorted { $0.date > $1.date }
        cachedPhotos = items
        hasLoadedIndex = true
        return items
    }

    func savePhoto(_ image: UIImage, title: String = "无题", date: Date = Date()) throws -> SavedPhotoArtifact {
        try ensureDirectories()

        let normalizedImage = normalizeOrientation(of: image)
        let thumbnail = makeThumbnail(from: normalizedImage, maxDimension: 320)

        let encodedImage = try encodePrimaryImage(normalizedImage)

        guard let thumbnailData = thumbnail.jpegData(compressionQuality: 0.82) else {
            throw PhotoLibraryStoreError.thumbnailEncodingFailed
        }

        let id = UUID().uuidString.lowercased()
        let imageFileName = "\(id).\(encodedImage.fileExtension)"
        let thumbnailFileName = "\(id)_thumb.jpg"

        try encodedImage.data.write(to: Self.imageURL(for: imageFileName), options: .atomic)
        try thumbnailData.write(to: Self.thumbnailURL(for: thumbnailFileName), options: .atomic)

        let _ = try loadPhotos()
        let item = PhotoItem(
            id: id,
            title: title,
            date: date,
            imageFileName: imageFileName,
            thumbnailFileName: thumbnailFileName
        )
        cachedPhotos.removeAll { $0.id == item.id }
        cachedPhotos.insert(item, at: 0)

        guard let indexData = try? encoder.encode(cachedPhotos) else {
            throw PhotoLibraryStoreError.indexSaveFailed
        }

        do {
            try indexData.write(to: Self.indexURL(), options: .atomic)
        } catch {
            throw PhotoLibraryStoreError.indexSaveFailed
        }

        return SavedPhotoArtifact(item: item, thumbnailData: thumbnailData)
    }

    nonisolated static func imageURL(for fileName: String) -> URL {
        originalsDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    nonisolated static func thumbnailURL(for fileName: String) -> URL {
        thumbnailsDirectoryURL().appendingPathComponent(fileName, isDirectory: false)
    }

    private func ensureDirectories() throws {
        if directoriesPrepared {
            return
        }

        for directory in [Self.libraryRootURL(), Self.originalsDirectoryURL(), Self.thumbnailsDirectoryURL()] {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw PhotoLibraryStoreError.directoryCreationFailed(directory.path)
            }
        }
        directoriesPrepared = true
    }

    private nonisolated static func libraryRootURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL.appendingPathComponent("PhotoLibrary", isDirectory: true)
    }

    private nonisolated static func originalsDirectoryURL() -> URL {
        libraryRootURL().appendingPathComponent("originals", isDirectory: true)
    }

    private nonisolated static func thumbnailsDirectoryURL() -> URL {
        libraryRootURL().appendingPathComponent("thumbnails", isDirectory: true)
    }

    private nonisolated static func indexURL() -> URL {
        libraryRootURL().appendingPathComponent("index.json", isDirectory: false)
    }

    private func normalizeOrientation(of image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private func makeThumbnail(from image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > maxDimension else {
            return image
        }

        let scale = maxDimension / longestEdge
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func encodePrimaryImage(_ image: UIImage) throws -> (data: Data, fileExtension: String) {
        if let heicData = heicData(for: image, compressionQuality: 0.86) {
            return (heicData, "heic")
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.92) else {
            throw PhotoLibraryStoreError.imageEncodingFailed
        }

        return (jpegData, "jpg")
    }

    private func heicData(for image: UIImage, compressionQuality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.heic.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}

enum StoredPhotoImageLoader {
    static func image(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded()))
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
