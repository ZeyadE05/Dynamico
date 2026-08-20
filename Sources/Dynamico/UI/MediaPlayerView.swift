import SwiftUI

public struct MediaPlayerView: View {
    @ObservedObject var mediaManager = MediaManager.shared
    @State private var volume: Double = 50

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Column 1: Album Art & Dynamic "Open App" Button
            leftColumn
                .frame(width: 105)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            // Column 2: Track Details & Playback Controls
            middleColumn
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 6)

            // Column 3: Volume Slider & Speaker Icon
            rightColumn
                .frame(width: 105)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            mediaManager.refreshNowPlaying()
        }
    }

    // Column 1: Artwork & Open App Pill Button
    private var leftColumn: some View {
        VStack(spacing: 6) {
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
                                mediaManager.currentItem?.appName == "Spotify"
                                    ? Color(red: 29/255, green: 185/255, blue: 84/255).opacity(0.45)
                                    : Color(red: 250/255, green: 35/255, blue: 59/255).opacity(0.45),
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

            Button(action: {
                mediaManager.openActiveApp()
            }) {
                Text(openButtonTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // Column 2: Live Track Title, Artist Name & Playback Controls
    private var middleColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                        .fill(themeColor)
                        .frame(width: geo.size.width * currentProgressFraction, height: 3.5)
                }
            }
            .frame(height: 3.5)

            // Controls
            HStack(spacing: 16) {
                Button(action: {
                    mediaManager.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    mediaManager.togglePlayPause()
                }) {
                    Image(systemName: mediaManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(themeColor)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: {
                    mediaManager.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 1)
        }
    }

    // Column 3: Volume Control & Speaker Icon
    private var rightColumn: some View {
        VStack(spacing: 8) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))

            Slider(value: $volume, in: 0...100) { editing in
                if !editing {
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
            return Color(red: 29/255, green: 185/255, blue: 84/255)
        } else if mediaManager.currentItem?.appName == "Apple Music" {
            return Color(red: 250/255, green: 35/255, blue: 59/255)
        }
        return Color(red: 0, green: 210/255, blue: 255/255)
    }
}
