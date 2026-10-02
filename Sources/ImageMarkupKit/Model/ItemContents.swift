import CoreGraphics
import Foundation

/// Position of a boxed item: an unrotated frame in canvas units plus a rotation (radians) about its center.
public struct Box: Equatable, Sendable {
    public var frame: CGRect
    public var rotation: CGFloat

    public init(frame: CGRect, rotation: CGFloat = 0) {
        self.frame = frame
        self.rotation = rotation
    }
}

extension Box: Codable {
    private enum CodingKeys: String, CodingKey { case frame, rotation }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decode(CGRect.self, forKey: .frame)
        rotation = try c.decodeIfPresent(CGFloat.self, forKey: .rotation) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(frame, forKey: .frame)
        try c.encode(rotation, forKey: .rotation)
    }
}

public enum ShapeKind: String, Codable, CaseIterable, Sendable {
    case rectangle, roundedRectangle, ellipse, triangle, diamond, star, pentagon, speechBubble, highlightBox
}

public enum ArrowHead: String, Codable, CaseIterable, Sendable {
    case none, arrow
}

public enum TextAlignmentOption: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case system, rounded, serif, monospaced, hiraginoSans, hiraginoMincho
}

public struct FontSpec: Equatable, Sendable {
    public var family: FontFamily
    public var size: CGFloat
    public var bold: Bool
    public var italic: Bool

    public init(family: FontFamily = .system, size: CGFloat = 36, bold: Bool = false, italic: Bool = false) {
        self.family = family
        self.size = size
        self.bold = bold
        self.italic = italic
    }
}

extension FontSpec: Codable {
    private enum CodingKeys: String, CodingKey { case family, size, bold, italic }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        family = (try? c.decodeIfPresent(FontFamily.self, forKey: .family)) ?? .system
        size = try c.decodeIfPresent(CGFloat.self, forKey: .size) ?? 36
        bold = try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(family, forKey: .family)
        try c.encode(size, forKey: .size)
        try c.encode(bold, forKey: .bold)
        try c.encode(italic, forKey: .italic)
    }
}

public struct ImageContent: Codable, Equatable, Sendable {
    /// Key into the document's asset catalog (the original file is stored untouched).
    public var assetID: String
    /// Pixel size after applying EXIF orientation.
    public var pixelSize: CGSize
    public var box: Box

    public init(assetID: String, pixelSize: CGSize, box: Box) {
        self.assetID = assetID
        self.pixelSize = pixelSize
        self.box = box
    }
}

public struct ShapeContent: Codable, Equatable, Sendable {
    public var kind: ShapeKind
    public var box: Box
    /// Circle / square: resizing keeps the aspect ratio.
    public var lockAspect: Bool

    public init(kind: ShapeKind, box: Box, lockAspect: Bool = false) {
        self.kind = kind
        self.box = box
        self.lockAspect = lockAspect
    }

    private enum CodingKeys: String, CodingKey { case kind, box, lockAspect }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(ShapeKind.self, forKey: .kind)
        box = try c.decode(Box.self, forKey: .box)
        lockAspect = try c.decodeIfPresent(Bool.self, forKey: .lockAspect) ?? false
    }
}

/// Text and notes. A note is a text item whose style has a fill and a border.
public struct TextContent: Equatable, Sendable {
    public var text: String
    public var font: FontSpec
    public var color: RGBAColor
    public var alignment: TextAlignmentOption
    /// `nil` = the box grows to fit the text; otherwise text wraps at this box width.
    public var fixedWidth: CGFloat?
    public var padding: CGFloat
    public var box: Box

    public init(
        text: String,
        font: FontSpec,
        color: RGBAColor,
        alignment: TextAlignmentOption = .left,
        fixedWidth: CGFloat? = nil,
        padding: CGFloat = 8,
        box: Box
    ) {
        self.text = text
        self.font = font
        self.color = color
        self.alignment = alignment
        self.fixedWidth = fixedWidth
        self.padding = padding
        self.box = box
    }
}

extension TextContent: Codable {
    private enum CodingKeys: String, CodingKey { case text, font, color, alignment, fixedWidth, padding, box }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        font = try c.decodeIfPresent(FontSpec.self, forKey: .font) ?? FontSpec()
        color = try c.decodeIfPresent(RGBAColor.self, forKey: .color) ?? .black
        alignment = (try? c.decodeIfPresent(TextAlignmentOption.self, forKey: .alignment)) ?? .left
        fixedWidth = try c.decodeIfPresent(CGFloat.self, forKey: .fixedWidth)
        padding = try c.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 8
        box = try c.decode(Box.self, forKey: .box)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(font, forKey: .font)
        try c.encode(color, forKey: .color)
        try c.encode(alignment, forKey: .alignment)
        try c.encodeIfPresent(fixedWidth, forKey: .fixedWidth)
        try c.encode(padding, forKey: .padding)
        try c.encode(box, forKey: .box)
    }
}

