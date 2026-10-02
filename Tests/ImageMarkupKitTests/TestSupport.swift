import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import ImageMarkupKit

enum TestSupport {
    static var temporaryDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImageMarkupKitTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a solid-color JPEG of the given stored pixel size and EXIF orientation.
    static func writeJPEG(width: Int, height: Int, color: UIColor = .gray, orientation: Int = 1, name: String = UUID().uuidString) -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let url = temporaryDirectory.appendingPathComponent("\(name).jpg")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.cgImage!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return url
    }

    struct RGBA: Equatable {
        var r: Int, g: Int, b: Int, a: Int

        func isClose(to other: RGBA, tolerance: Int = 12) -> Bool {
            abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance && abs(a - other.a) <= tolerance
        }
    }

    /// Reads one pixel (top-left origin).
    static func pixel(_ image: UIImage, x: Int, y: Int) -> RGBA {
        guard let cgImage = image.cgImage else { return RGBA(r: -1, g: -1, b: -1, a: -1) }
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Draw so that pixel (x, y) (top-left origin) lands on the 1×1 context.
        context.draw(cgImage, in: CGRect(x: -x, y: y - cgImage.height + 1, width: cgImage.width, height: cgImage.height))
        return RGBA(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]), a: Int(bytes[3]))
    }
}
