import SwiftUI

/// macOS 13 or later runs the SwiftUI scenes (Window, MenuBarExtra). macOS 12 has neither,
/// so it runs PruneLegacyApp: the main window and the menu bar monitor come from AppKit.
/// PRUNE_LEGACY_UI=1 forces the macOS 12 path on newer systems (CI tests it this way).
@main
enum PruneMain {
    static let legacyUI: Bool = {
        if #available(macOS 13, *) { return usesLegacyUI(hasSceneAPIs: true, environment: ProcessInfo.processInfo.environment) }
        return true
    }()

    static func usesLegacyUI(hasSceneAPIs: Bool, environment: [String: String]) -> Bool {
        !hasSceneAPIs || environment["PRUNE_LEGACY_UI"] == "1"
    }

    static func main() {
        if #available(macOS 13, *), !legacyUI {
            PruneApp.main()
        } else {
            PruneLegacyApp.main()
        }
    }

    static func startDiagnostics() {
        // The diagnostic tools start only once the main run loop is running. Started from here, their
        // background scans could touch AppKit (e.g. NSWorkspace) before the main event queue exists,
        // and on macOS 14 AppKit then stops the app (_NSAssertMainEventQueueIsCurrentEventQueue).
        DispatchQueue.main.async {
            SelfTest.fdaCheckIfRequested()
            SelfTest.runIfRequested()
            MemoryBench.runIfRequested()
        }
    }
}

@available(macOS 13, *)
struct PruneApp: App {
    @AppStorage("showMenuBar") private var showMenuBar = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { PruneMain.startDiagnostics() }

    var body: some Scene {
        Window("Prune", id: "main") {
            MainWindowContent()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// macOS 12: only the Settings scene comes from SwiftUI; WindowOpener creates the main
/// window and LegacyMenuBar the menu bar monitor.
struct PruneLegacyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { PruneMain.startDiagnostics() }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Follows the system appearance (light/dark). PRUNE_APPEARANCE=light|dark forces one of them (screenshots).
        switch ProcessInfo.processInfo.environment["PRUNE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private var memoryPressure: DispatchSourceMemoryPressure?
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Frees heavy results when the main window closes (the app stays in the menu bar)…
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            // The notification arrives on the main queue (queue: .main); the Task makes that explicit.
            Task { @MainActor in
                guard let closing, closing === WindowOpener.shared.mainWindow else { return }
                AppState.shared.releaseHeavyResults()
                // Hides the Dock icon: the app keeps running in the menu bar.
                NSApp.setActivationPolicy(BackgroundMode.activationPolicy(mainWindowVisible: false, menuBarEnabled: BackgroundMode.menuBarEnabled))
            }
        }
        // …and when the system warns that memory is running low.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { Task { @MainActor in AppState.shared.releaseHeavyResults() } }
        source.resume()
        memoryPressure = source

        Task { @MainActor in Analytics.track("app_open") }

        if PruneMain.legacyUI {
            Task { @MainActor in LegacyMenuBar.shared.start() }
        }

        // Always opens the main window on launch (even if it was closed in the last session).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Task { @MainActor in
                if WindowOpener.shared.mainWindow?.isVisible != true { WindowOpener.shared.openMain() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Task { @MainActor in WindowOpener.shared.openMain() } }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !BackgroundMode.menuBarEnabled
    }

    /// Quit from the Dock or ⌘Q only sends the app to the background; the menu bar's Quit ends it.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if BackgroundMode.shouldTerminate(menuBarEnabled: BackgroundMode.menuBarEnabled, explicitQuit: BackgroundMode.quitRequested) {
            return .terminateNow
        }
        BackgroundMode.sendToBackground()
        return .terminateCancel
    }
}
