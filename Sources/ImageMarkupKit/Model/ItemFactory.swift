import CoreGraphics
import Foundation

/// Convenience constructors that compute derived geometry (text box size, stroke box, connector endpoints).
/// Used by the editor's tools and available to host apps that want to add annotations programmatically.
public extension MarkupItem {
    static func shape(_ kind: ShapeKind, frame: CGRect, rotation: CGFloat = 0, lockAspect: Bool = false, style: ItemStyle) -> MarkupItem {
        MarkupItem(content: .shape(ShapeContent(kind: kind, box: Box(frame: frame.standardized, rotation: rotation), lockAspect: lockAspect)), style: style)
    }

    /// A text box whose top-left corner is at `origin` (before rotation). The box is sized to the text.
    static func text(
        _ text: String,
        at origin: CGPoint,
        font: FontSpec,
        color: RGBAColor,
        alignment: TextAlignmentOption = .left,
        fixedWidth: CGFloat? = nil,
        padding: CGFloat = 8,
        rotation: CGFloat = 0,
        style: ItemStyle = ItemStyle(strokeColor: nil)
    ) -> MarkupItem {
        var content = TextContent(
            text: text, font: font, color: color, alignment: alignment,
            fixedWidth: fixedWidth, padding: padding,
            box: Box(frame: CGRect(origin: origin, size: .zero))
        )
        let size = TextLayout.measuredSize(for: content)
        let center = origin + CGPoint(x: size.width / 2, y: size.height / 2)
        content.box = Box(frame: CGRect(center: center, size: size), rotation: rotation)
        return MarkupItem(content: .text(content), style: style)
    }

    /// A freehand stroke through world-space `points`.
    static func stroke(points: [CGPoint], style: ItemStyle, isHighlighter: Bool = false) -> MarkupItem {
        let box = StrokeGeometry.box(for: points, lineWidth: style.lineWidth)
        let normalized = StrokeGeometry.normalize(points, in: box)
        return MarkupItem(content: .stroke(StrokeContent(points: normalized, box: Box(frame: box), isHighlighter: isHighlighter)), style: style)
    }

    /// A free line or arrow between two world points.
    static func line(from start: CGPoint, to end: CGPoint, startHead: ArrowHead = .none, endHead: ArrowHead = .arrow, style: ItemStyle) -> MarkupItem {
        MarkupItem(content: .line(LineContent(start: Endpoint(point: start), end: Endpoint(point: end), startHead: startHead, endHead: endHead)), style: style)
    }

    /// Straight segments through world `points` (at least two); `closed` joins the last point to the first.
    static func polyline(points: [CGPoint], closed: Bool = false, startHead: ArrowHead = .none, endHead: ArrowHead = .none, style: ItemStyle) -> MarkupItem {
        pathItem(.polyline, points: points, closed: closed, startHead: startHead, endHead: endHead, style: style)
    }

    /// A smooth curve through world `points` (at least two).
    static func curve(through points: [CGPoint], closed: Bool = false, startHead: ArrowHead = .none, endHead: ArrowHead = .none, style: ItemStyle) -> MarkupItem {
        pathItem(.curve, points: points, closed: closed, startHead: startHead, endHead: endHead, style: style)
    }

    private static func pathItem(_ kind: LineKind, points: [CGPoint], closed: Bool, startHead: ArrowHead, endHead: ArrowHead, style: ItemStyle) -> MarkupItem {
        let first = points.first ?? .zero
        let last = points.count > 1 ? points[points.count - 1] : first
        let line = LineContent(
            start: Endpoint(point: first), end: Endpoint(point: last),
            startHead: startHead, endHead: endHead,
            kind: kind, waypoints: Array(points.dropFirst().dropLast()),
            isClosed: closed && points.count >= 3
        )
        return MarkupItem(content: .line(line), style: style)
    }

    /// A connector whose ends are attached to items of `document`.
    static func connector(
        from start: ConnectorBinding,
        to end: ConnectorBinding,
        in document: MarkupDocument,
        startHead: ArrowHead = .none,
        endHead: ArrowHead = .arrow,
        style: ItemStyle
    ) -> MarkupItem {
        var line = LineContent(start: Endpoint(point: .zero, binding: start), end: Endpoint(point: .zero, binding: end), startHead: startHead, endHead: endHead)
        let (s, e) = Bindings.resolvedEndpoints(line, in: document)
        line.start.point = s
        line.end.point = e
        return MarkupItem(content: .line(line), style: style)
    }
}

enum StrokeGeometry {
    /// Bounding box of the samples plus half the line width, never thinner than the line width
    /// (a perfectly straight stroke would otherwise have a zero-height box).
    static func box(for points: [CGPoint], lineWidth: CGFloat) -> CGRect {
        let pad = max(lineWidth, 1) / 2
        var rect = CGRect.bounding(points)
        if rect.isNull { rect = .zero }
        rect = rect.insetBy(dx: -pad, dy: -pad)
        let minimum = max(lineWidth, 1)
        if rect.width < minimum { rect = rect.insetBy(dx: (rect.width - minimum) / 2, dy: 0) }
        if rect.height < minimum { rect = rect.insetBy(dx: 0, dy: (rect.height - minimum) / 2) }
        return rect
    }

    static func normalize(_ points: [CGPoint], in rect: CGRect) -> [CGPoint] {
        let w = max(rect.width, .ulpOfOne), h = max(rect.height, .ulpOfOne)
        return points.map { CGPoint(x: ($0.x - rect.minX) / w, y: ($0.y - rect.minY) / h) }
    }
}

public extension ImageMetadata {
    /// Reads size and orientation without decoding pixels.
    static func read(from url: URL) -> ImageMetadata? { ImagePipeline.metadata(at: url) }
}
