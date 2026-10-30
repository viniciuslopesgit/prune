import SwiftUI

/// Opens the main window from anywhere (menu bar, Dock, AppDelegate).
/// macOS 13 or later: keeps SwiftUI's `openWindow` action. macOS 12 has no `Window` scene,
/// so the main window is an AppKit window that hosts ContentView.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var action: ((String) -> Void)?
    private var legacyWindow: NSWindow?

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Prune" }
    }

    func openMain() {
        NSApp.setActivationPolicy(.regular)
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
        } else if let action {
            action("main")
        } else {
            makeLegacyWindow().makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeLegacyWindow() -> NSWindow {
        if let legacyWindow { return legacyWindow }
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1180, height: 760),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.identifier = NSUserInterfaceItemIdentifier("main")
        w.title = "Prune"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: MainWindowContent())
        w.setContentSize(CGSize(width: 1180, height: 760))
        w.center()
        w.setFrameAutosaveName("PruneMain")
        legacyWindow = w
        return w
    }
}

/// The main window's root, shared by the SwiftUI scene and the macOS 12 AppKit window.
struct MainWindowContent: View {
    var body: some View {
        ContentView()
            .frame(minWidth: 1040, minHeight: 680)
            .tint(Theme.leaf)
            .capturesOpenWindow()
    }
}

extension View {
    /// Hands SwiftUI's `openWindow` to WindowOpener (macOS 13 or later).
    @ViewBuilder
    func capturesOpenWindow() -> some View {
        if #available(macOS 13, *), !PruneMain.legacyUI { modifier(OpenWindowCapture()) } else { self }
    }
}

@available(macOS 13, *)
private struct OpenWindowCapture: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onAppear { WindowOpener.shared.action = { openWindow(id: $0) } }
    }
}
