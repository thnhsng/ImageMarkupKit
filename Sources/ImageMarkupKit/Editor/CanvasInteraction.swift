import UIKit

/// One gesture on the canvas (move an item, draw a stroke, drag out a shape…). Points are in canvas units.
/// Interactions show progress through `EditorStore.setPreview` or canvas preview layers, and commit once at the end.
@MainActor
protocol CanvasInteraction: AnyObject {
    func begin(at point: CGPoint)
    /// `samples` are coalesced touch positions since the last call (oldest first); `predicted` are
    /// predicted positions, only for drawing previews.
    func move(to point: CGPoint, samples: [CGPoint], predicted: [CGPoint])
    func end(at point: CGPoint)
    func cancel()
}

/// Shared services for interactions.
@MainActor
final class InteractionEnvironment {
    unowned let store: EditorStore
    unowned let canvas: CanvasView
    unowned let overlay: SelectionOverlayView
    /// Starts editing a text item in place (`isNew`: remove it if left empty).
    var beginTextEditing: ((UUID, _ isNew: Bool) -> Void)?
    /// Whether a text item is being edited, and how to finish that edit.
    var isEditingText: () -> Bool = { false }
    var endTextEditing: () -> Void = {}
    /// The polyline being drawn with the Polyline tool (it spans several touches).
    let polylineDraft = PolylineDraft()
    /// Point of the selected polyline or curve the user tapped (offers "Delete Point").
    var activeLineVertex: (itemID: UUID, index: Int)?

    init(store: EditorStore, canvas: CanvasView, overlay: SelectionOverlayView) {
        self.store = store
        self.canvas = canvas
        self.overlay = overlay
    }

    var zoom: CGFloat { max(canvas.zoomScale, 0.01) }
    /// Touch tolerance in canvas units (10 screen points).
    var tolerance: CGFloat { 10 / zoom }

    /// After creating an item, select it and return to Select (Preview behavior), unless the tool is sticky.
    func finishCreating(_ id: UUID, keepTool: Bool) {
        store.select([id])
        if !keepTool && !store.tool.staysActiveAfterUse {
            store.tool = .select
        }
    }

    /// Ends the polyline being drawn (`close`: joining its last point to the first). It stays selected and the
    /// editor returns to Select.
    func finishPolyline(close: Bool = false) {
        let id = polylineDraft.itemID
        polylineDraft.reset()
        guard let id, store.document.contains(id) else { return }
        if close { store.setLineClosed(true, for: id) }
        finishCreating(id, keepTool: false)
    }
}
