import AppKit
import ImageIO
import SwiftUI

/// Miniaturas de imagens, descodificadas já no tamanho final.
/// Abrir uma fotografia de 48 MP com `NSImage(contentsOf:)` ocupa ~190 MB descodificada;
/// uma miniatura de 400 px ocupa ~0,6 MB.
enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func cached(_ url: URL, maxPixel: Int) -> NSImage? {
        cache.object(forKey: "\(maxPixel)|\(url.path)" as NSString)
    }

    static func load(_ url: URL, maxPixel: Int) -> NSImage? {
        let key = "\(maxPixel)|\(url.path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        return autoreleasepool {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
            return image
        }
    }

    static func clear() { cache.removeAllObjects() }
}

/// Mostra a miniatura (carregada fora da thread principal) ou o ícone do ficheiro.
struct ThumbnailView: View {
    let url: URL
    var maxPixel = 400
    var iconSize: CGFloat = 64
    var fill = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                FileIcon(url: url, size: iconSize)
            }
        }
        .task(id: url) {
            if let hit = Thumbnails.cached(url, maxPixel: maxPixel) { image = hit; return }
            let url = url, maxPixel = maxPixel
            image = await Task.detached(priority: .utility) { Thumbnails.load(url, maxPixel: maxPixel) }.value
        }
    }
}
