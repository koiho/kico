import Foundation
import Security

struct KeychainStore {
    private let service: String

    nonisolated init(service: String = "app.monuo.kico") {
        self.service = service
    }

    nonisolated func save(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainStoreError.osStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.osStatus(addStatus)
        }
    }

    nonisolated func load(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.osStatus(status)
        }

        guard let data = item as? Data else {
            throw KeychainStoreError.invalidData
        }

        return data
    }

    nonisolated func delete(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.osStatus(status)
        }
    }
}

enum KeychainStoreError: LocalizedError {
    case invalidData
    case osStatus(OSStatus)
    case encodingError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Keychain 数据格式无效"
        case .osStatus(let status):
            return "Keychain 操作失败：\(status)"
        case .encodingError(let error):
            return "数据编码失败：\(error.localizedDescription)"
        case .decodingError(let error):
            return "数据解码失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - Codable Convenience Methods

extension KeychainStore {
    /// Saves a Codable object to Keychain
    /// - Parameters:
    ///   - object: The Codable object to save
    ///   - key: The key to store the object under
    /// - Throws: KeychainStoreError if encoding or saving fails
    func save<T: Codable>(_ object: T, for key: String) throws {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(object)
            try save(data, for: key)
        } catch {
            throw KeychainStoreError.encodingError(error)
        }
    }

    /// Loads a Codable object from Keychain
    /// - Parameters:
    ///   - type: The type of the Codable object to load
    ///   - key: The key to load the object from
    /// - Returns: The decoded object, or nil if not found
    /// - Throws: KeychainStoreError if decoding fails (other than not found)
    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try load(for: key) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(type, from: data)
        } catch {
            throw KeychainStoreError.decodingError(error)
        }
    }

    /// Updates a Codable object in Keychain
    /// - Parameters:
    ///   - object: The Codable object to update
    ///   - key: The key to update the object under
    /// - Throws: KeychainStoreError if encoding or saving fails
    func update<T: Codable>(_ object: T, for key: String) throws {
        try save(object, for: key)
    }
}
