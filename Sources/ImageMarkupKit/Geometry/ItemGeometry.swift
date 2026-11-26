import CoreGraphics

/// Extents of items as drawn (including stroke width, arrowheads and shadow).
enum ItemGeometry {
    static let shadowExtent: CGFloat = 10

    static func visualBounds(of item: MarkupItem, in document: MarkupDocument) -> CGRect {
        let shadow = item.style.shadow ? shadowExtent : 0
        switch item.content {
        case .line(let line):
            // Curves can swing outside their points, so measure the flattened samples.
            let samples = LinePath.samples(of: line, in: document)
            let hasHead = !line.isClosed && (line.startHead == .arrow || line.endHead == .arrow)
            let pad = max(item.style.lineWidth / 2, hasHead ? PathFactory.arrowHeadLength(lineWidth: item.style.lineWidth) : 0)
            return CGRect.bounding(samples).insetBy(dx: -(pad + shadow), dy: -(pad + shadow))
        case .stroke(let stroke):
            // Stroke boxes already include half the line width.
            return stroke.box.boundingRect.insetBy(dx: -shadow, dy: -shadow)
        default:
            guard let box = item.box else { return .null }
            let pad = item.style.effectiveLineWidth / 2 + shadow
            return box.boundingRect.insetBy(dx: -pad, dy: -pad)
        }
    }

    static func visualBounds(of items: [MarkupItem], in document: MarkupDocument) -> CGRect {
        items.reduce(CGRect.null) { $0.union(visualBounds(of: $1, in: document)) }
    }

    // MARK: Ink

    /// What an item puts on the canvas, for fitting a board export edge to edge: tight around arrowheads, with the
    /// sharp corners of mitered borders, and without the drop shadow. `visualBounds` stays the looser extent the
    /// editor works with.
    static func inkBounds(of item: MarkupItem, in document: MarkupDocument) -> CGRect {
        let style = item.style
        let half = style.strokeColor != nil && style.lineWidth > 0 ? style.lineWidth / 2 : 0
        switch item.content {
        case .image(let content):
            let path = CGPath(rect: CGRect(origin: .zero, size: content.box.frame.size), transform: nil)
            return strokedBounds(of: path, placedBy: content.box.boxToWorld, half: half, join: .miter)
        case .shape(let content):
            let path = PathFactory.shapePath(kind: content.kind, size: content.box.frame.size, cornerRadius: style.cornerRadius)
            return strokedBounds(of: path, placedBy: content.box.boxToWorld, half: half, join: PathFactory.lineJoin(for: content.kind))
        case .text(let content):
            let pad = style.effectiveLineWidth / 2
            return content.box.boundingRect.insetBy(dx: -pad, dy: -pad)
        case .stroke(let content):
            // Stroke boxes already include half the line width.
            return content.box.boundingRect
        case .line(let content):
            // Round caps and joins: the shaft reaches half the line width past its path; heads are filled.
            let geometry = PathFactory.lineGeometry(content, in: document, lineWidth: style.lineWidth)
            let shaft = geometry.shaft.boundingBoxOfPath.insetBy(dx: -half, dy: -half)
            guard style.strokeColor != nil, let heads = geometry.heads else { return shaft }
            return shaft.union(heads.boundingBoxOfPath)
        }
    }

    static func inkBounds(of items: [MarkupItem], in document: MarkupDocument) -> CGRect {
        items.reduce(CGRect.null) { $0.union(inkBounds(of: $1, in: document)) }
    }

    /// Miter limit of every stroke the editor draws (`ItemDrawing`, the on-screen layers).
    static let miterLimit: CGFloat = 10

    /// Bounds of a box-space `path` placed in the world by `transform`, stroked `half` wide on each side of it.
    private static func strokedBounds(of path: CGPath, placedBy transform: CGAffineTransform, half: CGFloat, join: CGLineJoin) -> CGRect {
        var transform = transform
        guard let world = path.copy(using: &transform) else { return .null }
        let bounds = world.boundingBoxOfPath
        guard half > 0, !bounds.isNull else { return bounds }
        let stroked = bounds.insetBy(dx: -half, dy: -half)
        guard join == .miter else { return stroked }
        // Curved outlines (rounded corners) meet their straight edges smoothly, so only polygons have miters.
        let tips = polygons(in: world).flatMap { miterTips(around: $0, half: half) }
        return stroked.union(CGRect.bounding(tips))
    }

    /// The closed subpaths made only of straight segments, as their vertices.
    private static func polygons(in path: CGPath) -> [[CGPoint]] {
        var found: [[CGPoint]] = []
        var points: [CGPoint] = []
        var straight = true
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                points = [element.points[0]]
                straight = true
            case .addLineToPoint:
                points.append(element.points[0])
            case .closeSubpath:
                if straight { found.append(points) }
                points = []
            default:
                // Curves.
                straight = false
            }
        }
        return found
    }

    /// Outer points of the miter joins around a polygon. A join whose miter would pass the limit is beveled
    /// instead, and stays within `half` of the path.
    private static func miterTips(around polygon: [CGPoint], half: CGFloat) -> [CGPoint] {
        // Repeated points (such as a last point back on the first) have no direction.
        let vertices = polygon.indices
            .filter { polygon[$0].distance(to: polygon[($0 + 1) % polygon.count]) > 1e-9 }
            .map { polygon[$0] }
        let count = vertices.count
        var tips: [CGPoint] = []
        for (index, vertex) in vertices.enumerated() {
            let incoming = (vertex - vertices[(index + count - 1) % count]).normalizedVector
            let outgoing = (vertices[(index + 1) % count] - vertex).normalizedVector
            // Sine of half the corner's angle; the miter reaches half / sine from the vertex.
            let sine = sqrt(max((1 + incoming.dot(outgoing)) / 2, 0))
            let outward = incoming - outgoing
            if sine >= 1 / miterLimit, outward.length > 1e-9 {
                tips.append(vertex + outward.normalizedVector * (half / sine))
            }
        }
        return tips
    }
}
