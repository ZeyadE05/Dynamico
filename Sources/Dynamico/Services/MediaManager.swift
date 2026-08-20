import Foundation
import Combine
import AppKit

@MainActor
public final class MediaManager: ObservableObject {
    public static let shared = MediaManager()

    @Published public var currentItem: MediaItem?
    @Published public var isPlaying: Bool = false
    @Published public var systemVolume: Double = 50

    private var pollTimer: Timer?
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var artworkCache: [String: NSImage] = [:]

    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool

    private var registerNotificationsFn: MRMediaRemoteRegisterForNowPlayingNotificationsFn?
    private var getNowPlayingInfoFn: MRMediaRemoteGetNowPlayingInfoFn?
    private var getApplicationIsPlayingFn: MRMediaRemoteGetNowPlayingApplicationIsPlayingFn?
    private var sendCommandFn: MRMediaRemoteSendCommandFn?

    private init() {
        setupMediaRemote()
        setupNotificationObservers()
        startPolling()
        refreshNowPlaying()
    }

    private func setupMediaRemote() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            print("MediaManager: Failed to open MediaRemote framework")
            return
        }
        self.mediaRemoteHandle = handle

        if let regPtr = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerNotificationsFn = unsafeBitCast(regPtr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self)
        }
        if let getInfoPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfoFn = unsafeBitCast(getInfoPtr, to: MRMediaRemoteGetNowPlayingInfoFn.self)
        }
        if let isPlayingPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getApplicationIsPlayingFn = unsafeBitCast(isPlayingPtr, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFn.self)
        }
        if let sendPtr = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(sendPtr, to: MRMediaRemoteSendCommandFn.self)
        }

        registerNotificationsFn?(DispatchQueue.main)
    }

    private func setupNotificationObservers() {
        // Spotify distributed notification observer
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }

        // Apple Music distributed notification observer
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }

        // System MediaRemote notification observer
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }
    }

    public func refreshNowPlaying() {
        // Priority 1: Check Spotify directly via AppleScript
        if isSpotifyRunning(), let spotifyItem = fetchSpotifyMediaItem(), !spotifyItem.title.isEmpty && spotifyItem.title != "No Track" {
            if spotifyItem.isPlaying || isSpotifyRunningAndPlaying() {
                self.currentItem = spotifyItem
                self.isPlaying = spotifyItem.isPlaying
                return
            }
        }

        // Priority 2: System Now Playing via MediaRemote
        if let getNowPlayingInfoFn = getNowPlayingInfoFn {
            getNowPlayingInfoFn(DispatchQueue.main) { [weak self] dict in
                guard let self = self else { return }

                // Guard against MediaRemote callback race condition overwriting Spotify state
                if self.isSpotifyRunning(), let spotifyItem = self.fetchSpotifyMediaItem(), spotifyItem.isPlaying {
                    self.currentItem = spotifyItem
                    self.isPlaying = true
                    return
                }

                let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0.0
                let elapsedTime = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0.0
                let playbackRate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0.0
                let isPlaying = playbackRate > 0.0

                var artworkImage: NSImage? = nil
                if let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    artworkImage = NSImage(data: artworkData)
                }

                var appName = "Media"
                if let clientProperties = dict["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] as? Data,
                   let plist = try? PropertyListSerialization.propertyList(from: clientProperties, options: [], format: nil) as? [String: Any],
                   let bundleIdentifier = plist["kMRMediaRemoteNowPlayingInfoClientPropertiesBundleIdentifier"] as? String {
                    appName = self.appNameForBundleIdentifier(bundleIdentifier)
                } else if self.isAppRunning("com.apple.Music") {
                    appName = "Apple Music"
                }

                if !title.isEmpty || !artist.isEmpty {
                    self.currentItem = MediaItem(
                        title: title,
                        artist: artist.isEmpty ? appName : artist,
                        album: album,
                        duration: duration,
                        elapsedTime: elapsedTime,
                        isPlaying: isPlaying,
                        appName: appName,
                        artwork: artworkImage
                    )
                    self.isPlaying = isPlaying
                } else if let spotifyItem = self.fetchSpotifyMediaItem() {
                    self.currentItem = spotifyItem
                    self.isPlaying = spotifyItem.isPlaying
                } else {
                    self.currentItem = nil
                    self.isPlaying = false
                }
            }
        } else if let spotifyItem = fetchSpotifyMediaItem() {
            self.currentItem = spotifyItem
            self.isPlaying = spotifyItem.isPlaying
        }
    }

    // MARK: - Spotify Detection & AppleScript Helpers
    private func isSpotifyRunning() -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").contains(where: { !$0.isTerminated })
    }

    private func isSpotifyRunningAndPlaying() -> Bool {
        guard isSpotifyRunning() else { return false }
        let script = "tell application \"Spotify\" to get player state as string"
        if let res = executeAppleScript(script) {
            let clean = res.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return clean == "playing"
        }
        return false
    }

    private func fetchSpotifyMediaItem() -> MediaItem? {
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

        let image: NSImage? = artworkCache[artUrlStr]
        if image == nil, let url = URL(string: artUrlStr), !artUrlStr.isEmpty {
            fetchArtworkAsync(urlStr: artUrlStr, url: url)
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

    private func fetchArtworkAsync(urlStr: String, url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data, let img = NSImage(data: data) else { return }
            Task { @MainActor in
                self?.artworkCache[urlStr] = img
                if let current = self?.currentItem, current.appName == "Spotify" {
                    self?.currentItem = MediaItem(
                        title: current.title,
                        artist: current.artist,
                        album: current.album,
                        duration: current.duration,
                        elapsedTime: current.elapsedTime,
                        isPlaying: current.isPlaying,
                        appName: current.appName,
                        artwork: img
                    )
                }
            }
        }.resume()
    }

    // MARK: - Media Playback Controls
    public func togglePlayPause() {
        if isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
            _ = executeAppleScript("tell application \"Spotify\" to playpause")
        } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
            _ = executeAppleScript("tell application \"Music\" to playpause")
        } else if let sendCommandFn = sendCommandFn {
            _ = sendCommandFn(2, nil) // 2 = Toggle Play/Pause
        } else {
            postMediaKeyEvent(key: 16) // Play/Pause media key
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func play() {
        if isSpotifyRunning() {
            _ = executeAppleScript("tell application \"Spotify\" to play")
        } else if let sendCommandFn = sendCommandFn {
            _ = sendCommandFn(0, nil) // 0 = Play
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func pause() {
        if isSpotifyRunning() {
            _ = executeAppleScript("tell application \"Spotify\" to pause")
        } else if let sendCommandFn = sendCommandFn {
            _ = sendCommandFn(1, nil) // 1 = Pause
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func nextTrack() {
        if isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
            _ = executeAppleScript("tell application \"Spotify\" to next track")
        } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
            _ = executeAppleScript("tell application \"Music\" to next track")
        } else if let sendCommandFn = sendCommandFn {
            _ = sendCommandFn(4, nil) // 4 = Next Track
        } else {
            postMediaKeyEvent(key: 19)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func previousTrack() {
        if isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
            _ = executeAppleScript("tell application \"Spotify\" to previous track")
        } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
            _ = executeAppleScript("tell application \"Music\" to previous track")
        } else if let sendCommandFn = sendCommandFn {
            _ = sendCommandFn(5, nil) // 5 = Previous Track
        } else {
            postMediaKeyEvent(key: 20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    public func openActiveApp() {
        let appName = currentItem?.appName ?? "Spotify"
        if appName == "Spotify" {
            if let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            } else if let webURL = URL(string: "https://open.spotify.com") {
                NSWorkspace.shared.open(webURL)
            }
        } else if appName == "Apple Music" {
            if let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: musicURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        } else if isSpotifyRunning() {
            if let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        } else {
            if let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: musicURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }

    public func setVolume(percent: Int) {
        if isSpotifyRunning() {
            _ = executeAppleScript("tell application \"Spotify\" to set sound volume to \(percent)")
        } else {
            _ = executeAppleScript("set volume output volume \(percent)")
        }
    }

    // MARK: - Utilities
    private func executeAppleScript(_ script: String) -> String? {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if error == nil {
                return output.stringValue
            }
        }
        return nil
    }

    private func isAppRunning(_ bundleIdentifier: String) -> Bool {
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { !$0.isTerminated })
    }

    private func appNameForBundleIdentifier(_ bundleIdentifier: String) -> String {
        switch bundleIdentifier {
        case "com.spotify.client": return "Spotify"
        case "com.apple.Music": return "Apple Music"
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.podcasts": return "Podcasts"
        case "com.apple.TV": return "Apple TV"
        default: return "Media"
        }
    }

    private func postMediaKeyEvent(key: Int32) {
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }
}
