import SwiftUI

/// Keeps SwiftUI's `openWindow` action so it can be used outside views.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var action: OpenWindowAction?

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Prune" }
    }

    func openMain() {
        NSApp.setActivationPolicy(.regular)
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
        } else {
            action?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
