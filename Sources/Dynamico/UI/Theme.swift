import SwiftUI
import AppKit

public enum Theme {
    // MARK: - Brand Accents
    public static let cyanAccent = Color(red: 0, green: 210/255, blue: 255/255)
    public static let todoistRed = Color(red: 228/255, green: 71/255, blue: 62/255)
    public static let spotifyGreen = Color(red: 29/255, green: 185/255, blue: 84/255)
    public static let appleMusicPink = Color(red: 250/255, green: 35/255, blue: 59/255)
    public static let purpleAccent = Color(red: 175/255, green: 82/255, blue: 222/255)
    public static let orangeAccent = Color.orange

    // MARK: - Standardized Surface Opacities
    public static let surfaceLow: CGFloat = 0.04
    public static let surfaceMid: CGFloat = 0.06
    public static let surfaceHigh: CGFloat = 0.08
    public static let surfaceActive: CGFloat = 0.12

    // MARK: - Text Opacities
    public static let textMuted = Color.white.opacity(0.45)
    public static let textSecondary = Color.white.opacity(0.65)
    public static let textPrimary = Color.white.opacity(0.95)

    // MARK: - Haptic Feedback Helper
    public static func playHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}

// MARK: - Pointer Cursor Adaptor ViewModifier (Flicker-Free Direct Cursor Set)
public struct PointerCursorOnHoverModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}

extension View {
    public func pointerCursorOnHover() -> some View {
        self.modifier(PointerCursorOnHoverModifier())
    }
}
