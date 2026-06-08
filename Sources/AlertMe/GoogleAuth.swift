import AppKit
import CryptoKit
import Foundation

enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}

/// Handles the OAuth 2.0 Authorization Code flow with PKCE for an installed
/// (desktop) app, plus access-token refresh. Refresh tokens live in the
/// Keychain; access tokens stay in memory.
actor GoogleAuth {
    private let config: Config

    private var accessToken: String?
    private var accessTokenExpiry: Date?

    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    init(config: Config) {
        self.config = config
    }

    var isSignedIn: Bool {
        Keychain.loadRefreshToken() != nil
    }

    /// Returns a valid access token, refreshing or prompting sign-in as needed.
    func validAccessToken() async throws -> String {
        if let token = accessToken, let expiry = accessTokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        guard let refresh = Keychain.loadRefreshToken() else {
            throw AuthError.message("Not signed in")
        }
        return try await refreshAccessToken(refreshToken: refresh)
    }

    /// Runs the full interactive sign-in: opens the browser, captures the
    /// redirect on a loopback port, and exchanges the code for tokens.
    func signIn() async throws {
        guard !config.clientId.isEmpty else {
            throw AuthError.message("No clientId configured. Edit config.json (see README) and add your Google OAuth Client ID.")
        }

        let verifier = Self.randomURLSafe(count: 64)
        let challenge = Self.codeChallenge(for: verifier)

        let server = LoopbackServer()
        let codeBox = CodeBox()
        let port = try server.start { params in
            Task { await codeBox.set(params) }
        }
        defer { server.stop() }

        let redirectURI = "http://127.0.0.1:\(port)"
        var comps = URLComponents(string: Self.authEndpoint)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = comps.url else { throw AuthError.message("Failed to build auth URL") }

        _ = await MainActor.run { NSWorkspace.shared.open(authURL) }

        let params = try await codeBox.wait(timeout: 180)
        if let error = params["error"] {
            throw AuthError.message("Authorization denied: \(error)")
        }
        guard let code = params["code"] else {
            throw AuthError.message("No authorization code received")
        }

        try await exchangeCode(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    func signOut() {
        Keychain.deleteRefreshToken()
        accessToken = nil
        accessTokenExpiry = nil
    }

    // MARK: - Token requests

    private func exchangeCode(code: String, verifier: String, redirectURI: String) async throws {
        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientId,
            "code_verifier": verifier
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            fields["client_secret"] = secret
        }

        let json = try await postForm(fields)
        guard let access = json["access_token"] as? String else {
            throw AuthError.message("Token exchange failed: \(json)")
        }
        accessToken = access
        accessTokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        if let refresh = json["refresh_token"] as? String {
            Keychain.saveRefreshToken(refresh)
        }
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientId
        ]
        if let secret = config.clientSecret, !secret.isEmpty {
            fields["client_secret"] = secret
        }

        let json = try await postForm(fields)
        guard let access = json["access_token"] as? String else {
            // Refresh token was revoked or invalid; force re-auth.
            Keychain.deleteRefreshToken()
            throw AuthError.message("Session expired, please sign in again")
        }
        accessToken = access
        accessTokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        return access
    }

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.message("Invalid token response")
        }
        return json
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hash))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

/// Bridges the loopback server's callback into async/await.
private actor CodeBox {
    private var params: [String: String]?
    private var waiter: CheckedContinuation<[String: String], Never>?

    func set(_ value: [String: String]) {
        params = value
        if let waiter {
            waiter.resume(returning: value)
            self.waiter = nil
        }
    }

    func wait(timeout seconds: Double) async throws -> [String: String] {
        if let params { return params }
        let deadline = Task {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        let result = await withCheckedContinuation { (cont: CheckedContinuation<[String: String], Never>) in
            self.waiter = cont
            Task {
                try? await deadline.value
                if self.params == nil { self.set(["error": "timeout"]) }
            }
        }
        deadline.cancel()
        return result
    }
}
