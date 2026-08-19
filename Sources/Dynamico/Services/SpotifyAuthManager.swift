import Foundation
import AuthenticationServices
import CryptoKit
import Combine
import AppKit

@MainActor
public final class SpotifyAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = SpotifyAuthManager()

    @Published public var isAuthenticated: Bool = false
    @Published public var authError: String? = nil
    @Published public var clientID: String = UserDefaults.standard.string(forKey: "spotify_client_id") ?? "" {
        didSet {
            UserDefaults.standard.set(clientID, forKey: "spotify_client_id")
            if !clientID.isEmpty && authError?.contains("Client ID") == true {
                authError = nil
            }
        }
    }
    @Published public var redirectURI: String = UserDefaults.standard.string(forKey: "spotify_redirect_uri") ?? "notchnook://callback" {
        didSet {
            UserDefaults.standard.set(redirectURI, forKey: "spotify_redirect_uri")
        }
    }

    private let keyAccessToken = "spotify_access_token"
    private let keyRefreshToken = "spotify_refresh_token"
    private let keyExpiresAt = "spotify_token_expires_at"
    private let keyCodeVerifier = "spotify_code_verifier"

    private var webAuthSession: ASWebAuthenticationSession?

    override private init() {
        super.init()
        checkAuthStatus()
    }

    public func checkAuthStatus() {
        if getValidAccessToken() != nil || getRefreshToken() != nil {
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = false
        }
    }

    public func getValidAccessToken() -> String? {
        guard let token = KeychainHelper.shared.read(forKey: keyAccessToken),
              let expiresAtStr = KeychainHelper.shared.read(forKey: keyExpiresAt),
              let expiresAt = Double(expiresAtStr) else {
            return nil
        }

        // Buffer of 60 seconds before expiration
        if Date().timeIntervalSince1970 < (expiresAt - 60) {
            return token
        }
        return nil
    }

    public func getRefreshToken() -> String? {
        return KeychainHelper.shared.read(forKey: keyRefreshToken)
    }

    public func startPKCEAuth() async throws {
        authError = nil

        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            let msg = "Spotify Client ID is required. Please set it in Settings."
            self.authError = msg
            throw NSError(domain: "SpotifyAuthManager", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let verifier = generateCodeVerifier()
        UserDefaults.standard.set(verifier, forKey: keyCodeVerifier)
        let challenge = generateCodeChallenge(from: verifier)

        let scopes = ["user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing"].joined(separator: " ")
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes)
        ]

        guard let authURL = components.url else {
            let msg = "Invalid Authorization URL"
            self.authError = msg
            throw NSError(domain: "SpotifyAuthManager", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let callbackScheme = URL(string: redirectURI)?.scheme ?? "notchnook"

        // Attempt ASWebAuthenticationSession first
        let sessionStarted = await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                guard let self = self else { return }

                if let error = error {
                    if (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        Task { @MainActor in
                            self.authError = error.localizedDescription
                        }
                    }
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    Task { @MainActor in
                        self.authError = "No authentication code received from callback."
                    }
                    return
                }

                Task {
                    do {
                        try await self.exchangeCodeForTokens(code: code)
                    } catch {
                        Task { @MainActor in
                            self.authError = error.localizedDescription
                        }
                    }
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            let success = session.start()
            continuation.resume(returning: success)
        }

        // Fallback to system web browser if ASWebAuthenticationSession fails to present
        if !sessionStarted {
            NSWorkspace.shared.open(authURL)
        }
    }

    public func exchangeCodeForTokens(code: String) async throws {
        guard let verifier = UserDefaults.standard.string(forKey: keyCodeVerifier) else {
            let msg = "Missing PKCE code verifier"
            self.authError = msg
            throw NSError(domain: "SpotifyAuthManager", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": trimmedClientID,
            "code_verifier": verifier
        ]

        request.httpBody = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown token error"
            self.authError = "Token Exchange Error: \(errorText)"
            throw NSError(domain: "SpotifyAuthManager", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        saveTokenResponse(tokenResponse)
        self.authError = nil
    }

    public func refreshAccessToken() async throws -> String {
        guard let refreshToken = getRefreshToken() else {
            self.isAuthenticated = false
            let msg = "No refresh token available. Please reconnect."
            self.authError = msg
            throw NSError(domain: "SpotifyAuthManager", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": trimmedClientID
        ]

        request.httpBody = bodyParameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Failed to refresh token"
            self.authError = errorText
            throw NSError(domain: "SpotifyAuthManager", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        saveTokenResponse(tokenResponse)
        self.authError = nil
        return tokenResponse.access_token
    }

    public func getOrRefreshToken() async throws -> String {
        if let token = getValidAccessToken() {
            return token
        }
        return try await refreshAccessToken()
    }

    public func logout() {
        KeychainHelper.shared.delete(forKey: keyAccessToken)
        KeychainHelper.shared.delete(forKey: keyRefreshToken)
        KeychainHelper.shared.delete(forKey: keyExpiresAt)
        UserDefaults.standard.removeObject(forKey: keyCodeVerifier)
        self.isAuthenticated = false
        self.authError = nil
    }

    private func saveTokenResponse(_ response: SpotifyTokenResponse) {
        let _ = KeychainHelper.shared.save(response.access_token, forKey: keyAccessToken)
        if let refreshToken = response.refresh_token {
            let _ = KeychainHelper.shared.save(refreshToken, forKey: keyRefreshToken)
        }
        let expiresAt = Date().timeIntervalSince1970 + Double(response.expires_in)
        let _ = KeychainHelper.shared.save(String(expiresAt), forKey: keyExpiresAt)
        self.isAuthenticated = true
    }

    // PKCE Helper utilities
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isVisible } ?? NSWindow()
    }
}
