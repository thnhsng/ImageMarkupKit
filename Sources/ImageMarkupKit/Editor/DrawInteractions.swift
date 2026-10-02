import UIKit

/// Freehand pen and highlighter. The stroke in progress is a single preview layer; on release it becomes
/// a stroke item (simplified, normalized to its box).
final class PenInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let isHighlighter: Bool
    private let style: ItemStyle
    private var points: [CGPoint] = []
    private let previewLayer = NoAnimationShapeLayer()

    init(env: InteractionEnvironment, isHighlighter: Bool) {
        self.env = env
        self.isHighlighter = isHighlighter
        self.style = isHighlighter ? env.store.defaults.highlighter : env.store.defaults.pen
    }

    func begin(at point: CGPoint) {
        points = [point]
        previewLayer.strokeColor = style.strokeColor?.cgColor
        previewLayer.fillColor = nil
        previewLayer.lineWidth = style.lineWidth
        previewLayer.lineCap = .round
        previewLayer.lineJoin = .round
        previewLayer.opacity = Float(style.opacity)
        previewLayer.lineDashPattern = PathFactory.dashPattern(style.dash, lineWidth: style.lineWidth)?.map { NSNumber(value: Double($0)) }
        env.canvas.previewHost.layer.addSublayer(previewLayer)
        updatePreview(predicted: [])
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        let minimumDistance = 0.75 / env.zoom
        for sample in samples where sample.distance(to: points[points.count - 1]) >= minimumDistance {
            points.append(sample)
        }
        updatePreview(predicted: predicted)
    }

    func end(at point: CGPoint) {
        if point.distance(to: points[points.count - 1]) > 0 { points.append(point) }
        let simplified = GeometryMath.simplify(points, epsilon: 0.5 / env.zoom)
        let item = MarkupItem.stroke(points: simplified, style: style, isHighlighter: isHighlighter)
        var document = env.store.document
        document.items.append(item)
        document = Attachments.reassigningParents(of: [item.id], in: document)
        env.store.commit(document, actionName: isHighlighter ? Strings.actionHighlight : Strings.actionDraw)
        // Remove the preview in the same run-loop turn the committed view appears, so nothing flickers.
        previewLayer.removeFromSuperlayer()
    }

    func cancel() {
        previewLayer.removeFromSuperlayer()
    }

    private func updatePreview(predicted: [CGPoint]) {
        previewLayer.path = PathFactory.smoothedPath(points + predicted)
    }
}

/// Drags out a shape; a tap inserts a default-size shape. Preview uses the real item view (WYSIWYG).
final class ShapeCreateInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let kind: ShapeKind
    private let lockAspect: Bool
    private let itemID = UUID()
    private var start: CGPoint = .zero
    private var startDocument: MarkupDocument

    init(env: InteractionEnvironment, kind: ShapeKind, lockAspect: Bool) {
        self.env = env
        self.kind = kind
        self.lockAspect = lockAspect
        self.startDocument = env.store.document
    }

    private var style: ItemStyle {
        kind == .highlightBox ? env.store.defaults.highlightBox : env.store.defaults.shape
    }

    func begin(at point: CGPoint) {
        start = point
        startDocument = env.store.document
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        let rect = TransformMath.creationRect(from: start, to: point, lockAspect: lockAspect)
        guard max(rect.width, rect.height) * env.zoom > 4 else { return }
        env.store.setPreview(document(with: rect))
    }

    func end(at point: CGPoint) {
        var rect = TransformMath.creationRect(from: start, to: point, lockAspect: lockAspect)
        let minimum = TransformMath.minimumSize(zoom: env.zoom)
        if rect.width < minimum || rect.height < minimum {
            // A tap (or a tiny drag): insert a default-size shape centered on the touch.
            let size = lockAspect ? CGSize(width: 140, height: 140) : CGSize(width: 160, height: 120)
            rect = CGRect(center: start, size: size)
        }
        var document = document(with: rect)
        document = Attachments.reassigningParents(of: [itemID], in: document)
        env.store.commit(document, actionName: Strings.actionAddShape, select: [itemID])
        env.finishCreating(itemID, keepTool: false)
    }

    func cancel() {
        env.store.setPreview(nil)
    }

    private func document(with rect: CGRect) -> MarkupDocument {
        var document = startDocument
        var item = MarkupItem.shape(kind, frame: rect, lockAspect: lockAspect, style: style)
        item.id = itemID
        document.items.append(item)
        return document
    }
}

