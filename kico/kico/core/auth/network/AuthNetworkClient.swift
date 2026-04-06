import Connect
import Foundation
import grpc

/// Factory for creating authenticated gRPC clients with automatic token injection
final class AuthNetworkClient: Sendable {
    private let config: AuthConfig
    private let interceptor: AuthInterceptor

    init(config: AuthConfig, interceptor: AuthInterceptor) {
        self.config = config
        self.interceptor = interceptor
    }

    /// Creates an authenticated Authentication_AuthnClient
    /// - Returns: A client wrapper that automatically injects auth tokens
    func makeAuthnClient() -> AuthenticatedAuthnClient {
        let protocolClient = createProtocolClient()
        let baseClient = Authentication_AuthnClient(client: protocolClient)
        return AuthenticatedAuthnClient(client: baseClient, interceptor: interceptor)
    }

    // MARK: - Private Methods

    private func createProtocolClient() -> ProtocolClient {
        let protocolConfig = ProtocolClientConfig(
            host: config.authAPIHost,
            networkProtocol: .grpcWeb,
            codec: ProtoCodec()
        )

        return ProtocolClient(
            httpClient: URLSessionHTTPClient(),
            config: protocolConfig
        )
    }
}

// MARK: - Authenticated Client Wrappers

/// Wrapper for Authentication_AuthnClient with automatic auth token injection
final class AuthenticatedAuthnClient: Sendable {
    private let client: Authentication_AuthnClient
    private let interceptor: AuthInterceptor

    init(client: Authentication_AuthnClient, interceptor: AuthInterceptor) {
        self.client = client
        self.interceptor = interceptor
    }

    /// Performs the Up request with automatic token injection and retry
    func up(request: Authentication_AuthnUpRequest) async throws -> Authentication_AuthnUpResponse {
        return try await interceptor.intercept { headers in
            let response = await self.client.up(request: request, headers: headers)
            if let error = response.error {
                throw error
            }
            guard let message = response.message else {
                throw ConnectError(code: .unknown, message: "Invalid response", exception: nil, metadata: [:])
            }
            return message
        }
    }

    /// Performs the Refresh request with automatic token injection and retry
    func refresh(request: Authentication_AuthnRefreshRequest) async throws -> Authentication_AuthnRefreshResponse {
        return try await interceptor.intercept { headers in
            let response = await self.client.refresh(request: request, headers: headers)
            if let error = response.error {
                throw error
            }
            guard let message = response.message else {
                throw ConnectError(code: .unknown, message: "Invalid response", exception: nil, metadata: [:])
            }
            return message
        }
    }

    /// Performs the Down request with automatic token injection and retry
    func down(request: Authentication_AuthnDownRequest) async throws -> Authentication_AuthnDownResponse {
        return try await interceptor.intercept { headers in
            let response = await self.client.down(request: request, headers: headers)
            if let error = response.error {
                throw error
            }
            guard let message = response.message else {
                throw ConnectError(code: .unknown, message: "Invalid response", exception: nil, metadata: [:])
            }
            return message
        }
    }
}
