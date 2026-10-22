import SwiftUI

@main
struct PruneApp: App {
    @State private var state = AppState.shared
    @AppStorage("showMenuBar") private var showMenuBar = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        LegacyMigration.run()
        SelfTest.fdaCheckIfRequested()
        SelfTest.runIfRequested()
        MemoryBench.runIfRequested()
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
        // Segue o aspeto do sistema (claro/escuro). PRUNE_APPEARANCE=light|dark força um deles (capturas).
        switch ProcessInfo.processInfo.environment["PRUNE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private var memoryPressure: DispatchSourceMemoryPressure?
    private var windowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Liberta resultados pesados quando a janela principal fecha (a app fica na barra de menus)…
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            // A notificação chega na fila principal (queue: .main); o Task torna isso explícito.
            Task { @MainActor in
                guard let closing, closing === WindowOpener.shared.mainWindow else { return }
                AppState.shared.releaseHeavyResults()
            }
        }
        // …e quando o sistema avisa que a memória está a acabar.
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { Task { @MainActor in AppState.shared.releaseHeavyResults() } }
        source.resume()
        memoryPressure = source

        Task { @MainActor in Analytics.track("app_open") }

        // Abre sempre a janela principal ao iniciar (mesmo que tenha sido fechada na última sessão).
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