/// Freehand pen or highlighter stroke. Points are normalized (0…1) within `box.frame`,
/// so resizing the box scales the drawing.
public struct StrokeContent: Codable, Equatable, Sendable {
    public var points: [CGPoint]
    public var box: Box
    public var isHighlighter: Bool

    public init(points: [CGPoint], box: Box, isHighlighter: Bool = false) {
        self.points = points
        self.box = box
        self.isHighlighter = isHighlighter
    }

    private enum CodingKeys: String, CodingKey { case points, box, isHighlighter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode([CGPoint].self, forKey: .points)
        box = try c.decode(Box.self, forKey: .box)
        isHighlighter = try c.decodeIfPresent(Bool.self, forKey: .isHighlighter) ?? false
    }
}

/// Attaches a line endpoint to a point on another item.
public struct ConnectorBinding: Codable, Equatable, Sendable {
    public var itemID: UUID
    /// Normalized position (0…1) inside the target's unrotated frame.
    public var anchor: CGPoint

    public init(itemID: UUID, anchor: CGPoint) {
        self.itemID = itemID
        self.anchor = anchor
    }
}

public struct Endpoint: Codable, Equatable, Sendable {
    /// Canvas position. For bound endpoints this caches the last resolved position.
    public var point: CGPoint
    public var binding: ConnectorBinding?

    public init(point: CGPoint, binding: ConnectorBinding? = nil) {
        self.point = point
        self.binding = binding
    }
}

/// How a line runs from `start` to `end`.
public enum LineKind: String, Codable, CaseIterable, Sendable {
    /// Arrow / line: a straight segment (no waypoints).
    case straight
    /// Straight segments through the waypoints (Paint's polygon tool when closed).
    case polyline
    /// Smooth curve passing through the waypoints.
    case curve
}

public struct LineContent: Codable, Equatable, Sendable {
    public var start: Endpoint
    public var end: Endpoint
    public var startHead: ArrowHead
    public var endHead: ArrowHead
    public var kind: LineKind
    /// Canvas positions the line passes through between `start` and `end` (always free, never bound).
    /// Empty for straight lines.
    public var waypoints: [CGPoint]
    /// Polylines and curves only: the last point joins the first. Closed lines have no arrowheads,
    /// no endpoint bindings, and are filled with the style's fill color.
    public var isClosed: Bool

    public init(
        start: Endpoint,
        end: Endpoint,
        startHead: ArrowHead = .none,
        endHead: ArrowHead = .arrow,
        kind: LineKind = .straight,
        waypoints: [CGPoint] = [],
        isClosed: Bool = false
    ) {
        self.start = start
        self.end = end
        self.startHead = startHead
        self.endHead = endHead
        self.kind = kind
        self.waypoints = kind == .straight ? [] : waypoints
        self.isClosed = kind == .straight ? false : isClosed
    }

    /// Unresolved points in drawing order (bound endpoints use their cached position).
    public var points: [CGPoint] { [start.point] + waypoints + [end.point] }

    /// Polylines and curves have editable points; straight lines only have their two ends.
    public var hasEditablePoints: Bool { kind != .straight }

    private enum CodingKeys: String, CodingKey { case start, end, startHead, endHead, kind, waypoints, isClosed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Endpoint.self, forKey: .start)
        end = try c.decode(Endpoint.self, forKey: .end)
        startHead = (try? c.decodeIfPresent(ArrowHead.self, forKey: .startHead)) ?? ArrowHead.none
        endHead = (try? c.decodeIfPresent(ArrowHead.self, forKey: .endHead)) ?? .arrow
        kind = (try? c.decodeIfPresent(LineKind.self, forKey: .kind)) ?? .straight
        waypoints = kind == .straight ? [] : (try c.decodeIfPresent([CGPoint].self, forKey: .waypoints) ?? [])
        isClosed = kind == .straight ? false : (try c.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false)
    }

    /// Straight lines are written exactly as before polylines and curves existed.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(startHead, forKey: .startHead)
        try c.encode(endHead, forKey: .endHead)
        guard kind != .straight else { return }
        try c.encode(kind, forKey: .kind)
        try c.encode(waypoints, forKey: .waypoints)
        if isClosed { try c.encode(isClosed, forKey: .isClosed) }
    }
}
