import SwiftUI

@main
struct PruneApp: App {
    @State private var state = AppState.shared
    @AppStorage("showMenuBar") private var showMenuBar = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // The diagnostic tools start only once the main run loop is running. Started from here, their
        // background scans could touch AppKit (e.g. NSWorkspace) before the main event queue exists,
        // and on macOS 14 AppKit then stops the app (_NSAssertMainEventQueueIsCurrentEventQueue).
        DispatchQueue.main.async {
            SelfTest.fdaCheckIfRequested()
            SelfTest.runIfRequested()
            MemoryBench.runIfRequested()
        }
    }

    var body: some Scene {
        Window("Prune", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1040, minHeight: 680)
                .tint(Theme.leaf)
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
                .environment(state)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
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
            }
        }
        // …and when the system warns that memory is running low.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { Task { @MainActor in AppState.shared.releaseHeavyResults() } }
        source.resume()
        memoryPressure = source

        Task { @MainActor in Analytics.track("app_open") }

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
        UserDefaults.standard.object(forKey: "showMenuBar") as? Bool == false
    }
}
