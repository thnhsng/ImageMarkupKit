import CoreGraphics
import Foundation

/// Board mode: annotations drawn on a photo are attached to it (`parentID`) and follow it when the photo is
/// moved, resized or rotated, so rearranging photos never strands the marks made on them.
enum Attachments {
    /// Applies a photo's change (`old` → `new`) to its attached annotations as one similarity transform:
    /// S(p) = c₁ + k·R(θ₁ − θ₀)(p − c₀), with k = w₁ / w₀ (photos keep their aspect ratio).
    /// Shapes and strokes move, scale and rotate; text only moves (its font size stays); free line ends move,
    /// bound ends already follow their target, line waypoints move with the photo.
    static func carryChildren(of old: MarkupItem, to new: MarkupItem, from source: MarkupDocument, into document: inout MarkupDocument) {
        guard source.isBoard, old.isImage, let b0 = old.box, let b1 = new.box, b0 != b1 else { return }
        let k = b1.frame.width / max(b0.frame.width, .ulpOfOne)
        let deltaAngle = b1.rotation - b0.rotation
        let c0 = b0.center, c1 = b1.center
        func map(_ p: CGPoint) -> CGPoint { c1 + (p - c0).rotated(by: deltaAngle) * k }

        for child in source.items where child.parentID == old.id {
            document.update(child.id) { item in
                switch item.content {
                case .shape, .stroke:
                    guard let box = item.box else { return }
                    let size = CGSize(width: box.frame.width * k, height: box.frame.height * k)
                    item.box = Box(frame: CGRect(center: map(box.center), size: size), rotation: box.rotation + deltaAngle)
                case .text:
                    guard let box = item.box else { return }
                    item.box = box.centered(at: map(box.center))
                case .line(var line):
                    if line.start.binding == nil { line.start.point = map(line.start.point) }
                    if line.end.binding == nil { line.end.point = map(line.end.point) }
                    line.waypoints = line.waypoints.map(map)
                    item.content = .line(line)
                case .image:
                    break
                }
            }
        }
    }

    /// The photo an annotation belongs to: the topmost photo containing the annotation's visual center.
    static func parent(for item: MarkupItem, in document: MarkupDocument) -> UUID? {
        guard document.isBoard, !item.isImage else { return nil }
        let center: CGPoint
        if let line = item.lineContent {
            center = CGRect.bounding(Bindings.resolvedPoints(line, in: document)).center
        } else if let box = item.box {
            center = box.center
        } else {
            return nil
        }
        return document.items.last { $0.isImage && ($0.box?.contains(center) ?? false) }?.id
    }

    /// Re-evaluates the parent of the given annotations (after they were created or moved).
    static func reassigningParents(of ids: [UUID], in document: MarkupDocument) -> MarkupDocument {
        guard document.isBoard else { return document }
        var result = document
        for id in ids {
            guard let item = document.item(id), !item.isImage else { continue }
            let parent = parent(for: item, in: document)
            if parent != item.parentID {
                result.update(id) { $0.parentID = parent }
            }
        }
        return result
    }
}
