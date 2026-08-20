import Foundation
import AppKit

/// Dedicated background actor for executing AppleScript queries (Spotify / Apple Music)
/// and processing media playback state off the main thread.
public actor MediaBackgroundActor {
    public static let shared = MediaBackgroundActor()

    private var artworkCache: [String: NSImage] = [:]

    private init() {}

    // MARK: - Spotify AppleScript Execution (Background QoS)

    public func isSpotifyRunning() -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").contains(where: { !$0.isTerminated })
    }

    public func isSpotifyRunningAndPlaying() -> Bool {
        guard isSpotifyRunning() else { return false }
        let script = "tell application \"Spotify\" to get player state as string"
        if let res = executeAppleScript(script) {
            let clean = res.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return clean == "playing"
        }
        return false
    }

    public func fetchSpotifyMediaItem() async -> MediaItem? {
        guard isSpotifyRunning() else { return nil }
        let script = """
        tell application "Spotify"
            set playerState to player state as string
            try
                set trackName to name of current track
                set artistName to artist of current track
                set albumName to album of current track
                set trackDuration to (duration of current track) / 1000
                set playerPos to player position
                set artUrl to artwork url of current track
                return playerState & "|||" & trackName & "|||" & artistName & "|||" & albumName & "|||" & playerPos & "|||" & trackDuration & "|||" & artUrl
            on error
                return playerState & "|||No Track|||Spotify||||||0|||0|||"
            end try
        end tell
        """

        guard let output = executeAppleScript(script) else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 7 else { return nil }

        let stateStr = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaying = (stateStr == "playing")
        let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
        let pos = Double(parts[4].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let dur = Double(parts[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
        let artUrlStr = parts[6].trimmingCharacters(in: .whitespacesAndNewlines)

        var image: NSImage? = artworkCache[artUrlStr]
        if image == nil, let url = URL(string: artUrlStr), !artUrlStr.isEmpty {
            if let data = try? await URLSession.shared.data(from: url).0, let downloadedImg = NSImage(data: data) {
                artworkCache[artUrlStr] = downloadedImg
                image = downloadedImg
            }
        }

        return MediaItem(
            title: title.isEmpty ? "Spotify" : title,
            artist: artist.isEmpty ? "Spotify" : artist,
            album: album,
            duration: dur,
            elapsedTime: pos,
            isPlaying: isPlaying,
            appName: "Spotify",
            artwork: image
        )
    }

    // MARK: - Playback Command Dispatchers

    public func toggleSpotifyPlayPause() {
        _ = executeAppleScript("tell application \"Spotify\" to playpause")
    }

    public func toggleAppleMusicPlayPause() {
        _ = executeAppleScript("tell application \"Music\" to playpause")
    }

    public func playSpotify() {
        _ = executeAppleScript("tell application \"Spotify\" to play")
    }

    public func pauseSpotify() {
        _ = executeAppleScript("tell application \"Spotify\" to pause")
    }

    public func nextSpotifyTrack() {
        _ = executeAppleScript("tell application \"Spotify\" to next track")
    }

    public func nextAppleMusicTrack() {
        _ = executeAppleScript("tell application \"Music\" to next track")
    }

    public func previousSpotifyTrack() {
        _ = executeAppleScript("tell application \"Spotify\" to previous track")
    }

    public func previousAppleMusicTrack() {
        _ = executeAppleScript("tell application \"Music\" to previous track")
    }

    public func setSpotifyVolume(percent: Int) {
        _ = executeAppleScript("tell application \"Spotify\" to set sound volume to \(percent)")
    }

    public func setSystemVolume(percent: Int) {
        _ = executeAppleScript("set volume output volume \(percent)")
    }

    // MARK: - Utility AppleScript Execution

    private func executeAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if error == nil, let val = output.stringValue, !val.isEmpty {
                return val
            }
        }

        // Fallback to /usr/bin/osascript execution
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                return output
            }
        } catch {
            return nil
        }
        return nil
    }
}
