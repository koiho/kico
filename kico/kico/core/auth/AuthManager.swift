import AppAuth
import Combine
import Connect
import Foundation
import UIKit
import grpc

@MainActor
final class AuthManager: ObservableObject {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    // MARK: - Published Properties

    @Published private(set) var state: State = .signedOut

    // New: Expose user info and avatar
    @Published private(set) var userInfo: UserInfo?
    @Published private(set) var avatarImage: UIImage?

    // MARK: - OIDC Flow

    var currentAuthorizationFlow: OIDExternalUserAgentSession?

    // MARK: - Storage & Network

    private let keychainStore: KeychainStore

    // New: Separated stores for tokens and user info
    private let tokenStore: SecureTokenStore
    private let userInfoStore: UserInfoStore
    private let refreshManager: TokenRefreshManager
    private let avatarManager: AvatarImageManager
    private var networkClient: AuthNetworkClient?

    // Legacy: Session key for migration
    private let sessionKey = "authn.session"
    private var session: BackendSession?

    // MARK: - Initialization

    nonisolated init(
        keychainStore: KeychainStore = KeychainStore(),
        tokenStore: SecureTokenStore = SecureTokenStore(),
        userInfoStore: UserInfoStore = UserInfoStore(),
        avatarManager: AvatarImageManager? = nil
    ) {
        self.keychainStore = keychainStore
        self.tokenStore = tokenStore
        self.userInfoStore = userInfoStore
        self.avatarManager = avatarManager ?? AvatarImageManager()

        // TokenRefreshManager requires config, defer initialization
        self.refreshManager = TokenRefreshManager(tokenStore: tokenStore, config: try! AuthConfig.loadFromPlist())
    }

    private func setupAvatarObservation() {
        avatarManager.$currentAvatar
            .assign(to: &$avatarImage)
    }

    func startLogin() {
        guard state != .signingIn else {
            return
        }

        do {
            let config = try AuthConfig.loadFromPlist()
            state = .signingIn

            let discoveryURL = config.issuer.appendingPathComponent(".well-known/openid-configuration")

            OIDAuthorizationService.discoverConfiguration(forDiscoveryURL: discoveryURL) { [weak self] discoveredConfiguration, error in
                guard let self else { return }

                Task { @MainActor in
                    if let error {
                        self.state = .failed(self.userFriendlyAuthMessage(for: error, fallback: "登录服务暂时不可用，请稍后重试"))
                        return
                    }

                    guard let discoveredConfiguration else {
                        self.state = .failed("登录服务配置异常，请稍后再试")
                        return
                    }

                    guard let presentingViewController = Self.topViewController() else {
                        self.state = .failed("当前页面无法发起登录，请返回重试")
                        return
                    }

                    guard let codeVerifier = OIDAuthorizationRequest.generateCodeVerifier(),
                          let codeChallenge = OIDAuthorizationRequest.codeChallengeS256(forVerifier: codeVerifier) else {
                        self.state = .failed("登录初始化失败，请稍后重试")
                        return
                    }

                    let serviceConfiguration = OIDServiceConfiguration(
                        authorizationEndpoint: discoveredConfiguration.authorizationEndpoint,
                        tokenEndpoint: discoveredConfiguration.tokenEndpoint
                    )

                    let request = OIDAuthorizationRequest(
                        configuration: serviceConfiguration,
                        clientId: config.clientId,
                        clientSecret: nil,
                        scopes: config.scopes,
                        redirectURL: config.redirectUri,
                        responseType: OIDResponseTypeCode,
                        additionalParameters: [
                            "code_challenge": codeChallenge,
                            "code_challenge_method": "S256",
                        ]
                    )

                    self.currentAuthorizationFlow = OIDAuthorizationService.present(
                        request,
                        presenting: presentingViewController
                    ) { [weak self] response, authorizationError in
                        guard let self else { return }

                        Task { @MainActor in
                            self.currentAuthorizationFlow = nil

                            if let authorizationError {
                                self.state = .failed(self.userFriendlyAuthMessage(for: authorizationError, fallback: "登录未完成，请重试"))
                                return
                            }

                            guard let code = response?.authorizationCode, !code.isEmpty else {
                                self.state = .failed("登录信息不完整，请重新登录")
                                return
                            }

                            await self.exchangeCodeWithBackend(
                                code: code,
                                codeVerifier: codeVerifier,
                                redirectURI: config.redirectUri.absoluteString,
                                authAPIHost: config.authAPIHost
                            )
                        }
                    }
                }
            }
        } catch {
            state = .failed("登录暂不可用，请稍后重试")
        }
    }

    func restoreFromKeychain() {
        setupAvatarObservation()

        do {
            // Try new stores first
            if let userInfo = try userInfoStore.loadUserInfo(),
               let _ = try tokenStore.loadTokens() {
                self.userInfo = userInfo
                state = .signedIn

                // Initialize network client
                initializeNetworkClient()

                // Load avatar if URI exists
                if !userInfo.avatarURI.isEmpty {
                    Task {
                        try? await avatarManager.loadImage(from: userInfo.avatarURI)
                    }
                }
                return
            }

            // Fallback: try migrating from legacy BackendSession
            try migrateFromLegacySession()
        } catch {
            session = nil
            userInfo = nil
            state = .failed("登录状态恢复失败，请重新登录")
        }
    }

