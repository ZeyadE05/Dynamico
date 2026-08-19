import AppKit
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Set accessory policy to run as lightweight menu bar / notch utility
        NSApp.setActivationPolicy(.accessory)

        // Initialize notch panel controller
        _ = NotchPanelController.shared

        // Register custom URL scheme handler for OAuth callback
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // If Spotify OAuth callback URL received
        if url.scheme == "notchnook" || url.absoluteString.hasPrefix("notchnook://") {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                Task { @MainActor in
                    try? await SpotifyAuthManager.shared.exchangeCodeForTokens(code: code)
                }
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
