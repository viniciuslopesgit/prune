import SwiftUI

/// Guarda a ação `openWindow` do SwiftUI para a poder usar fora das vistas.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    var action: OpenWindowAction?

    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true || $0.title == "Prune" }
    }

    func openMain() {
        if let w = mainWindow {
            w.makeKeyAndOrderFront(nil)
        } else {
            action?(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
