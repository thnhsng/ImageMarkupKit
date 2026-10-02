import UIKit

/// A view that ignores touches on itself but passes them to its subviews.
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// Hosts the zoomable canvas: a scroll view whose zoom view (`contentView`) uses canvas units as its
/// bounds coordinates, so `contentView.convert(_:from:)` yields canvas points directly.
final class CanvasView: UIView, UIScrollViewDelegate {
    let scrollView = CanvasScrollView()
    /// Zoom view. Its bounds are the canvas content bounds; item views are positioned in canvas units.
    let contentView = UIView()
    /// Holds transient previews (pen stroke in progress, shape being dragged out), above all items.
    let previewHost = UIView()
    /// Screen-space layer above the scroll view: selection handles, text editor. Handles keep a constant size.
    let overlayHost = PassthroughView()

    private(set) var document: MarkupDocument?
    private(set) var contentBounds: CGRect = .zero
    private var itemViews: [UUID: ItemView] = [:]
    private var renderedOrder: [UUID] = []
    private var needsInitialZoom = true
    private var lastLayoutSize: CGSize = .zero

    var assetURL: (String) -> URL? = { _ in nil }
    /// Items not drawn (e.g. text being edited, objects under the eraser).
    var hiddenItemIDs: Set<UUID> = [] {
        didSet { if hiddenItemIDs != oldValue { applyHiddenState() } }
    }
    /// Called whenever the visible region or zoom changes (the overlay re-syncs).
    var onViewportChange: (() -> Void)?
    /// Extra space at the edges of the visible area that stays clear of content when fitting (e.g. floating bars).
    var fitInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    /// Keyboard overlap, added to the bottom inset.
    var keyboardInset: CGFloat = 0 {
        didSet { if keyboardInset != oldValue { updateCentering() } }
    }

