import UIKit

/// Toolbar items, modelled on the Markup toolbar of macOS Preview, with their SF Symbols.
/// All symbol names used by the toolbar live here (plus the action bar and panels), so iOS 15 availability can be
/// audited in one place: names in `SymbolCatalog.sf(...)` must exist on iOS 15.0.
enum ToolbarCatalog {
    enum Item: Hashable {
        case select, sketch, highlight, shapes, arrow, text, note, eraser
        case shapeStyle, borderColor, fillColor, textStyle
        case addImages, arrange
    }

    static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)

    static func image(for item: Item) -> UIImage? {
        let c = symbolConfiguration
        switch item {
        case .select: return SymbolCatalog.sf("cursorarrow", "hand.point.up.left", configuration: c)
        case .sketch: return SymbolCatalog.sf("scribble", "pencil.tip", configuration: c)
        case .highlight: return SymbolCatalog.sf("highlighter", configuration: c)
        case .shapes: return SymbolCatalog.sf("square.on.circle", configuration: c)
        case .arrow: return SymbolCatalog.sf("line.diagonal.arrow", "arrow.up.right", configuration: c)
        case .text: return SymbolCatalog.sf("textbox", "t.square", configuration: c)
        case .note: return SymbolCatalog.sf("note.text", "text.bubble", configuration: c)
        case .eraser: return SymbolCatalog.sfGuarded("eraser", iOS: 16, fallback: "pencil.slash", configuration: c)
        case .shapeStyle: return SymbolCatalog.sf("lineweight", "line.3.horizontal", configuration: c)
        case .borderColor, .fillColor: return nil // drawn swatches
        case .textStyle: return SymbolCatalog.sf("textformat", "textformat.size", configuration: c)
        case .addImages: return SymbolCatalog.sf("plus.rectangle.on.rectangle", configuration: c)
        case .arrange: return SymbolCatalog.sf("square.grid.2x2", configuration: c)
        }
    }

    static func title(for item: Item) -> String {
        switch item {
        case .select: return Strings.toolSelect
        case .sketch: return Strings.toolSketch
        case .highlight: return Strings.toolHighlight
        case .shapes: return Strings.toolShapes
        case .arrow: return Strings.toolArrow
        case .text: return Strings.toolText
        case .note: return Strings.toolNote
        case .eraser: return Strings.toolEraser
        case .shapeStyle: return Strings.shapeStyle
        case .borderColor: return Strings.borderColor
        case .fillColor: return Strings.fillColor
        case .textStyle: return Strings.textStyle
        case .addImages: return Strings.addImages
        case .arrange: return Strings.arrange
        }
    }

    /// Entries of the Shapes menu (closed shapes only; lines, arrows, polylines and curves are in the Arrow menu).
    static let shapes: [(kind: ShapeKind, lockAspect: Bool)] = [
        (.rectangle, false), (.roundedRectangle, false), (.ellipse, false), (.ellipse, true),
        (.rectangle, true), (.triangle, false), (.diamond, false), (.star, false),
        (.pentagon, false), (.speechBubble, false), (.highlightBox, false),
    ]

    static func shapeImage(_ kind: ShapeKind, lockAspect: Bool) -> UIImage? {
        let c = symbolConfiguration
        switch (kind, lockAspect) {
        case (.rectangle, false): return SymbolCatalog.sf("rectangle", configuration: c)
        case (.rectangle, true): return SymbolCatalog.sf("square", configuration: c)
        case (.roundedRectangle, _): return SymbolCatalog.sf("app", configuration: c)
        case (.ellipse, false): return SymbolCatalog.sf("oval", "circle", configuration: c)
        case (.ellipse, true): return SymbolCatalog.sf("circle", configuration: c)
        case (.triangle, _): return SymbolCatalog.sf("triangle", configuration: c)
        case (.diamond, _): return SymbolCatalog.sf("diamond", configuration: c)
        case (.star, _): return SymbolCatalog.sf("star", configuration: c)
        case (.pentagon, _): return SymbolCatalog.sf("pentagon", "hexagon", configuration: c)
        case (.speechBubble, _): return SymbolCatalog.sf("bubble.left", configuration: c)
        case (.highlightBox, _): return SymbolCatalog.sf("rectangle.inset.filled", "rectangle.fill", configuration: c)
        }
    }

    /// Entries of the Arrow menu: straight lines and arrows, polylines, curves.
    static let lineTools: [MarkupTool] = [.arrow, .polyline, .curve]

    static func lineToolImage(_ tool: MarkupTool) -> UIImage? {
        switch tool {
        case .polyline: return pathIcon(closed: false)
        case .curve:
            return SymbolCatalog.sf("point.topleft.down.curvedto.point.bottomright.up", configuration: symbolConfiguration)
                ?? curveIcon()
        default: return image(for: .arrow)
        }
    }

    static func lineToolTitle(_ tool: MarkupTool) -> String {
        switch tool {
        case .polyline: return Strings.toolPolyline
        case .curve: return Strings.toolCurve
        default: return Strings.toolArrow
        }
    }

    /// Polyline icon (open zigzag) or polygon icon (closed), with dots on the points. iOS 15 has no SF Symbol
    /// for these, so they are drawn like the color swatches.
    static func pathIcon(closed: Bool) -> UIImage {
        let points = closed
            ? [CGPoint(x: 4, y: 9), CGPoint(x: 12, y: 3.5), CGPoint(x: 20, y: 9), CGPoint(x: 17, y: 20), CGPoint(x: 7, y: 20)]
            : [CGPoint(x: 3.5, y: 19), CGPoint(x: 9, y: 6), CGPoint(x: 15, y: 17), CGPoint(x: 20.5, y: 5)]
        return drawnIcon { path, dots in
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
            if closed { path.close() }
            points.forEach { dots.append(UIBezierPath(arcCenter: $0, radius: 2, startAngle: 0, endAngle: 2 * .pi, clockwise: true)) }
        }
    }

    /// S-curve fallback for the Curve tool.
    private static func curveIcon() -> UIImage {
        drawnIcon { path, dots in
            let start = CGPoint(x: 3.5, y: 19), end = CGPoint(x: 20.5, y: 5)
            path.move(to: start)
            path.addCurve(to: end, controlPoint1: CGPoint(x: 6, y: 2), controlPoint2: CGPoint(x: 18, y: 22))
            [start, end].forEach { dots.append(UIBezierPath(arcCenter: $0, radius: 2, startAngle: 0, endAngle: 2 * .pi, clockwise: true)) }
        }
    }

    /// 24 × 24 template image: `build` adds the stroked line to `path` and filled dots to `dots`.
    private static func drawnIcon(_ build: (UIBezierPath, UIBezierPath) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        return UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { _ in
            let path = UIBezierPath()
            let dots = UIBezierPath()
            build(path, dots)
            UIColor.black.set()
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
            dots.fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    static func arrangementImage(_ arrangement: BoardLayout.Arrangement) -> UIImage? {
        switch arrangement {
        case .row: return SymbolCatalog.sf("rectangle.split.3x1")
        case .column: return SymbolCatalog.sf("rectangle.split.1x2", "rectangle.grid.1x2")
        case .grid: return SymbolCatalog.sf("square.grid.2x2")
        case .tidy: return SymbolCatalog.sf("square.grid.3x2")
        }
    }

    static func arrangementTitle(_ arrangement: BoardLayout.Arrangement) -> String {
        switch arrangement {
        case .row: return Strings.arrangeRow
        case .column: return Strings.arrangeColumn
        case .grid: return Strings.arrangeGrid
        case .tidy: return Strings.arrangeTidy
        }
    }

    /// Color swatch for the Border (outline) and Fill (solid) buttons; `nil` color draws a "none" slash.
    static func swatch(_ color: RGBAColor?, filled: Bool, size: CGFloat = 24) -> UIImage {
        let format = UIGraphicsImageRendererFormat.preferred()
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { _ in
            let rect = CGRect(x: 3, y: 3, width: size - 6, height: size - 6)
            if filled {
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
                (color?.uiColor ?? .systemBackground).setFill()
                path.fill()
                UIColor.separator.setStroke()
                path.lineWidth = 1
                path.stroke()
            } else {
                let path = UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 3)
                path.lineWidth = 4
                (color?.uiColor ?? .systemGray4).setStroke()
                path.stroke()
            }
            if color == nil {
                let slash = UIBezierPath()
                slash.move(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1))
                slash.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
                slash.lineWidth = 2
                UIColor.systemRed.setStroke()
                slash.stroke()
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
