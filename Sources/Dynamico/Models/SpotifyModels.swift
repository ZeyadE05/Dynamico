import Foundation

public struct SpotifyTokenResponse: Codable, Sendable {
    public let access_token: String
    public let token_type: String
    public let scope: String?
    public let expires_in: Int
    public let refresh_token: String?

    public enum CodingKeys: String, CodingKey {
        case access_token
        case token_type
        case scope
        case expires_in
        case refresh_token
    }
}

public struct SpotifyPlaybackState: Codable, Sendable {
    public let is_playing: Bool
    public let item: SpotifyTrack?
    public let progress_ms: Int?
    public let device: SpotifyDevice?

    public enum CodingKeys: String, CodingKey {
        case is_playing
        case item
        case progress_ms
        case device
    }
}

public struct SpotifyTrack: Codable, Sendable, Identifiable {
    public let id: String?
    public let name: String
    public let artists: [SpotifyArtist]
    public let album: SpotifyAlbum
    public let duration_ms: Int

    public var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }

    public var albumArtURL: URL? {
        if let urlString = album.images.first?.url {
            return URL(string: urlString)
        }
        return nil
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case artists
        case album
        case duration_ms
    }
}

public struct SpotifyArtist: Codable, Sendable {
    public let name: String
}

public struct SpotifyAlbum: Codable, Sendable {
    public let name: String
    public let images: [SpotifyImage]
}

public struct SpotifyImage: Codable, Sendable {
    public let url: String
    public let height: Int?
    public let width: Int?
}

public struct SpotifyDevice: Codable, Sendable {
    public let id: String?
    public let is_active: Bool
    public let name: String
    public let volume_percent: Int?
}
