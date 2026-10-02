#if DEBUG
import UIKit

/// Scripted gestures for screenshot scenarios and manual QA. They drive the same interaction objects that
/// touches drive, so they exercise the real move/resize/rotate/draw code (everything except UIKit touch delivery).
public enum MarkupDebugGesture {
    /// Drag the item at `itemIndex` (document order) by `delta` canvas units.
    case drag(itemIndex: Int, by: CGPoint)
    /// Drag the resize handle at normalized (u, v) by `delta`.
    case resize(itemIndex: Int, u: CGFloat, v: CGFloat, by: CGPoint)
    /// Rotate with the rotation handle by `degrees` (clockwise).
    case rotate(itemIndex: Int, degrees: CGFloat)
    /// One-finger stroke with a tool through canvas `points`.
    case draw(MarkupTool, points: [CGPoint])
    /// Separate taps with a tool, one per point (e.g. the points of a polyline).
    case taps(MarkupTool, points: [CGPoint])
    /// Drag point `vertex` (0 = start) of the line at `itemIndex` by `delta`.
    case dragLineVertex(itemIndex: Int, vertex: Int, by: CGPoint)
    /// Drag a new point out of the "+" handle of `segment` of the polyline or curve at `itemIndex`.
    case insertLineVertex(itemIndex: Int, segment: Int, by: CGPoint)
}

public extension MarkupEditorViewController {
    func debugPerform(_ gesture: MarkupDebugGesture) {
        loadViewIfNeeded()
        let env = interactions.env
        switch gesture {
        case .drag(let index, let delta):
            guard let item = item(at: index) else { return }
            store.select([item.id])
            let start = anchorPoint(of: item)
            run(MoveInteraction(env: env, itemID: item.id), through: [start, start + delta * 0.5, start + delta])
        case .resize(let index, let u, let v, let delta):
            guard let item = item(at: index), let box = item.box else { return }
            store.select([item.id])
            let start = box.worldPoint(normalized: CGPoint(x: u, y: v))
            run(ResizeInteraction(env: env, itemID: item.id, u: u, v: v), through: [start, start + delta * 0.5, start + delta])
        case .rotate(let index, let degrees):
            guard let item = item(at: index), let box = item.box else { return }
            store.select([item.id])
            let start = box.worldPoint(normalized: CGPoint(x: 0.5, y: 0)) + CGPoint(x: 0, y: -40).rotated(by: box.rotation)
            let end = start.rotated(by: degrees * .pi / 180, around: box.center)
            run(RotateInteraction(env: env, itemID: item.id), through: [start, end])
        case .draw(let tool, let points):
            guard !points.isEmpty else { return }
            store.tool = tool
            guard let interaction = Self.makeInteraction(for: tool, env: env) else { return }
            run(interaction, through: points)
        case .taps(let tool, let points):
            store.tool = tool
            for point in points {
                guard let interaction = Self.makeInteraction(for: store.tool, env: env) else { return }
                run(interaction, through: [point])
            }
        case .dragLineVertex(let index, let vertex, let delta):
            guard let item = item(at: index), let line = item.lineContent else { return }
            let points = Bindings.resolvedPoints(line, in: store.document)
            guard points.indices.contains(vertex) else { return }
            store.select([item.id])
            let start = points[vertex]
            run(LineVertexInteraction(env: env, itemID: item.id, index: vertex), through: [start, start + delta * 0.5, start + delta])
        case .insertLineVertex(let index, let segment, let delta):
            guard let item = item(at: index), let line = item.lineContent else { return }
            let points = Bindings.resolvedPoints(line, in: store.document)
            let handles = LinePath.insertionPoints(points, kind: line.kind, closed: line.isClosed)
            guard handles.indices.contains(segment) else { return }
            store.select([item.id])
            let start = handles[segment]
            run(LineInsertInteraction(env: env, itemID: item.id, segment: segment), through: [start, start + delta * 0.5, start + delta])
        }
    }

    /// Starts editing the text item at `itemIndex`.
    func debugBeginEditingText(itemIndex: Int) {
        guard let item = item(at: itemIndex), item.isText else { return }
        textEditing.begin(itemID: item.id, isNew: false)
    }

    /// Opens a style panel by name: shapeStyle, borderColor, fillColor or textStyle.
    func debugPresentPanel(_ name: String) {
        let kinds: [String: (PanelKind, ToolbarCatalog.Item)] = [
            "shapeStyle": (.shapeStyle, .shapeStyle),
            "borderColor": (.borderColor, .borderColor),
            "fillColor": (.fillColor, .fillColor),
            "textStyle": (.textStyle, .textStyle),
        ]
        guard let (kind, item) = kinds[name], let button = toolbar.button(for: item) else { return }
        panels.present(kind, from: button)
    }

    /// Types into the text box being edited.
    func debugTypeText(_ text: String) {
        guard textEditing.isEditing else { return }
        textEditing.textView.insertText(text)
    }

    func debugArrange(_ arrangement: BoardLayout.Arrangement) {
        store.arrange(arrangement)
        canvasView.zoomToFit(animated: false)
    }

    /// Same as picking a fill color in the Fill panel (applies to the selection).
    func debugSetFill(_ color: RGBAColor?) {
        store.updateStyle { $0.fillColor = color }
    }

    /// Same as tapping Done.
    func debugDone() {
        doneTapped()
    }

    func debugZoomToFit() {
        canvasView.zoomToFit(animated: false)
    }

    private func item(at index: Int) -> MarkupItem? {
        store.document.items.indices.contains(index) ? store.document.items[index] : nil
    }

    private func anchorPoint(of item: MarkupItem) -> CGPoint {
        if let line = item.lineContent {
            let samples = LinePath.samples(of: line, in: store.document)
            return LinePath.point(atDistance: LinePath.length(of: samples) / 2, along: samples)
        }
        return item.box?.center ?? .zero
    }

    private func run(_ interaction: CanvasInteraction, through points: [CGPoint]) {
        interaction.begin(at: points[0])
        for point in points.dropFirst() {
            interaction.move(to: point, samples: [point], predicted: [])
        }
        interaction.end(at: points[points.count - 1])
    }
}
#endif
