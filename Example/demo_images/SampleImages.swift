import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Synthetic "inspection photos" for simulator demos and screenshots.
/// Written once to Caches/Samples as camera-sized JPEGs; one is stored rotated with EXIF orientation 6
/// to exercise orientation handling.
enum SampleImages {
    struct Spec {
        let name: String
        let title: String
        /// Displayed (upright) pixel size.
        let size: CGSize
        let exifOrientation: Int
        let tint: UIColor
    }

    static let specs: [Spec] = [
        Spec(name: "sample-a", title: "A · Wall 4032×3024", size: CGSize(width: 4032, height: 3024), exifOrientation: 1, tint: .systemBlue),
        Spec(name: "sample-b", title: "B · Pillar (EXIF 6)", size: CGSize(width: 3024, height: 4032), exifOrientation: 6, tint: .systemGreen),
        Spec(name: "sample-c", title: "C · Panorama 4000×1500", size: CGSize(width: 4000, height: 1500), exifOrientation: 1, tint: .systemOrange),
        Spec(name: "sample-d", title: "D · Pipe 3024×4032", size: CGSize(width: 3024, height: 4032), exifOrientation: 1, tint: .systemPurple),
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

    /// A concrete-wall scene with a crack, a grid, and a big label.
    private static func draw(_ spec: Spec) -> UIImage {
        let size = spec.size
        return renderer(size: size).image { context in
            let ctx = context.cgContext
            let colors = [UIColor(white: 0.82, alpha: 1).cgColor, UIColor(white: 0.62, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }

            // Panel grid.
            let unit = min(size.width, size.height) / 6
            ctx.setStrokeColor(UIColor(white: 0.5, alpha: 0.6).cgColor)
            ctx.setLineWidth(unit * 0.02)
            var x: CGFloat = 0
            while x < size.width { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)); x += unit * 1.5 }
            var y: CGFloat = 0
            while y < size.height { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)); y += unit }
            ctx.strokePath()

            // Tinted element (pipe / beam) and bolts.
            spec.tint.withAlphaComponent(0.55).setFill()
            ctx.fill(CGRect(x: 0, y: size.height * 0.62, width: size.width, height: unit * 0.55))
            UIColor(white: 0.25, alpha: 1).setFill()
            for i in 0..<6 {
                let cx = size.width * (0.1 + 0.16 * CGFloat(i))
                ctx.fillEllipse(in: CGRect(x: cx - unit * 0.08, y: size.height * 0.62 + unit * 0.19, width: unit * 0.16, height: unit * 0.16))
            }

            // Crack.
            ctx.setStrokeColor(UIColor(white: 0.12, alpha: 1).cgColor)
            ctx.setLineWidth(unit * 0.035)
            ctx.setLineJoin(.round)
            let crack = [(0.18, 0.12), (0.24, 0.2), (0.22, 0.28), (0.3, 0.36), (0.29, 0.45), (0.36, 0.52)]
            ctx.addLines(between: crack.map { CGPoint(x: size.width * $0.0, y: size.height * $0.1) })
            ctx.strokePath()

            // Label.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: unit * 0.42, weight: .heavy),
                .foregroundColor: UIColor(white: 0.1, alpha: 0.85),
                .paragraphStyle: paragraph,
            ]
            let labelRect = CGRect(x: 0, y: size.height * 0.8, width: size.width, height: unit)
            (spec.title as NSString).draw(in: labelRect, withAttributes: attributes)

            // Orientation marker: an arrow pointing up in the upright image.
            ctx.setFillColor(UIColor.systemRed.cgColor)
            let ax = size.width * 0.88, ay = size.height * 0.1
            ctx.move(to: CGPoint(x: ax, y: ay))
            ctx.addLine(to: CGPoint(x: ax + unit * 0.3, y: ay + unit * 0.5))
            ctx.addLine(to: CGPoint(x: ax - unit * 0.3, y: ay + unit * 0.5))
            ctx.closePath()
            ctx.fillPath()
            ("UP" as NSString).draw(
                in: CGRect(x: ax - unit * 0.5, y: ay + unit * 0.55, width: unit, height: unit * 0.4),
                withAttributes: [.font: UIFont.systemFont(ofSize: unit * 0.25, weight: .bold), .foregroundColor: UIColor.systemRed, .paragraphStyle: paragraph]
            )
        }
    }
}
