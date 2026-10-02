import CoreGraphics

/// Builds every path the editor draws. Used by both the on-screen layers and the export renderer,
/// which is what keeps the screen and the exported image identical.
enum PathFactory {

    // MARK: Shapes (box space)

    static func shapePath(kind: ShapeKind, size: CGSize, cornerRadius: CGFloat) -> CGPath {
        let rect = CGRect(origin: .zero, size: size)
        let w = size.width, h = size.height
        switch kind {
        case .rectangle, .highlightBox:
            return roundedRect(rect, radius: cornerRadius)
        case .roundedRectangle:
            return roundedRect(rect, radius: cornerRadius > 0 ? cornerRadius : min(w, h) * 0.2)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .triangle:
            return polygon([CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)])
        case .diamond:
            return polygon([CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h / 2), CGPoint(x: w / 2, y: h), CGPoint(x: 0, y: h / 2)])
        case .pentagon:
            return polygon(fitted(regularPolygon(sides: 5, innerRatio: nil), into: rect))
        case .star:
            return polygon(fitted(regularPolygon(sides: 5, innerRatio: 0.4), into: rect))
        case .speechBubble:
            return speechBubble(size: size, cornerRadius: cornerRadius)
        }
    }

    /// Stroke joins: sharp for polygons (like Preview), round otherwise.
    static func lineJoin(for kind: ShapeKind) -> CGLineJoin {
        switch kind {
        case .rectangle, .triangle, .diamond, .pentagon, .star: return .miter
        default: return .round
        }
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(max(radius, 0), min(rect.width, rect.height) / 2)
        guard r > 0.01 else { return CGPath(rect: rect, transform: nil) }
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// Vertices on the unit circle starting at 12 o'clock; alternates inner points when `innerRatio` is set.
    private static func regularPolygon(sides: Int, innerRatio: CGFloat?) -> [CGPoint] {
        let count = innerRatio == nil ? sides : sides * 2
        return (0..<count).map { i in
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(count)
            let radius: CGFloat = (innerRatio != nil && i % 2 == 1) ? innerRatio! : 1
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
    }

    /// Scales points so their bounding box exactly fills `rect`.
    private static func fitted(_ points: [CGPoint], into rect: CGRect) -> [CGPoint] {
        let bounds = CGRect.bounding(points)
        guard bounds.width > 0, bounds.height > 0 else { return points }
        let sx: CGFloat = rect.width / bounds.width
        let sy: CGFloat = rect.height / bounds.height
        return points.map { p -> CGPoint in
            let x: CGFloat = rect.minX + (p.x - bounds.minX) * sx
            let y: CGFloat = rect.minY + (p.y - bounds.minY) * sy
            return CGPoint(x: x, y: y)
        }
    }

    private static func speechBubble(size: CGSize, cornerRadius: CGFloat) -> CGPath {
        let w = size.width, h = size.height
        let bodyHeight = h * 0.78
        let tailLeft = w * 0.26, tailRight = w * 0.42, tailTip = CGPoint(x: w * 0.16, y: h)
        let r = min(cornerRadius > 0 ? cornerRadius : min(w, bodyHeight) * 0.22, tailLeft, bodyHeight / 2, w / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
        path.addLine(to: CGPoint(x: w, y: bodyHeight - r))
        path.addArc(tangent1End: CGPoint(x: w, y: bodyHeight), tangent2End: CGPoint(x: w - r, y: bodyHeight), radius: r)
        path.addLine(to: CGPoint(x: tailRight, y: bodyHeight))
        path.addLine(to: tailTip)
        path.addLine(to: CGPoint(x: tailLeft, y: bodyHeight))
        path.addLine(to: CGPoint(x: r, y: bodyHeight))
        path.addArc(tangent1End: CGPoint(x: 0, y: bodyHeight), tangent2End: CGPoint(x: 0, y: bodyHeight - r), radius: r)
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: .zero, tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.closeSubpath()
        return path
    }

    // MARK: Freehand strokes

    /// Denormalized stroke points in box space.
    static func strokePoints(_ content: StrokeContent) -> [CGPoint] {
        let size = content.box.frame.size
        return content.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// Smooth path through the samples: quadratic curves between midpoints, using each sample as the
    /// control point (the pen-smoothing approach from Drawsana's `PenShape`).
    static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        switch points.count {
        case 1:
            // A dot: zero-length segment drawn with a round cap.
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
        case 2:
            path.addLine(to: points[1])
        default:
            path.addLine(to: .midpoint(points[0], points[1]))
            for i in 1..<(points.count - 1) {
                path.addQuadCurve(to: .midpoint(points[i], points[i + 1]), control: points[i])
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }

    // MARK: Lines and arrows (world space)

    struct LineGeometry {
        var shaft: CGPath
        /// Filled arrowheads, or `nil` when the line has none.
        var heads: CGPath?
    }

    static func arrowHeadLength(lineWidth: CGFloat) -> CGFloat {
        max(lineWidth * 3.2, 14)
    }

    static func lineGeometry(start: CGPoint, end: CGPoint, lineWidth: CGFloat, startHead: ArrowHead, endHead: ArrowHead) -> LineGeometry {
        lineGeometry(samples: [start, end], closed: false, lineWidth: lineWidth, startHead: startHead, endHead: endHead)
    }

    /// Geometry of any line (straight, polyline or curve) with its endpoints resolved in `document`.
    static func lineGeometry(_ line: LineContent, in document: MarkupDocument, lineWidth: CGFloat) -> LineGeometry {
        let points = Bindings.resolvedPoints(line, in: document)
        return lineGeometry(
            samples: LinePath.flattened(points, kind: line.kind, closed: line.isClosed),
            closed: LinePath.closes(points, closed: line.isClosed),
            lineWidth: lineWidth, startHead: line.startHead, endHead: line.endHead
        )
    }

    /// Shaft and heads along flattened `samples` (see `LinePath`). Closed lines have no heads; their shaft is a
    /// closed path that can also be filled.
    static func lineGeometry(samples: [CGPoint], closed: Bool, lineWidth: CGFloat, startHead: ArrowHead, endHead: ArrowHead) -> LineGeometry {
        let shaft = CGMutablePath()
        guard let start = samples.first else { return LineGeometry(shaft: shaft, heads: nil) }
        let length = LinePath.length(of: samples)
        guard length > 0.001 else {
            shaft.move(to: start)
            shaft.addLine(to: CGPoint(x: start.x + 0.01, y: start.y))
            return LineGeometry(shaft: shaft, heads: nil)
        }
        if closed {
            shaft.addLines(between: Array(samples.dropLast()))
            shaft.closeSubpath()
            return LineGeometry(shaft: shaft, heads: nil)
        }
        let end = samples[samples.count - 1]
        let headCount = (startHead == .arrow ? 1 : 0) + (endHead == .arrow ? 1 : 0)
        // Heads shrink on very short lines so they never overlap.
        let headLength = headCount == 0 ? 0 : min(arrowHeadLength(lineWidth: lineWidth), length / CGFloat(headCount) * 0.9)
        let halfWidth = headLength * 0.55
        // End the shaft inside the head so thick lines don't poke through the tip.
        let inset = headLength * 0.7

        shaft.addLines(between: LinePath.trimmed(
            samples,
            head: startHead == .arrow ? inset : 0,
            tail: endHead == .arrow ? inset : 0
        ))

        guard headCount > 0 else { return LineGeometry(shaft: shaft, heads: nil) }
        let heads = CGMutablePath()
        // A head points along the line where its base sits, so it follows curves and the last polyline segment.
        func addHead(tip: CGPoint, base baseOnLine: CGPoint) {
            let dir = (tip - baseOnLine).normalizedVector
            let base = tip - dir * headLength
            let normal = dir.perpendicular * halfWidth
            heads.addLines(between: [tip, base + normal, base - normal])
            heads.closeSubpath()
        }
        if endHead == .arrow {
            addHead(tip: end, base: LinePath.point(atDistance: length - headLength, along: samples))
        }
        if startHead == .arrow {
            addHead(tip: start, base: LinePath.point(atDistance: headLength, along: samples))
        }
        return LineGeometry(shaft: shaft, heads: heads)
    }

    // MARK: Dashes

    static func dashPattern(_ dash: DashStyle, lineWidth: CGFloat) -> [CGFloat]? {
        let w = max(lineWidth, 1)
        switch dash {
        case .solid: return nil
        case .dashed: return [w * 3, w * 2]
        case .dotted: return [0, w * 2]
        }
    }

    /// Dotted lines need round caps (zero-length dashes become dots).
    static func lineCap(for dash: DashStyle, default cap: CGLineCap) -> CGLineCap {
        dash == .dotted ? .round : cap
    }
}
