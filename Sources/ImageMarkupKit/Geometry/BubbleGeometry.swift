import CoreGraphics
import Foundation

/// A handle of a speech bubble's tail: its tip, or the end of its base, which sets the tail's width.
public enum BubbleTailPart: Equatable, Sendable {
    case tip, width
}

/// Speech bubbles. Without a tail (`ShapeContent.tail == nil`) a bubble is drawn as it always was: the body fills the
/// top 78% of the box and the tail's tip sits on the box's bottom edge. With a tail, the box is the body, a rounded
/// rectangle, and the tail leaves the side that faces its tip, which may lie outside the box.
enum BubbleGeometry {
    /// The body's share of the box height in a bubble without a tail.
    static let originalBodyRatio: CGFloat = 0.78
    /// The tail of a bubble without one, relative to its body: tip at 16% of the width, base from 26% to 42%.
    static let originalTail = BubbleTail(tip: CGPoint(x: 0.16, y: 1 / 0.78), width: 0.16)
    /// How far the base leans from the middle of its side toward the tip; 8/17 puts the original tail's base back
    /// at 26–42% of the width.
    static let lean: CGFloat = 8 / 17
    /// The narrowest tail the width handle makes, as a fraction of the side.
    static let minimumWidth: CGFloat = 0.04

    enum Side { case top, right, bottom, left }

    /// Where a tail goes, in box space with the box's size made positive (see `mirrored`).
    struct Layout: Equatable {
        var side: Side
        /// The side's length.
        var length: CGFloat
        var radius: CGFloat
        /// The base's middle and width along the side, measured from its left (top and bottom) or top end.
        var center: CGFloat
        var width: CGFloat
        var tip: CGPoint
        /// The tip projected onto the side, clamped to it.
        var projection: CGFloat
        var size: CGSize

        var isHorizontal: Bool { side == .top || side == .bottom }

        /// The point `along` units from the side's left or top end.
        func point(along s: CGFloat) -> CGPoint {
            switch side {
            case .top: return CGPoint(x: s, y: 0)
            case .bottom: return CGPoint(x: s, y: size.height)
            case .left: return CGPoint(x: 0, y: s)
            case .right: return CGPoint(x: size.width, y: s)
            }
        }

        /// The base's ends in the order a clockwise outline meets them.
        var clockwiseBase: (CGPoint, CGPoint) {
            let low = point(along: center - width / 2), high = point(along: center + width / 2)
            return side == .top || side == .right ? (low, high) : (high, low)
        }

        /// The end of the base away from the tip, where the width handle sits.
        var widthHandle: CGPoint {
            point(along: projection <= center ? center + width / 2 : center - width / 2)
        }
    }

    /// Corner radius of a bubble with a tail.
    static func radius(size: CGSize, cornerRadius: CGFloat) -> CGFloat {
        let w = abs(size.width), h = abs(size.height)
        return min(cornerRadius > 0 ? cornerRadius : min(w, h) * 0.22, w / 2, h / 2)
    }