/// Lines and arrows, and curves (a line with one bend point in the middle, selected afterwards so it can be
/// bent right away). Ends that start or finish on an item attach to it, so the line follows that item.
final class ArrowCreateInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let kind: LineKind
    private let itemID = UUID()
    private var start: CGPoint = .zero
    private var startTarget: MarkupItem?
    private var startDocument: MarkupDocument

    init(env: InteractionEnvironment, kind: LineKind = .straight) {
        self.env = env
        self.kind = kind
        self.startDocument = env.store.document
    }

    func begin(at point: CGPoint) {
        start = point
        startDocument = env.store.document
        startTarget = HitTesting.bindTarget(at: point, in: startDocument, tolerance: env.tolerance)
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        guard start.distance(to: point) * env.zoom > 6 else { return }
        let endTarget = HitTesting.bindTarget(at: point, in: startDocument, tolerance: env.tolerance)
        env.overlay.showBindTarget(endTarget, canvas: env.canvas)
        env.store.setPreview(document(to: point, endTarget: nil))
    }

    func end(at point: CGPoint) {
        env.overlay.showBindTarget(nil, canvas: env.canvas)
        guard start.distance(to: point) * env.zoom > 6 else {
            env.store.setPreview(nil)
            return
        }
        let endTarget = HitTesting.bindTarget(at: point, in: startDocument, tolerance: env.tolerance)
        var document = document(to: point, endTarget: endTarget)
        document = Attachments.reassigningParents(of: [itemID], in: document)
        env.store.commit(document, actionName: kind == .curve ? Strings.actionAddCurve : Strings.actionAddArrow, select: [itemID])
        env.finishCreating(itemID, keepTool: false)
    }

    func cancel() {
        env.overlay.showBindTarget(nil, canvas: env.canvas)
        env.store.setPreview(nil)
    }

    private func document(to point: CGPoint, endTarget: MarkupItem?) -> MarkupDocument {
        let snap = 12 / env.zoom
        let startBinding = startTarget.flatMap { Bindings.binding(for: start, on: $0, snapDistance: snap) }
        let endBinding = endTarget.flatMap { Bindings.binding(for: point, on: $0, snapDistance: snap) }
        let defaults = env.store.defaults
        let isCurve = kind == .curve
        var line = LineContent(
            start: Endpoint(point: start, binding: startBinding),
            end: Endpoint(point: point, binding: endBinding),
            startHead: isCurve ? defaults.pathStartHead : defaults.lineStartHead,
            endHead: isCurve ? defaults.pathEndHead : defaults.lineEndHead,
            kind: kind
        )
        var document = startDocument
        let (s, e) = Bindings.resolvedEndpoints(line, in: document)
        line.start.point = s
        line.end.point = e
        // The bend point starts in the middle, so the new curve is straight until it is dragged.
        if isCurve { line.waypoints = [.midpoint(s, e)] }
        document.items.append(MarkupItem(id: itemID, content: .line(line), style: defaults.line))
        return document
    }
}

/// A polyline drawn over several touches: the committed item being extended, or the first tapped point.
@MainActor
final class PolylineDraft {
    /// The polyline being drawn (committed after its first segment; every further point is one undo step).
    private(set) var itemID: UUID?
    /// The first point, tapped before any segment exists. Nothing is committed for it.
    private(set) var pendingStart: CGPoint?
    /// Dot shown at `pendingStart`.
    private let marker = NoAnimationShapeLayer()

    var isActive: Bool { itemID != nil || pendingStart != nil }

    func begin(itemID: UUID) {
        self.itemID = itemID
        clearPendingStart()
    }

