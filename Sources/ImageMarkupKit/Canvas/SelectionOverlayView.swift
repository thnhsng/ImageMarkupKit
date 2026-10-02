import UIKit

/// Selection chrome drawn in screen space (above the zoomed canvas), so handles keep a constant size.
/// Only handles and the action bar take touches; everything else passes through to the canvas.
final class SelectionOverlayView: UIView {
    struct Handle {
        let kind: HandleKind
        /// Overlay coordinates.
        let point: CGPoint
        var touchRadius: CGFloat = SelectionOverlayView.touchRadius
    }

    static let handleRadius: CGFloat = 6
    static let touchRadius: CGFloat = 22
    static let rotationKnobOffset: CGFloat = 28
    /// "+" handles are smaller and grab less, so the line around them can still be dragged.
    static let insertHandleRadius: CGFloat = 5
    static let insertTouchRadius: CGFloat = 14
    /// Segments shorter than this on screen get no "+" handle (it would crowd the point handles).
    static let minimumInsertSegment: CGFloat = 44

    let actionBar = SelectionActionBar()
    private(set) var handles: [Handle] = []
    /// Hides the action bar while a gesture is in progress.
    var isInteracting = false {
        didSet { if isInteracting != oldValue { setNeedsLayout() } }
    }

    private let outlineLayer = NoAnimationShapeLayer()
    private let rotationLineLayer = NoAnimationShapeLayer()
    private let handlesLayer = NoAnimationShapeLayer()
    private let boundHandlesLayer = NoAnimationShapeLayer()
    private let activeHandleLayer = NoAnimationShapeLayer()
    private let insertHandlesLayer = NoAnimationShapeLayer()
    private let insertPlusLayer = NoAnimationShapeLayer()
    private let targetLayer = NoAnimationShapeLayer()
    private var selectionScreenBounds: CGRect = .null
    /// While a polyline is drawn the bar sits at the bottom, away from where the next point goes.
    private var pinsActionBarToBottom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false