    static let boardExtent: CGFloat = 20000

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(scrollView)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)

        previewHost.isUserInteractionEnabled = false
        contentView.addSubview(previewHost)

        overlayHost.frame = bounds
        overlayHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(overlayHost)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Loading

    /// Configures the canvas for a document (bounds, clipping) and shows it.
    func load(_ document: MarkupDocument) {
        itemViews.values.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        renderedOrder.removeAll()
        self.document = nil

        let policy = document.policy
        if let canvas = policy.canvasRect, canvas.width > 0, canvas.height > 0 {
            contentBounds = canvas
            contentView.clipsToBounds = true
            backgroundColor = .secondarySystemBackground
        } else {
            let extent = Self.boardExtent
            contentBounds = CGRect(x: -extent / 2, y: -extent / 2, width: extent, height: extent)
            contentView.clipsToBounds = false
            backgroundColor = document.backgroundColor.uiColor
        }
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1
        scrollView.zoomScale = 1
        contentView.transform = .identity
        contentView.bounds = contentBounds
        contentView.frame = CGRect(origin: .zero, size: contentBounds.size)
        scrollView.contentSize = contentBounds.size
        // Preview layers draw in canvas units: align the host's own coordinates with the canvas.
        previewHost.frame = contentBounds
        previewHost.bounds = contentBounds

        apply(document)
        needsInitialZoom = true
        setNeedsLayout()
    }

    // MARK: Reconciliation

    /// Brings item views in line with `document`: creates, updates, removes and re-stacks views.
    func apply(_ document: MarkupDocument) {
        let previous = self.document
        self.document = document
        let context = itemViewContext(for: document)
        var seen = Set<UUID>()
        seen.reserveCapacity(document.items.count)

        for item in document.items {
            seen.insert(item.id)
            var view = itemViews[item.id]
            if let existing = view, !existing.canDisplay(item) {
                existing.removeFromSuperview()
                view = nil
            }
            if view == nil {
                let created = ItemView.make(for: item)
                contentView.addSubview(created)
                itemViews[item.id] = created
                created.update(item: item, in: document, context: context)
                created.isHidden = hiddenItemIDs.contains(item.id)
                continue
            }
            // Lines are cheap and may follow a bound target, so they always refresh.
            if item.isLine || previous?.item(item.id) != item {
                view?.update(item: item, in: document, context: context)
            }
        }

        for (id, view) in itemViews where !seen.contains(id) {
            view.removeFromSuperview()
            itemViews[id] = nil
        }

        let order = document.items.map(\.id)
        if order != renderedOrder {
            for id in order {
                if let view = itemViews[id] { contentView.bringSubviewToFront(view) }
            }
            contentView.bringSubviewToFront(previewHost)
            renderedOrder = order
        }
    }

    func itemView(for id: UUID) -> ItemView? { itemViews[id] }

    private func itemViewContext(for document: MarkupDocument) -> ItemViewContext {
        let imageCount = document.items.reduce(0) { $0 + ($1.isImage ? 1 : 0) }
        let maxPixel: CGFloat = document.isBoard ? (imageCount > 8 ? 1536 : 2048) : 4096
        return ItemViewContext(assetURL: assetURL, displayImageMaxPixel: maxPixel, renderScale: renderScale)
    }

    private func applyHiddenState() {
        for (id, view) in itemViews {
            view.isHidden = hiddenItemIDs.contains(id)
        }
    }

    // MARK: Coordinates

    var zoomScale: CGFloat { scrollView.zoomScale }

    var renderScale: CGFloat { scrollView.zoomScale * max(traitCollection.displayScale, 1) }

    /// Canvas point for a point in `view`'s coordinates.
    func canvasPoint(_ point: CGPoint, from view: UIView) -> CGPoint {
        contentView.convert(point, from: view)
    }

    /// Point in `view`'s coordinates for a canvas point.
    func point(fromCanvas point: CGPoint, to view: UIView) -> CGPoint {
        contentView.convert(point, to: view)
    }

    /// Visible canvas rect.
    var visibleCanvasRect: CGRect {
        contentView.convert(scrollView.bounds, from: scrollView)
    }

    // MARK: Zoom

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1, document != nil else { return }
        if needsInitialZoom {
            needsInitialZoom = false
            lastLayoutSize = bounds.size
            updateZoomLimits()
            zoomToFit(animated: false)
        } else if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            updateZoomLimits()
            updateCentering()
        }
    }

    /// The region "zoom to fit" shows: the photo in image mode, all items on a board.
    var fitRect: CGRect {
        guard let document else { return contentBounds }
        if document.policy.canvasRect != nil { return contentBounds }
        let bounds = ItemGeometry.visualBounds(of: document.items, in: document)
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            return CGRect(x: -400, y: -300, width: 800, height: 600)
        }
        return bounds.insetBy(dx: -40, dy: -40)
    }

    func fitZoomScale(for rect: CGRect) -> CGFloat {
        let available = scrollView.bounds.inset(by: fitInsets).size
        guard rect.width > 0, rect.height > 0, available.width > 0, available.height > 0 else { return 1 }
        return min(available.width / rect.width, available.height / rect.height)
    }

    private func updateZoomLimits() {
        let fit = fitZoomScale(for: fitRect)
        if document?.policy.canvasRect != nil {
            scrollView.minimumZoomScale = fit * 0.5
            scrollView.maximumZoomScale = fit * 8
        } else {
            scrollView.minimumZoomScale = min(0.05, fit * 0.5)
            scrollView.maximumZoomScale = max(4, fit)
        }
    }

    func zoomToFit(animated: Bool) {
        zoom(toCanvasRect: fitRect, animated: animated)
    }

    /// Shows `rect` (canvas units) centered and as large as fits.
    func zoom(toCanvasRect rect: CGRect, animated: Bool) {
        let scale = min(max(fitZoomScale(for: rect), scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let apply = {
            self.scrollView.zoomScale = scale
            self.updateCentering()
            self.center(onCanvasPoint: CGPoint(x: rect.midX, y: rect.midY))
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut], animations: apply) { _ in
                self.didFinishZooming()
            }
        } else {
            apply()
            didFinishZooming()
        }
    }

    /// Scrolls so `point` is in the middle of the visible area (clamped to the scrollable range).
    func center(onCanvasPoint point: CGPoint) {
        let zoom = scrollView.zoomScale
        let target = CGPoint(x: (point.x - contentBounds.minX) * zoom, y: (point.y - contentBounds.minY) * zoom)
        let size = scrollView.bounds.size
        let inset = scrollView.contentInset
        var offset = CGPoint(x: target.x - size.width / 2, y: target.y - (size.height - keyboardInset) / 2)
        offset.x = min(max(offset.x, -inset.left), max(scrollView.contentSize.width - size.width + inset.right, -inset.left))
        offset.y = min(max(offset.y, -inset.top), max(scrollView.contentSize.height - size.height + inset.bottom, -inset.top))
        scrollView.contentOffset = offset
    }

    /// Keeps content smaller than the viewport centered.
    func updateCentering() {
        let viewport = scrollView.bounds.size
        let content = scrollView.contentSize
        let availableHeight = viewport.height - keyboardInset
        let x = max((viewport.width - content.width) / 2, 0)
        let y = max((availableHeight - content.height) / 2, 0)
        let insets = UIEdgeInsets(top: y, left: x, bottom: y + keyboardInset, right: x)
        if scrollView.contentInset != insets {
            scrollView.contentInset = insets
        }
    }

    private func didFinishZooming() {
        let scale = renderScale
        for view in itemViews.values { view.updateRenderScale(scale) }
        onViewportChange?()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateCentering()
        onViewportChange?()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        onViewportChange?()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        didFinishZooming()
    }
}
