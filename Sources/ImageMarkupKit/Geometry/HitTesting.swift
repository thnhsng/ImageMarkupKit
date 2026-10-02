import CoreGraphics
import Foundation

/// Which item a touch lands on. All tests run against the model, never the views.
enum HitTesting {
    /// Topmost selectable item at `point` (canvas units). `tolerance` is in canvas units (≈ 10 pt on screen).
    ///
    /// Pass 1 respects what is drawn (strokes, outlines, fills). Pass 2 lets a finger grab an unfilled
    /// shape by touching its inside, when nothing else was hit.
    static func item(at point: CGPoint, in document: MarkupDocument, tolerance: CGFloat) -> MarkupItem? {
        let backgroundID = document.backgroundItemID
        for item in document.items.reversed() where item.id != backgroundID {
            if hits(item, point, in: document, tolerance: tolerance) { return item }
        }
        for item in document.items.reversed() where item.id != backgroundID && item.style.fillColor == nil {
            switch item.content {
            case .shape(let shape):
                let local = boxSpacePoint(point, in: shape.box)
                let path = PathFactory.shapePath(kind: shape.kind, size: shape.box.frame.size, cornerRadius: item.style.cornerRadius)
                if path.contains(local) { return item }
            case .line(let line) where line.isClosed:
                if closedLinePath(line, in: document).contains(point) { return item }
            default:
                continue
            }
        }
        return nil
    }

    /// Outline of a closed polyline or curve (canvas units).
    private static func closedLinePath(_ line: LineContent, in document: MarkupDocument) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: LinePath.samples(of: line, in: document))
        path.closeSubpath()
        return path
    }

    static func hits(_ item: MarkupItem, _ point: CGPoint, in document: MarkupDocument, tolerance t: CGFloat) -> Bool {
        let lineWidth = item.style.effectiveLineWidth
        switch item.content {
        case .image(let content):
            return content.box.contains(point, tolerance: t)
        case .text(let content):
            return content.box.contains(point, tolerance: t)
        case .shape(let content):
            guard content.box.contains(point, tolerance: t + lineWidth / 2) else { return false }
            let local = boxSpacePoint(point, in: content.box)
            let path = PathFactory.shapePath(kind: content.kind, size: content.box.frame.size, cornerRadius: item.style.cornerRadius)
            if item.style.fillColor != nil, path.contains(local) { return true }
            let outline = path.copy(strokingWithWidth: max(lineWidth, 1) + 2 * t, lineCap: .round, lineJoin: .round, miterLimit: 10)
            return outline.contains(local)
        case .stroke(let content):
            guard content.box.contains(point, tolerance: t) else { return false }
            let local = boxSpacePoint(point, in: content.box)
            return GeometryMath.distance(from: local, toPolyline: PathFactory.strokePoints(content)) <= lineWidth / 2 + t
        case .line(let content):
            let samples = LinePath.samples(of: content, in: document)
            if GeometryMath.distance(from: point, toPolyline: samples) <= max(lineWidth, 1) / 2 + t { return true }
            if content.isClosed, item.style.fillColor != nil, closedLinePath(content, in: document).contains(point) { return true }
            let geometry = PathFactory.lineGeometry(content, in: document, lineWidth: item.style.lineWidth)
            return geometry.heads?.contains(point) ?? false
        }
    }

    /// Items touched by an eraser segment from `a` to `b` with radius `r` (canvas units).
    /// Photos, the background and locked items are never erased.
    static func erasableItems(alongSegment a: CGPoint, _ b: CGPoint, radius r: CGFloat, in document: MarkupDocument) -> [UUID] {
        let segmentBounds = CGRect.bounding([a, b]).insetBy(dx: -r, dy: -r)
        let samples = sample(from: a, to: b, step: max(r / 2, 0.5))
        var hitIDs: [UUID] = []
        for item in document.items where !item.isImage && !item.isLocked && item.id != document.backgroundItemID {
            guard ItemGeometry.visualBounds(of: item, in: document).intersects(segmentBounds) else { continue }
            let lineWidth = item.style.effectiveLineWidth
            let hit: Bool
            switch item.content {
            case .stroke(let content):
                let points = PathFactory.strokePoints(content).map { content.box.toWorld($0 + content.box.frame.origin) }
                hit = zip(points, points.dropFirst()).contains { GeometryMath.distance(segment: $0, $1, segment: a, b) <= r + lineWidth / 2 }
                    || (points.count == 1 && GeometryMath.distance(from: points[0], toSegment: a, b) <= r + lineWidth / 2)
            case .line(let content):
                let points = LinePath.samples(of: content, in: document)
                if zip(points, points.dropFirst()).contains(where: { GeometryMath.distance(segment: $0, $1, segment: a, b) <= r + max(lineWidth, 1) / 2 }) {
                    hit = true
                } else if content.isClosed, item.style.fillColor != nil {
                    let fill = closedLinePath(content, in: document)
                    hit = samples.contains { fill.contains($0) }
                } else {
                    hit = false
                }
            case .shape(let content):
                let path = PathFactory.shapePath(kind: content.kind, size: content.box.frame.size, cornerRadius: item.style.cornerRadius)
                let outline = path.copy(strokingWithWidth: max(lineWidth, 1) + 2 * r, lineCap: .round, lineJoin: .round, miterLimit: 10)
                hit = samples.contains { sample in
                    let local = boxSpacePoint(sample, in: content.box)
                    return outline.contains(local) || (item.style.fillColor != nil && path.contains(local))
                }
            case .text(let content):
                hit = samples.contains { content.box.contains($0, tolerance: r) }
            case .image:
                hit = false
            }
            if hit { hitIDs.append(item.id) }
        }
        return hitIDs
    }

    /// Topmost item that can receive a connector endpoint at `point`, skipping `excluding`.
    static func bindTarget(at point: CGPoint, in document: MarkupDocument, tolerance: CGFloat, excluding: Set<UUID> = []) -> MarkupItem? {
        for item in document.items.reversed() where !excluding.contains(item.id) && Bindings.isValidTarget(item, in: document) {
            if let box = item.box, box.contains(point, tolerance: tolerance) { return item }
        }
        return nil
    }

    /// World point → box space (origin at the frame's top-left, rotation undone).
    static func boxSpacePoint(_ point: CGPoint, in box: Box) -> CGPoint {
        let q = box.toLocal(point)
        return CGPoint(x: q.x - box.frame.minX, y: q.y - box.frame.minY)
    }

    private static func sample(from a: CGPoint, to b: CGPoint, step: CGFloat) -> [CGPoint] {
        let length = a.distance(to: b)
        let count = max(Int(ceil(length / step)), 1)
        return (0...count).map { i in a + (b - a) * (CGFloat(i) / CGFloat(count)) }
    }
}
