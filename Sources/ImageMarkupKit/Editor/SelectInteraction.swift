import UIKit

/// Drags an item. Photos carry their attached annotations along (board mode).
final class MoveInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let itemID: UUID
    private var startDocument: MarkupDocument
    private var startPoint: CGPoint = .zero
    private var didMove = false

    init(env: InteractionEnvironment, itemID: UUID) {
        self.env = env
        self.itemID = itemID
        self.startDocument = env.store.document
    }

    func begin(at point: CGPoint) {
        startDocument = env.store.document
        startPoint = point
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard let item = startDocument.item(itemID), !item.isLocked else { return }
        let delta = point - startPoint
        guard didMove || delta.length * env.zoom > 2 else { return }
        didMove = true
        var document = startDocument
        let moved = TransformMath.translated(item, by: delta, in: startDocument)
        document.update(itemID) { $0 = moved }
        Attachments.carryChildren(of: item, to: moved, from: startDocument, into: &document)
        env.store.setPreview(document)
    }

    func end(at point: CGPoint) {
        guard didMove, let preview = env.store.preview else {
            env.store.setPreview(nil)
            return
        }
        env.store.commit(Attachments.reassigningParents(of: [itemID], in: preview), actionName: Strings.actionMove)
    }

    func cancel() {
        env.store.setPreview(nil)
    }
}

/// Resizes the selected item from one of its 8 handles (text: left/right only).
final class ResizeInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let itemID: UUID
    private let u: CGFloat
    private let v: CGFloat
    private var startDocument: MarkupDocument
    private var session: ResizeSession?

    init(env: InteractionEnvironment, itemID: UUID, u: CGFloat, v: CGFloat) {
        self.env = env
        self.itemID = itemID
        self.u = u
        self.v = v
        self.startDocument = env.store.document
    }

    func begin(at point: CGPoint) {
        startDocument = env.store.document
        guard let item = startDocument.item(itemID), let box = item.box, !item.isLocked else { return }
        session = ResizeSession(
            box: box, u: u, v: v, touch: point,
            lockAspect: item.locksAspectRatio,
            minimumSize: TransformMath.minimumSize(zoom: env.zoom),
            anchorsTop: item.isText
        )
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard let session, let item = startDocument.item(itemID) else { return }
        let resized = TransformMath.resized(item, to: session.box(for: point), session: session)
        var document = startDocument
        document.update(itemID) { $0 = resized }
        Attachments.carryChildren(of: item, to: resized, from: startDocument, into: &document)
        env.store.setPreview(document)
    }

    func end(at point: CGPoint) {
        guard session != nil, let preview = env.store.preview else {
            env.store.setPreview(nil)
            return
        }
        env.store.commit(preview, actionName: Strings.actionResize)
    }

    func cancel() {
        env.store.setPreview(nil)
    }
}

/// Rotates the selected item about its center; snaps to 45° steps.
final class RotateInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let itemID: UUID
    private var startDocument: MarkupDocument
    private var session: RotateSession?

    init(env: InteractionEnvironment, itemID: UUID) {
        self.env = env
        self.itemID = itemID
        self.startDocument = env.store.document
    }

    func begin(at point: CGPoint) {
        startDocument = env.store.document
        guard let item = startDocument.item(itemID), let box = item.box, !item.isLocked else { return }
        session = RotateSession(box: box, touch: point)
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard let session, let item = startDocument.item(itemID) else { return }
        var rotated = item
        rotated.box = session.box(for: point)
        var document = startDocument
        document.update(itemID) { $0 = rotated }
        Attachments.carryChildren(of: item, to: rotated, from: startDocument, into: &document)
        env.store.setPreview(document)
    }

    func end(at point: CGPoint) {
        guard session != nil, let preview = env.store.preview else {
            env.store.setPreview(nil)
            return
        }
        env.store.commit(preview, actionName: Strings.actionRotate)
    }

    func cancel() {
        env.store.setPreview(nil)
    }
}

