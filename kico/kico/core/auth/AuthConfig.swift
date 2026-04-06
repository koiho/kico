import Foundation

struct AuthConfig {
    let issuer: URL
    let clientId: String
    let redirectUri: URL
    let scopes: [String]
    let authAPIHost: String

    nonisolated static func loadFromPlist(bundle: Bundle = .main) throws -> AuthConfig {
        guard
            let issuerString = bundle.object(forInfoDictionaryKey: "OIDC_ISSUER") as? String,
            !issuerString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let issuer = URL(string: issuerString)
        else {
            throw AuthConfigError.missingOrInvalidValue("OIDC_ISSUER")
        }

        guard
            let clientId = bundle.object(forInfoDictionaryKey: "OIDC_CLIENT_ID") as? String,
            !clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AuthConfigError.missingOrInvalidValue("OIDC_CLIENT_ID")
        }

        guard
            let redirectUriString = bundle.object(forInfoDictionaryKey: "OIDC_REDIRECT_URI") as? String,
            !redirectUriString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let redirectUri = URL(string: redirectUriString)
        else {
            throw AuthConfigError.missingOrInvalidValue("OIDC_REDIRECT_URI")
        }

        let scopeString = (bundle.object(forInfoDictionaryKey: "OIDC_SCOPES") as? String) ?? "openid profile email"
        let scopes = scopeString
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !scopes.isEmpty else {
            throw AuthConfigError.missingOrInvalidValue("OIDC_SCOPES")
        }

        guard
            let authAPIHost = bundle.object(forInfoDictionaryKey: "AUTH_API_HOST") as? String,
            !authAPIHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            URL(string: authAPIHost) != nil
        else {
            throw AuthConfigError.missingOrInvalidValue("AUTH_API_HOST")
        }

        return AuthConfig(
            issuer: issuer,
            clientId: clientId,
            redirectUri: redirectUri,
            scopes: scopes,
            authAPIHost: authAPIHost
        )
    }
}

enum AuthConfigError: LocalizedError {
    case missingOrInvalidValue(String)

    var errorDescription: String? {
        switch self {
        case .missingOrInvalidValue(let key):
            return "OpenID 配置缺失或无效：\(key)"
        }
    }
}
