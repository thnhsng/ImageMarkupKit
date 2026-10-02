import CoreGraphics
import Foundation

/// Connector endpoints that are attached to other items.
enum Bindings {
    /// World position of an endpoint. Bound endpoints follow their target's move/resize/rotation.
    static func resolve(_ endpoint: Endpoint, in document: MarkupDocument) -> CGPoint {
        guard
            let binding = endpoint.binding,
            let target = document.item(binding.itemID),
            let box = target.box
        else { return endpoint.point }
        return box.worldPoint(normalized: binding.anchor)
    }

    static func resolvedEndpoints(_ line: LineContent, in document: MarkupDocument) -> (start: CGPoint, end: CGPoint) {
        (resolve(line.start, in: document), resolve(line.end, in: document))
    }

    /// Every point of the line in drawing order: resolved start, waypoints, resolved end.
    static func resolvedPoints(_ line: LineContent, in document: MarkupDocument) -> [CGPoint] {
        [resolve(line.start, in: document)] + line.waypoints + [resolve(line.end, in: document)]
    }

    /// Whether `item` may receive a connector endpoint.
    static func isValidTarget(_ item: MarkupItem, in document: MarkupDocument) -> Bool {
        item.box != nil && item.id != document.backgroundItemID
    }

    /// Binding for a world point dropped on `target`. Snaps to the center or an edge midpoint when close.
    static func binding(for point: CGPoint, on target: MarkupItem, snapDistance: CGFloat) -> ConnectorBinding? {
        guard let box = target.box else { return nil }
        var anchor = box.normalizedPoint(world: point)
        anchor.x = min(max(anchor.x, 0), 1)
        anchor.y = min(max(anchor.y, 0), 1)
        let magnets = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.5, y: 1), CGPoint(x: 0, y: 0.5)]
        for magnet in magnets where box.worldPoint(normalized: magnet).distance(to: point) <= snapDistance {
            anchor = magnet
            break
        }
        return ConnectorBinding(itemID: target.id, anchor: anchor)
    }

    /// Removes references to deleted items. Bound endpoints freeze at their last resolved position
    /// (the cached `point`), attached annotations become free.
    static func detachReferences(to removed: Set<UUID>, in document: inout MarkupDocument) {
        guard !removed.isEmpty else { return }
        for index in document.items.indices {
            if let parent = document.items[index].parentID, removed.contains(parent) {
                document.items[index].parentID = nil
            }
            guard case .line(var line) = document.items[index].content else { continue }
            var changed = false
            if let binding = line.start.binding, removed.contains(binding.itemID) {
                line.start.binding = nil
                changed = true
            }
            if let binding = line.end.binding, removed.contains(binding.itemID) {
                line.end.binding = nil
                changed = true
            }
            if changed { document.items[index].content = .line(line) }
        }
    }

    /// Writes resolved positions into every line's cached `point`, so stored JSON stays self-consistent.
    static func refreshCachedEndpoints(in document: inout MarkupDocument) {
        let snapshot = document
        for index in document.items.indices {
            guard case .line(var line) = document.items[index].content else { continue }
            let (start, end) = resolvedEndpoints(line, in: snapshot)
            guard start != line.start.point || end != line.end.point else { continue }
            line.start.point = start
            line.end.point = end
            document.items[index].content = .line(line)
        }
    }
}
