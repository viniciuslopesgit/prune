import SwiftUI
import Combine

/// The menu bar monitor on macOS 12, which has no MenuBarExtra: an NSStatusItem that opens
/// MenuBarView in a popover. Follows the "showMenuBar" setting like MenuBarExtra(isInserted:).
@MainActor
final class LegacyMenuBar: NSObject {
    static let shared = LegacyMenuBar()
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions: Set<AnyCancellable> = []

    func start() {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
        SystemStats.shared.$cpu
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu in self?.item?.button?.title = Self.title(cpu: cpu) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)
        sync()
    }

    var isInstalled: Bool { item != nil }

    nonisolated static func title(cpu: Double) -> String { " \(Int(cpu * 100))%" }

    private func sync() {
        if BackgroundMode.menuBarEnabled, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = MenuBarLabel.leafTemplate
            item.button?.imagePosition = .imageLeading
            item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            item.button?.title = Self.title(cpu: SystemStats.shared.cpu)
            item.button?.target = self
            item.button?.action = #selector(toggle(_:))
            self.item = item
        } else if !BackgroundMode.menuBarEnabled, let item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
