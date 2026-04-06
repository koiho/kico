import Foundation
import UIKit

/// Disk-based image cache with automatic size management
final class DiskImageCache: Sendable {
    nonisolated(unsafe) private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxSize: UInt64

    /// Thread-safe cache size tracking
    private actor CacheSizeTracker {
        private var currentSize: UInt64 = 0

        func add(_ size: UInt64) {
            currentSize += size
        }

        func subtract(_ size: UInt64) {
            currentSize = max(0, currentSize - size)
        }

        func get() -> UInt64 {
            return currentSize
        }

        func set(_ size: UInt64) {
            currentSize = size
        }
    }

    private let sizeTracker = CacheSizeTracker()

    /// Initializes the disk cache
    /// - Parameters:
    ///   - directory: Cache directory URL (defaults to app's cache directory)
    ///   - maxSize: Maximum cache size in bytes (default: 50MB)
    nonisolated init(directory: URL? = nil, maxSize: UInt64 = 50 * 1024 * 1024) {
        self.maxSize = maxSize

        if let directory = directory {
            self.cacheDirectory = directory
        } else {
            let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.cacheDirectory = cachesDirectory.appendingPathComponent("AvatarCache", isDirectory: true)
        }

        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Initialize size tracker
        Task {
            await sizeTracker.set(calculateCurrentSize())
        }
    }

    /// Retrieves an image from disk cache
    /// - Parameter key: Cache key (typically SHA256 hash of URL)
    /// - Returns: The cached UIImage, or nil if not found
    func getImage(for key: String) throws -> UIImage? {
        let fileURL = cacheDirectory.appendingPathComponent(key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw DiskImageCacheError.readFailed(fileURL.path)
        }

        guard let image = UIImage(data: imageData) else {
            throw DiskImageCacheError.invalidImageData
        }

        return image
    }

    /// Saves an image to disk cache
    /// - Parameters:
    ///   - image: The UIImage to save
    ///   - key: Cache key
    /// - Throws: DiskImageCacheError if saving fails
    func setImage(_ image: UIImage, for key: String) async throws {
        let fileURL = cacheDirectory.appendingPathComponent(key)

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw DiskImageCacheError.encodingFailed
        }

        let imageSize = UInt64(imageData.count)

        // Check if we need to trim cache before adding
        let currentSize = await sizeTracker.get()
        if currentSize + imageSize > maxSize {
            try await trim(toSize: maxSize - imageSize)
        }

        // Write the file
        do {
            try imageData.write(to: fileURL)
            await sizeTracker.add(imageSize)
        } catch {
            throw DiskImageCacheError.writeFailed(fileURL.path)
        }
    }

    /// Removes an image from disk cache
    /// - Parameter key: Cache key
    /// - Throws: DiskImageCacheError if deletion fails
    func removeImage(for key: String) async throws {
        let fileURL = cacheDirectory.appendingPathComponent(key)

        if fileManager.fileExists(atPath: fileURL.path) {
            let fileSize = getFileSize(at: fileURL)

            try fileManager.removeItem(at: fileURL)
            await sizeTracker.subtract(fileSize)
        }
    }

    /// Removes all images from disk cache
    /// - Throws: DiskImageCacheError if clearing fails
    func removeAllImages() async throws {
        let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)

        for file in files {
            try fileManager.removeItem(at: file)
        }

        await sizeTracker.set(0)
    }

    /// Trims cache to specified size by removing oldest files
    /// - Parameter targetSize: Target cache size in bytes
    /// - Throws: DiskImageCacheError if trimming fails
    func trim(toSize targetSize: UInt64) async throws {
        let files = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )

        // Sort files by modification date (oldest first)
        let sortedFiles = files.sorted { file1, file2 in
            guard let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return false
            }
            return date1 < date2
        }

        var currentSize = await sizeTracker.get()

        for file in sortedFiles {
            if currentSize <= targetSize {
                break
            }

            let fileSize = getFileSize(at: file)
            try fileManager.removeItem(at: file)
            await sizeTracker.subtract(fileSize)
            currentSize = await sizeTracker.get()
        }
    }

    /// Returns the current cache size in bytes
    /// - Returns: Current cache size
    func getCurrentSize() async -> UInt64 {
        return await sizeTracker.get()
    }

    // MARK: - Private Methods

    private func calculateCurrentSize() -> UInt64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return files.reduce(0) { total, file in
            let size = getFileSize(at: file)
            return total + size
        }
    }

    private func getFileSize(at url: URL) -> UInt64 {
        guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = resourceValues.fileSize else {
            return 0
        }
        return UInt64(fileSize)
    }
}

// MARK: - Disk Image Cache Error

enum DiskImageCacheError: LocalizedError {
    case readFailed(String)
    case writeFailed(String)
    case invalidImageData
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .readFailed(let path):
            return "读取缓存图片失败: \(path)"
        case .writeFailed(let path):
            return "写入缓存图片失败: \(path)"
        case .invalidImageData:
            return "无效的图片数据"
        case .encodingFailed:
            return "图片编码失败"
        }
    }
}
