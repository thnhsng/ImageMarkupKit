import UIKit

/// Values item views need beyond the item itself.
struct ItemViewContext {
    var assetURL: (String) -> URL?
    /// Longest side, in pixels, of decoded display images.
    var displayImageMaxPixel: CGFloat
    /// Canvas zoom × screen scale; text re-rasterizes at this scale.
    var renderScale: CGFloat
}

/// A shape layer that never animates implicitly (sublayers of a view animate by default).
final class NoAnimationShapeLayer: CAShapeLayer {
    override func action(forKey event: String) -> CAAction? { NSNull() }
}

/// One view per item. Views are display-only: hit testing is done against the model.
class ItemView: UIView {
    let itemID: UUID

    init(itemID: UUID) {
        self.itemID = itemID
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func make(for item: MarkupItem) -> ItemView {
        switch item.content {
        case .image: return ImageItemView(itemID: item.id)
        case .shape: return ShapeItemView(itemID: item.id)
        case .text: return TextItemView(itemID: item.id)
        case .stroke: return StrokeItemView(itemID: item.id)
        case .line: return LineItemView(itemID: item.id)
        }
    }

    /// Whether this view can display `item` (the content kind did not change).
    func canDisplay(_ item: MarkupItem) -> Bool {
        switch (self, item.content) {
        case (is ImageItemView, .image), (is ShapeItemView, .shape), (is TextItemView, .text),
             (is StrokeItemView, .stroke), (is LineItemView, .line):
            return true
        default:
            return false
        }
    }

    func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {}

    /// Text views re-rasterize for the current zoom; others are vector or image backed.
    func updateRenderScale(_ scale: CGFloat) {}

    /// Positions the view like a box: bounds = frame size, rotated about the center.
    /// Uses bounds/center/transform (never `frame`, which is undefined for rotated views).
    func applyBox(_ box: Box) {
        let size = box.frame.size
        if bounds.size != size { bounds = CGRect(origin: .zero, size: size) }
        center = box.center
        transform = box.rotation == 0 ? .identity : CGAffineTransform(rotationAngle: box.rotation)
    }

    func applyCommonStyle(_ style: ItemStyle, shadowPath: CGPath? = nil) {
        alpha = min(max(style.opacity, 0), 1)
        if style.shadow {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = Float(ShadowStyle.opacity)
            layer.shadowRadius = ShadowStyle.blur / 2
            layer.shadowOffset = CGSize(width: 0, height: ShadowStyle.offsetY)
            layer.shadowPath = shadowPath
        } else {
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
    }

    static func configure(_ layer: CAShapeLayer, stroke: RGBAColor?, fill: RGBAColor?, style: ItemStyle, join: CGLineJoin, cap: CGLineCap) {
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = stroke == nil ? 0 : style.lineWidth
        layer.lineJoin = join == .miter ? .miter : .round
        layer.miterLimit = 10
        let effectiveCap = PathFactory.lineCap(for: style.dash, default: cap)
        switch effectiveCap {
        case .round: layer.lineCap = .round
        case .square: layer.lineCap = .square
        default: layer.lineCap = .butt
        }
        layer.lineDashPattern = PathFactory.dashPattern(style.dash, lineWidth: style.lineWidth)?.map { NSNumber(value: Double($0)) }
    }
}

final class ShapeItemView: ItemView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    override func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {
        guard case .shape(let content) = item.content else { return }
        applyBox(content.box)
        let path = PathFactory.shapePath(kind: content.kind, size: content.box.frame.size, cornerRadius: item.style.cornerRadius)
        shapeLayer.path = path
        Self.configure(shapeLayer, stroke: item.style.strokeColor, fill: item.style.fillColor, style: item.style,
                       join: PathFactory.lineJoin(for: content.kind), cap: .butt)
        applyCommonStyle(item.style)
    }
}

final class StrokeItemView: ItemView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shapeLayer: CAShapeLayer { layer as! CAShapeLayer }

    override func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {
        guard case .stroke(let content) = item.content else { return }
        applyBox(content.box)
        shapeLayer.path = PathFactory.smoothedPath(PathFactory.strokePoints(content))
        Self.configure(shapeLayer, stroke: item.style.strokeColor, fill: nil, style: item.style, join: .round, cap: .round)
        applyCommonStyle(item.style)
    }
}

final class LineItemView: ItemView {
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var shaftLayer: CAShapeLayer { layer as! CAShapeLayer }
    private let headsLayer = NoAnimationShapeLayer()