    func setPendingStart(_ point: CGPoint, style: ItemStyle, zoom: CGFloat, in host: UIView) {
        pendingStart = point
        let diameter = max(style.lineWidth * 1.6, 8 / zoom)
        marker.path = CGPath(ellipseIn: CGRect(center: point, size: CGSize(width: diameter, height: diameter)), transform: nil)
        marker.fillColor = (style.strokeColor ?? .red).cgColor
        marker.strokeColor = UIColor.white.cgColor
        marker.lineWidth = 1.5 / zoom
        host.layer.addSublayer(marker)
    }

    func clearPendingStart() {
        pendingStart = nil
        marker.removeFromSuperlayer()
    }

    func reset() {
        itemID = nil
        clearPendingStart()
    }

    /// Drops the draft if its polyline no longer exists (e.g. undone past its creation) or was closed.
    func validate(in document: MarkupDocument) {
        guard let itemID else { return }
        guard let line = document.item(itemID)?.lineContent, line.kind == .polyline, !line.isClosed else {
            self.itemID = nil
            return
        }
    }
}

/// Polylines, Paint-style but for fingers: each tap (or drag) adds a point; while the finger is down a segment
/// from the last point follows it (touch screens have no hover). Tapping the last point again finishes, tapping
/// the first point closes the shape. Every point is its own undo step, so Undo removes the last point.
final class PolylineCreateInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let newItemID = UUID()
    private var startDocument: MarkupDocument
    private var touchStart: CGPoint = .zero
    private var didMove = false

    init(env: InteractionEnvironment) {
        self.env = env
        self.startDocument = env.store.document
    }

    private var draft: PolylineDraft { env.polylineDraft }
    /// Touches within this distance of a point hit it (canvas units, same as the handles).
    private var snapDistance: CGFloat { SelectionOverlayView.touchRadius / env.zoom }
    private var style: ItemStyle { env.store.defaults.line }

    private var line: (id: UUID, content: LineContent)? {
        guard let id = draft.itemID, let content = startDocument.item(id)?.lineContent else { return nil }
        return (id, content)
    }

    /// Where the segment being drawn starts.
    private var anchor: CGPoint? {
        if let line { return Bindings.resolve(line.content.end, in: startDocument) }
        return draft.pendingStart ?? (didMove ? touchStart : nil)
    }

    func begin(at point: CGPoint) {
        draft.validate(in: env.store.document)
        startDocument = env.store.document
        touchStart = point
        didMove = false
        updatePreview(to: point)
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        if !didMove && point.distance(to: touchStart) * env.zoom > 6 { didMove = true }
        updatePreview(to: point)
    }

    func end(at point: CGPoint) {
        env.store.setPreview(nil)
        if let line {
            let points = Bindings.resolvedPoints(line.content, in: startDocument)
            if point.distance(to: points[points.count - 1]) <= snapDistance {
                env.finishPolyline()
            } else if points.count >= 3, point.distance(to: points[0]) <= snapDistance {
                env.finishPolyline(close: true)
            } else {
                env.store.commit(document(appending: point, to: line), actionName: Strings.actionAddPoint, select: [line.id])
            }
            return
        }
        if let pending = draft.pendingStart {
            if point.distance(to: pending) <= snapDistance {
                // Tapping the only point again takes it back.
                draft.clearPendingStart()
            } else {
                create(from: pending, to: point)
            }
            return
        }
        if didMove {
            create(from: touchStart, to: point)
        } else {
            draft.setPendingStart(point, style: style, zoom: env.zoom, in: env.canvas.previewHost)
        }
    }

    func cancel() {
        env.store.setPreview(nil)
    }

    private func updatePreview(to point: CGPoint) {
        guard let anchor, anchor.distance(to: point) * env.zoom > 1 else {
            if env.store.preview != nil { env.store.setPreview(nil) }
            return
        }
        if let line {
            env.store.setPreview(document(appending: point, to: line))
        } else {
            env.store.setPreview(document(creatingFrom: anchor, to: point))
        }
    }

    private func create(from start: CGPoint, to end: CGPoint) {
        var document = document(creatingFrom: start, to: end)
        document = Attachments.reassigningParents(of: [newItemID], in: document)
        env.store.commit(document, actionName: Strings.actionAddPolyline, select: [newItemID])
        draft.begin(itemID: newItemID)
    }

    private func document(creatingFrom start: CGPoint, to end: CGPoint) -> MarkupDocument {
        let defaults = env.store.defaults
        var item = MarkupItem.polyline(points: [start, end], startHead: defaults.pathStartHead, endHead: defaults.pathEndHead, style: style)
        item.id = newItemID
        var document = startDocument
        document.items.append(item)
        return document
    }

    /// The old end becomes a (free) waypoint and `point` the new end.
    private func document(appending point: CGPoint, to line: (id: UUID, content: LineContent)) -> MarkupDocument {
        var content = line.content
        content.waypoints.append(Bindings.resolve(content.end, in: startDocument))
        content.end = Endpoint(point: point)
        var document = startDocument
        document.update(line.id) { $0.content = .line(content) }
        return Attachments.reassigningParents(of: [line.id], in: document)
    }
}

