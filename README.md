# Dynamico 🚀

**Dynamico** is a native, lightweight macOS menu bar utility that transforms your MacBook's camera notch (or top screen area) into an interactive productivity dashboard. 

Built completely in **SwiftUI** and **AppKit**, Dynamico expands smoothly from the notch when hovered or clicked, giving you instant access to media controls, task management, clipboard history, file staging, and power monitoring—without interrupting your workflow.

---

## 🌟 Key Features

* 🎵 **Spotify Media Controls**
  * Full player control directly under the notch (Play, Pause, Skip, Previous).
  * Real-time track progress slider and volume control.
  * Album artwork rendering and live metadata display.
  * OAuth 2.0 Web API authentication stored securely in macOS Keychain.

* 📝 **Todoist Task Manager**
  * Quick-add tasks directly to your Todoist Inbox.
  * View active task list with priority indicators and due dates.
  * One-click task completion (`/close` endpoint integration).

* 📋 **Clipboard Manager**
  * Automatic clipboard history tracking.
  * Searchable text snippets for quick retrieval.
  * One-click re-copy back to active clipboard.

* 📥 **File Shelf (Staging Area)**
  * Drag-and-drop file staging area under the notch.
  * Temporarily store images, documents, or archives before moving them to another app.
  * Drag staged items directly out of the notch to Finder, emails, or chat apps.

* ⚡ **Battery & Power Monitor**
  * Real-time battery percentage and charging state.
  * Thermal state and power source indicator.

* ⚙️ **Customizable Settings & Layout**
  * Toggle tab visibility (Spotify, Todoist, Clipboard, Shelf, Power).
  * Toggle icon labels in the notch header bar.
  * Manage API credentials safely via native Settings window.

---

## 💻 System Requirements

* **OS:** macOS 13.0 (Ventura) or later.
* **Architecture:** Universal (Apple Silicon M1/M2/M3/M4 & Intel Macs).
* **Hardware:** Designed for MacBook camera notch screens, but fully functional on non-notch Mac displays.

---

## 🛠️ Building & Installation

### Option 1: Automated Build & Install (Recommended)

1. Clone the repository:
   ```bash
   git clone https://github.com/ZeyadE05/Dynamico.git
   cd Dynamico
   ```

2. Make the build script executable and run it:
   ```bash
   chmod +x build_app.sh
   ./build_app.sh
   ```
   *This script compiles the release binary using SwiftPM, packages the `Dynamico.app` bundle, installs it directly into `/Applications`, and registers it with LaunchServices.*

3. Launch **Dynamico** from your `/Applications` folder or Spotlight (`Cmd + Space` -> *Dynamico*).

---

### Option 2: Swift Package Manager CLI

If you only want to build the executable binary:

```bash
# Build debug binary
swift build

# Build release binary
swift build -c release
```

The compiled binary will be located in `.build/release/Dynamico`.

---

## 🔑 Initial Configuration

After launching Dynamico for the first time:

1. Click the **Gear icon (Settings)** in the expanded notch panel or menu bar icon.
2. **Spotify Integration:**
   * Create an application in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
   * Add `notchnook://spotify-callback` to your Spotify App's **Redirect URIs**.
   * Copy your **Client ID** into Dynamico Settings and click **Connect Spotify**.
3. **Todoist Integration:**
   * Grab your API Token from [Todoist Settings > Integrations](https://todoist.com/app/settings/integrations).
   * Paste your token into Dynamico Settings and click **Save Token**.

---

## 🛠️ Architecture & Tech Stack

* **Language:** Swift 5.9+
* **Frameworks:** SwiftUI, AppKit, Combine, Foundation, Security (Keychain)
* **Windowing:** Custom floating `NSPanel` with borderless transparent canvas, level elevated to `.floating`, tracking mouse hover events.
* **Security:** Sensitive tokens (Spotify OAuth Token, Todoist API Token) stored via macOS Keychain Services (`SecItemAdd` / `SecItemCopyMatching`).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check out the [Issues page](https://github.com/ZeyadE05/Dynamico/issues).
