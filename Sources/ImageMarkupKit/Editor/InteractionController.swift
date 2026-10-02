import UIKit

/// Routes canvas touches to interactions and arbitrates with the scroll view:
/// - Select: touches on items/handles move/resize; touches elsewhere scroll with one finger.
/// - Drawing tools: one finger draws; two fingers pan and pinch.
@MainActor
final class InteractionController: NSObject, UIGestureRecognizerDelegate {
    let env: InteractionEnvironment
    private let touchRecognizer = CanvasTouchRecognizer(target: nil, action: nil)
    private let emptyTapRecognizer = UITapGestureRecognizer(target: nil, action: nil)
    private var active: CanvasInteraction?
    private var tapTarget: (id: UUID, wasSelected: Bool)?
    private var previousActiveVertex: (itemID: UUID, index: Int)?
    /// Views whose touches the canvas must ignore (text editor, panels).
    var excludedViews: () -> [UIView] = { [] }
    /// Called with `true` when a gesture starts and `false` when it ends.
    var onInteractionActiveChange: ((Bool) -> Void)?
    /// Makes interactions for the drawing tools (set by the editor; Select is handled here).
    var makeToolInteraction: ((MarkupTool, InteractionEnvironment) -> CanvasInteraction?)?

    init(env: InteractionEnvironment) {
        self.env = env
        super.init()
        touchRecognizer.addTarget(self, action: #selector(handleTouch(_:)))
        touchRecognizer.delegate = self
        touchRecognizer.shouldTrack = { [weak self] touch in self?.shouldTrack(touch) ?? false }
        env.canvas.addGestureRecognizer(touchRecognizer)

        emptyTapRecognizer.addTarget(self, action: #selector(handleEmptyTap(_:)))
        emptyTapRecognizer.delegate = self
        emptyTapRecognizer.cancelsTouchesInView = false
        env.canvas.addGestureRecognizer(emptyTapRecognizer)

        env.canvas.scrollView.shouldBeginPan = { [weak self] _ in !(self?.isTracking ?? false) }
        updateForTool()
    }

    var isTracking: Bool { touchRecognizer.state == .began || touchRecognizer.state == .changed }

    var isInteracting: Bool { active != nil }

    func updateForTool() {
        let scrollView = env.canvas.scrollView
        scrollView.panGestureRecognizer.minimumNumberOfTouches = env.store.tool.drawsWithOneFinger ? 2 : 1
        // Leaving the Polyline tool ends the polyline being drawn (its points are already committed).
        if env.store.tool != .polyline { env.polylineDraft.reset() }
    }

    /// Stops any gesture in progress (e.g. when the tool changes).
    func cancelActiveInteraction() {
        active?.cancel()
        active = nil
        touchRecognizer.isEnabled = false
        touchRecognizer.isEnabled = true
        onInteractionActiveChange?(false)
    }

    // MARK: Touch routing

    private func shouldTrack(_ touch: UITouch) -> Bool {
        // A touch outside the text being edited finishes the edit and does nothing else.
        if env.isEditingText() {
            env.endTextEditing()
            return false
        }
        guard env.store.tool == .select else { return true }
        if env.overlay.handle(at: touch.location(in: env.overlay)) != nil { return true }
        let point = env.canvas.canvasPoint(touch.location(in: env.canvas), from: env.canvas)
        return HitTesting.item(at: point, in: env.store.displayed, tolerance: env.tolerance) != nil
    }

    @objc private func handleTouch(_ recognizer: CanvasTouchRecognizer) {
        let canvas = env.canvas
        let point = canvas.canvasPoint(recognizer.currentLocation, from: canvas)
        switch recognizer.state {
        case .began:
            let start = canvas.canvasPoint(recognizer.startLocation, from: canvas)
            // Any touch deselects the tapped line point; tapping a point sets it again (see `vertexInteraction`).
            previousActiveVertex = env.activeLineVertex
            env.activeLineVertex = nil
            active = makeInteraction(startingAt: start, screenPoint: recognizer.startLocation)
            active?.begin(at: start)
            onInteractionActiveChange?(true)
        case .changed:
            let samples = recognizer.samples.map { canvas.canvasPoint($0, from: canvas) }
            let predicted = recognizer.predictedSamples.map { canvas.canvasPoint($0, from: canvas) }
            active?.move(to: point, samples: samples, predicted: predicted)
        case .ended:
            active?.end(at: point)
            active = nil
            if recognizer.isTap { handleTap(tapCount: recognizer.tapCount) }
            tapTarget = nil
            onInteractionActiveChange?(false)
        case .cancelled, .failed:
            active?.cancel()
            active = nil
            tapTarget = nil
            onInteractionActiveChange?(false)
        default:
            break
        }
    }

    private func makeInteraction(startingAt point: CGPoint, screenPoint: CGPoint) -> CanvasInteraction? {
        let store = env.store
        let overlayPoint = env.overlay.convert(screenPoint, from: env.canvas)
        if store.tool == .polyline,
           let id = env.polylineDraft.itemID, store.selectedItem?.id == id,
           case .lineVertex(let index)? = env.overlay.handle(at: overlayPoint),
           let count = store.document.item(id)?.lineContent?.points.count,
           index > 0 && index < count - 1 {
            // While drawing a polyline, dragging one of its middle points moves it; touches near the first or
            // last point still add, close or finish (see `PolylineCreateInteraction`).
            return LineVertexInteraction(env: env, itemID: id, index: index)
        }
        guard store.tool == .select else {
            return makeToolInteraction?(store.tool, env)
        }
        if let handle = env.overlay.handle(at: overlayPoint), let item = store.selectedItem {
            switch handle {
            case .resize(let u, let v): return ResizeInteraction(env: env, itemID: item.id, u: u, v: v)
            case .rotate: return RotateInteraction(env: env, itemID: item.id)
            case .lineVertex(let index): return vertexInteraction(item: item, index: index)
            case .lineInsert(let segment): return LineInsertInteraction(env: env, itemID: item.id, segment: segment)
            }
        }
        guard let item = HitTesting.item(at: point, in: store.displayed, tolerance: env.tolerance) else { return nil }
        tapTarget = (item.id, store.selection.contains(item.id))
        store.select([item.id])
        return MoveInteraction(env: env, itemID: item.id)
    }

    /// Drags a line point. Tapping a point of a polyline or curve marks it (the action bar offers Delete Point);
    /// tapping it again unmarks it.
    private func vertexInteraction(item: MarkupItem, index: Int) -> CanvasInteraction {
        let interaction = LineVertexInteraction(env: env, itemID: item.id, index: index)
        let wasActive = previousActiveVertex.map { $0.itemID == item.id && $0.index == index } ?? false
        if item.lineContent?.hasEditablePoints == true && !wasActive {
            interaction.onTap = { [env] in env.activeLineVertex = (item.id, index) }
        }
        return interaction
    }

    /// Select mode taps: tapping a selected text item (or double-tapping one) edits it.
    private func handleTap(tapCount: Int) {
        guard env.store.tool == .select, let target = tapTarget, let item = env.store.document.item(target.id) else { return }
        if item.isText && !item.isLocked && (target.wasSelected || tapCount >= 2) {
            env.beginTextEditing?(item.id, false)
        }
    }

    @objc private func handleEmptyTap(_ recognizer: UITapGestureRecognizer) {
        guard env.store.tool == .select, recognizer.state == .ended, !env.isEditingText() else { return }
        env.store.clearSelection()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let view = touch.view else { return true }
        if view is UIControl || view.isDescendant(of: env.overlay.actionBar) { return false }
        return !excludedViews().contains { view.isDescendant(of: $0) }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === touchRecognizer else { return false }
        let scrollView = env.canvas.scrollView
        return other === scrollView.panGestureRecognizer || other === scrollView.pinchGestureRecognizer
    }
}
