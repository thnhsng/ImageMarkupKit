import CoreGraphics

/// Geometry of lines through several points (polylines and curves).
///
/// Curves are centripetal Catmull-Rom splines through the points (no cusps or loops between close points),
/// flattened to short segments. Drawing, hit testing, erasing and bounds all use the flattened samples, so one
/// code path serves every line kind and the screen and the export always agree.
enum LinePath {
    /// Samples along the line in canvas units, for all of its points. Closed lines end with the first sample.
    static func samples(of line: LineContent, in document: MarkupDocument) -> [CGPoint] {
        flattened(Bindings.resolvedPoints(line, in: document), kind: line.kind, closed: line.isClosed)
    }

    /// Samples through `points` (first to last, then back to the first when `closed`).
    static func flattened(_ points: [CGPoint], kind: LineKind, closed: Bool) -> [CGPoint] {
        let parts = segments(points, kind: kind, closed: closed)
        guard var result = parts.first else { return points }
        for part in parts.dropFirst() { result += part.dropFirst() }
        return result
    }

    /// Whether `points` form a closed line (closing needs at least three points).
    static func closes(_ points: [CGPoint], closed: Bool) -> Bool {
        closed && points.count >= 3
    }

    /// Samples of each segment (point i → point i+1, plus last → first when closed), both ends included.
    static func segments(_ points: [CGPoint], kind: LineKind, closed: Bool) -> [[CGPoint]] {
        guard points.count > 1 else { return points.isEmpty ? [] : [points] }
        let isClosed = closes(points, closed: closed)
        let count = points.count
        let segmentCount = isClosed ? count : count - 1
        let smooth = kind == .curve && (count >= 3 || isClosed)

        func point(_ i: Int) -> CGPoint {
            if isClosed { return points[((i % count) + count) % count] }
            // Open ends: reflect the neighbor, so the curve leaves the end smoothly without a zero-length knot.
            if i < 0 { return points[0] * 2 - points[1] }
            if i >= count { return points[count - 1] * 2 - points[count - 2] }
            return points[i]
        }

        return (0..<segmentCount).map { i in
            let a = point(i), b = point(i + 1)
            guard smooth else { return [a, b] }
            return catmullRom(point(i - 1), a, b, point(i + 2))
        }
    }

    /// Where the "+" handles go: the middle (by length) of each segment.
    static func insertionPoints(_ points: [CGPoint], kind: LineKind, closed: Bool) -> [CGPoint] {
        segments(points, kind: kind, closed: closed).map { point(atDistance: length(of: $0) / 2, along: $0) }
    }

    // MARK: Polyline measurements

    static func length(of samples: [CGPoint]) -> CGFloat {
        zip(samples, samples.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point `distance` along the samples from the first one (clamped to the ends).
    static func point(atDistance distance: CGFloat, along samples: [CGPoint]) -> CGPoint {
        guard var previous = samples.first else { return .zero }
        var remaining = max(distance, 0)
        for next in samples.dropFirst() {
            let step = previous.distance(to: next)
            if step >= remaining, step > 0 {
                return previous + (next - previous) * (remaining / step)
            }
            remaining -= step
            previous = next
        }
        return previous
    }

    /// The samples with `head` removed from the start and `tail` from the end (lengths along the line).
    static func trimmed(_ samples: [CGPoint], head: CGFloat, tail: CGFloat) -> [CGPoint] {
        guard samples.count > 1, head > 0 || tail > 0 else { return samples }
        let total = length(of: samples)
        let from = min(max(head, 0), total)
        let to = max(total - max(tail, 0), from)
        var result = [point(atDistance: from, along: samples)]
        var travelled: CGFloat = 0
        for (a, b) in zip(samples, samples.dropFirst()) {
            travelled += a.distance(to: b)
            if travelled > from && travelled < to { result.append(b) }
        }
        result.append(point(atDistance: to, along: samples))
        return result
    }

    // MARK: Catmull-Rom

    /// Centripetal Catmull-Rom (α = ½) from `p1` to `p2`, sampled densely enough to look smooth when zoomed
    /// in or exported at full photo resolution. Barry–Goldman evaluation.
    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> [CGPoint] {
        let chord = p1.distance(to: p2)
        guard chord > 0.0001 else { return [p1, p2] }
        func knot(_ a: CGPoint, _ b: CGPoint) -> CGFloat { max(sqrt(a.distance(to: b)), 0.0001) }
        let t0: CGFloat = 0
        let t1 = t0 + knot(p0, p1)
        let t2 = t1 + knot(p1, p2)
        let t3 = t2 + knot(p2, p3)
        func lerp(_ a: CGPoint, _ b: CGPoint, _ ta: CGFloat, _ tb: CGFloat, _ t: CGFloat) -> CGPoint {
            a * ((tb - t) / (tb - ta)) + b * ((t - ta) / (tb - ta))
        }
        let count = min(max(Int((chord / 6).rounded(.up)), 12), 96)
        var result: [CGPoint] = [p1]
        for step in 1..<count {
            let t = t1 + (t2 - t1) * CGFloat(step) / CGFloat(count)
            let a1 = lerp(p0, p1, t0, t1, t)
            let a2 = lerp(p1, p2, t1, t2, t)
            let a3 = lerp(p2, p3, t2, t3, t)
            let b1 = lerp(a1, a2, t0, t2, t)
            let b2 = lerp(a2, a3, t1, t3, t)
            result.append(lerp(b1, b2, t1, t2, t))
        }
        result.append(p2)
        return result
    }
}