    func signOut() {
        userInfo = nil
        avatarImage = nil
        session = nil
        currentAuthorizationFlow = nil
        networkClient = nil

        do {
            try tokenStore.deleteTokens()
            try userInfoStore.deleteUserInfo()
            avatarManager.clearCache()
            state = .signedOut
        } catch {
            state = .failed("退出登录失败，请重试")
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        guard let currentAuthorizationFlow else {
            return false
        }

        if currentAuthorizationFlow.resumeExternalUserAgentFlow(with: url) {
            self.currentAuthorizationFlow = nil
            return true
        }

        return false
    }

    private func exchangeCodeWithBackend(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        authAPIHost: String
    ) async {
        do {
            let authnClient = try makeAuthnClient(host: authAPIHost)
            var upRequest = Authentication_AuthnUpRequest()
            upRequest.code = code
            upRequest.redirectUri = redirectURI
            upRequest.codeVerifier = codeVerifier
            upRequest.userRegion = Locale.current.region?.identifier ?? "US"

            let response = await authnClient.up(request: upRequest)

            if response.error != nil {
                state = .failed("登录失败，请稍后重试")
                return
            }

            guard let message = response.message else {
                state = .failed("登录结果异常，请重新登录")
                return
            }

            // Store tokens separately
            let tokenData = TokenData(from: message)
            try tokenStore.saveTokens(tokenData)

            // Store user info separately
            let userInfo = UserInfo(from: message)
            try userInfoStore.saveUserInfo(userInfo)

            // Update published properties
            self.userInfo = userInfo
            state = .signedIn

            // Initialize network client with auth
            initializeNetworkClient()

            // Load avatar in background
            if !userInfo.avatarURI.isEmpty {
                Task { @MainActor in
                    do {
                        _ = try await avatarManager.loadImage(from: userInfo.avatarURI)
                    } catch {
                    }
                }
            }
        } catch {
            state = .failed("登录失败，请稍后重试")
        }
    }

    private func makeAuthnClient(host: String) throws -> Authentication_AuthnClient {
        guard URL(string: host) != nil else {
            throw AuthManagerError.invalidAuthHost
        }

        let config = ProtocolClientConfig(
            host: host,
            networkProtocol: .grpcWeb,
            codec: ProtoCodec()
        )

        let protocolClient = ProtocolClient(
            httpClient: URLSessionHTTPClient(),
            config: config
        )

        return Authentication_AuthnClient(client: protocolClient)
    }

    // MARK: - New Helper Methods

    private func initializeNetworkClient() {
        guard let config = try? AuthConfig.loadFromPlist() else {
            return
        }

        let interceptor = AuthInterceptor(tokenStore: tokenStore, refreshManager: refreshManager)
        networkClient = AuthNetworkClient(config: config, interceptor: interceptor)
    }

    private func migrateFromLegacySession() throws {
        // Try to load old BackendSession
        guard let data = try keychainStore.load(for: sessionKey) else {
            state = .signedOut
            return
        }

        let legacySession = try JSONDecoder().decode(BackendSession.self, from: data)

        // Create TokenData from legacy session
        let tokenData = TokenData(
            accessToken: legacySession.accessToken,
            refreshToken: legacySession.refreshToken,
            accessTokenExpiresAt: legacySession.accessTokenExpiresAt,
            refreshTokenExpiresAt: legacySession.refreshTokenExpiresAt
        )

        // Create UserInfo from legacy session
        let userInfo = UserInfo(
            id: legacySession.id,
            email: legacySession.email,
            displayName: legacySession.displayName,
            avatarURI: legacySession.avatarURI
        )

        // Save to new stores
        try tokenStore.saveTokens(tokenData)
        try userInfoStore.saveUserInfo(userInfo)

        // Update published properties
        self.userInfo = userInfo
        state = .signedIn

        // Initialize network client
        initializeNetworkClient()

        // Load avatar
        if !userInfo.avatarURI.isEmpty {
            Task {
                try? await avatarManager.loadImage(from: userInfo.avatarURI)
            }
        }

        // Clean up old session
        try? keychainStore.delete(for: sessionKey)
    }

    // MARK: - Public Convenience Methods

    /// Creates an authenticated network client for making API calls
    /// - Returns: AuthNetworkClient if authenticated, nil otherwise
    func createAuthenticatedClient() -> AuthNetworkClient? {
        return networkClient
    }

    /// Returns the current access token if available
    var currentAccessToken: String? {
        return tokenStore.getAccessToken()
    }

    /// Checks if the user is currently authenticated
    var isAuthenticated: Bool {
        return state == .signedIn && tokenStore.isAccessTokenValid()
    }

    private func userFriendlyAuthMessage(for error: Error, fallback: String) -> String {
        let nsError = error as NSError
        let lower = nsError.localizedDescription.lowercased()

        if lower.contains("cancel") {
            return "已取消登录"
        }

        if lower.contains("network") || lower.contains("timed out") || lower.contains("offline") {
            return "网络异常，请检查网络后重试"
        }

        if nsError.domain == NSURLErrorDomain {
            return "网络异常，请检查网络后重试"
        }

        return fallback
    }

    @MainActor
    private static func topViewController(
        from root: UIViewController? = nil
    ) -> UIViewController? {
        let root = root ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = root as? UITabBarController,
           let selected = tabBarController.selectedViewController {
            return topViewController(from: selected)
        }

        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }

        return root
    }
}

private struct BackendSession: Codable {
    let id: String
    let accessToken: String
    let accessTokenExpiresAt: UInt64
    let email: String
    let displayName: String
    let avatarURI: String
    let refreshToken: String
    let refreshTokenExpiresAt: UInt64
}

private enum AuthManagerError: LocalizedError {
    case invalidAuthHost

    var errorDescription: String? {
        switch self {
        case .invalidAuthHost:
            return "认证服务地址无效"
        }
    }
}
