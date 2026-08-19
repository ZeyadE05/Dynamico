import Foundation
import Combine
import SwiftUI

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    @Published public var showSpotifyTab: Bool = UserDefaults.standard.object(forKey: "show_tab_spotify") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showSpotifyTab, forKey: "show_tab_spotify")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var showClipboardTab: Bool = UserDefaults.standard.object(forKey: "show_tab_clipboard") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showClipboardTab, forKey: "show_tab_clipboard")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var showFileShelfTab: Bool = UserDefaults.standard.object(forKey: "show_tab_file_shelf") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showFileShelfTab, forKey: "show_tab_file_shelf")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var showPowerTab: Bool = UserDefaults.standard.object(forKey: "show_tab_power") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showPowerTab, forKey: "show_tab_power")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var showTodoistTab: Bool = UserDefaults.standard.object(forKey: "show_tab_todoist") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showTodoistTab, forKey: "show_tab_todoist")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var showTabLabels: Bool = UserDefaults.standard.object(forKey: "show_tab_labels") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showTabLabels, forKey: "show_tab_labels")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    @Published public var customWidth: Double = UserDefaults.standard.double(forKey: "custom_expanded_width") == 0 ? 680 : UserDefaults.standard.double(forKey: "custom_expanded_width") {
        didSet {
            UserDefaults.standard.set(customWidth, forKey: "custom_expanded_width")
            NotchPanelController.shared.updatePanelFrame(animated: true)
        }
    }

    private init() {}

    public var activeLeftTabs: [NotchTab] {
        var tabs: [NotchTab] = []
        if showSpotifyTab { tabs.append(.spotify) }
        if showClipboardTab { tabs.append(.clipboard) }
        if showFileShelfTab { tabs.append(.fileShelf) }
        if showPowerTab { tabs.append(.power) }
        if showTodoistTab { tabs.append(.todoist) }
        return tabs
    }
}
