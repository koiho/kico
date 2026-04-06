import Foundation
import grpc

// MARK: - Token Data

/// Stores authentication tokens with expiration information
struct TokenData: @unchecked Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: UInt64
    let refreshTokenExpiresAt: UInt64

    /// Checks if the access token is valid with a buffer time
    /// - Parameter buffer: Buffer time in seconds (default: 300 seconds = 5 minutes)
    /// - Returns: true if the access token is still valid
    nonisolated func isAccessTokenValid(buffer: TimeInterval = 300) -> Bool {
        let currentTime = UInt64(Date().timeIntervalSince1970 * 1000)
        let expiryTime = accessTokenExpiresAt - UInt64(buffer * 1000)
        return currentTime < expiryTime
    }

    /// Checks if the access token needs to be refreshed soon
    /// - Parameter threshold: Threshold in seconds before expiry (default: 300 seconds = 5 minutes)
    /// - Returns: true if the token should be refreshed
    nonisolated func needsRefresh(threshold: TimeInterval = 300) -> Bool {
        let currentTime = UInt64(Date().timeIntervalSince1970 * 1000)
        let refreshThreshold = accessTokenExpiresAt - UInt64(threshold * 1000)
        return currentTime >= refreshThreshold
    }

    /// Checks if the refresh token is still valid
    /// - Returns: true if the refresh token is still valid
    nonisolated func isRefreshTokenValid() -> Bool {
        let currentTime = UInt64(Date().timeIntervalSince1970 * 1000)
        return currentTime < refreshTokenExpiresAt
    }

    /// Creates TokenData from backend response
    nonisolated init(from response: Authentication_AuthnUpResponse) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        self.accessTokenExpiresAt = response.accessTokenExpiresAt
        self.refreshTokenExpiresAt = response.refreshTokenExpiresAt
    }

    /// Creates TokenData from refresh response
    nonisolated init(fromRefresh response: Authentication_AuthnRefreshResponse, existingRefreshToken: String) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken.isEmpty ? existingRefreshToken : response.refreshToken
        self.accessTokenExpiresAt = response.accessTokenExpiresAt
        self.refreshTokenExpiresAt = response.refreshTokenExpiresAt
    }

    /// Creates TokenData from individual components (used for migration)
    nonisolated init(
        accessToken: String,
        refreshToken: String,
        accessTokenExpiresAt: UInt64,
        refreshTokenExpiresAt: UInt64
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

// MARK: - TokenData Codable
extension TokenData: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.accessTokenExpiresAt = try container.decode(UInt64.self, forKey: .accessTokenExpiresAt)
        self.refreshTokenExpiresAt = try container.decode(UInt64.self, forKey: .refreshTokenExpiresAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(accessTokenExpiresAt, forKey: .accessTokenExpiresAt)
        try container.encode(refreshTokenExpiresAt, forKey: .refreshTokenExpiresAt)
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, accessTokenExpiresAt, refreshTokenExpiresAt
    }
}

// MARK: - User Info

/// Stores user profile information
struct UserInfo: Codable, Sendable, Equatable {
    let id: String
    let email: String
    let displayName: String
    let avatarURI: String

    /// Returns the avatar URL if the URI is valid
    var avatarURL: URL? {
        URL(string: avatarURI)
    }

    /// Creates UserInfo from backend response
    nonisolated init(from response: Authentication_AuthnUpResponse) {
        self.id = response.id
        self.email = response.email
        self.displayName = response.displayName
        self.avatarURI = response.avatarUri
    }

    /// Creates UserInfo from individual components (used for migration)
    nonisolated init(
        id: String,
        email: String,
        displayName: String,
        avatarURI: String
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURI = avatarURI
    }
}

// MARK: - Auth Session

/// Combines user info and token data into a complete authentication session
struct AuthSession: Codable, Sendable {
    let userInfo: UserInfo
    let tokenData: TokenData

    /// Returns true if the session is valid (access token is still valid)
    var isValid: Bool {
        tokenData.isAccessTokenValid()
    }

    /// Returns true if the session should be refreshed soon
    var needsRefresh: Bool {
        tokenData.needsRefresh()
    }

    /// Creates AuthSession from user info and token data
    init(userInfo: UserInfo, tokenData: TokenData) {
        self.userInfo = userInfo
        self.tokenData = tokenData
    }

    /// Creates AuthSession from backend response
    init(from response: Authentication_AuthnUpResponse) {
        self.userInfo = UserInfo(from: response)
        self.tokenData = TokenData(from: response)
    }
}

// MARK: - Token Refresh Error

enum TokenRefreshError: LocalizedError, Sendable {
    case noRefreshToken
    case refreshFailed(String)
    case networkError(Error)
    case invalidResponse
    case refreshTokenExpired

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "没有可用的刷新令牌"
        case .refreshFailed(let reason):
            return "刷新令牌失败: \(reason)"
        case .networkError(let error):
            return "网络异常: \(error.localizedDescription)"
        case .invalidResponse:
            return "刷新响应无效"
        case .refreshTokenExpired:
            return "刷新令牌已过期，请重新登录"
        }
    }
}
