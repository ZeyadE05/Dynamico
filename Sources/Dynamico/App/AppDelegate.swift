import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set accessory policy to run as lightweight menu bar / notch utility
        NSApp.setActivationPolicy(.accessory)

        // Initialize notch panel controller, idle coordinator, and system HUD monitor
        _ = NotchPanelController.shared
        _ = IdleCoordinator.shared
        _ = SystemHUDMonitor.shared
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
