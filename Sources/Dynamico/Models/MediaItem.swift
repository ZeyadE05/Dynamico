import Foundation
import AppKit

public struct MediaItem: Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double // in seconds
    public let elapsedTime: Double // in seconds
    public let isPlaying: Bool
    public let appName: String
    public let artwork: NSImage?

    public init(
        title: String = "No Track Playing",
        artist: String = "Media",
        album: String = "",
        duration: Double = 0,
        elapsedTime: Double = 0,
        isPlaying: Bool = false,
        appName: String = "Media",
        artwork: NSImage? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.appName = appName
        self.artwork = artwork
    }
}
