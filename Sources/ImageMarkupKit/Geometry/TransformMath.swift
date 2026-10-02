import CoreGraphics
import Foundation

/// Selection handles.
enum HandleKind: Equatable {
    /// Resize handle at normalized position (u, v) ∈ {0, ½, 1}² of the box.
    case resize(u: CGFloat, v: CGFloat)
    case rotate
    /// A point of a line: 0 is the start, the last index the end.
    case lineVertex(Int)
    /// The "+" in the middle of segment i (point i → i + 1) of a polyline or curve.
    case lineInsert(Int)

    static let allResize: [HandleKind] = [
        .resize(u: 0, v: 0), .resize(u: 0.5, v: 0), .resize(u: 1, v: 0),
        .resize(u: 1, v: 0.5), .resize(u: 1, v: 1), .resize(u: 0.5, v: 1),
        .resize(u: 0, v: 1), .resize(u: 0, v: 0.5),
    ]
}

/// Resizing a (possibly rotated) box from one handle. The opposite point (the anchor) stays fixed in world space.
struct ResizeSession {
    let original: Box
    let u: CGFloat
    let v: CGFloat
    let lockAspect: Bool
    let minimumSize: CGFloat
    /// Text grows downward: its vertical anchor is always the top edge.
    let anchorsTop: Bool
    private let anchor: CGPoint // normalized (1-u, 1-v)
    private let anchorWorld: CGPoint
    private let grabOffset: CGPoint

    init(box: Box, u: CGFloat, v: CGFloat, touch: CGPoint, lockAspect: Bool, minimumSize: CGFloat, anchorsTop: Bool = false) {
        original = box
        self.u = u
        self.v = v
        self.lockAspect = lockAspect
        self.minimumSize = minimumSize
        self.anchorsTop = anchorsTop
        anchor = CGPoint(x: 1 - u, y: anchorsTop ? 0 : 1 - v)
        let frame = box.frame
        anchorWorld = box.toWorld(CGPoint(x: frame.minX + anchor.x * frame.width, y: frame.minY + anchor.y * frame.height))
        let handleWorld = box.toWorld(CGPoint(x: frame.minX + u * frame.width, y: frame.minY + v * frame.height))
        grabOffset = handleWorld - touch
    }

    /// The resized box for the current touch position. Width/height never flip; they clamp at the minimum.
    func box(for touch: CGPoint) -> Box {
        let w0 = max(original.frame.width, .ulpOfOne)
        let h0 = max(original.frame.height, .ulpOfOne)
        let d = (touch + grabOffset - anchorWorld).rotated(by: -original.rotation)
        let sx: CGFloat = u == 0.5 ? 0 : (u > anchor.x ? 1 : -1)
        let sy: CGFloat = v == 0.5 ? 0 : (v > anchor.y ? 1 : -1)
        var w = w0, h = h0
        if lockAspect {
            let minimumScale = minimumSize / min(w0, h0)
            if sx != 0 && sy != 0 {
                // Project the drag onto the box diagonal.
                let scale = max(minimumScale, (sx * d.x * w0 + sy * d.y * h0) / (w0 * w0 + h0 * h0))
                w = scale * w0
                h = scale * h0
            } else if sx != 0 {
                let scale = max(minimumScale, sx * d.x / w0)
                w = scale * w0
                h = scale * h0
            } else if sy != 0 {
                let scale = max(minimumScale, sy * d.y / h0)
                w = scale * w0
                h = scale * h0
            }
        } else {
            if sx != 0 { w = max(minimumSize, sx * d.x) }
            if sy != 0 { h = max(minimumSize, sy * d.y) }
        }
        return placed(width: w, height: h)
    }

    /// Box of the given size positioned so the anchor keeps its world position.
    func placed(width w: CGFloat, height h: CGFloat) -> Box {
        let offset = CGPoint(x: (anchor.x - 0.5) * w, y: (anchor.y - 0.5) * h).rotated(by: original.rotation)
        let center = anchorWorld - offset
        return Box(frame: CGRect(center: center, size: CGSize(width: w, height: h)), rotation: original.rotation)
    }
}

/// Rotating a box about its center with the rotation handle.
struct RotateSession {
    let original: Box
    private let startAngle: CGFloat

    init(box: Box, touch: CGPoint) {
        original = box
        let v = touch - box.center
        startAngle = atan2(v.y, v.x)
    }

    func box(for touch: CGPoint) -> Box {
        let v = touch - original.center
        let angle = GeometryMath.snapAngle(original.rotation + atan2(v.y, v.x) - startAngle)
        return Box(frame: original.frame, rotation: angle)
    }
}

enum TransformMath {
    /// Rect dragged out from `start` to `point`. Aspect-locked shapes (circle, square) use the longer side.
    static func creationRect(from start: CGPoint, to point: CGPoint, lockAspect: Bool) -> CGRect {
        guard lockAspect else { return CGRect.bounding([start, point]) }
        let dx = point.x - start.x, dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        let x = dx < 0 ? start.x - side : start.x
        let y = dy < 0 ? start.y - side : start.y
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// Moves an item by `delta`. Dragging a connector's body detaches both ends.
    static func translated(_ item: MarkupItem, by delta: CGPoint, in document: MarkupDocument) -> MarkupItem {
        var moved = item
        switch item.content {
        case .line(var line):
            let (start, end) = Bindings.resolvedEndpoints(line, in: document)
            line.start = Endpoint(point: start + delta)
            line.end = Endpoint(point: end + delta)
            line.waypoints = line.waypoints.map { $0 + delta }
            moved.content = .line(line)
        default:
            if let box = item.box { moved.box = box.offsetBy(delta) }
        }
        return moved
    }

    /// Replaces an item's box after a resize. Text switches to a fixed width and re-measures its height.
    static func resized(_ item: MarkupItem, to box: Box, session: ResizeSession) -> MarkupItem {
        var result = item
        switch item.content {
        case .text(var text):
            text.fixedWidth = box.frame.width
            let height = TextLayout.measuredSize(for: TextContent(
                text: text.text, font: text.font, color: text.color, alignment: text.alignment,
                fixedWidth: box.frame.width, padding: text.padding, box: box
            )).height
            text.box = session.placed(width: box.frame.width, height: height)
            result.content = .text(text)
        default:
            result.box = box
        }
        return result
    }

    /// Minimum item size for the current zoom: never smaller than 8 units or 24 screen points.
    static func minimumSize(zoom: CGFloat) -> CGFloat {
        max(8, 24 / max(zoom, 0.01))
    }
}
