import AppKit
import SwiftUI
import ServiceManagement

@MainActor
public final class StatusItemManager: NSObject {
    public static let shared = StatusItemManager()

    private var statusItem: NSStatusItem?

    override private init() {
        super.init()
        setupStatusItem()
    }

    public func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Dynamico")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = statusItem
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            openMenu()
        } else {
            NotchPanelController.shared.toggleExpand()
        }
    }

    public func openMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: NotchPanelController.shared.isExpanded ? "Collapse Notch" : "Expand Notch", action: #selector(toggleNotch), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Spotify Auth Option
        let spotifyTitle = SpotifyAuthManager.shared.isAuthenticated ? "Disconnect Spotify Account" : "Connect Spotify Account"
        let spotifyItem = NSMenuItem(title: spotifyTitle, action: #selector(toggleSpotifyAuth), keyEquivalent: "")
        spotifyItem.target = self
        menu.addItem(spotifyItem)

        // Settings Option
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit Option
        let quitItem = NSMenuItem(title: "Quit Dynamico", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // Reset so primary click stays custom toggle
    }

    @objc private func toggleNotch() {
        NotchPanelController.shared.toggleExpand()
    }

    @objc private func toggleSpotifyAuth() {
        Task {
            if SpotifyAuthManager.shared.isAuthenticated {
                SpotifyAuthManager.shared.logout()
            } else {
                if SpotifyAuthManager.shared.clientID.isEmpty {
                    SettingsWindowManager.shared.showSettingsWindow()
                } else {
                    try? await SpotifyAuthManager.shared.startPKCEAuth()
                }
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettingsWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
