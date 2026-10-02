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
}
