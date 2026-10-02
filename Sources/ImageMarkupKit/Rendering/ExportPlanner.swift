import CoreGraphics

/// Which canvas rect to export and at what pixel size.
struct ExportPlan: Equatable {
    /// Exported region, in canvas units.
    var rect: CGRect
    /// Output size in whole pixels.
    var pixelSize: CGSize
    /// True when the pixel caps reduced the natural resolution.
    var isClamped: Bool

    var scaleX: CGFloat { pixelSize.width / rect.width }
    var scaleY: CGFloat { pixelSize.height / rect.height }
}

enum ExportPlanner {
    static func plan(for document: MarkupDocument, options: MarkupExportOptions) -> ExportPlan {
        let rect = exportRect(for: document, options: options)

        // Density: pixels per canvas unit of the sharpest photo, so photos keep their resolution.
        var density: CGFloat = 0
        for item in document.items {
            guard let image = item.imageContent, image.box.frame.width > 0 else { continue }
            density = max(density, image.pixelSize.width / image.box.frame.width)
        }
        if density <= 0 { density = 1 }

        let natural = document.isBoard ? max(density, options.minimumBoardScale) : density
        let dimensionCap = options.maxPixelDimension / max(rect.width, rect.height)
        let countCap = sqrt(options.maxPixelCount / max(rect.width * rect.height, 1))
        let scale = min(natural, dimensionCap, countCap)
        let isClamped = scale < natural - 1e-9

        var pixelSize = CGSize(width: max((rect.width * scale).rounded(), 1), height: max((rect.height * scale).rounded(), 1))
        // Image mode at natural resolution: reproduce the original pixel size exactly (no rounding drift).
        if !document.isBoard, !isClamped, let background = document.backgroundItem?.imageContent {
            pixelSize = CGSize(width: background.pixelSize.width.rounded(), height: background.pixelSize.height.rounded())
        }
        return ExportPlan(rect: rect, pixelSize: pixelSize, isClamped: isClamped)
    }

    static func exportRect(for document: MarkupDocument, options: MarkupExportOptions) -> CGRect {
        if let canvas = document.policy.canvasRect, canvas.width > 0, canvas.height > 0 {
            return canvas
        }
        let bounds = ItemGeometry.visualBounds(of: document.items, in: document)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 800, height: 600)
        }
        return bounds.insetBy(dx: -options.boardPadding, dy: -options.boardPadding).integral
    }
}
