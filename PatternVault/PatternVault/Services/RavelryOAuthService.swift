//
//  RavelryOAuthService.swift
//  PatternVault
//
//  OAuth 2.0 authorization code flow for Ravelry. Tokens stored in Keychain per app user id.
//

import Foundation

@MainActor
final class RavelryOAuthService: ObservableObject {

    static let shared = RavelryOAuthService()

    /// Per Ravelry API docs: OAuth 2 URLs are oauth2/auth and oauth2/token.
    private let authorizeURLBase = URL(string: "https://www.ravelry.com/oauth2/auth")!
    private let tokenURL = URL(string: "https://www.ravelry.com/oauth2/token")!

    /// Callback URL (patternvault://oauth/ravelry). Must match Ravelry app "Authorized Redirect URIs".
    var callbackURLScheme: String { "patternvault" }
    var callbackPath: String { "oauth/ravelry" }
    var redirectURI: String { "\(callbackURLScheme)://\(callbackPath)" }

    private static let appGroupId = "group.com.patternvault.app"
    private static let oauth2StateKey = "ravelry_oauth2_state"

    /// OAuth 2.0 client id/secret from Config. Nil if not configured.
    private var clientCredentials: (clientId: String, clientSecret: String)? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_OAUTH2_CLIENT_ID") as? String,
              let secret = Bundle.main.object(forInfoDictionaryKey: "RAVELRY_OAUTH2_CLIENT_SECRET") as? String,
              !id.isEmpty, id != "placeholder",
              !secret.isEmpty, secret != "placeholder" else {
            return nil
        }
        return (id, secret)
    }

    var isOAuthConfigured: Bool { clientCredentials != nil }

    /// True if the given app user has stored Ravelry tokens.
    func isConnected(userId: UUID) -> Bool {
        KeychainHelper.loadRavelryTokens(userId: userId) != nil
    }

    /// Start OAuth 2.0: build authorize URL with state and return it to open in browser.
    func startOAuth() async throws -> URL {
        guard let creds = clientCredentials else {
            throw RavelryOAuthError.notConfigured
        }
        let state = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        defaults?.set(state, forKey: Self.oauth2StateKey)
        defaults?.synchronize()

        var comp = URLComponents(url: authorizeURLBase, resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: creds.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = comp.url else { throw RavelryOAuthError.requestTokenFailed(statusCode: nil, serverMessage: nil) }
        return url
    }

    /// Call after user returns to app with callback URL. Exchanges code for access token and stores in Keychain.
    func handleCallback(url: URL, userId: UUID) async throws {
        guard url.scheme == callbackURLScheme else { return }
        let path = url.path
        guard path.hasPrefix("/oauth/ravelry") || path == "/oauth/ravelry" || url.host == "oauth" else { return }
        guard let creds = clientCredentials else { throw RavelryOAuthError.notConfigured }
        let comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = comp?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = comp?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let code = code else {
            let error = comp?.queryItems?.first(where: { $0.name == "error" })?.value
            throw RavelryOAuthError.callbackMissingParams(serverError: error)
        }
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        let savedState = defaults?.string(forKey: Self.oauth2StateKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        defaults?.removeObject(forKey: Self.oauth2StateKey)
        defaults?.synchronize()
        let callbackState = state?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let savedState, let callbackState, !savedState.isEmpty, !callbackState.isEmpty,
           savedState != callbackState {
            throw RavelryOAuthError.stateMismatch
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        // Ravelry: "we support basic auth (the Authorization header) for passing your client ID and secret. Submitting these as form parameters is not supported."
        let basic = "\(creds.clientId):\(creds.clientSecret)"
        let basicData = Data(basic.utf8)
        let basicEncoded = basicData.base64EncodedString()
        request.setValue("Basic \(basicEncoded)", forHTTPHeaderField: "Authorization")
        let body = [
            "grant_type=authorization_code",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RavelryOAuthError.accessTokenFailed() }
        guard http.statusCode == 200 else {
            let hint = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
                ?? String(data: data, encoding: .utf8).map { String($0.prefix(120)) }
            throw RavelryOAuthError.accessTokenFailed(serverMessage: hint)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken = json?["access_token"] as? String, !accessToken.isEmpty else {
            throw RavelryOAuthError.accessTokenFailed(serverMessage: "No access_token in response")
        }
        try KeychainHelper.saveRavelryTokens(userId: userId, accessToken: accessToken, accessTokenSecret: "")
    }

    func disconnect(userId: UUID) {
        KeychainHelper.deleteRavelryTokens(userId: userId)
    }

    /// Tokens for API requests. OAuth 2.0: returns (accessToken, ""); use Bearer token.
    func tokens(for userId: UUID) -> (accessToken: String, accessTokenSecret: String)? {
        KeychainHelper.loadRavelryTokens(userId: userId)
    }

    enum RavelryOAuthError: Error, LocalizedError {
        case notConfigured
        case requestTokenFailed(statusCode: Int?, serverMessage: String?)
        case callbackMissingParams(serverError: String?)
        case stateMismatch
        case accessTokenFailed(serverMessage: String? = nil)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Ravelry OAuth is not configured."
            case .requestTokenFailed(let code, let msg):
                var s = "Could not get Ravelry authorization link."
                if let code { s += " (HTTP \(code))" }
                if let msg, !msg.isEmpty { s += " \(msg)" }
                return s
            case .callbackMissingParams(let err):
                return err ?? "Invalid return from Ravelry."
            case .stateMismatch: return "Security check failed. Please try connecting again."
            case .accessTokenFailed(let msg):
                return msg ?? "Could not connect your Ravelry account."
            }
        }
    }
}