    /// Where the tail goes, or nil when its tip is inside the body (then no tail is drawn).
    static func layout(size: CGSize, cornerRadius: CGFloat, tail: BubbleTail) -> Layout? {
        let w = abs(size.width), h = abs(size.height)
        let dx = tail.tip.x - 0.5, dy = tail.tip.y - 0.5
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return nil }
        let r = radius(size: size, cornerRadius: cornerRadius)
        let side: Side = abs(dy) >= abs(dx) ? (dy > 0 ? .bottom : .top) : (dx > 0 ? .right : .left)
        let horizontal = side == .top || side == .bottom
        let length = horizontal ? w : h
        let projection = min(max((horizontal ? tail.tip.x : tail.tip.y) * length, 0), length)
        let width = min(max(tail.width * length, 0), max(length - 2 * r, 0))
        let center = min(max(length / 2 + (projection - length / 2) * lean, r + width / 2), length - r - width / 2)
        return Layout(
            side: side, length: length, radius: r, center: center, width: width,
            tip: CGPoint(x: tail.tip.x * w, y: tail.tip.y * h), projection: projection, size: CGSize(width: w, height: h)
        )
    }

    /// Box-space point for a point computed with the size made positive (a negative width or height mirrors it).
    static func mirrored(_ p: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: size.width < 0 ? -p.x : p.x, y: size.height < 0 ? -p.y : p.y)
    }

    /// Outline of a bubble with a tail, in box space: the rounded body, clockwise from the top-left corner like the
    /// original drawing, with the tail inserted into the side facing its tip.
    static func path(size: CGSize, cornerRadius: CGFloat, tail: BubbleTail) -> CGPath {
        let w = abs(size.width), h = abs(size.height)
        let r = radius(size: size, cornerRadius: cornerRadius)
        let layout = self.layout(size: size, cornerRadius: cornerRadius, tail: tail)
        let m = { (p: CGPoint) in mirrored(p, size: size) }
        let path = CGMutablePath()
        func addTail(on side: Side) {
            guard let layout, layout.side == side else { return }
            let (first, last) = layout.clockwiseBase
            path.addLine(to: m(first))
            path.addLine(to: m(layout.tip))
            path.addLine(to: m(last))
        }
        path.move(to: m(CGPoint(x: r, y: 0)))
        addTail(on: .top)
        path.addLine(to: m(CGPoint(x: w - r, y: 0)))
        path.addArc(tangent1End: m(CGPoint(x: w, y: 0)), tangent2End: m(CGPoint(x: w, y: r)), radius: r)
        addTail(on: .right)
        path.addLine(to: m(CGPoint(x: w, y: h - r)))
        path.addArc(tangent1End: m(CGPoint(x: w, y: h)), tangent2End: m(CGPoint(x: w - r, y: h)), radius: r)
        addTail(on: .bottom)
        path.addLine(to: m(CGPoint(x: r, y: h)))
        path.addArc(tangent1End: m(CGPoint(x: 0, y: h)), tangent2End: m(CGPoint(x: 0, y: h - r)), radius: r)
        addTail(on: .left)
        path.addLine(to: m(CGPoint(x: 0, y: r)))
        path.addArc(tangent1End: m(.zero), tangent2End: m(CGPoint(x: r, y: 0)), radius: r)
        path.closeSubpath()
        return path
    }

    // MARK: Adjusting

    /// A speech bubble with a tail drawing the same outline: one without a tail gets its box shrunk to the body and
    /// the original tail. Returns a bubble that has a tail unchanged, and nil for anything but a speech bubble.
    static func withTail(_ item: MarkupItem) -> MarkupItem? {
        guard case .shape(var shape) = item.content, shape.kind == .speechBubble else { return nil }
        guard shape.tail == nil else { return item }
        let size = shape.box.frame.size
        let body = CGSize(width: size.width, height: size.height * originalBodyRatio)
        let center = CGPoint(x: size.width / 2, y: body.height / 2).applying(shape.box.boxToWorld)
        shape.box = Box(frame: CGRect(center: center, size: body), rotation: shape.box.rotation)
        shape.tail = originalTail
        var result = item
        result.content = .shape(shape)
        // The original drawing keeps its corners clear of the tail: their radius is at most 26% of the width.
        let limit = abs(size.width) * 0.26
        if result.style.cornerRadius > limit { result.style.cornerRadius = limit }
        return result
    }

    /// The document with the speech bubble `id` given a tail (`withTail`). The ends of lines attached to the bubble
    /// stay where they are: their anchors are measured against the smaller box. Nil when `id` is not a speech bubble.
    static func documentWithTail(of id: UUID, in document: MarkupDocument) -> MarkupDocument? {
        guard let item = document.item(id), let adjusted = withTail(item) else { return nil }
        var result = document
        result.update(id) { $0 = adjusted }
        guard item.shapeContent?.tail == nil else { return result }
        for index in result.items.indices {
            guard case .line(var line) = result.items[index].content else { continue }
            var changed = false
            for end in [\LineContent.start, \LineContent.end] where line[keyPath: end].binding?.itemID == id {
                line[keyPath: end].binding?.anchor.y /= originalBodyRatio
                changed = true
            }
            if changed { result.items[index].content = .line(line) }
        }
        return result
    }

    /// World positions of a tail's handles. The width handle is nil when no tail is drawn (its tip is inside the body).
    struct Handles: Equatable {
        var tip: CGPoint
        var width: CGPoint?
    }

    /// The tail handles of a speech bubble (nil for other items). A bubble without a tail gets those of `withTail`,
    /// which sit on its tail as drawn.
    static func handles(of item: MarkupItem) -> Handles? {
        guard let adjusted = withTail(item), let shape = adjusted.shapeContent, let tail = shape.tail else { return nil }
        let size = shape.box.frame.size
        let toWorld = shape.box.boxToWorld
        let tip = CGPoint(x: tail.tip.x * size.width, y: tail.tip.y * size.height).applying(toWorld)
        guard let layout = layout(size: size, cornerRadius: adjusted.style.cornerRadius, tail: tail) else {
            return Handles(tip: tip, width: nil)
        }
        return Handles(tip: tip, width: mirrored(layout.widthHandle, size: size).applying(toWorld))
    }

    /// The tail of a bubble that has one after dragging `part` to the world point `world`. The tip goes where it is
    /// dragged; the width handle (the end of the base away from the tip) follows the pointer along the side, the
    /// base widening about its middle, or from its other end where a corner stops the middle from moving.
    static func tail(of item: MarkupItem, moving part: BubbleTailPart, to world: CGPoint) -> BubbleTail? {
        guard let shape = item.shapeContent, shape.kind == .speechBubble, let tail = shape.tail else { return nil }
        let size = shape.box.frame.size
        let local = world.applying(shape.box.boxToWorld.inverted())
        switch part {
        case .tip:
            let w = size.width == 0 ? .ulpOfOne : size.width
            let h = size.height == 0 ? .ulpOfOne : size.height
            return BubbleTail(tip: CGPoint(x: local.x / w, y: local.y / h), width: tail.width)
        case .width:
            guard let layout = layout(size: size, cornerRadius: item.style.cornerRadius, tail: tail), layout.length > 0 else {
                return tail
            }
            let p = mirrored(local, size: size)
            let along = layout.isHorizontal ? p.x : p.y
            let length = layout.length, r = layout.radius
            // Where the middle of the base would be if no corner stopped it (see `layout`).
            let free = length / 2 + (layout.projection - length / 2) * lean
            let base: CGFloat
            if layout.projection <= layout.center {
                // The handle is the base's far end: at max(free + b / 2, r + b).
                base = min(2 * (along - free), along - r)
            } else {
                // The handle is the base's near end: at min(free - b / 2, length - r - b).
                base = min(2 * (free - along), length - r - along)
            }
            let maximum = max(length - 2 * r, 0) / length
            let width = min(max(base / length, minimumWidth), maximum)
            return BubbleTail(tip: tail.tip, width: width)
        }
    }

    // MARK: Extent

    /// What a shape covers in frame space: its frame, plus the tip of a speech bubble's tail.
    static func frameSpaceBounds(of shape: ShapeContent) -> CGRect {
        let frame = shape.box.frame
        guard shape.kind == .speechBubble, let tail = shape.tail else { return frame }
        let size = frame.size
        let tip = CGPoint(x: frame.minX + tail.tip.x * size.width, y: frame.minY + tail.tip.y * size.height)
        return frame.union(CGRect(origin: tip, size: .zero))
    }

    /// Axis-aligned world bounds of `frameSpaceBounds`.
    static func worldBounds(of shape: ShapeContent) -> CGRect {
        let rect = frameSpaceBounds(of: shape)
        let box = shape.box
        guard box.rotation != 0 else { return rect }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        return CGRect.bounding(corners.map(box.toWorld))
    }
}
