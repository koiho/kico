import Foundation

/// Stores user profile information using Keychain
final class UserInfoStore: Sendable {
    private let keychainStore: KeychainStore
    private let userInfoKey = "authn.userinfo"

    nonisolated init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    /// Saves user info to Keychain
    /// - Parameter userInfo: The user info to save
    /// - Throws: KeychainStoreError if saving fails
    func saveUserInfo(_ userInfo: UserInfo) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(userInfo)
        try keychainStore.save(data, for: userInfoKey)
    }

    /// Loads user info from Keychain
    /// - Returns: The stored user info, or nil if not found
    /// - Throws: KeychainStoreError if loading fails (other than not found)
    func loadUserInfo() throws -> UserInfo? {
        guard let data = try keychainStore.load(for: userInfoKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(UserInfo.self, from: data)
    }

    /// Deletes user info from Keychain
    /// - Throws: KeychainStoreError if deletion fails
    func deleteUserInfo() throws {
        try keychainStore.delete(for: userInfoKey)
    }

    /// Updates user info with new data
    /// - Parameter userInfo: The new user info to save
    /// - Throws: KeychainStoreError if update fails
    func updateUserInfo(_ userInfo: UserInfo) throws {
        try saveUserInfo(userInfo)
    }
}
