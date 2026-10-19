import ImageIO
import SwiftUI
import UIKit

/// Images from the network, decoded at the size they are shown rather than full size, and kept in memory.
/// Downloads go through URLSession.shared, so the disk cache set up in `configureURLCache` applies.
enum ImageLoader {
    // NSCache is thread-safe.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 60 * 1024 * 1024
        return c
    }()

    static func cached(_ url: URL, maxPixels: Int) -> UIImage? {
        cache.object(forKey: key(url, maxPixels))
    }

    static func load(_ url: URL, maxPixels: Int) async throws -> UIImage {
        if let hit = cached(url, maxPixels: maxPixels) { return hit }
        let (data, _) = try await URLSession.shared.data(from: url)
        let image = try await Task.detached(priority: .userInitiated) { try downsample(data, maxPixels: maxPixels) }.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key(url, maxPixels), cost: cost)
        return image
    }

    private static func key(_ url: URL, _ maxPixels: Int) -> NSString { "\(maxPixels)|\(url.absoluteString)" as NSString }

    /// Decodes straight to a thumbnail no larger than `maxPixels` on its long side.
    nonisolated static func downsample(_ data: Data, maxPixels: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary)
        else { throw URLError(.cannotDecodeContentData) }
        return UIImage(cgImage: cg)
    }

    /// A bigger shared cache than the default (512 KB memory, about 20 MB disk), so Library photos and
    /// feed responses survive between visits. Responses over 5% of the disk size are never stored.
    static func configureURLCache() {
        URLCache.shared = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }
}

/// A remote image decoded for `points` (the longer side it is drawn at), with a placeholder while loading.
struct RemoteImage<Placeholder: View>: View {
    var url: URL?
    var points: CGFloat
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    private var maxPixels: Int { Int(points * scale) }

    var body: some View {
        Group {
            if let image = image ?? url.flatMap({ ImageLoader.cached($0, maxPixels: maxPixels) }) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            image = try? await ImageLoader.load(url, maxPixels: maxPixels)
        }
    }
}

/// Recent feed results kept in memory, so switching tabs or views doesn't refetch them.
/// Pull to refresh bypasses it.
@MainActor
enum FeedMemo {
    private static var store: [String: (at: Date, value: Any)] = [:]

    static func get<T>(_ key: String, maxAge: TimeInterval) -> T? {
        guard let hit = store[key], Date.now.timeIntervalSince(hit.at) < maxAge else { return nil }
        return hit.value as? T
    }

    static func set(_ key: String, _ value: Any) { store[key] = (.now, value) }
}
