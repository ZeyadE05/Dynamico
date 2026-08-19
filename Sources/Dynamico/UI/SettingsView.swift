import SwiftUI
import ServiceManagement

public enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case modules = "Modules"
    case integrations = "Integrations"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .modules: return "square.grid.2x2"
        case .integrations: return "link"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var authManager = SpotifyAuthManager.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var todoistClient = TodoistAPIClient.shared

    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLogin: Bool = false
    @State private var todoistTokenInput: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Tab Header Bar
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? Color.white.opacity(0.14)
                                : Color.clear
                        )
                        .foregroundColor(
                            selectedTab == tab
                                ? Color.white
                                : Color.white.opacity(0.45)
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Tab Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .general:
                        generalTabContent
                    case .modules:
                        modulesTabContent
                    case .integrations:
                        integrationsTabContent
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 14/255, green: 14/255, blue: 18/255))
        .onAppear {
            checkLaunchAtLoginStatus()
            todoistTokenInput = todoistClient.apiToken
        }
    }

    // MARK: - General Tab
    private var generalTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Launch at Login
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                    Text("Automatically open Dynamico when starting your Mac")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))
                }

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(enabled: newValue)
                    }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Appearance & Notch Layout
            VStack(alignment: .leading, spacing: 10) {
                Text("Notch Appearance & Layout")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.9))

                customToggle(
                    title: "Show Tab Text Titles",
                    subtitle: "Disable for ultra-compact Icon-Only mode in notch bar",
                    isOn: $settingsManager.showTabLabels
                )

                Divider().background(Color.white.opacity(0.08))

                // Custom Width Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Expanded Notch Width")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))
                        Spacer()
                        Text("\(Int(settingsManager.customWidth)) pt")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0, green: 210/255, blue: 255/255))
                    }

                    Slider(value: $settingsManager.customWidth, in: 480...920, step: 20)
                        .tint(Color(red: 0, green: 210/255, blue: 255/255))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Application Control
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Application Control")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                    Text("Terminate and close Dynamico process")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))
                }

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .bold))
                        Text("Quit App")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.18))
                    .foregroundColor(.red)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: - Modules Tab
    private var modulesTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Notch Modules")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.white.opacity(0.9))

            VStack(spacing: 8) {
                customToggle(title: "Spotify Player Tab", subtitle: "Playback deck & mini album art", isOn: $settingsManager.showSpotifyTab)
                customToggle(title: "Clipboard History Tab", subtitle: "Passive pasteboard & color inspector", isOn: $settingsManager.showClipboardTab)
                customToggle(title: "File Shelf Tab", subtitle: "Drag-and-drop file staging zone", isOn: $settingsManager.showFileShelfTab)
                customToggle(title: "Power Diagnostics Tab", subtitle: "Battery health & top energy consumers", isOn: $settingsManager.showPowerTab)
                customToggle(title: "Todoist Task Manager Tab", subtitle: "Active tasks, quick add & checkmarks", isOn: $settingsManager.showTodoistTab)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Integrations Tab
    private var integrationsTabContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Spotify API Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                        Text("Spotify Integration")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.9))
                    }

                    Spacer()

                    Button(action: {
                        if let url = URL(string: "https://developer.spotify.com/dashboard") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Open Dashboard")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Client ID")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))

                    TextField("Paste Spotify Client ID here", text: $authManager.clientID)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Redirect URI")
                            .font(.system(size: 9))
                            .foregroundColor(Color.white.opacity(0.45))
                        Spacer()
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(authManager.redirectURI, forType: .string)
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy URI")
                            }
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(red: 29/255, green: 185/255, blue: 84/255))
                        }
                        .buttonStyle(.plain)
                        .help("Copy redirect URI to paste into Spotify Developer Dashboard settings")
                    }

                    TextField("notchnook://callback", text: $authManager.redirectURI)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                if let error = authManager.authError {
                    Text(error)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }

                HStack {
                    if authManager.isAuthenticated {
                        Button(action: {
                            authManager.logout()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Disconnect Spotify")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            Task {
                                try? await authManager.startPKCEAuth()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("Connect Account")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 29/255, green: 185/255, blue: 84/255))
                            .foregroundColor(.black)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Todoist API Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255))
                        Text("Todoist Integration")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.9))
                    }

                    Spacer()

                    Button(action: {
                        if let url = URL(string: "https://todoist.com/app/settings/integrations") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Get API Token")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(red: 228/255, green: 71/255, blue: 62/255))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Personal API Token")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.45))

                    SecureField("Paste Todoist API Token here", text: $todoistTokenInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                if let error = todoistClient.errorMessage {
                    Text(error)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }

                HStack {
                    if todoistClient.isAuthenticated {
                        Button(action: {
                            todoistClient.disconnect()
                            todoistTokenInput = ""
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Disconnect Todoist")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.red.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {
                            Task {
                                await todoistClient.saveToken(todoistTokenInput)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                Text("Connect Account")
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 228/255, green: 71/255, blue: 62/255))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(todoistTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func customToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(Color.white.opacity(0.4))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.7)
        }
    }

    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Launch at login error: \(error)")
            }
        }
    }
}
