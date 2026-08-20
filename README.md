# Dynamico 🚀

**Dynamico** is a native, ultra-lightweight macOS menu bar utility that transforms your MacBook's camera notch (or top screen area) into an interactive, fluid productivity dashboard.

Built entirely in **SwiftUI** and **AppKit**, Dynamico morphs seamlessly from the notch when hovered or clicked, providing instant access to media controls, task management, clipboard history, file staging, and power diagnostics—without interrupting your workflow.

---

## 🌟 Key Features

* 🎵 **System-Wide Media Player (Zero-OAuth)**
  * Displays whatever media is currently playing across macOS (**Spotify**, **Apple Music**, **Safari/Chrome**, **Podcasts**, **Apple TV**, etc.).
  * Automatic priority detection: prioritizes Spotify when running and active.
  * Real-time track metadata, interactive progress bar, system volume control, and animated audio equalizer visualizer.
  * **Zero Setup Required**: Uses native macOS `MediaRemote` and AppleScript for instant playback control without Spotify Developer API keys or OAuth logins.

* 📝 **Todoist Task Manager**
  * Quick-add tasks directly to your Todoist Inbox.
  * View active task lists with color-coded priority indicators and due dates.
  * One-click task completion with instant haptic feedback.

* 📋 **Clipboard History Manager**
  * Passive clipboard history tracking with color inspector, URL badges, and image previews.
  * Searchable text snippets for instant retrieval.
  * One-click copy back to active pasteboard with subtle haptic confirmation.

* 📥 **File Shelf (Staging Area)**
  * Drag-and-drop file staging target under the notch.
  * Temporarily stage images, documents, or archives before moving them to another app.
  * Previews system file icons (`NSWorkspace`) and supports dragging staged items directly back out to Finder, Slack, or email.

* ⚡ **Power Diagnostics**
  * Real-time battery percentage, charging state, thermal state, and power source indicators.

* 🎨 **Design System & Interaction Physics**
  * Centralized `Theme` design system with brand accents, surface opacity standards, and pointer-cursor hover feedback.
  * Native macOS `NSHapticFeedbackManager` triggers on snaps, drops, and tab transitions.
  * Smooth `0.18s` layer crossfade and scale transform tab mounting.

---

## 💻 System Requirements

* **OS:** macOS 13.0 (Ventura) or later.
* **Architecture:** Universal (Apple Silicon M1/M2/M3/M4 & Intel Macs).
* **Hardware:** Optimized for MacBook camera notch displays, but fully functional on non-notch Mac screens.

---

## 🛠️ Building & Installation

### Option 1: Automated Release Build & Install (Recommended)

1. Clone the repository:
   ```bash
   git clone https://github.com/ZeyadE05/Dynamico.git
   cd Dynamico
   ```

2. Run the automated build script:
   ```bash
   chmod +x build_app.sh
   ./build_app.sh
   ```
   *This script compiles the release binary via SwiftPM, packages the `Dynamico.app` bundle, installs it directly into `/Applications`, and registers it with LaunchServices.*

3. Launch **Dynamico** from your `/Applications` folder or Spotlight (`Cmd + Space` -> *Dynamico*).

---

### Option 2: Swift Package Manager CLI

```bash
# Build debug binary
swift build

# Build release binary
swift build -c release
```

The compiled executable will be output to `.build/release/Dynamico`.

---

## 🔑 Configuration

After launching Dynamico:

1. **Media Player:** Works automatically out of the box for Spotify, Apple Music, and web media. No login or Client ID configuration required!
2. **Todoist Integration (Optional):**
   * Obtain your personal API Token from [Todoist Settings > Integrations](https://todoist.com/app/settings/integrations).
   * Enter your token in the Todoist tab or Settings window to sync your tasks.

---

## 🛠️ Architecture & Tech Stack

* **Language:** Swift 5.9+
* **Frameworks:** SwiftUI, AppKit, Combine, Foundation, Security (Keychain), `MediaRemote.framework`
* **Windowing:** Custom floating `NSPanel` with elevated floating layer level (`.floating`) and GPU-accelerated `CASpringAnimation` layer container.
* **Audio & Media:** Dynamic loading of macOS `MediaRemote` private framework with native AppleScript control fallbacks.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
