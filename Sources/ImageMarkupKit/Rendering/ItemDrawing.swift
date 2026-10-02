import UIKit

/// Core Graphics drawing of items, used by the export renderer.
/// Paths and text layout come from `PathFactory` / `TextLayout`, the same code the on-screen views use.
enum ItemDrawing {
    /// Draws `item` into `ctx`, whose CTM maps canvas units to output pixels (UIKit-flipped, top-left origin).
    /// `ctx` must be the current UIKit context (text and images draw through UIKit).
    /// - Parameter deviceScale: output pixels per canvas unit (shadows are specified in device space).
    static func draw(
        _ item: MarkupItem,
        in document: MarkupDocument,
        context ctx: CGContext,
        deviceScale: CGFloat,
        image: (ImageContent) -> CGImage?
    ) {
        let style = item.style
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if style.shadow {
            ctx.setShadow(
                offset: CGSize(width: 0, height: ShadowStyle.offsetY * deviceScale),
                blur: ShadowStyle.blur * deviceScale,
                color: UIColor.black.withAlphaComponent(ShadowStyle.opacity).cgColor
            )
        }
        let usesLayer = style.opacity < 0.999 || style.shadow
        if usesLayer {
            // Group opacity: overlapping parts of one item don't darken (matches CALayer opacity).
            ctx.setAlpha(min(max(style.opacity, 0), 1))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer { if usesLayer { ctx.endTransparencyLayer() } }

        switch item.content {
        case .image(let content):
            ctx.concatenate(content.box.boxToWorld)
            let rect = CGRect(origin: .zero, size: content.box.frame.size)
            if let cgImage = image(content) {
                UIImage(cgImage: cgImage).draw(in: rect)
            } else {
                ctx.setFillColor(UIColor.systemGray5.cgColor)
                ctx.fill(rect)
            }
            if let stroke = style.strokeColor, style.lineWidth > 0 {
                strokePath(CGPath(rect: rect, transform: nil), color: stroke, style: style, join: .miter, cap: .butt, in: ctx)
            }

        case .shape(let content):
            ctx.concatenate(content.box.boxToWorld)
            let path = PathFactory.shapePath(kind: content.kind, size: content.box.frame.size, cornerRadius: style.cornerRadius)
            fillAndStroke(path, style: style, join: PathFactory.lineJoin(for: content.kind), in: ctx)

        case .text(let content):
            ctx.concatenate(content.box.boxToWorld)
            let rect = CGRect(origin: .zero, size: content.box.frame.size)
            if style.fillColor != nil || style.strokeColor != nil {
                let path = CGPath(
                    roundedRect: rect,
                    cornerWidth: min(style.cornerRadius, rect.width / 2, rect.height / 2),
                    cornerHeight: min(style.cornerRadius, rect.width / 2, rect.height / 2),
                    transform: nil
                )
                fillAndStroke(path, style: style, join: .round, in: ctx)
            }
            TextLayout.draw(content, size: rect.size)

        case .stroke(let content):
            ctx.concatenate(content.box.boxToWorld)
            guard let color = style.strokeColor else { break }
            let path = PathFactory.smoothedPath(PathFactory.strokePoints(content))
            strokePath(path, color: color, style: style, join: .round, cap: .round, in: ctx)

        case .line(let content):
            let geometry = PathFactory.lineGeometry(content, in: document, lineWidth: style.lineWidth)
            if content.isClosed, let fill = style.fillColor {
                ctx.addPath(geometry.shaft)
                ctx.setFillColor(fill.cgColor)
                ctx.fillPath()
            }
            guard let color = style.strokeColor else { break }
            strokePath(geometry.shaft, color: color, style: style, join: .round, cap: .round, in: ctx)
            if let heads = geometry.heads {
                ctx.addPath(heads)
                ctx.setFillColor(color.cgColor)
                ctx.fillPath()
            }
        }
    }

    private static func fillAndStroke(_ path: CGPath, style: ItemStyle, join: CGLineJoin, in ctx: CGContext) {
        if let fill = style.fillColor {
            ctx.addPath(path)
            ctx.setFillColor(fill.cgColor)
            ctx.fillPath()
        }
        if let stroke = style.strokeColor, style.lineWidth > 0 {
            strokePath(path, color: stroke, style: style, join: join, cap: .butt, in: ctx)
        }
    }

    private static func strokePath(_ path: CGPath, color: RGBAColor, style: ItemStyle, join: CGLineJoin, cap: CGLineCap, in ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineJoin(join)
        ctx.setMiterLimit(10)
        ctx.setLineCap(PathFactory.lineCap(for: style.dash, default: cap))
        if let pattern = PathFactory.dashPattern(style.dash, lineWidth: style.lineWidth) {
            ctx.setLineDash(phase: 0, lengths: pattern)
        } else {
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.strokePath()
    }
}

/// Drop shadow used by notes (and any item with `style.shadow`), in canvas units.
enum ShadowStyle {
    static let offsetY: CGFloat = 3
    static let blur: CGFloat = 8
    static let opacity: CGFloat = 0.3
}
