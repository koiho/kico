import Foundation

/// Securely stores authentication tokens using Keychain
final class SecureTokenStore: Sendable {
    private let keychainStore: KeychainStore
    private let tokenKey = "authn.tokens"

    nonisolated init(keychainStore: KeychainStore = KeychainStore()) {
        self.keychainStore = keychainStore
    }

    /// Saves token data to Keychain
    /// - Parameter tokenData: The token data to save
    /// - Throws: KeychainStoreError if saving fails
    nonisolated func saveTokens(_ tokenData: TokenData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(tokenData)
        try keychainStore.save(data, for: tokenKey)
    }

    /// Loads token data from Keychain
    /// - Returns: The stored token data, or nil if not found
    /// - Throws: KeychainStoreError if loading fails (other than not found)
    nonisolated func loadTokens() throws -> TokenData? {
        guard let data = try keychainStore.load(for: tokenKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try decoder.decode(TokenData.self, from: data)
    }

    /// Deletes token data from Keychain
    /// - Throws: KeychainStoreError if deletion fails
    nonisolated func deleteTokens() throws {
        try keychainStore.delete(for: tokenKey)
    }

    /// Checks if the stored access token is valid
    /// - Parameter buffer: Buffer time in seconds before expiry
    /// - Returns: true if the access token is still valid, false otherwise
    nonisolated func isAccessTokenValid(buffer: TimeInterval = 300) -> Bool {
        guard let tokenData = try? loadTokens() else {
            return false
        }
        return tokenData.isAccessTokenValid(buffer: buffer)
    }

    /// Checks if the access token needs to be refreshed
    /// - Parameter threshold: Threshold in seconds before expiry
    /// - Returns: true if the token should be refreshed, false otherwise
    nonisolated func needsRefresh(threshold: TimeInterval = 300) -> Bool {
        guard let tokenData = try? loadTokens() else {
            return false
        }
        return tokenData.needsRefresh(threshold: threshold)
    }

    /// Gets the current access token if valid
    /// - Returns: The access token string, or nil if invalid/not found
    nonisolated func getAccessToken() -> String? {
        guard let tokenData = try? loadTokens(), tokenData.isAccessTokenValid() else {
            return nil
        }
        return tokenData.accessToken
    }

    /// Gets the current refresh token if valid
    /// - Returns: The refresh token string, or nil if invalid/not found
    nonisolated func getRefreshToken() -> String? {
        guard let tokenData = try? loadTokens(), tokenData.isRefreshTokenValid() else {
            return nil
        }
        return tokenData.refreshToken
    }
}
