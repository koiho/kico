import Connect
import Foundation

/// Intercepts gRPC requests to inject auth tokens and handle token refresh on 401/403 errors
final class AuthInterceptor: Sendable {
    private let tokenStore: SecureTokenStore
    private let refreshManager: TokenRefreshManager

    init(tokenStore: SecureTokenStore, refreshManager: TokenRefreshManager) {
        self.tokenStore = tokenStore
        self.refreshManager = refreshManager
    }

    /// Executes a request with automatic token injection and retry on auth failure
    /// - Parameter request: The async request to execute (with headers injection)
    /// - Returns: The response from the request
    /// - Throws: The original error if retry fails, or a token refresh error
    func intercept<T>(_ request: (Connect.Headers) async throws -> T) async throws -> T {
        // First attempt with current token
        do {
            return try await executeRequest(request)
        } catch let error as ConnectError {
            // Check if it's an auth error (401 or 403)
            if isAuthError(error) {
                return try await handleAuthError(request: request)
            }
            throw error
        }
    }

    /// Creates authorization headers with current access token
    /// - Returns: Headers dictionary with Authorization Bearer token, or empty headers if no token
    func createAuthHeaders() -> Connect.Headers {
        guard let accessToken = tokenStore.getAccessToken() else {
            return [:]
        }

        return ["Authorization": ["Bearer \(accessToken)"]]
    }

    /// Checks if the stored token needs refresh
    /// - Returns: true if the token should be refreshed before use
    func needsTokenRefresh() -> Bool {
        return tokenStore.needsRefresh()
    }

    /// Forces a token refresh before the next request
    /// - Throws: TokenRefreshError if refresh fails
    func forceTokenRefresh() async throws {
        _ = try await refreshManager.refreshToken()
    }

    // MARK: - Private Methods

    private func executeRequest<T>(_ request: (Connect.Headers) async throws -> T) async throws -> T {
        // Check if token needs proactive refresh
        if needsTokenRefresh() {
            _ = try? await refreshManager.refreshToken()
        }

        let headers = createAuthHeaders()
        return try await request(headers)
    }

    private func isAuthError(_ error: ConnectError) -> Bool {
        return error.code == .unauthenticated || error.code == .permissionDenied
    }

    private func handleAuthError<T>(request: (Connect.Headers) async throws -> T) async throws -> T {
        do {
            // Try to refresh the token
            _ = try await refreshManager.refreshToken()

            // Retry the original request with new token
            let headers = createAuthHeaders()
            return try await request(headers)
        } catch {
            // Refresh failed - throw a clear error
            if let refreshError = error as? TokenRefreshError {
                throw AuthError.tokenRefreshFailed(refreshError)
            } else {
                throw AuthError.tokenRefreshFailed(TokenRefreshError.networkError(error))
            }
        }
    }
}

// MARK: - Auth Error

enum AuthError: LocalizedError {
    case tokenRefreshFailed(TokenRefreshError)
    case sessionExpired
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .tokenRefreshFailed(let error):
            return error.errorDescription
        case .sessionExpired:
            return "登录已过期，请重新登录"
        case .unauthorized:
            return "未授权访问"
        }
    }
}