/// Drags one point of a line (`index` 0 is the start, the last index the end). The ends of an open line attach
/// to the item they are released over. A tap without dragging calls `onTap`.
final class LineVertexInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let itemID: UUID
    private let index: Int
    private var startDocument: MarkupDocument
    private var startTouch: CGPoint = .zero
    private var origin: CGPoint?
    private var didMove = false
    var onTap: (() -> Void)?

    init(env: InteractionEnvironment, itemID: UUID, index: Int) {
        self.env = env
        self.itemID = itemID
        self.index = index
        self.startDocument = env.store.document
    }

    private var line: LineContent? { startDocument.item(itemID)?.lineContent }

    /// Ends of open lines can attach to items.
    private var isBindable: Bool {
        guard let line else { return false }
        return !line.isClosed && (index == 0 || index == line.waypoints.count + 1)
    }

    func begin(at point: CGPoint) {
        startDocument = env.store.document
        startTouch = point
        guard let item = startDocument.item(itemID), !item.isLocked, let line = item.lineContent else { return }
        let points = Bindings.resolvedPoints(line, in: startDocument)
        origin = points.indices.contains(index) ? points[index] : nil
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard let origin else { return }
        guard didMove || point.distance(to: startTouch) * env.zoom > 3 else { return }
        didMove = true
        // Keep the finger's offset from the point, so the point doesn't jump under the finger.
        let position = origin + (point - startTouch)
        if isBindable {
            let target = HitTesting.bindTarget(at: position, in: startDocument, tolerance: env.tolerance, excluding: [itemID])
            env.overlay.showBindTarget(target, canvas: env.canvas)
        }
        update(Endpoint(point: position))
    }

    func end(at point: CGPoint) {
        env.overlay.showBindTarget(nil, canvas: env.canvas)
        guard didMove, let origin else {
            env.store.setPreview(nil)
            if !didMove { onTap?() }
            return
        }
        let position = origin + (point - startTouch)
        var endpoint = Endpoint(point: position)
        if isBindable,
           let target = HitTesting.bindTarget(at: position, in: startDocument, tolerance: env.tolerance, excluding: [itemID]),
           let binding = Bindings.binding(for: position, on: target, snapDistance: 12 / env.zoom) {
            endpoint.binding = binding
        }
        update(endpoint)
        if let preview = env.store.preview {
            let isEnd = index == 0 || index == (line?.waypoints.count ?? 0) + 1
            env.store.commit(preview, actionName: isEnd ? Strings.actionMoveEndpoint : Strings.actionMovePoint)
        }
    }

    func cancel() {
        env.overlay.showBindTarget(nil, canvas: env.canvas)
        env.store.setPreview(nil)
    }

    private func update(_ endpoint: Endpoint) {
        guard let item = startDocument.item(itemID), !item.isLocked, case .line(var line) = item.content else { return }
        if index == 0 {
            line.start = endpoint
        } else if index == line.waypoints.count + 1 {
            line.end = endpoint
        } else if line.waypoints.indices.contains(index - 1) {
            line.waypoints[index - 1] = endpoint.point
        } else {
            return
        }
        var document = startDocument
        document.update(itemID) { $0.content = .line(line) }
        env.store.setPreview(document)
    }
}

/// The "+" handle in the middle of a polyline or curve segment: inserts a point there and drags it.
/// A tap inserts the point in place.
final class LineInsertInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let itemID: UUID
    /// Segment from point `segment` to point `segment + 1` (for closed lines, the last one returns to the start).
    private let segment: Int
    private var startDocument: MarkupDocument
    private var startTouch: CGPoint = .zero
    private var origin: CGPoint?

    init(env: InteractionEnvironment, itemID: UUID, segment: Int) {
        self.env = env
        self.itemID = itemID
        self.segment = segment
        self.startDocument = env.store.document
    }

    func begin(at point: CGPoint) {
        startDocument = env.store.document
        startTouch = point
        guard let item = startDocument.item(itemID), !item.isLocked, let line = item.lineContent, line.hasEditablePoints else { return }
        let points = Bindings.resolvedPoints(line, in: startDocument)
        let handles = LinePath.insertionPoints(points, kind: line.kind, closed: line.isClosed)
        guard handles.indices.contains(segment) else { return }
        origin = handles[segment]
        update(to: handles[segment])
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard let origin else { return }
        update(to: origin + (point - startTouch))
    }

    func end(at point: CGPoint) {
        guard let origin else { return }
        update(to: origin + (point - startTouch))
        if let preview = env.store.preview {
            env.store.commit(preview, actionName: Strings.actionAddPoint)
        }
    }

    func cancel() {
        env.store.setPreview(nil)
    }

    private func update(to position: CGPoint) {
        guard let item = startDocument.item(itemID), case .line(var line) = item.content else { return }
        if segment <= line.waypoints.count {
            line.waypoints.insert(position, at: segment)
        } else {
            // Closing segment (end → start): the old end becomes a waypoint and the new point the end.
            line.waypoints.append(Bindings.resolve(line.end, in: startDocument))
            line.end = Endpoint(point: position)
        }
        var document = startDocument
        document.update(itemID) { $0.content = .line(line) }
        env.store.setPreview(document)
    }
}
