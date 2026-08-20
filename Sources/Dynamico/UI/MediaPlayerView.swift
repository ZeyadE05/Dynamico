import SwiftUI

public struct MediaPlayerView: View {
    @ObservedObject var mediaManager = MediaManager.shared
    @State private var volume: Double = 50
    @State private var isVisualizing: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            if mediaManager.currentItem == nil || (mediaManager.currentItem?.title.isEmpty ?? true) {
                idleStateView
            } else {
                // Column 1: Album Art & Dynamic "Open App" Button
                leftColumn
                    .frame(width: 105)

                Rectangle()
                    .fill(Color.white.opacity(Theme.surfaceMid))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                // Column 2: Live Track Details, Visualizer & Controls
                middleColumn
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(Theme.surfaceMid))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                // Column 3: Volume Control & Speaker Icon
                rightColumn
                    .frame(width: 105)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            mediaManager.refreshNowPlaying()
        }
    }

    // MARK: - Idle State View
    private var idleStateView: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.cyanAccent.opacity(0.12))
                    .frame(width: 48, height: 48)

                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.cyanAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("No Media Playing")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text("Open Spotify or Apple Music to start playing")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Theme.playHaptic(.alignment)
                    if let spotifyURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                        NSWorkspace.shared.openApplication(at: spotifyURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    } else if let webURL = URL(string: "https://open.spotify.com") {
                        NSWorkspace.shared.open(webURL)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                        Text("Spotify")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.spotifyGreen)
                    .foregroundColor(.black)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()

                Button(action: {
                    Theme.playHaptic(.alignment)
                    if let musicURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") {
                        NSWorkspace.shared.openApplication(at: musicURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "applelogo")
                        Text("Music")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.appleMusicPink)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Column 1: Artwork & Open App Button
    private var leftColumn: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let artwork = mediaManager.currentItem?.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 2)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [
                                    themeColor.opacity(0.45),
                                    Color.black
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        Image(systemName: mediaManager.currentItem?.appName == "Spotify" ? "music.note" : "waveform")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 48, height: 48)
                }

                if mediaManager.isPlaying {
                    audioWaveformOverlay
                        .offset(x: 2, y: 2)
                }
            }

            Button(action: {
                Theme.playHaptic(.alignment)
                mediaManager.openActiveApp()
            }) {
                Text(openButtonTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(Theme.surfaceHigh))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .pointerCursorOnHover()
        }
    }

    // Live Audio Waveform Indicator Overlay
    private var audioWaveformOverlay: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(themeColor)
                    .frame(width: 2.5, height: isVisualizing ? CGFloat([10, 14, 8][i]) : 4)
                    .animation(
                        Animation.easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: isVisualizing
                    )
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.8))
        .cornerRadius(4)
        .onAppear { isVisualizing = true }
    }

    // MARK: - Column 2: Track Metadata, Visualizer & Controls
    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentTrackTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)

                Text(currentArtistName)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(Theme.surfaceActive))
                        .frame(height: 3.5)

                    Capsule()
                        .fill(themeColor)
                        .frame(width: geo.size.width * currentProgressFraction, height: 3.5)
                }
            }
            .frame(height: 3.5)

            // Playback Control Buttons
            HStack(spacing: 16) {
                Button(action: {
                    Theme.playHaptic(.alignment)
                    mediaManager.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()

                Button(action: {
                    Theme.playHaptic(.levelChange)
                    mediaManager.togglePlayPause()
                }) {
                    Image(systemName: mediaManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(themeColor)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()

                Button(action: {
                    Theme.playHaptic(.alignment)
                    mediaManager.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursorOnHover()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 1)
        }
    }

    // MARK: - Column 3: Volume Control & Speaker Icon
    private var rightColumn: some View {
        VStack(spacing: 8) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            Slider(value: $volume, in: 0...100) { editing in
                if !editing {
                    Theme.playHaptic(.alignment)
                    mediaManager.setVolume(percent: Int(volume))
                }
            }
            .tint(themeColor)
            .frame(width: 85)
        }
    }

    private var openButtonTitle: String {
        let appName = mediaManager.currentItem?.appName ?? "Spotify"
        return "Open \(appName)"
    }

    private var currentTrackTitle: String {
        if let item = mediaManager.currentItem, !item.title.isEmpty {
            return item.title
        }
        return "No Media Playing"
    }

    private var currentArtistName: String {
        if let item = mediaManager.currentItem, !item.artist.isEmpty {
            return item.artist
        }
        return "Media Player"
    }

    private var currentProgressFraction: CGFloat {
        guard let item = mediaManager.currentItem, item.duration > 0 else {
            return 0.0
        }
        let fraction = CGFloat(item.elapsedTime / item.duration)
        return min(max(fraction, 0.0), 1.0)
    }

    private var themeColor: Color {
        if mediaManager.currentItem?.appName == "Spotify" {
            return Theme.spotifyGreen
        } else if mediaManager.currentItem?.appName == "Apple Music" {
            return Theme.appleMusicPink
        }
        return Theme.cyanAccent
    }
}
