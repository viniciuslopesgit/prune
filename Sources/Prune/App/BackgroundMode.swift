import AppKit

/// Decides how the app keeps running in the background (like WireGuard): with the menu bar monitor on,
/// closing the window or choosing Quit in the Dock only hides the app (no Dock icon) instead of ending it.
/// Only the menu bar's Quit button (or a relaunch) really ends it.
enum BackgroundMode {
    /// Set right before an explicit quit, so `applicationShouldTerminate` lets it through.
    @MainActor static var quitRequested = false

    /// Whether a quit request really ends the app or just sends it to the background.
    static func shouldTerminate(menuBarEnabled: Bool, explicitQuit: Bool) -> Bool {
        explicitQuit || !menuBarEnabled
    }

    /// The Dock icon is shown only while the main window is open (or when there is no menu bar to fall back on).
    static func activationPolicy(mainWindowVisible: Bool, menuBarEnabled: Bool) -> NSApplication.ActivationPolicy {
        mainWindowVisible || !menuBarEnabled ? .regular : .accessory
    }

    static var menuBarEnabled: Bool {
        UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true
    }

    /// Ends the app for real.
    @MainActor static func quit() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    /// Hides the window and the Dock icon; the app keeps running in the menu bar.
    @MainActor static func sendToBackground() {
        WindowOpener.shared.mainWindow?.close()
        NSApp.setActivationPolicy(activationPolicy(mainWindowVisible: false, menuBarEnabled: menuBarEnabled))
    }
}