/// Text and notes: a tap creates an empty box and starts editing it in place.
/// Nothing is committed until the text is non-empty (an abandoned box leaves no undo step).
final class TextCreateInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private let isNote: Bool
    private var start: CGPoint = .zero

    init(env: InteractionEnvironment, isNote: Bool) {
        self.env = env
        self.isNote = isNote
    }

    func begin(at point: CGPoint) {
        start = point
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {}

    func end(at point: CGPoint) {
        let defaults = env.store.defaults
        let font = isNote ? defaults.noteFont : defaults.textFont
        let padding: CGFloat = isNote ? 16 : 8
        // Put the first line's middle under the finger.
        let origin = CGPoint(x: start.x - padding, y: start.y - padding - font.size * 0.6)
        var item = MarkupItem.text(
            "", at: origin, font: font,
            color: isNote ? defaults.noteTextColor : defaults.textColor,
            alignment: defaults.textAlignment,
            fixedWidth: isNote ? 280 : nil,
            padding: padding,
            style: isNote ? defaults.note : defaults.text
        )
        item.id = UUID()
        var document = env.store.document
        document.items.append(item)
        env.store.setPreview(document)
        env.beginTextEditing?(item.id, true)
    }

    func cancel() {}
}

/// Object eraser: removes whole annotations the finger passes over (never photos or locked items).
final class EraserInteraction: CanvasInteraction {
    private let env: InteractionEnvironment
    private var last: CGPoint = .zero
    private var erased: [UUID] = []
    private let cursorLayer = NoAnimationShapeLayer()

    init(env: InteractionEnvironment) {
        self.env = env
    }

    private var radius: CGFloat { 12 / env.zoom }

    func begin(at point: CGPoint) {
        last = point
        cursorLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.25).cgColor
        cursorLayer.strokeColor = UIColor.systemGray.cgColor
        cursorLayer.lineWidth = 1 / env.zoom
        env.canvas.previewHost.layer.addSublayer(cursorLayer)
        erase(from: point, to: point)
    }

    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint]) {
        for sample in samples {
            erase(from: last, to: sample)
            last = sample
        }
    }

    func end(at point: CGPoint) {
        cursorLayer.removeFromSuperlayer()
        let ids = Set(erased)
        env.canvas.hiddenItemIDs.subtract(ids)
        guard !ids.isEmpty else { return }
        env.store.perform(Strings.actionErase, select: []) { document in
            document.items.removeAll { ids.contains($0.id) }
            Bindings.detachReferences(to: ids, in: &document)
        }
    }

    func cancel() {
        cursorLayer.removeFromSuperlayer()
        env.canvas.hiddenItemIDs.subtract(erased)
        erased = []
    }

    private func erase(from a: CGPoint, to b: CGPoint) {
        cursorLayer.path = CGPath(ellipseIn: CGRect(center: b, size: CGSize(width: 2 * radius, height: 2 * radius)), transform: nil)
        let hits = HitTesting.erasableItems(alongSegment: a, b, radius: radius, in: env.store.document)
        let new = hits.filter { !erased.contains($0) }
        guard !new.isEmpty else { return }
        erased += new
        env.canvas.hiddenItemIDs.formUnion(new)
    }
}
