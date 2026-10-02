import CoreGraphics
import Foundation

public enum ItemContent: Equatable, Sendable {
    case image(ImageContent)
    case shape(ShapeContent)
    case text(TextContent)
    case stroke(StrokeContent)
    case line(LineContent)

    /// Discriminator written to JSON as `"type"`.
    public var typeName: String {
        switch self {
        case .image: return "image"
        case .shape: return "shape"
        case .text: return "text"
        case .stroke: return "stroke"
        case .line: return "line"
        }
    }
}

public enum MarkupDecodingError: Error, Equatable {
    case unknownItemType(String)
    case unsupportedSchemaVersion(Int)
}

/// One object on the canvas. Array order in `MarkupDocument.items` is the z-order (last = top).
public struct MarkupItem: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var content: ItemContent
    public var style: ItemStyle
    /// Locked items can be selected (to unlock) but not moved, resized or erased.
    public var isLocked: Bool
    /// Board mode: the image this annotation is attached to; it follows that image when it moves.
    public var parentID: UUID?

    public init(id: UUID = UUID(), content: ItemContent, style: ItemStyle, isLocked: Bool = false, parentID: UUID? = nil) {
        self.id = id
        self.content = content
        self.style = style
        self.isLocked = isLocked
        self.parentID = parentID
    }

    /// The item's box. `nil` for lines, which are positioned by their endpoints.
    public var box: Box? {
        get {
            switch content {
            case .image(let c): return c.box
            case .shape(let c): return c.box
            case .text(let c): return c.box
            case .stroke(let c): return c.box
            case .line: return nil
            }
        }
        set {
            guard let newValue else { return }
            switch content {
            case .image(var c): c.box = newValue; content = .image(c)
            case .shape(var c): c.box = newValue; content = .shape(c)
            case .text(var c): c.box = newValue; content = .text(c)
            case .stroke(var c): c.box = newValue; content = .stroke(c)
            case .line: break
            }
        }
    }

    public var isImage: Bool { if case .image = content { return true } else { return false } }
    public var isLine: Bool { if case .line = content { return true } else { return false } }
    public var isText: Bool { if case .text = content { return true } else { return false } }
    public var isStroke: Bool { if case .stroke = content { return true } else { return false } }

    public var imageContent: ImageContent? { if case .image(let c) = content { return c } else { return nil } }
    public var shapeContent: ShapeContent? { if case .shape(let c) = content { return c } else { return nil } }
    public var textContent: TextContent? { if case .text(let c) = content { return c } else { return nil } }
    public var strokeContent: StrokeContent? { if case .stroke(let c) = content { return c } else { return nil } }
    public var lineContent: LineContent? { if case .line(let c) = content { return c } else { return nil } }

    /// Whether resizing must keep the width/height ratio.
    var locksAspectRatio: Bool {
        switch content {
        case .image: return true
        case .shape(let c): return c.lockAspect
        default: return false
        }
    }
}

extension MarkupItem: Codable {
    private enum CodingKeys: String, CodingKey { case id, type, content, style, isLocked, parentID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "image": content = .image(try c.decode(ImageContent.self, forKey: .content))
        case "shape": content = .shape(try c.decode(ShapeContent.self, forKey: .content))
        case "text": content = .text(try c.decode(TextContent.self, forKey: .content))
        case "stroke": content = .stroke(try c.decode(StrokeContent.self, forKey: .content))
        case "line": content = .line(try c.decode(LineContent.self, forKey: .content))
        default: throw MarkupDecodingError.unknownItemType(type)
        }
        style = try c.decodeIfPresent(ItemStyle.self, forKey: .style) ?? ItemStyle()
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(content.typeName, forKey: .type)
        switch content {
        case .image(let v): try c.encode(v, forKey: .content)
        case .shape(let v): try c.encode(v, forKey: .content)
        case .text(let v): try c.encode(v, forKey: .content)
        case .stroke(let v): try c.encode(v, forKey: .content)
        case .line(let v): try c.encode(v, forKey: .content)
        }
        try c.encode(style, forKey: .style)
        if isLocked { try c.encode(isLocked, forKey: .isLocked) }
        try c.encodeIfPresent(parentID, forKey: .parentID)
    }
}
