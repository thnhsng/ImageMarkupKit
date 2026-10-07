import UIKit

/// What changed in the editor state.
struct EditorChange: OptionSet {
    let rawValue: Int
    static let document = EditorChange(rawValue: 1 << 0)
    static let selection = EditorChange(rawValue: 1 << 1)
    static let tool = EditorChange(rawValue: 1 << 2)
    static let undoState = EditorChange(rawValue: 1 << 3)
    static let defaults = EditorChange(rawValue: 1 << 4)
    static let all: EditorChange = [.document, .selection, .tool, .undoState, .defaults]
}

/// Editor state: the committed document, a transient preview during gestures, selection, tool, and
/// style defaults. Every commit is one undo step (whole-document snapshots; the model is value types).
@MainActor
final class EditorStore {
    private(set) var document: MarkupDocument
    /// Shown instead of `document` while a gesture is in progress.
    private(set) var preview: MarkupDocument?
    private(set) var selection: [UUID] = []
    var tool: MarkupTool = .select {
        didSet { if tool != oldValue { notify(.tool) } }
    }
    var defaults: StyleDefaults {
        didSet { if defaults != oldValue { notify(.defaults) } }
    }
    let assets: AssetStore
    /// The user-facing texts of the editor's locale; undo action names come from here.
    let strings: Strings
    let undoManager = UndoManager()
    var onChange: ((EditorChange) -> Void)?

    private var lastCoalescingKey: String?
    private var lastCommitTime: CFTimeInterval = 0

    init(document: MarkupDocument, assets: AssetStore, defaults: StyleDefaults = .standard, strings: Strings = .english) {
        var initial = document
        initial.normalizeZOrder()
        Bindings.refreshCachedEndpoints(in: &initial)
        self.document = initial
        self.assets = assets
        self.defaults = defaults
        self.strings = strings
        undoManager.levelsOfUndo = 100
        // One commit = one undo step, independent of run-loop grouping.
        undoManager.groupsByEvent = false
    }

    var displayed: MarkupDocument { preview ?? document }

    var hasChanges: Bool { undoManager.canUndo }

    // MARK: Preview & commit

    func setPreview(_ document: MarkupDocument?) {
        preview = document
        notify(.document)
    }

    /// Commits a new document as one undo step.
    /// - Parameter coalescingKey: consecutive commits with the same key (within 1.5 s) share one undo step,
    ///   e.g. dragging a slider.
    func commit(_ newDocument: MarkupDocument, actionName: String, coalescingKey: String? = nil, select newSelection: [UUID]? = nil) {
        var next = newDocument
        next.normalizeZOrder()
        Bindings.refreshCachedEndpoints(in: &next)
        preview = nil
        let resolvedSelection = (newSelection ?? selection).filter { next.contains($0) }
        guard next != document else {
            let selectionChanged = resolvedSelection != selection
            selection = resolvedSelection
            notify(selectionChanged ? [.document, .selection] : .document)
            return
        }
        let now = CACurrentMediaTime()
        let coalesce = coalescingKey != nil
            && coalescingKey == lastCoalescingKey
            && now - lastCommitTime < 1.5
            && undoManager.canUndo
        if !coalesce {
            registerUndo(restoring: document, selection: selection, actionName: actionName)
        }
        lastCoalescingKey = coalescingKey
        lastCommitTime = now
        document = next
        selection = resolvedSelection
        notify([.document, .selection, .undoState])
    }

    /// Applies `body` to a copy of the document and commits it.
    func perform(_ actionName: String, coalescingKey: String? = nil, select newSelection: [UUID]? = nil, _ body: (inout MarkupDocument) -> Void) {
        var copy = document
        body(&copy)
        commit(copy, actionName: actionName, coalescingKey: coalescingKey, select: newSelection)
    }

