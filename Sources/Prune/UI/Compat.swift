import SwiftUI

/// SwiftUI's @State property wrapper. Newer SDKs also declare a `@State` macro whose plugin
/// the Command Line Tools do not ship; through this alias the compiler always picks the
/// property wrapper, which exists on every supported macOS.
typealias ViewState = SwiftUI.State

/// Modifiers that only exist from macOS 13. On macOS 12 they do nothing (the look is
/// slightly plainer, the behavior is the same).
extension View {
    @ViewBuilder
    func hiddenScrollBackground() -> some View {
        if #available(macOS 13, *) { scrollContentBackground(.hidden) } else { self }
    }

    @ViewBuilder
    func hiddenRowSeparator() -> some View {
        if #available(macOS 13, *) { listRowSeparator(.hidden) } else { self }
    }

    @ViewBuilder
    func groupedFormStyle() -> some View {
        if #available(macOS 13, *) { formStyle(.grouped) } else { self }
    }
}

enum Snapshot {
    /// Draws a SwiftUI view into an image. ImageRenderer only exists from macOS 13;
    /// on macOS 12 the view is drawn through an NSHostingView.
    @MainActor
    static func image<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2) -> NSImage {
        if #available(macOS 13, *) {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = scale
            if let image = renderer.nsImage { return image }
        }
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return NSImage(size: size) }
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
