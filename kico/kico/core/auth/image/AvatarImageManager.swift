import Combine
import CryptoKit
import Foundation
import UIKit

/// Manages avatar image loading with two-tier caching (memory + disk)
@MainActor
final class AvatarImageManager: ObservableObject {
    @Published private(set) var currentAvatar: UIImage?

    private let memoryCache = MemoryCache(maxCount: 20)
    private let diskCache: DiskImageCache
    private let urlSession: URLSession

    nonisolated init(diskCache: DiskImageCache = DiskImageCache()) {
        self.diskCache = diskCache

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        self.urlSession = URLSession(configuration: configuration)
    }

    /// Loads an avatar image from the given URI with automatic caching
    /// - Parameter uri: The avatar URI (URL string)
    /// - Returns: The loaded UIImage
    /// - Throws: AvatarImageError if loading fails
    func loadImage(from uri: String) async throws -> UIImage {
        guard !uri.isEmpty else {
            throw AvatarImageError.invalidURL
        }

        guard let url = URL(string: uri) else {
            throw AvatarImageError.invalidURL
        }

        let cacheKey = uri.sha256()

        // Check memory cache first
        if let cachedImage = memoryCache.get(cacheKey) {
            currentAvatar = cachedImage
            return cachedImage
        }

        // Check disk cache
        if let diskImage = try? diskCache.getImage(for: cacheKey) {
            memoryCache.set(diskImage, forKey: cacheKey)
            currentAvatar = diskImage
            return diskImage
        }

        // Download from network
        let image = try await downloadImage(from: url)

        // Save to caches
        try? await diskCache.setImage(image, for: cacheKey)
        memoryCache.set(image, forKey: cacheKey)
        currentAvatar = image

        return image
    }

    /// Preloads an avatar image without updating the currentAvatar property
    /// - Parameter uri: The avatar URI (URL string)
    func preloadImage(from uri: String) async {
        guard !uri.isEmpty, let url = URL(string: uri) else {
            return
        }

        let cacheKey = uri.sha256()

        // Skip if already in memory cache
        if memoryCache.get(cacheKey) != nil {
            return
        }

        // Check disk cache
        if let diskImage = try? diskCache.getImage(for: cacheKey) {
            memoryCache.set(diskImage, forKey: cacheKey)
            return
        }

        // Download in background
        do {
            let image = try await downloadImage(from: url)
            try? await diskCache.setImage(image, for: cacheKey)
            memoryCache.set(image, forKey: cacheKey)
        } catch {
            // Silent fail for preloading
        }
    }

    /// Clears all cached images (memory and disk)
    func clearCache() {
        memoryCache.removeAll()
        Task {
            try? await diskCache.removeAllImages()
        }
        currentAvatar = nil
    }

    // MARK: - Private Methods

    private func downloadImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AvatarImageError.httpError(httpResponse.statusCode)
        }

        guard let image = UIImage(data: data) else {
            throw AvatarImageError.invalidImageData
        }

        return image
    }
}

// MARK: - Memory Cache (LRU)

private final class MemoryCache: Sendable {
    private let maxCount: Int
    private final class CacheStorage: @unchecked Sendable {
        private var cache: [String: UIImage] = [:]
        private var accessOrder: [String] = []
        private let lock = NSLock()

        func get(_ key: String) -> UIImage? {
            lock.lock()
            defer { lock.unlock() }

            guard let image = cache[key] else {
                return nil
            }

            // Move to end (most recently used)
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)

            return image
        }

        func set(_ image: UIImage, forKey key: String, maxCount: Int) {
            lock.lock()
            defer { lock.unlock() }

            // Update access order
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)

            cache[key] = image

            // Evict least recently used if over capacity
            while cache.count > maxCount {
                let lruKey = accessOrder.removeFirst()
                cache.removeValue(forKey: lruKey)
            }
        }

        func remove(_ key: String) {
            lock.lock()
            defer { lock.unlock() }

            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }

        func removeAll() {
            lock.lock()
            defer { lock.unlock() }

            cache.removeAll()
            accessOrder.removeAll()
        }

        func getCount() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return cache.count
        }
    }

    private let storage = CacheStorage()

    init(maxCount: Int = 20) {
        self.maxCount = maxCount
    }

    func get(_ key: String) -> UIImage? {
        return storage.get(key)
    }

    func set(_ image: UIImage, forKey key: String) {
        storage.set(image, forKey: key, maxCount: maxCount)
    }

    func remove(_ key: String) {
        storage.remove(key)
    }

    func removeAll() {
        storage.removeAll()
    }
}

// MARK: - Avatar Image Error

enum AvatarImageError: LocalizedError {
    case invalidURL
    case downloadFailed(Error)
    case invalidResponse
    case httpError(Int)
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的头像地址"
        case .downloadFailed(let error):
            return "下载失败：\(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let code):
            return "HTTP 错误：\(code)"
        case .invalidImageData:
            return "无效的图片数据"
        }
    }
}

// MARK: - String SHA256 Extension

extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else {
            return self
        }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