    override init(itemID: UUID) {
        super.init(itemID: itemID)
        layer.addSublayer(headsLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {
        guard case .line(let content) = item.content else { return }
        let lineWidth = item.style.lineWidth
        let geometry = PathFactory.lineGeometry(content, in: document, lineWidth: lineWidth)
        var bounds = geometry.shaft.boundingBoxOfPath
        if let heads = geometry.heads { bounds = bounds.union(heads.boundingBoxOfPath) }
        bounds = bounds.insetBy(dx: -lineWidth - 2, dy: -lineWidth - 2)

        transform = .identity
        frame = bounds
        var toLocal = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        shaftLayer.path = geometry.shaft.copy(using: &toLocal)
        Self.configure(shaftLayer, stroke: item.style.strokeColor, fill: content.isClosed ? item.style.fillColor : nil, style: item.style, join: .round, cap: .round)
        headsLayer.frame = layer.bounds
        headsLayer.path = geometry.heads?.copy(using: &toLocal)
        headsLayer.fillColor = item.style.strokeColor?.cgColor
        headsLayer.strokeColor = nil
        applyCommonStyle(item.style)
    }
}

final class TextItemView: ItemView {
    /// Background (note fill and border).
    override class var layerClass: AnyClass { CAShapeLayer.self }
    private var backgroundLayer: CAShapeLayer { layer as! CAShapeLayer }
    private let textView = TextDrawingView()

    override init(itemID: UUID) {
        super.init(itemID: itemID)
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Hidden while the text is being edited in the on-screen text view.
    var isTextHidden: Bool {
        get { textView.isHidden }
        set { textView.isHidden = newValue }
    }

    override func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {
        guard case .text(let content) = item.content else { return }
        applyBox(content.box)
        let rect = CGRect(origin: .zero, size: content.box.frame.size)
        let radius = min(item.style.cornerRadius, rect.width / 2, rect.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        backgroundLayer.path = path
        Self.configure(backgroundLayer, stroke: item.style.strokeColor, fill: item.style.fillColor, style: item.style, join: .round, cap: .butt)
        applyCommonStyle(item.style, shadowPath: item.style.fillColor != nil ? path : nil)
        textView.frame = bounds
        textView.content = content
        updateRenderScale(context.renderScale)
    }

    override func updateRenderScale(_ scale: CGFloat) {
        // Cap the backing store at ~16 MB.
        let area = max(bounds.width * bounds.height, 1)
        let cap = sqrt(4_000_000 / area)
        let target = min(max(scale, 0.5), max(cap, 0.5))
        if abs(textView.contentScaleFactor - target) > 0.01 {
            textView.contentScaleFactor = target
            textView.setNeedsDisplay()
        }
    }
}

/// Draws text with `TextLayout`, the same code the exporter uses.
final class TextDrawingView: UIView {
    var content: TextContent? {
        didSet { if content != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let content else { return }
        TextLayout.draw(content, size: bounds.size)
    }
}

final class ImageItemView: ItemView {
    private let imageView = UIImageView()
    private let borderLayer = NoAnimationShapeLayer()
    private var loadedKey: String?

    override init(itemID: UUID) {
        super.init(itemID: itemID)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.layer.minificationFilter = .trilinear
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        layer.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func update(item: MarkupItem, in document: MarkupDocument, context: ItemViewContext) {
        guard case .image(let content) = item.content else { return }
        applyBox(content.box)
        imageView.frame = bounds

        borderLayer.frame = bounds
        if let stroke = item.style.strokeColor, item.style.lineWidth > 0 {
            borderLayer.path = CGPath(rect: bounds, transform: nil)
            Self.configure(borderLayer, stroke: stroke, fill: nil, style: item.style, join: .miter, cap: .butt)
        } else {
            borderLayer.path = nil
        }
        applyCommonStyle(item.style)

        guard let url = context.assetURL(content.assetID) else { return }
        let maxPixel = min(context.displayImageMaxPixel, max(content.pixelSize.width, content.pixelSize.height))
        let key = "\(url.path)#\(Int(maxPixel))"
        guard key != loadedKey else { return }
        loadedKey = key
        if let cached = ImageCache.shared.cachedImage(for: url, maxPixelSize: maxPixel) {
            imageView.image = cached
            return
        }
        ImageCache.shared.loadImage(for: url, maxPixelSize: maxPixel) { [weak self] image in
            guard let self, self.loadedKey == key else { return }
            self.imageView.image = image
        }
    }

    var hasImage: Bool { imageView.image != nil }
}