        targetLayer.strokeColor = UIColor.systemGreen.cgColor
        targetLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.12).cgColor
        targetLayer.lineWidth = 3
        layer.addSublayer(targetLayer)

        outlineLayer.strokeColor = UIColor.systemBlue.cgColor
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 1.5
        layer.addSublayer(outlineLayer)

        rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLineLayer.lineWidth = 1.5
        layer.addSublayer(rotationLineLayer)

        insertHandlesLayer.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        insertHandlesLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.8).cgColor
        insertHandlesLayer.lineWidth = 1
        layer.addSublayer(insertHandlesLayer)

        insertPlusLayer.fillColor = nil
        insertPlusLayer.strokeColor = UIColor.systemBlue.cgColor
        insertPlusLayer.lineWidth = 1.5
        insertPlusLayer.lineCap = .round
        layer.addSublayer(insertPlusLayer)

        handlesLayer.fillColor = UIColor.white.cgColor
        handlesLayer.strokeColor = UIColor.systemBlue.cgColor
        handlesLayer.lineWidth = 1.5
        layer.addSublayer(handlesLayer)

        boundHandlesLayer.fillColor = UIColor.systemGreen.cgColor
        boundHandlesLayer.strokeColor = UIColor.white.cgColor
        boundHandlesLayer.lineWidth = 1.5
        layer.addSublayer(boundHandlesLayer)

        activeHandleLayer.fillColor = UIColor.systemBlue.cgColor
        activeHandleLayer.strokeColor = UIColor.white.cgColor
        activeHandleLayer.lineWidth = 2
        layer.addSublayer(activeHandleLayer)

        actionBar.isHidden = true
        addSubview(actionBar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Updating

    /// Shows selection chrome for `item` (or nothing). Handle positions come from the displayed document.
    /// - Parameters:
    ///   - activeVertex: point of a polyline or curve the user tapped (drawn filled).
    ///   - isDrawing: `item` is a polyline being drawn: no "+" handles, action bar pinned to the bottom.
    func update(
        item: MarkupItem?,
        in document: MarkupDocument,
        canvas: CanvasView,
        actions: [SelectionActionBar.Action],
        activeVertex: Int? = nil,
        isDrawing: Bool = false
    ) {
        handles = []
        selectionScreenBounds = .null
        pinsActionBarToBottom = isDrawing
        guard let item else {
            outlineLayer.path = nil
            rotationLineLayer.path = nil
            handlesLayer.path = nil
            boundHandlesLayer.path = nil
            activeHandleLayer.path = nil
            insertHandlesLayer.path = nil
            insertPlusLayer.path = nil
            actionBar.isHidden = true
            return
        }
        let toScreen = { (p: CGPoint) in canvas.point(fromCanvas: p, to: self) }

        let outline = CGMutablePath()
        let rotation = CGMutablePath()
        let dots = CGMutablePath()
        let boundDots = CGMutablePath()
        let activeDots = CGMutablePath()
        let insertDots = CGMutablePath()
        let insertPluses = CGMutablePath()

        switch item.content {
        case .line(let line):
            let points = Bindings.resolvedPoints(line, in: document)
            let screenPoints = points.map(toScreen)
            let segments = LinePath.segments(points, kind: line.kind, closed: line.isClosed)
            // Curves can swing outside their points.
            selectionScreenBounds = CGRect.bounding(segments.flatMap { $0 }.map(toScreen) + screenPoints)
            guard !item.isLocked else { break }
            let last = screenPoints.count - 1
            for (index, point) in screenPoints.enumerated() {
                handles.append(Handle(kind: .lineVertex(index), point: point))
                let isBound = (index == 0 && line.start.binding != nil) || (index == last && line.end.binding != nil)
                addDot(at: point, to: index == activeVertex ? activeDots : (isBound ? boundDots : dots))
            }
            guard line.hasEditablePoints, !isDrawing else { break }
            for (index, segment) in segments.enumerated() {
                let length = LinePath.length(of: segment)
                guard length * canvas.zoomScale >= Self.minimumInsertSegment else { continue }
                let point = toScreen(LinePath.point(atDistance: length / 2, along: segment))
                handles.append(Handle(kind: .lineInsert(index), point: point, touchRadius: Self.insertTouchRadius))
                addInsertHandle(at: point, circle: insertDots, plus: insertPluses)
            }
        default:
            guard let box = item.box else { break }
            let corners = box.corners.map(toScreen)
            outline.addLines(between: corners)
            outline.closeSubpath()
            selectionScreenBounds = CGRect.bounding(corners)
            guard !item.isLocked else { break }

            // Fewer handles on items that are small on screen, so they stay individually grabbable.
            let screenSize = CGSize(width: box.frame.width * canvas.zoomScale, height: box.frame.height * canvas.zoomScale)
            let resizeHandles: [HandleKind]
            if item.isText {
                resizeHandles = [.resize(u: 0, v: 0.5), .resize(u: 1, v: 0.5)]
            } else if min(screenSize.width, screenSize.height) < 36 {
                resizeHandles = [.resize(u: 1, v: 1)]
            } else if min(screenSize.width, screenSize.height) < 72 {
                resizeHandles = [.resize(u: 0, v: 0), .resize(u: 1, v: 0), .resize(u: 1, v: 1), .resize(u: 0, v: 1)]
            } else {
                resizeHandles = HandleKind.allResize
            }
            for kind in resizeHandles {
                guard case .resize(let u, let v) = kind else { continue }
                let point = toScreen(box.worldPoint(normalized: CGPoint(x: u, y: v)))
                handles.append(Handle(kind: kind, point: point))
                addDot(at: point, to: dots)
            }
            // Rotation knob above the top edge, in the box's rotated "up" direction.
            let top = toScreen(box.worldPoint(normalized: CGPoint(x: 0.5, y: 0)))
            let up = CGPoint(x: 0, y: -1).rotated(by: box.rotation)
            let knob = top + up * Self.rotationKnobOffset
            rotation.move(to: top)
            rotation.addLine(to: knob)
            handles.append(Handle(kind: .rotate, point: knob))
            addDot(at: knob, to: dots)
            selectionScreenBounds = selectionScreenBounds.union(CGRect(origin: knob, size: .zero))
        }

        outlineLayer.path = outline
        outlineLayer.strokeColor = (item.isLocked ? UIColor.systemGray : UIColor.systemBlue).cgColor
        rotationLineLayer.path = rotation
        handlesLayer.path = dots
        boundHandlesLayer.path = boundDots
        activeHandleLayer.path = activeDots
        insertHandlesLayer.path = insertDots
        insertPlusLayer.path = insertPluses
        actionBar.configure(actions: actions)
        setNeedsLayout()
    }

    /// Highlights the item a connector endpoint will attach to.
    func showBindTarget(_ item: MarkupItem?, canvas: CanvasView) {
        guard let box = item?.box else {
            targetLayer.path = nil
            return
        }
        let corners = box.corners.map { canvas.point(fromCanvas: $0, to: self) }
        let path = CGMutablePath()
        path.addLines(between: corners)
        path.closeSubpath()
        targetLayer.path = path
    }

    private func addDot(at point: CGPoint, to path: CGMutablePath) {
        let r = Self.handleRadius
        path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
    }

    private func addInsertHandle(at point: CGPoint, circle: CGMutablePath, plus: CGMutablePath) {
        let r = Self.insertHandleRadius
        circle.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r))
        let arm = r * 0.55
        plus.move(to: CGPoint(x: point.x - arm, y: point.y))
        plus.addLine(to: CGPoint(x: point.x + arm, y: point.y))
        plus.move(to: CGPoint(x: point.x, y: point.y - arm))
        plus.addLine(to: CGPoint(x: point.x, y: point.y + arm))
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !selectionScreenBounds.isNull, !isInteracting, !actionBar.actions.isEmpty else {
            actionBar.isHidden = true
            return
        }
        let size = actionBar.bounds.size
        let margin: CGFloat = 8
        if pinsActionBarToBottom {
            let origin = CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - safeAreaInsets.bottom - size.height - 12)
            actionBar.frame = CGRect(origin: origin, size: size)
            actionBar.isHidden = false
            return
        }
        var y = selectionScreenBounds.minY - size.height - 14
        if y < safeAreaInsets.top + margin {
            y = selectionScreenBounds.maxY + 14
        }
        y = min(max(y, safeAreaInsets.top + margin), bounds.height - safeAreaInsets.bottom - size.height - margin)
        var x = selectionScreenBounds.midX - size.width / 2
        x = min(max(x, margin), bounds.width - size.width - margin)
        actionBar.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        actionBar.isHidden = !bounds.intersects(selectionScreenBounds.insetBy(dx: -40, dy: -40))
    }

    // MARK: Touches

    /// The handle under `point` (overlay coordinates), nearest first.
    func handle(at point: CGPoint) -> HandleKind? {
        handles
            .map { ($0, $0.point.distance(to: point)) }
            .filter { $0.1 <= $0.0.touchRadius }
            .min { $0.1 < $1.1 }?
            .0.kind
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !actionBar.isHidden, actionBar.frame.contains(point) { return true }
        return handle(at: point) != nil
    }
}
