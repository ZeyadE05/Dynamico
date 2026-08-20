import SwiftUI

public enum NotchTab: String, CaseIterable, Identifiable {
    case spotify = "music.note"
    case clipboard = "doc.on.clipboard"
    case fileShelf = "tray.and.arrow.down"
    case power = "bolt.batteryblock"
    case todoist = "checkmark.circle.fill"
    case settings = "gearshape"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spotify: return "Media"
        case .clipboard: return "Clipboard"
        case .fileShelf: return "Shelf"
        case .power: return "Power"
        case .todoist: return "Todoist"
        case .settings: return "Settings"
        }
    }
}

public struct NotchContentView: View {
    @ObservedObject var controller: NotchPanelController
    @ObservedObject var settingsManager = SettingsManager.shared

    public init(controller: NotchPanelController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack(alignment: .top) {
            if controller.isExpanded {
                // Sapphire Ultra-Dark Notch Container
                RoundedCornerShape(
                    topLeft: 0,
                    topRight: 0,
                    bottomLeft: 26,
                    bottomRight: 26
                )
                .fill(Color(red: 8/255, green: 8/255, blue: 10/255))
                .overlay(
                    RoundedCornerShape(
                        topLeft: 0,
                        topRight: 0,
                        bottomLeft: 26,
                        bottomRight: 26
                    )
                    .stroke(
                        Color.white.opacity(0.06),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.black.opacity(0.75), radius: 28, x: 0, y: 12)

                expandedView
                    .clipShape(
                        RoundedCornerShape(
                            topLeft: 0,
                            topRight: 0,
                            bottomLeft: 26,
                            bottomRight: 26
                        )
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            } else {
                // 100% Invisible Standby Mode (Triggered on Notch Hover)
                Color.clear
                    .frame(height: controller.notchHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.10, dampingFraction: 0.85), value: controller.isExpanded)
        .animation(.easeInOut(duration: 0.18), value: controller.selectedTab)
    }

    // Expanded View (Dynamic side-flanking tabs)
    private var expandedView: some View {
        VStack(spacing: 0) {
            // Header Bar at menu bar height (flanking notch on left & right)
            HStack(spacing: 0) {
                // Left Wing Active Tabs
                HStack(spacing: 3) {
                    ForEach(settingsManager.activeLeftTabs) { tab in
                        tabButton(for: tab)
                    }
                }
                .padding(.leading, 10)

                // Middle Gap for Physical Camera Notch
                Spacer(minLength: controller.notchWidth + 14)

                // Right Wing Settings Button & Collapse Button
                HStack(spacing: 3) {
                    Button(action: {
                        SettingsWindowManager.shared.showSettingsWindow()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11, weight: .semibold))
                            if settingsManager.showTabLabels {
                                Text("Settings")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, settingsManager.showTabLabels ? 10 : 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 28)
                        .foregroundColor(Color.white.opacity(0.45))
                        .cornerRadius(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        controller.setExpanded(false)
                    }) {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.4))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
                .padding(.trailing, 10)
            }
            .frame(height: max(controller.notchHeight, 32))

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Content Area (Dropdown below notch)
            Group {
                switch controller.selectedTab {
                case .spotify:
                    MediaPlayerView()
                case .clipboard:
                    ClipboardView()
                case .fileShelf:
                    FileShelfView()
                case .power:
                    BatteryView()
                case .todoist:
                    TodoistView()
                default:
                    MediaPlayerView()
                }
            }
        }
    }

    private func tabButton(for tab: NotchTab) -> some View {
        Button(action: {
            controller.selectedTab = tab
        }) {
            HStack(spacing: 5) {
                Image(systemName: tab.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                if settingsManager.showTabLabels {
                    Text(tab.title)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .padding(.horizontal, settingsManager.showTabLabels ? 10 : 8)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(
                controller.selectedTab == tab
                    ? Color.white.opacity(0.16)
                    : Color.clear
            )
            .foregroundColor(
                controller.selectedTab == tab
                    ? Color.white
                    : Color.white.opacity(0.45)
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Custom Shape for asymmetric corner radii (top flat, bottom rounded)
public struct RoundedCornerShape: Shape {
    public var topLeft: CGFloat
    public var topRight: CGFloat
    public var bottomLeft: CGFloat
    public var bottomRight: CGFloat

    public func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height

        let tr = min(min(self.topRight, h/2), w/2)
        let tl = min(min(self.topLeft, h/2), w/2)
        let bl = min(min(self.bottomLeft, h/2), w/2)
        let br = min(min(self.bottomRight, h/2), w/2)

        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        path.closeSubpath()

        return path
    }
}
