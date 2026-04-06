import Connect
import Foundation
import grpc

/// Manages token refresh operations in a thread-safe manner using actor
actor TokenRefreshManager {
    private let tokenStore: SecureTokenStore
    private let config: AuthConfig

    private var isRefreshing = false
    private var pendingRefreshTasks: [CheckedContinuation<TokenData, Error>] = []

    init(tokenStore: SecureTokenStore, config: AuthConfig) {
        self.tokenStore = tokenStore
        self.config = config
    }

    /// Refreshes the access token using the refresh token
    /// - Returns: The new token data
    /// - Throws: TokenRefreshError if refresh fails
    func refreshToken() async throws -> TokenData {
        // If already refreshing, wait for the existing refresh to complete
        if isRefreshing {
            return try await withCheckedThrowingContinuation { continuation in
                pendingRefreshTasks.append(continuation)
            }
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newTokens = try await performRefresh()

            // Notify all waiting tasks with the new tokens
            for task in pendingRefreshTasks {
                task.resume(returning: newTokens)
            }
            pendingRefreshTasks.removeAll()

            return newTokens
        } catch {
            // Fail all waiting tasks with the error
            for task in pendingRefreshTasks {
                task.resume(throwing: error)
            }
            pendingRefreshTasks.removeAll()
            throw error
        }
    }

    /// Checks if a refresh operation is currently in progress
    func isRefreshingInProgress() -> Bool {
        return isRefreshing
    }

    /// Cancels all pending refresh tasks
    func cancelPendingRefreshes() {
        for task in pendingRefreshTasks {
            task.resume(throwing: TokenRefreshError.refreshFailed("刷新已取消"))
        }
        pendingRefreshTasks.removeAll()
        isRefreshing = false
    }

    // MARK: - Private Methods

    private func performRefresh() async throws -> TokenData {
        // Get current tokens
        guard let currentTokens = try? tokenStore.loadTokens() else {
            throw TokenRefreshError.noRefreshToken
        }

        // Check if refresh token is still valid
        guard currentTokens.isRefreshTokenValid() else {
            throw TokenRefreshError.refreshTokenExpired
        }

        // Create the refresh request
        var request = Authentication_AuthnRefreshRequest()
        request.refreshToken = currentTokens.refreshToken

        // Create the authn client
        let client = try makeAuthnClient()

        // Execute the refresh request
        let response = await client.refresh(request: request)

        // Check for errors
        if let error = response.error {
            throw TokenRefreshError.refreshFailed(error.localizedDescription)
        }

        guard let message = response.message else {
            throw TokenRefreshError.invalidResponse
        }

        // Create new token data (preserve refresh token if backend doesn't return a new one)
        let newTokens = TokenData(
            fromRefresh: message,
            existingRefreshToken: currentTokens.refreshToken
        )

        // Save the new tokens
        try tokenStore.saveTokens(newTokens)

        return newTokens
    }

    private func makeAuthnClient() throws -> Authentication_AuthnClient {
        guard URL(string: config.authAPIHost) != nil else {
            throw AuthConfigError.missingOrInvalidValue("AUTH_API_HOST")
        }

        let protocolConfig = ProtocolClientConfig(
            host: config.authAPIHost,
            networkProtocol: .grpcWeb,
            codec: ProtoCodec()
        )

        let protocolClient = ProtocolClient(
            httpClient: URLSessionHTTPClient(),
            config: protocolConfig
        )

        return Authentication_AuthnClient(client: protocolClient)
    }
}
