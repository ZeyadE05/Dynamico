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

    private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (Int32, AnyObject?) -> Bool

    private var registerNotificationsFn: MRMediaRemoteRegisterForNowPlayingNotificationsFn?
    private var getNowPlayingInfoFn: MRMediaRemoteGetNowPlayingInfoFn?
    private var sendCommandFn: MRMediaRemoteSendCommandFn?

    private init() {
        setupMediaRemote()
        setupNotificationObservers()
        refreshNowPlaying()
    }

    private func setupMediaRemote() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return
        }
        self.mediaRemoteHandle = handle

        if let regPtr = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerNotificationsFn = unsafeBitCast(regPtr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self)
        }
        if let getInfoPtr = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getNowPlayingInfoFn = unsafeBitCast(getInfoPtr, to: MRMediaRemoteGetNowPlayingInfoFn.self)
        }
        if let sendPtr = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(sendPtr, to: MRMediaRemoteSendCommandFn.self)
        }

        registerNotificationsFn?(DispatchQueue.main)
    }

    private func setupNotificationObservers() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }

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

    // MARK: - Adaptive Timer Throttling

    /// Starts polling only when active/expanded and playing; otherwise stops timer completely.
    public func updatePollingState(isNotchExpanded: Bool) {
        if isNotchExpanded && isPlaying {
            startPolling()
        } else {
            stopPolling()
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNowPlaying()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Async Now Playing Refresh

    public func refreshNowPlaying() {
        Task {
            let actor = MediaBackgroundActor.shared
            let isSpotifyRunning = await actor.isSpotifyRunning()
            
            if isSpotifyRunning, let spotifyItem = await actor.fetchSpotifyMediaItem(), !spotifyItem.title.isEmpty && spotifyItem.title != "No Track" {
                let spotifyPlaying: Bool
                if spotifyItem.isPlaying {
                    spotifyPlaying = true
                } else {
                    spotifyPlaying = await actor.isSpotifyRunningAndPlaying()
                }

                if spotifyPlaying {
                    self.currentItem = spotifyItem
                    self.isPlaying = true
                    self.updatePollingState(isNotchExpanded: NotchPanelController.shared.isExpanded)
                    return
                }
            }

            if let getNowPlayingInfoFn = self.getNowPlayingInfoFn {
                getNowPlayingInfoFn(DispatchQueue.main) { [weak self] dict in
                    guard let self = self else { return }

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
                    } else {
                        Task {
                            if let spotifyItem = await actor.fetchSpotifyMediaItem() {
                                self.currentItem = spotifyItem
                                self.isPlaying = spotifyItem.isPlaying
                            } else {
                                self.currentItem = nil
                                self.isPlaying = false
                            }
                        }
                    }
                    self.updatePollingState(isNotchExpanded: NotchPanelController.shared.isExpanded)
                }
            } else {
                if let spotifyItem = await actor.fetchSpotifyMediaItem() {
                    self.currentItem = spotifyItem
                    self.isPlaying = spotifyItem.isPlaying
                } else {
                    self.currentItem = nil
                    self.isPlaying = false
                }
                self.updatePollingState(isNotchExpanded: NotchPanelController.shared.isExpanded)
            }
        }
    }

    // MARK: - Playback Controls (Background Actor Offloading)

    public func togglePlayPause() {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
                await actor.toggleSpotifyPlayPause()
            } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
                await actor.toggleAppleMusicPlayPause()
            } else if let sendCommandFn = sendCommandFn {
                _ = sendCommandFn(2, nil) // 2 = Toggle Play/Pause
            } else {
                postMediaKeyEvent(key: 16)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.refreshNowPlaying()
        }
    }

    public func play() {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunning() {
                await actor.playSpotify()
            } else if let sendCommandFn = sendCommandFn {
                _ = sendCommandFn(0, nil)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.refreshNowPlaying()
        }
    }

    public func pause() {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunning() {
                await actor.pauseSpotify()
            } else if let sendCommandFn = sendCommandFn {
                _ = sendCommandFn(1, nil)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.refreshNowPlaying()
        }
    }

    public func nextTrack() {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
                await actor.nextSpotifyTrack()
            } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
                await actor.nextAppleMusicTrack()
            } else if let sendCommandFn = sendCommandFn {
                _ = sendCommandFn(4, nil)
            } else {
                postMediaKeyEvent(key: 19)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.refreshNowPlaying()
        }
    }

    public func previousTrack() {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunningAndPlaying() || currentItem?.appName == "Spotify" {
                await actor.previousSpotifyTrack()
            } else if isAppRunning("com.apple.Music") && currentItem?.appName == "Apple Music" {
                await actor.previousAppleMusicTrack()
            } else if let sendCommandFn = sendCommandFn {
                _ = sendCommandFn(5, nil)
            } else {
                postMediaKeyEvent(key: 20)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.refreshNowPlaying()
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
        } else {
            if let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                NSWorkspace.shared.openApplication(at: musicURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }

    public func setVolume(percent: Int) {
        Task {
            let actor = MediaBackgroundActor.shared
            if await actor.isSpotifyRunning() {
                await actor.setSpotifyVolume(percent: percent)
            } else {
                await actor.setSystemVolume(percent: percent)
            }
        }
    }

    // MARK: - Utilities
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
