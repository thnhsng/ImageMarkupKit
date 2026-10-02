import CoreGraphics
import Foundation

/// A markup document: either one photo with annotations, or a board holding several photos.
/// Coordinates are canvas units, independent of image resolution (see `MarkupDocument.imageLongEdge`).
public struct MarkupDocument: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    /// Image mode: the background photo is fitted so its long edge is this many canvas units.
    public static let imageLongEdge: CGFloat = 1024
    /// Board mode: photos are placed at this height.
    public static let boardImageHeight: CGFloat = 600

    public enum Kind: Equatable, Sendable {
        /// One locked background photo; the canvas is clipped to it.
        case image(backgroundItemID: UUID)
        /// Several photos on an open canvas.
        case board
    }

    public var schemaVersion: Int
    public var id: UUID
    public var kind: Kind
    public var backgroundColor: RGBAColor
    /// Z-ordered, bottom first. In board mode images always precede annotations.
    public var items: [MarkupItem]

    public init(id: UUID = UUID(), kind: Kind, backgroundColor: RGBAColor = .white, items: [MarkupItem] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.kind = kind
        self.backgroundColor = backgroundColor
        self.items = items
    }

    public var isBoard: Bool { kind == .board }

    public var backgroundItemID: UUID? {
        if case .image(let id) = kind { return id }
        return nil
    }

    public var backgroundItem: MarkupItem? { backgroundItemID.flatMap { item($0) } }

    public func index(of id: UUID) -> Int? { items.firstIndex { $0.id == id } }

    public func item(_ id: UUID) -> MarkupItem? { items.first { $0.id == id } }

    public func contains(_ id: UUID) -> Bool { items.contains { $0.id == id } }

    /// Mutates the item with the given id, if present.
    public mutating func update(_ id: UUID, _ body: (inout MarkupItem) -> Void) {
        guard let index = index(of: id) else { return }
        body(&items[index])
    }

    public var policy: DocumentPolicy {
        switch kind {
        case .image:
            return DocumentPolicy(canvasRect: backgroundItem?.box?.frame, clipsToCanvas: true, allowsAddingImages: false)
        case .board:
            return DocumentPolicy(canvasRect: nil, clipsToCanvas: false, allowsAddingImages: true)
        }
    }

    /// Keeps the z-bands intact: background first (image mode), then images (board), then annotations.
    /// Relative order inside each band is preserved.
    public mutating func normalizeZOrder() {
        let backgroundID = backgroundItemID
        var background: [MarkupItem] = []
        var images: [MarkupItem] = []
        var annotations: [MarkupItem] = []
        for item in items {
            if item.id == backgroundID {
                background.append(item)
            } else if item.isImage {
                images.append(item)
            } else {
                annotations.append(item)
            }
        }
        let normalized = background + images + annotations
        if normalized.map(\.id) != items.map(\.id) {
            items = normalized
        }
    }

    public var imageItems: [MarkupItem] { items.filter(\.isImage) }
}

public struct DocumentPolicy: Equatable, Sendable {
    /// Image mode: the background frame. Board mode: `nil` (open canvas).
    public var canvasRect: CGRect?
    public var clipsToCanvas: Bool
    public var allowsAddingImages: Bool
}

extension MarkupDocument: Codable {
    private enum CodingKeys: String, CodingKey { case schemaVersion, id, kind, backgroundItemID, backgroundColor, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw MarkupDecodingError.unsupportedSchemaVersion(schemaVersion)
        }
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let kindName = try c.decodeIfPresent(String.self, forKey: .kind) ?? "board"
        if kindName == "image", let backgroundID = try c.decodeIfPresent(UUID.self, forKey: .backgroundItemID) {
            kind = .image(backgroundItemID: backgroundID)
        } else {
            kind = .board
        }
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? .white

        // Lossy: an item with an unknown type (written by a newer version) is skipped, not fatal.
        var decoded: [MarkupItem] = []
        if var array = try? c.nestedUnkeyedContainer(forKey: .items) {
            while !array.isAtEnd {
                if let item = try? array.decode(MarkupItem.self) {
                    decoded.append(item)
                } else {
                    _ = try? array.decode(SkippedElement.self)
                }
            }
        }
        items = decoded
        if case .image(let backgroundID) = kind, !items.contains(where: { $0.id == backgroundID }) {
            kind = .board
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        switch kind {
        case .image(let backgroundID):
            try c.encode("image", forKey: .kind)
            try c.encode(backgroundID, forKey: .backgroundItemID)
        case .board:
            try c.encode("board", forKey: .kind)
        }
        try c.encode(backgroundColor, forKey: .backgroundColor)
        try c.encode(items, forKey: .items)
    }

    /// Consumes one array element without interpreting it.
    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

public extension MarkupDocument {
    /// Pretty, stable JSON (sorted keys) for storage and debugging.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> MarkupDocument {
        try JSONDecoder().decode(MarkupDocument.self, from: data)
    }
}
