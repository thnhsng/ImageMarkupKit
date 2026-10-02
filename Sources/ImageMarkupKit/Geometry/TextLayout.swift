import UIKit

/// Measures and draws text items. The same functions are used on screen and in export.
enum TextLayout {
    private static let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    static func font(for spec: FontSpec) -> UIFont {
        let size = max(spec.size, 1)
        let weight: UIFont.Weight = spec.bold ? .bold : .regular
        var font: UIFont
        switch spec.family {
        case .system:
            font = .systemFont(ofSize: size, weight: weight)
        case .rounded:
            font = withDesign(.rounded, size: size, weight: weight)
        case .serif:
            font = withDesign(.serif, size: size, weight: weight)
        case .monospaced:
            font = withDesign(.monospaced, size: size, weight: weight)
        case .hiraginoSans:
            font = UIFont(name: spec.bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .hiraginoMincho:
            font = UIFont(name: spec.bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size) ?? .systemFont(ofSize: size, weight: weight)
        }
        if spec.italic {
            var traits = font.fontDescriptor.symbolicTraits
            traits.insert(.traitItalic)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: size)
            } else {
                // Families without an italic face (e.g. Hiragino) get a synthesized oblique.
                let oblique = font.fontDescriptor.withMatrix(CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0))
                font = UIFont(descriptor: oblique, size: size)
            }
        }
        return font
    }

    private static func withDesign(_ design: UIFontDescriptor.SystemDesign, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func attributes(for content: TextContent) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch content.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        return [
            .font: font(for: content.font),
            .foregroundColor: content.color.uiColor,
            .paragraphStyle: paragraph,
        ]
    }

    static func attributedString(for content: TextContent) -> NSAttributedString {
        NSAttributedString(string: content.text, attributes: attributes(for: content))
    }

    /// Box size for the content: auto width grows with the text, fixed width wraps.
    static func measuredSize(for content: TextContent) -> CGSize {
        let padding = max(content.padding, 0)
        // Empty text is measured as one line so a new box has a sensible height.
        let string = content.text.isEmpty ? " " : content.text
        let attributed = NSAttributedString(string: string, attributes: attributes(for: content))
        let maxWidth = content.fixedWidth.map { max($0 - 2 * padding, 1) } ?? .greatestFiniteMagnitude
        let bounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: options,
            context: nil
        )
        let width = content.fixedWidth ?? (ceil(bounds.width) + 1 + 2 * padding)
        let height = ceil(bounds.height) + 2 * padding
        return CGSize(width: max(width, 2 * padding + 4), height: height)
    }

    /// Draws the text into the current UIKit graphics context, in box space.
    static func draw(_ content: TextContent, size: CGSize) {
        guard !content.text.isEmpty else { return }
        let padding = max(content.padding, 0)
        let rect = CGRect(x: padding, y: padding, width: max(size.width - 2 * padding, 1), height: max(size.height - 2 * padding, 1))
        attributedString(for: content).draw(with: rect, options: options, context: nil)
    }

    /// Returns a copy whose box matches the measured size, keeping the top-left corner fixed in world space.
    static func fitted(_ content: TextContent) -> TextContent {
        var result = content
        let measured = measuredSize(for: content)
        let box = content.box
        guard abs(measured.width - box.frame.width) > 0.01 || abs(measured.height - box.frame.height) > 0.01 else {
            return content
        }
        let topLeftWorld = box.toWorld(box.frame.origin)
        let newCenter = topLeftWorld + CGPoint(x: measured.width / 2, y: measured.height / 2).rotated(by: box.rotation)
        result.box = Box(frame: CGRect(center: newCenter, size: measured), rotation: box.rotation)
        return result
    }
}
