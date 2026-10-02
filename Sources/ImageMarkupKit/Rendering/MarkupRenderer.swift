import UIKit

/// A flattened export of a document.
public struct MarkupRendering: Sendable {
    public let image: UIImage
    /// Encoded bytes in the requested format (JPEG by default).
    public let data: Data
    public let pixelSize: CGSize
}

/// Flattens a document into a single image. Safe to call off the main thread.
public enum MarkupRenderer {
    /// Renders on a background thread.
    public static func render(_ document: MarkupDocument, assets: AssetCatalog, options: MarkupExportOptions = .default) async -> MarkupRendering {
        await Task.detached(priority: .userInitiated) {
            renderSynchronously(document, assets: assets, options: options)
        }.value
    }

    public static func renderSynchronously(_ document: MarkupDocument, assets: AssetCatalog, options: MarkupExportOptions = .default) -> MarkupRendering {
        // Background threads may not drain autorelease pools promptly; large temporaries must not linger.
        autoreleasepool { renderInPool(document, assets: assets, options: options) }
    }

    private static func renderInPool(_ document: MarkupDocument, assets: AssetCatalog, options: MarkupExportOptions) -> MarkupRendering {
        let plan = ExportPlanner.plan(for: document, options: options)
        let isJPEG: Bool
        if case .jpeg = options.format { isJPEG = true } else { isJPEG = false }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = isJPEG
        // Avoid 16-bit extended-range buffers on wide-gamut devices (twice the memory).
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: plan.pixelSize, format: format)

        let image = renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.setFillColor(document.backgroundColor.cgColor)
            ctx.fill(CGRect(origin: .zero, size: plan.pixelSize))
            ctx.interpolationQuality = .high

            ctx.scaleBy(x: plan.scaleX, y: plan.scaleY)
            ctx.translateBy(x: -plan.rect.minX, y: -plan.rect.minY)
            if document.policy.clipsToCanvas {
                ctx.clip(to: plan.rect)
            }
            let deviceScale = max(plan.scaleX, plan.scaleY)
            for item in document.items {
                autoreleasepool {
                    ItemDrawing.draw(item, in: document, context: ctx, deviceScale: deviceScale) { content in
                        decodeForExport(content, assets: assets, deviceScale: deviceScale)
                    }
                }
            }
        }

        let data: Data
        switch options.format {
        case .jpeg(let quality):
            data = image.jpegData(compressionQuality: quality) ?? Data()
        case .png:
            data = image.pngData() ?? Data()
        }
        return MarkupRendering(image: image, data: data, pixelSize: plan.pixelSize)
    }

    /// Decodes a photo at the size it occupies in the output (never above its original size).
    private static func decodeForExport(_ content: ImageContent, assets: AssetCatalog, deviceScale: CGFloat) -> CGImage? {
        guard let url = assets.url(for: content.assetID) else { return nil }
        let frame = content.box.frame.size
        let needed = max(frame.width, frame.height) * deviceScale
        let original = max(content.pixelSize.width, content.pixelSize.height)
        return ImagePipeline.downsample(at: url, maxPixelSize: min(needed.rounded(.up), original))
    }
}