    private func registerUndo(restoring snapshot: MarkupDocument, selection snapshotSelection: [UUID], actionName: String) {
        undoManager.beginUndoGrouping()
        defer { undoManager.endUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { store in
            // Registering the current state while undoing makes it the redo step.
            store.registerUndo(restoring: store.document, selection: store.selection, actionName: actionName)
            store.document = snapshot
            store.selection = snapshotSelection.filter { snapshot.contains($0) }
            store.preview = nil
            store.lastCoalescingKey = nil
            store.notify([.document, .selection, .undoState])
        }
        undoManager.setActionName(actionName)
    }

    func undo() {
        guard undoManager.canUndo else { return }
        preview = nil
        undoManager.undo()
    }

    func redo() {
        guard undoManager.canRedo else { return }
        preview = nil
        undoManager.redo()
    }

    /// Ends the current coalescing run (e.g. when a slider is released).
    func endCoalescing() {
        lastCoalescingKey = nil
    }

    // MARK: Selection

    func select(_ ids: [UUID]) {
        let filtered = ids.filter { document.contains($0) && $0 != document.backgroundItemID }
        guard filtered != selection else { return }
        selection = filtered
        notify(.selection)
    }

    func clearSelection() { select([]) }

    var selectedItems: [MarkupItem] { selection.compactMap { displayed.item($0) } }

    var selectedItem: MarkupItem? { selection.count == 1 ? displayed.item(selection[0]) : nil }

    // MARK: Item operations

    func deleteSelection() {
        let ids = Set(selectedItems.filter { !$0.isLocked }.map(\.id))
        guard !ids.isEmpty else { return }
        perform(strings.actionDelete, select: []) { document in
            document.items.removeAll { ids.contains($0.id) }
            Bindings.detachReferences(to: ids, in: &document)
        }
    }

    func duplicateSelection() {
        let originals = selectedItems.filter { $0.id != document.backgroundItemID }
        guard !originals.isEmpty else { return }
        var copies: [MarkupItem] = []
        for original in originals {
            var copy = original
            copy.id = UUID()
            copy.isLocked = false
            let offset = CGPoint(x: 24, y: 24)
            switch copy.content {
            case .line(var line):
                // Copies of connectors are free lines.
                line.start = Endpoint(point: line.start.point + offset)
                line.end = Endpoint(point: line.end.point + offset)
                line.waypoints = line.waypoints.map { $0 + offset }
                copy.content = .line(line)
            default:
                if let box = copy.box { copy.box = box.offsetBy(offset) }
            }
            copies.append(copy)
        }
        perform(strings.actionDuplicate, select: copies.map(\.id)) { document in
            document.items.append(contentsOf: copies)
        }
    }

    enum ZOrderMove { case front, back }

    func moveSelection(_ move: ZOrderMove) {
        let ids = selection
        guard !ids.isEmpty else { return }
        perform(move == .front ? strings.actionBringToFront : strings.actionSendToBack) { document in
            let moving = document.items.filter { ids.contains($0.id) }
            document.items.removeAll { ids.contains($0.id) }
            switch move {
            case .front: document.items.append(contentsOf: moving)
            case .back: document.items.insert(contentsOf: moving, at: 0)
            }
            // `commit` normalizes the bands, so images stay below annotations and the photo stays at the bottom.
        }
    }

    func toggleLockOnSelection() {
        let ids = selection
        guard !ids.isEmpty else { return }
        let lock = !(selectedItems.allSatisfy(\.isLocked))
        perform(lock ? strings.actionLock : strings.actionUnlock) { document in
            for id in ids { document.update(id) { $0.isLocked = lock } }
        }
    }

    // MARK: Board

    /// Re-lays out the board's photos; annotations attached to a photo move with it. One undo step.
    func arrange(_ arrangement: BoardLayout.Arrangement) {
        guard document.isBoard else { return }
        let source = document
        // Current reading order: rows (by vertical band), then left to right.
        let band = BoardLayout.imageHeight + BoardLayout.gap
        let images = source.imageItems.sorted { a, b in
            let ca = a.box?.center ?? .zero, cb = b.box?.center ?? .zero
            let ra = (ca.y / band).rounded(), rb = (cb.y / band).rounded()
            return ra == rb ? ca.x < cb.x : ra < rb
        }
        guard !images.isEmpty else { return }
        let origin = images.compactMap { $0.box?.boundingRect }.reduce(CGRect.null) { $0.union($1) }.origin
        let sizes = images.map { $0.imageContent?.pixelSize ?? $0.box?.frame.size ?? CGSize(width: 4, height: 3) }
        let frames = BoardLayout.frames(for: sizes, arrangement: arrangement, origin: origin)
        var result = source
        for (image, frame) in zip(images, frames) {
            var moved = image
            moved.box = Box(frame: frame, rotation: 0)
            result.update(image.id) { $0 = moved }
            Attachments.carryChildren(of: image, to: moved, from: source, into: &result)
        }
        commit(result, actionName: strings.actionArrange)
    }

    /// Adds photos to the board after the existing ones and selects them.
    func addImages(_ sources: [ImageSource]) {
        guard document.isBoard, !sources.isEmpty else { return }
        var result = document
        let ids = result.appendImages(sources)
        commit(result, actionName: strings.actionAddImages, select: ids.count == 1 ? ids : [])
    }

    // MARK: Styles

    /// The style shown in the style panels: the selection's, or the active tool's defaults.
    var currentStyle: ItemStyle {
        if let item = selectedItem { return item.style }
        switch tool {
        case .pen: return defaults.pen
        case .highlighter: return defaults.highlighter
        case .shape(let kind, _): return kind == .highlightBox ? defaults.highlightBox : defaults.shape
        case .arrow, .polyline, .curve: return defaults.line
        case .text: return defaults.text
        case .note: return defaults.note
        case .select, .eraser: return defaults.shape
        }
    }

    /// Text attributes shown in the Text Style panel.
    var currentTextContent: TextContent {
        if let text = selectedItem?.textContent { return text }
        let isNote = tool == .note
        return TextContent(
            text: "",
            font: isNote ? defaults.noteFont : defaults.textFont,
            color: isNote ? defaults.noteTextColor : defaults.textColor,
            alignment: defaults.textAlignment,
            padding: isNote ? 16 : 8,
            box: Box(frame: .zero)
        )
    }

    var currentArrowHeads: (start: ArrowHead, end: ArrowHead) {
        if let line = selectedItem?.lineContent { return (line.startHead, line.endHead) }
        return tool == .polyline || tool == .curve
            ? (defaults.pathStartHead, defaults.pathEndHead)
            : (defaults.lineStartHead, defaults.lineEndHead)
    }

    /// Edits the style of the selection (undoable) and makes it the default for new items of that kind.
    /// With nothing selected, only the active tool's default changes.
    func updateStyle(coalescingKey: String? = nil, _ change: (inout ItemStyle) -> Void) {
        let items = selectedItems
        guard !items.isEmpty else {
            var style = currentStyle
            change(&style)
            setDefaultStyle(style, forTool: tool)
            return
        }
        perform(strings.actionStyle, coalescingKey: coalescingKey) { document in
            for item in items {
                document.update(item.id) { change(&$0.style) }
            }
        }
        if let updated = selectedItem { adoptDefaults(from: updated) }
    }

    /// Edits text attributes of selected text items (box re-fitted), or the text defaults.
    func updateText(coalescingKey: String? = nil, _ change: (inout TextContent) -> Void) {
        let items = selectedItems.filter(\.isText)
        guard !items.isEmpty else {
            var content = currentTextContent
            change(&content)
            if tool == .note {
                defaults.noteFont = content.font
                defaults.noteTextColor = content.color
            } else {
                defaults.textFont = content.font
                defaults.textColor = content.color
            }
            defaults.textAlignment = content.alignment
            return
        }
        perform(strings.actionStyle, coalescingKey: coalescingKey) { document in
            for item in items {
                document.update(item.id) { item in
                    guard case .text(var content) = item.content else { return }
                    change(&content)
                    item.content = .text(TextLayout.fitted(content))
                }
            }
        }
        if let updated = selectedItem { adoptDefaults(from: updated) }
    }

    /// Sets the arrowheads of the selected lines and the defaults of their kind (arrows, or polylines and curves).
    func updateArrowHeads(start: ArrowHead, end: ArrowHead) {
        let lines = selectedItems.filter(\.isLine)
        let isPath = lines.first?.lineContent.map(\.hasEditablePoints) ?? (tool == .polyline || tool == .curve)
        if isPath {
            defaults.pathStartHead = start
            defaults.pathEndHead = end
        } else {
            defaults.lineStartHead = start
            defaults.lineEndHead = end
        }
        guard !lines.isEmpty else { return }
        perform(strings.actionStyle) { document in
            for item in lines {
                document.update(item.id) { item in
                    guard case .line(var line) = item.content else { return }
                    line.startHead = start
                    line.endHead = end
                    item.content = .line(line)
                }
            }
        }
    }

    // MARK: Line points

    /// Removes point `index` (0 = start) of a polyline or curve. A line keeps at least two points; a closed line
    /// left with fewer than three opens.
    func removeLinePoint(_ index: Int, of itemID: UUID) {
        guard let item = document.item(itemID), !item.isLocked, var line = item.lineContent, line.hasEditablePoints else { return }
        var points = line.points
        guard points.count > 2, points.indices.contains(index) else { return }
        points.remove(at: index)
        // Removing an end promotes the next point, which is free.
        if index == 0 { line.start = Endpoint(point: points[0]) }
        if index == points.count { line.end = Endpoint(point: points[points.count - 1]) }
        line.waypoints = Array(points.dropFirst().dropLast())
        if points.count < 3 { line.isClosed = false }
        perform(strings.actionDeletePoint) { document in
            document.update(itemID) { $0.content = .line(line) }
        }
    }

    /// Joins (or separates) the last and first points of a polyline or curve. Closing drops endpoint bindings.
    func setLineClosed(_ closed: Bool, for itemID: UUID) {
        guard let item = document.item(itemID), !item.isLocked, var line = item.lineContent, line.hasEditablePoints else { return }
        guard line.isClosed != closed, !closed || line.points.count >= 3 else { return }
        line.isClosed = closed
        if closed {
            line.start.binding = nil
            line.end.binding = nil
        }
        perform(closed ? strings.actionCloseShape : strings.actionOpenShape) { document in
            document.update(itemID) { $0.content = .line(line) }
        }
    }

    private func setDefaultStyle(_ style: ItemStyle, forTool tool: MarkupTool) {
        switch tool {
        case .pen: defaults.pen = style
        case .highlighter: defaults.highlighter = style
        case .shape(let kind, _):
            if kind == .highlightBox { defaults.highlightBox = style } else { defaults.shape = style }
        case .arrow, .polyline, .curve: defaults.line = style
        case .text: defaults.text = style
        case .note: defaults.note = style
        case .select, .eraser: defaults.shape = style
        }
    }

    /// Preview behavior: the last styled item sets the look of the next one of its kind.
    private func adoptDefaults(from item: MarkupItem) {
        switch item.content {
        case .shape(let shape):
            if shape.kind == .highlightBox { defaults.highlightBox = item.style } else { defaults.shape = item.style }
        case .line: defaults.line = item.style
        case .stroke(let stroke):
            if stroke.isHighlighter { defaults.highlighter = item.style } else { defaults.pen = item.style }
        case .text(let text):
            if item.style.fillColor != nil {
                defaults.note = item.style
                defaults.noteFont = text.font
                defaults.noteTextColor = text.color
            } else {
                defaults.text = item.style
                defaults.textFont = text.font
                defaults.textColor = text.color
            }
            defaults.textAlignment = text.alignment
        case .image:
            break
        }
    }

    // MARK: Notifications

    private func notify(_ change: EditorChange) {
        onChange?(change)
    }
}
