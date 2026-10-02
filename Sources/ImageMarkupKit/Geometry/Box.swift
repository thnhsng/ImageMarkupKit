import CoreGraphics

// Terminology:
// - world: canvas coordinates.
// - frame space: world coordinates with the box's rotation undone (the space `frame` lives in).
// - box space: origin at the frame's top-left, x/y in 0…width / 0…height. Paths are built here.

extension Box {
    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    public var size: CGSize { frame.size }

    /// Frame space → world.
    public func toWorld(_ p: CGPoint) -> CGPoint {
        rotation == 0 ? p : p.rotated(by: rotation, around: center)
    }

    /// World → frame space.
    public func toLocal(_ p: CGPoint) -> CGPoint {
        rotation == 0 ? p : p.rotated(by: -rotation, around: center)
    }

    /// World position of a normalized (0…1) point inside the box.
    public func worldPoint(normalized u: CGPoint) -> CGPoint {
        toWorld(CGPoint(x: frame.minX + u.x * frame.width, y: frame.minY + u.y * frame.height))
    }

    /// Normalized (0…1, unclamped) position of a world point inside the box.
    public func normalizedPoint(world p: CGPoint) -> CGPoint {
        let q = toLocal(p)
        return CGPoint(
            x: (q.x - frame.minX) / max(frame.width, .ulpOfOne),
            y: (q.y - frame.minY) / max(frame.height, .ulpOfOne)
        )
    }

    /// Box space → world. Equivalent to a view with `bounds.size = frame.size`, `center`, and a rotation transform.
    public var boxToWorld: CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation)
            .translatedBy(x: -frame.width / 2, y: -frame.height / 2)
    }

    /// Corners in world space: top-left, top-right, bottom-right, bottom-left.
    public var corners: [CGPoint] {
        [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY),
        ].map(toWorld)
    }

    /// Axis-aligned bounds of the rotated box.
    public var boundingRect: CGRect {
        rotation == 0 ? frame : CGRect.bounding(corners)
    }

    public func contains(_ p: CGPoint, tolerance: CGFloat = 0) -> Bool {
        frame.insetBy(dx: -tolerance, dy: -tolerance).contains(toLocal(p))
    }

    /// Moves the box so its center is at `center`, keeping size and rotation.
    func centered(at newCenter: CGPoint) -> Box {
        Box(frame: CGRect(center: newCenter, size: frame.size), rotation: rotation)
    }

    func offsetBy(_ delta: CGPoint) -> Box {
        Box(frame: frame.offsetBy(dx: delta.x, dy: delta.y), rotation: rotation)
    }
}
