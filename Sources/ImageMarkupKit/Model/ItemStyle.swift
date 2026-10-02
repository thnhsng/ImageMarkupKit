import CoreGraphics
import Foundation

/// An sRGB color with alpha. Encoded as `"#RRGGBBAA"`.
public struct RGBAColor: Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    /// Components are clamped to 0…1 and quantized to 8 bits, so a color survives a JSON round trip unchanged.
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = Self.quantize(red)
        self.green = Self.quantize(green)
        self.blue = Self.quantize(blue)
        self.alpha = Self.quantize(alpha)
    }

    public init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else { return nil }
        let hasAlpha = string.count == 8
        let r = hasAlpha ? (value >> 24) & 0xFF : (value >> 16) & 0xFF
        let g = hasAlpha ? (value >> 16) & 0xFF : (value >> 8) & 0xFF
        let b = hasAlpha ? (value >> 8) & 0xFF : value & 0xFF
        let a = hasAlpha ? value & 0xFF : 0xFF
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public var hexString: String {
        func byte(_ v: CGFloat) -> Int { Int((Self.clamp(v) * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func clamp(_ v: CGFloat) -> CGFloat { min(max(v.isFinite ? v : 0, 0), 1) }

    private static func quantize(_ v: CGFloat) -> CGFloat { (clamp(v) * 255).rounded() / 255 }
}

extension RGBAColor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = RGBAColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color \(string)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

public extension RGBAColor {
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let red = RGBAColor(hex: "#FF3B30")!
    static let orange = RGBAColor(hex: "#FF9500")!
    static let yellow = RGBAColor(hex: "#FFCC00")!
    static let green = RGBAColor(hex: "#34C759")!
    static let teal = RGBAColor(hex: "#30B0C7")!
    static let blue = RGBAColor(hex: "#007AFF")!
    static let purple = RGBAColor(hex: "#AF52DE")!
    static let pink = RGBAColor(hex: "#FF2D55")!
    static let brown = RGBAColor(hex: "#A2845E")!
    static let gray = RGBAColor(hex: "#8E8E93")!
    static let darkGray = RGBAColor(hex: "#3A3A3C")!
    static let highlighterYellow = RGBAColor(hex: "#FFE600")!
    static let noteYellow = RGBAColor(hex: "#FFF3A6")!
    static let noteBorder = RGBAColor(hex: "#E0B300")!
    static let boardBackground = RGBAColor(hex: "#F2F2F7")!

    /// Palette offered by the color panels, in display order.
    static let palette: [RGBAColor] = [
        .black, .darkGray, .gray, .white,
        .red, .orange, .yellow, .green,
        .teal, .blue, .purple, .pink,
        .brown, .highlighterYellow, .noteYellow, RGBAColor(hex: "#B3E5FC")!,
    ]
}

public enum DashStyle: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted
}

/// Visual style shared by all item kinds. Kinds ignore the fields that do not apply to them.
public struct ItemStyle: Equatable, Sendable {
    /// Border / line / pen color. `nil` = no border.
    public var strokeColor: RGBAColor?
    /// Background color. `nil` = transparent.
    public var fillColor: RGBAColor?
    public var lineWidth: CGFloat
    public var dash: DashStyle
    /// Group opacity of the whole item (0…1).
    public var opacity: CGFloat
    public var cornerRadius: CGFloat
    public var shadow: Bool

    public init(
        strokeColor: RGBAColor? = .red,
        fillColor: RGBAColor? = nil,
        lineWidth: CGFloat = 6,
        dash: DashStyle = .solid,
        opacity: CGFloat = 1,
        cornerRadius: CGFloat = 0,
        shadow: Bool = false
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.dash = dash
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    /// Stroke width actually drawn (0 when there is no stroke color).
    var effectiveLineWidth: CGFloat { strokeColor == nil ? 0 : lineWidth }
}

extension ItemStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case strokeColor, fillColor, lineWidth, dash, opacity, cornerRadius, shadow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokeColor = try c.decodeIfPresent(RGBAColor.self, forKey: .strokeColor)
        fillColor = try c.decodeIfPresent(RGBAColor.self, forKey: .fillColor)
        lineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .lineWidth) ?? 6
        dash = (try? c.decodeIfPresent(DashStyle.self, forKey: .dash)) ?? .solid
        opacity = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? 1
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(strokeColor, forKey: .strokeColor)
        try c.encodeIfPresent(fillColor, forKey: .fillColor)
        try c.encode(lineWidth, forKey: .lineWidth)
        try c.encode(dash, forKey: .dash)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(shadow, forKey: .shadow)
    }
}

/// Styles used for newly created items, per tool. Editing the style of a selected item also updates these
/// (Preview behavior), so the next item looks like the last one the user styled.
public struct StyleDefaults: Equatable, Sendable {
    public var shape: ItemStyle
    public var highlightBox: ItemStyle
    public var line: ItemStyle
    public var lineStartHead: ArrowHead
    public var lineEndHead: ArrowHead
    /// Arrowheads of new polylines and curves (they share the `line` style).
    public var pathStartHead: ArrowHead
    public var pathEndHead: ArrowHead
    public var pen: ItemStyle
    public var highlighter: ItemStyle
    public var text: ItemStyle
    public var textFont: FontSpec
    public var textColor: RGBAColor
    public var note: ItemStyle
    public var noteFont: FontSpec
    public var noteTextColor: RGBAColor
    public var textAlignment: TextAlignmentOption

    public static let standard = StyleDefaults(
        shape: ItemStyle(strokeColor: .red, fillColor: nil, lineWidth: 6),
        highlightBox: ItemStyle(strokeColor: nil, fillColor: RGBAColor.highlighterYellow.withAlpha(0.45), lineWidth: 0, cornerRadius: 4),
        line: ItemStyle(strokeColor: .red, fillColor: nil, lineWidth: 6),
        lineStartHead: .none,
        lineEndHead: .arrow,
        pathStartHead: .none,
        pathEndHead: .none,
        pen: ItemStyle(strokeColor: .red, fillColor: nil, lineWidth: 6),
        highlighter: ItemStyle(strokeColor: .highlighterYellow, fillColor: nil, lineWidth: 24, opacity: 0.45),
        text: ItemStyle(strokeColor: nil, fillColor: nil, lineWidth: 2),
        textFont: FontSpec(family: .system, size: 36, bold: true),
        textColor: .red,
        note: ItemStyle(strokeColor: .noteBorder, fillColor: .noteYellow, lineWidth: 2, cornerRadius: 6, shadow: true),
        noteFont: FontSpec(family: .system, size: 28),
        noteTextColor: RGBAColor(hex: "#1C1C1E")!,
        textAlignment: .left
    )
}
