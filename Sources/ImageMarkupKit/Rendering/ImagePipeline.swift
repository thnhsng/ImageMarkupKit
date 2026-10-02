import ImageIO
import UIKit

/// Size and orientation of an image file, read without decoding pixels.
public struct ImageMetadata: Equatable, Sendable {
    /// Pixel size after applying the EXIF orientation.
    public var pixelSize: CGSize
    /// EXIF orientation (1…8).
    public var orientation: UInt32
    public var typeIdentifier: String?
}

/// ImageIO-based decoding. Never decodes a full camera photo when a smaller version will do.
enum ImagePipeline {
    static func metadata(at url: URL) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return metadata(of: source)
    }

    static func metadata(of data: Data) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return metadata(of: source)
    }

    private static func metadata(of source: CGImageSource) -> ImageMetadata? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
        else { return nil }
        var orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
        if orientation == nil, let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            orientation = (tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.uint32Value
        }
        let exif = orientation ?? 1
        // Orientations 5–8 rotate by 90°, so the displayed width and height swap.
        let swapped = (5...8).contains(exif)
        let size = swapped ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        return ImageMetadata(pixelSize: size, orientation: exif, typeIdentifier: CGImageSourceGetType(source) as String?)
    }

    /// Upright image whose longest side is at most `maxPixelSize` (never upscaled).
    static func downsample(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source, maxPixelSize: maxPixelSize)
    }

    static func downsample(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return downsample(source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(_ source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            // Without "Always", ImageIO may return the tiny embedded EXIF thumbnail.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxPixelSize.rounded(.up)), 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Decoded display images, bounded by memory cost and purged on memory warnings.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    /// At most two decodes at a time: each camera photo briefly needs tens of MB while being downsampled.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ImageMarkupKit.ImageCache"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var observer: NSObjectProtocol?

    init(costLimit: Int = 256 * 1024 * 1024) {
        cache.totalCostLimit = costLimit
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [cache] _ in
            cache.removeAllObjects()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private static func key(_ url: URL, _ maxPixelSize: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixelSize))" as NSString
    }

    func cachedImage(for url: URL, maxPixelSize: CGFloat) -> UIImage? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    /// Decodes off the main thread; `completion` runs on the main queue.
    func loadImage(for url: URL, maxPixelSize: CGFloat, completion: @escaping @MainActor (UIImage?) -> Void) {
        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        queue.addOperation { [cache] in
            let image = ImagePipeline.downsample(at: url, maxPixelSize: maxPixelSize).map { UIImage(cgImage: $0) }
            if let image, let cgImage = image.cgImage {
                cache.setObject(image, forKey: Self.key(url, maxPixelSize), cost: cgImage.bytesPerRow * cgImage.height)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
