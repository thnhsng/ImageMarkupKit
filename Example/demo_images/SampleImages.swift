import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Sample photos for simulator demos and screenshots, bundled in `SamplePhotos/` (Unsplash, see README).
/// Written once to Caches/Samples as camera-sized JPEGs; one is stored rotated with EXIF orientation 6
/// to exercise orientation handling.
enum SampleImages {
    struct Spec {
        let name: String
        /// Bundled JPEG (without extension), drawn aspect-fill.
        let photo: String
        /// Displayed (upright) pixel size.
        let size: CGSize
        let exifOrientation: Int
    }

    static let specs: [Spec] = [
        Spec(name: "trip-a", photo: "mountain-lake", size: CGSize(width: 4032, height: 3024), exifOrientation: 1),
        Spec(name: "trip-b", photo: "paris", size: CGSize(width: 3024, height: 4032), exifOrientation: 6),
        Spec(name: "trip-c", photo: "stockholm", size: CGSize(width: 4000, height: 1500), exifOrientation: 1),
        Spec(name: "trip-d", photo: "new-york", size: CGSize(width: 3024, height: 4032), exifOrientation: 1),
    ]

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Samples", isDirectory: true)
    }

    /// URLs of the sample JPEGs, generating any that are missing.
    static func urls() -> [URL] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return specs.map { spec in
            let url = directory.appendingPathComponent("\(spec.name).jpg")
            if !FileManager.default.fileExists(atPath: url.path) {
                write(spec, to: url)
            }
            return url
        }
    }

    private static func write(_ spec: Spec, to url: URL) {
        let upright = draw(spec)
        let stored: UIImage
        if spec.exifOrientation == 6 {
            // Stored pixels are the upright image rotated 90° counter-clockwise; EXIF 6 rotates it back.
            let storedSize = CGSize(width: spec.size.height, height: spec.size.width)
            stored = renderer(size: storedSize).image { context in
                context.cgContext.concatenate(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: spec.size.width))
                upright.draw(at: .zero)
            }
        } else {
            stored = upright
        }
        guard
            let cgImage = stored.cgImage,
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: spec.exifOrientation,
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// The bundled photo scaled to fill `spec.size`, cropped to the center.
    private static func draw(_ spec: Spec) -> UIImage {
        let url = Bundle.main.url(forResource: spec.photo, withExtension: "jpg")
            ?? Bundle.main.url(forResource: spec.photo, withExtension: "jpg", subdirectory: "SamplePhotos")
        let photo = url.flatMap { UIImage(contentsOfFile: $0.path) }
        let size = spec.size
        return renderer(size: size).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            guard let photo, photo.size.width > 0, photo.size.height > 0 else { return }
            let scale = max(size.width / photo.size.width, size.height / photo.size.height)
            let drawn = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
    }
}
