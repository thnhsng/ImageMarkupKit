import CoreGraphics

// Vector helpers. Internal on purpose: operators on CoreGraphics types must not leak into host apps.

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    static func / (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x / s, y: a.y / s) }
    static prefix func - (a: CGPoint) -> CGPoint { CGPoint(x: -a.x, y: -a.y) }

    var length: CGFloat { hypot(x, y) }

    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }

    /// Rotates about the origin.
    func rotated(by angle: CGFloat) -> CGPoint {
        guard angle != 0 else { return self }
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }

    func rotated(by angle: CGFloat, around center: CGPoint) -> CGPoint {
        (self - center).rotated(by: angle) + center
    }

    var normalizedVector: CGPoint {
        let len = length
        return len > 0 ? self / len : .zero
    }

    /// Perpendicular (rotated +90°).
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }

    func dot(_ other: CGPoint) -> CGFloat { x * other.x + y * other.y }

    func cross(_ other: CGPoint) -> CGFloat { x * other.y - y * other.x }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    init(center: CGPoint, size: CGSize) {
        self.init(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Smallest rect containing all points (`.null` for an empty list).
    static func bounding(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

enum GeometryMath {
    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a
        let lengthSquared = ab.dot(ab)
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = min(max((p - a).dot(ab) / lengthSquared, 0), 1)
        return p.distance(to: a + ab * t)
    }

    static func distance(from p: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .greatestFiniteMagnitude }
        guard points.count > 1 else { return p.distance(to: first) }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 1..<points.count {
            best = min(best, distance(from: p, toSegment: points[i - 1], points[i]))
        }
        return best
    }

    static func segmentsIntersect(_ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint) -> Bool {
        let d1 = (a2 - a1).cross(b1 - a1)
        let d2 = (a2 - a1).cross(b2 - a1)
        let d3 = (b2 - b1).cross(a1 - b1)
        let d4 = (b2 - b1).cross(a2 - b1)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    static func distance(segment a1: CGPoint, _ a2: CGPoint, segment b1: CGPoint, _ b2: CGPoint) -> CGFloat {
        if segmentsIntersect(a1, a2, b1, b2) { return 0 }
        return min(
            distance(from: a1, toSegment: b1, b2),
            distance(from: a2, toSegment: b1, b2),
            distance(from: b1, toSegment: a1, a2),
            distance(from: b2, toSegment: a1, a2)
        )
    }

    /// Ramer–Douglas–Peucker simplification; always keeps the first and last point.
    static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, epsilon > 0 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            var maxDistance: CGFloat = 0
            var index = start
            for i in (start + 1)..<end {
                let d = distance(from: points[i], toSegment: points[start], points[end])
                if d > maxDistance {
                    maxDistance = d
                    index = i
                }
            }
            if maxDistance > epsilon {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Normalizes to (-π, π].
    static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }

    /// Snaps to the nearest multiple of `step` when within `tolerance`.
    static func snapAngle(_ angle: CGFloat, step: CGFloat = .pi / 4, tolerance: CGFloat = 4 * .pi / 180) -> CGFloat {
        let nearest = (angle / step).rounded() * step
        return abs(angle - nearest) <= tolerance ? normalizeAngle(nearest) : normalizeAngle(angle)
    }
}
