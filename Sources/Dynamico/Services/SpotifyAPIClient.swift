import Foundation
import Combine
import AppKit

@MainActor
public final class SpotifyAPIClient: ObservableObject {
    public static let shared = SpotifyAPIClient()

    @Published public var playbackState: SpotifyPlaybackState?
    @Published public var localTrackName: String?
    @Published public var localArtistName: String?
    @Published public var localIsPlaying: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupLocalNotificationObserver()
    }

    private func setupLocalNotificationObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let userInfo = notification.userInfo else { return }

            Task { @MainActor in
                if let stateStr = userInfo["Player State"] as? String {
                    self.localIsPlaying = (stateStr == "Playing")
                }
                if let name = userInfo["Name"] as? String {
                    self.localTrackName = name
                }
                if let artist = userInfo["Artist"] as? String {
                    self.localArtistName = artist
                }

                // Refresh remote state if authenticated
                if SpotifyAuthManager.shared.isAuthenticated {
                    await self.fetchCurrentPlayback()
                }
            }
        }
    }

    public func fetchCurrentPlayback() async {
        guard SpotifyAuthManager.shared.isAuthenticated else { return }

        do {
            let token = try await SpotifyAuthManager.shared.getOrRefreshToken()
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return }

            if httpResponse.statusCode == 204 {
                // No active device or player idle
                self.playbackState = nil
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return
            }

            let state = try JSONDecoder().decode(SpotifyPlaybackState.self, from: data)
            self.playbackState = state
        } catch {
            print("Spotify API fetch error: \(error)")
        }
    }

    public func togglePlayPause() async {
        guard let isPlaying = playbackState?.is_playing ?? Optional(localIsPlaying) else { return }
        if isPlaying {
            await pause()
        } else {
            await play()
        }
    }

    public func play() async {
        await sendPlayerCommand(endpoint: "play", method: "PUT")
    }

    public func pause() async {
        await sendPlayerCommand(endpoint: "pause", method: "PUT")
    }

    public func nextTrack() async {
        await sendPlayerCommand(endpoint: "next", method: "POST")
    }

    public func previousTrack() async {
        await sendPlayerCommand(endpoint: "previous", method: "POST")
    }

    public func setVolume(percent: Int) async {
        await sendPlayerCommand(endpoint: "volume?volume_percent=\(percent)", method: "PUT")
    }

    public func seek(positionMs: Int) async {
        await sendPlayerCommand(endpoint: "seek?position_ms=\(positionMs)", method: "PUT")
    }

    private func sendPlayerCommand(endpoint: String, method: String) async {
        guard SpotifyAuthManager.shared.isAuthenticated else {
            // Fallback to local AppleScript control if available
            executeLocalAppleScript(command: endpoint)
            return
        }

        do {
            let token = try await SpotifyAuthManager.shared.getOrRefreshToken()
            let url = URL(string: "https://api.spotify.com/v1/me/player/\(endpoint)")!
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                // Fetch updated state quickly
                try await Task.sleep(nanoseconds: 200_000_000)
                await fetchCurrentPlayback()
            }
        } catch {
            print("Player command \(endpoint) error: \(error)")
            executeLocalAppleScript(command: endpoint)
        }
    }

    private func executeLocalAppleScript(command: String) {
        let scriptSource: String
        switch command {
        case "play":
            scriptSource = "tell application \"Spotify\" to play"
        case "pause":
            scriptSource = "tell application \"Spotify\" to pause"
        case "next":
            scriptSource = "tell application \"Spotify\" to next track"
        case "previous":
            scriptSource = "tell application \"Spotify\" to previous track"
        default:
            return
        }

        if let appleScript = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
        }
    }
}
