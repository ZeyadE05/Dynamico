import SwiftUI

public struct SpotifyPlayerView: View {
    @ObservedObject var authManager = SpotifyAuthManager.shared
    @ObservedObject var apiClient = SpotifyAPIClient.shared

    @State private var volume: Double = 50

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            if !authManager.isAuthenticated && apiClient.localTrackName == nil {
                unauthenticatedView
            } else {
                // Column 1: Album Art & "Open Spotify" Pill Button
                leftColumn
                    .frame(width: 140)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Column 2: Track Details & Controls
                middleColumn
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
                    .padding(.vertical, 8)

                // Column 3: Volume & Audio Status
                rightColumn
                    .frame(width: 130)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Column 1: Artwork & Open Spotify Pill Button
    private var leftColumn: some View {
        VStack(spacing: 8) {
            if let albumArtURL = apiClient.playbackState?.item?.albumArtURL {
                AsyncImage(url: albumArtURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .overlay(ProgressView().scaleEffect(0.5))
                }
                .frame(width: 46, height: 46)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(gradient: Gradient(colors: [Color(red: 29/255, green: 185/255, blue: 84/255).opacity(0.4), Color.black]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 46, height: 46)
            }

            Button(action: {
                openSpotifyApp()
            }) {
                HStack(spacing: 4) {
                    Text("Open Spotify")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(14)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // Column 2: Live Track Title, Artist Name & Playback Controls
    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentTrackTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))
                    .lineLimit(1)

                Text(currentArtistName)
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3.5)

                    Capsule()
                        .fill(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .frame(width: geo.size.width * currentProgressFraction, height: 3.5)
                }
            }
            .frame(height: 3.5)

            // Controls
            HStack(spacing: 16) {
                Button(action: {
                    Task { await apiClient.previousTrack() }
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task { await apiClient.togglePlayPause() }
                }) {
                    Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    Task { await apiClient.nextTrack() }
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }

    // Column 3: Volume Control & Speaker Icon
    private var rightColumn: some View {
        VStack(spacing: 10) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16))
                .foregroundColor(Color.white.opacity(0.6))

            Slider(value: $volume, in: 0...100) { editing in
                if !editing {
                    Task {
                        await apiClient.setVolume(percent: Int(volume))
                    }
                }
            }
            .tint(Color(red: 29/255, green: 185/255, blue: 84/255))
            .frame(width: 90)
        }
    }

    private var unauthenticatedView: some View {
        HStack(spacing: 16) {
            // Left Column Icon
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))

                Button(action: {
                    openSpotifyApp()
                }) {
                    Text("Open Local App")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 110)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            // Right Info & Connect
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Connect Spotify Web API")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))

                    Spacer()

                    Button(action: {
                        if let url = URL(string: "https://developer.spotify.com/dashboard") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Dev Dashboard")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                    }
                    .buttonStyle(.plain)
                }

                if authManager.clientID.isEmpty {
                    HStack(spacing: 6) {
                        TextField("Paste Spotify Client ID...", text: $authManager.clientID)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.12), lineWidth: 1))

                        Button(action: {
                            Task {
                                try? await authManager.startPKCEAuth()
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "link")
                                Text("Connect")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(authManager.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(action: {
                            Task {
                                try? await authManager.startPKCEAuth()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("Connect Account")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            SettingsWindowManager.shared.showSettingsWindow()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                Text("Settings")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = authManager.authError {
                    Text(error)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
    }

    private func openSpotifyApp() {
        if let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else if let webURL = URL(string: "https://open.spotify.com") {
            NSWorkspace.shared.open(webURL)
        }
    }

    private var currentTrackTitle: String {
        if let trackName = apiClient.playbackState?.item?.name {
            return trackName
        }
        return apiClient.localTrackName ?? "No Track Playing"
    }

    private var currentArtistName: String {
        if let artist = apiClient.playbackState?.item?.artistNames {
            return artist
        }
        return apiClient.localArtistName ?? "Spotify"
    }

    private var isCurrentlyPlaying: Bool {
        return apiClient.playbackState?.is_playing ?? apiClient.localIsPlaying
    }

    private var currentProgressFraction: CGFloat {
        guard let state = apiClient.playbackState,
              let progress = state.progress_ms,
              let duration = state.item?.duration_ms, duration > 0 else {
            return 0.0
        }
        return CGFloat(progress) / CGFloat(duration)
    }
}
