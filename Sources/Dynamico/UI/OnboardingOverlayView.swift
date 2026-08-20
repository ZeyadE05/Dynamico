import SwiftUI

public struct OnboardingOverlayView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentStep: Int = 0

    public init() {}

    public var body: some View {
        if !hasCompletedOnboarding {
            VStack(spacing: 12) {
                HStack {
                    Text("Welcome to Dynamico")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Spacer()

                    Button(action: {
                        dismissOnboarding()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .pointerCursorOnHover()
                }

                HStack(spacing: 16) {
                    stepCard(
                        index: 0,
                        icon: "sparkles",
                        title: "1. Hover to Peek",
                        subtitle: "Move your cursor to the notch to preview playback & status"
                    )

                    stepCard(
                        index: 1,
                        icon: "hand.tap.fill",
                        title: "2. Click to Expand",
                        subtitle: "Click the peek bar to drop down full controls & modules"
                    )

                    stepCard(
                        index: 2,
                        icon: "tray.and.arrow.down",
                        title: "3. Drag Files to Shelf",
                        subtitle: "Drop files right into the shelf zone to stage them"
                    )
                }

                HStack {
                    Spacer()

                    Button(action: {
                        dismissOnboarding()
                    }) {
                        HStack(spacing: 4) {
                            Text("Explore Dynamico")
                                .font(.system(size: 11, weight: .bold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.cyanAccent)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                        .shadow(color: Theme.cyanAccent.opacity(0.3), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .pointerCursorOnHover()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 12/255, green: 12/255, blue: 16/255).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.cyanAccent.opacity(0.25), lineWidth: 1)
            )
            .padding(12)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private func stepCard(index: Int, icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.cyanAccent.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.cyanAccent)
            }

            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(Theme.surfaceLow))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(Theme.surfaceMid), lineWidth: 1)
        )
    }

    private func dismissOnboarding() {
        Theme.playHaptic(.levelChange)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            hasCompletedOnboarding = true
        }
    }
}
