import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()

    private var windowController: NSWindowController?
    private var window: NSWindow?

    override private init() {
        super.init()
    }

    public func showSettingsWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .frame(minWidth: 540, minHeight: 640)
            .background(Color(red: 14/255, green: 14/255, blue: 18/255))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Dynamico Settings"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.delegate = self
        window.backgroundColor = NSColor(red: 14/255, green: 14/255, blue: 18/255, alpha: 1.0)
        window.isMovableByWindowBackground = true

        let wc = NSWindowController(window: window)
        self.windowController = wc
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        self.window = nil
        self.windowController = nil
    }
}
