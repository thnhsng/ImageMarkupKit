import Foundation

/// Groups of editor features, as they appear in the toolbar and the selection action bar.
public enum MarkupFeatureGroup: String, CaseIterable, Sendable {
    /// Pen and highlighter.
    case draw
    /// The Shapes menu.
    case shapes
    /// The Arrow menu: arrow / line, polyline, curve.
    case lines
    /// Text and note.
    case text
    case eraser
    /// Style buttons: Shape Style, Border Color, Fill Color, Text Style.
    case style
    /// Board mode: Add Images (photo library, camera) and Arrange.
    case board
    /// Selection action bar.
    case actions

    public var features: [MarkupFeature] { MarkupFeature.allCases.filter { $0.group == self } }
}

/// One feature that can be turned off. Raw values are the names used in the JSON configuration.
public enum MarkupFeature: String, CaseIterable, Sendable {
    // draw
    case pen, highlighter
    // shapes
    case rectangle, roundedRectangle, oval, circle, square, triangle, diamond, star, pentagon, speechBubble, highlightBox
    // lines
    case arrow, polyline, curve
    // text
    case text, note
    // eraser
    case eraser
    // style
    case shapeStyle, borderColor, fillColor, textStyle
    // board
    case photoLibrary, camera, arrange
    // actions
    /// Editing existing text (the action and tapping a selected text item). New text is always typed in place.
    case editText
    case duplicate, bringToFront, sendToBack
    /// Lock. Unlock stays available for items that are already locked.
    case lock
    case delete

    public var group: MarkupFeatureGroup {
        switch self {
        case .pen, .highlighter: return .draw
        case .rectangle, .roundedRectangle, .oval, .circle, .square, .triangle, .diamond, .star, .pentagon, .speechBubble, .highlightBox:
            return .shapes
        case .arrow, .polyline, .curve: return .lines
        case .text, .note: return .text
        case .eraser: return .eraser
        case .shapeStyle, .borderColor, .fillColor, .textStyle: return .style
        case .photoLibrary, .camera, .arrange: return .board
        case .editText, .duplicate, .bringToFront, .sendToBack, .lock, .delete: return .actions
        }
    }

    /// The feature behind a tool (`nil` for Select, which is always available).
    public init?(tool: MarkupTool) {
        switch tool {
        case .select: return nil
        case .pen: self = .pen
        case .highlighter: self = .highlighter
        case .shape(let kind, let lockAspect): self = Self(shape: kind, lockAspect: lockAspect)
        case .arrow: self = .arrow
        case .polyline: self = .polyline
        case .curve: self = .curve
        case .text: self = .text
        case .note: self = .note
        case .eraser: self = .eraser
        }
    }

    init(shape kind: ShapeKind, lockAspect: Bool) {
        switch kind {
        case .rectangle: self = lockAspect ? .square : .rectangle
        case .ellipse: self = lockAspect ? .circle : .oval
        case .roundedRectangle: self = .roundedRectangle
        case .triangle: self = .triangle
        case .diamond: self = .diamond
        case .star: self = .star
        case .pentagon: self = .pentagon
        case .speechBubble: self = .speechBubble
        case .highlightBox: self = .highlightBox
        }
    }
}

/// Which tools, style buttons, board functions and selection actions the editor offers. Everything is on by
/// default; a feature is available when both it and its group are enabled. Select, undo/redo, zoom and the
/// polyline/curve point editing that comes with those tools are always available.
///
/// Usually loaded from a JSON file shipped with the app (see `init(contentsOf:)`):
///
///     {
///       "draw":    { "enabled": true, "items": { "pen": true, "highlighter": false } },
///       "shapes":  { "enabled": false },
///       "lines":   { "items": { "curve": false } },
///       "actions": { "items": { "lock": false } }
///     }
///
/// Missing groups and items are enabled. Unknown names are an error (they are usually typos); keys starting
/// with "_" are ignored and can hold comments.
public struct MarkupFeatures: Equatable, Sendable {
    public private(set) var disabledGroups: Set<MarkupFeatureGroup> = []
    public private(set) var disabledFeatures: Set<MarkupFeature> = []

    public init() {}

    /// Everything enabled.
    public static let all = MarkupFeatures()

    public func isEnabled(_ feature: MarkupFeature) -> Bool {
        !disabledGroups.contains(feature.group) && !disabledFeatures.contains(feature)
    }

    /// Whether any feature of the group is available.
    public func isEnabled(group: MarkupFeatureGroup) -> Bool {
        group.features.contains(where: isEnabled)
    }

    /// Whether the editor offers `tool` (Select always).
    public func allows(_ tool: MarkupTool) -> Bool {
        MarkupFeature(tool: tool).map(isEnabled) ?? true
    }

    public mutating func setEnabled(_ enabled: Bool, _ feature: MarkupFeature) {
        if enabled { disabledFeatures.remove(feature) } else { disabledFeatures.insert(feature) }
    }

    /// Turns a whole group on or off. Individually disabled features of the group stay disabled.
    public mutating func setEnabled(_ enabled: Bool, group: MarkupFeatureGroup) {
        if enabled { disabledGroups.remove(group) } else { disabledGroups.insert(group) }
    }
}

// MARK: - JSON

public enum MarkupFeaturesError: Error, Equatable, CustomStringConvertible {
    /// A group, item or key that does not exist, with its path (e.g. "shapes.items.hexagon").
    case unknownKey(String)
    /// A value of the wrong type: groups and "items" must be objects, "enabled" and items true or false.
    case invalidValue(String)

    public var description: String {
        switch self {
        case .unknownKey(let path): return "Unknown key \"\(path)\" in the markup features configuration."
        case .invalidValue(let path): return "\"\(path)\" in the markup features configuration must be \(path.hasSuffix(".items") || !path.contains(".") ? "an object" : "true or false")."
        }
    }
}

public extension MarkupFeatures {
    /// Reads a JSON configuration file.
    init(contentsOf url: URL) throws {
        try self.init(jsonData: Data(contentsOf: url))
    }

    init(jsonData: Data) throws {
        self = try JSONDecoder().decode(MarkupFeatures.self, from: jsonData)
    }

    /// The configuration in a bundle's JSON resource, or `.all` when the bundle has no such file.
    static func fromBundle(_ bundle: Bundle = .main, resource: String = "MarkupFeatures") throws -> MarkupFeatures {
        guard let url = bundle.url(forResource: resource, withExtension: "json") else { return .all }
        return try MarkupFeatures(contentsOf: url)
    }

    /// Every group and item with its current value: a complete template for a configuration file.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

extension MarkupFeatures: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let root = try decoder.container(keyedBy: Key.self)
        for groupKey in root.allKeys where !groupKey.stringValue.hasPrefix("_") {
            guard let group = MarkupFeatureGroup(rawValue: groupKey.stringValue) else {
                throw MarkupFeaturesError.unknownKey(groupKey.stringValue)
            }
            let settings = try object(in: root, forKey: groupKey, path: group.rawValue)
            for key in settings.allKeys where !key.stringValue.hasPrefix("_") {
                switch key.stringValue {
                case "enabled":
                    setEnabled(try bool(in: settings, forKey: key, path: "\(group.rawValue).enabled"), group: group)
                case "items":
                    let items = try object(in: settings, forKey: key, path: "\(group.rawValue).items")
                    for itemKey in items.allKeys where !itemKey.stringValue.hasPrefix("_") {
                        let path = "\(group.rawValue).items.\(itemKey.stringValue)"
                        guard let feature = MarkupFeature(rawValue: itemKey.stringValue), feature.group == group else {
                            throw MarkupFeaturesError.unknownKey(path)
                        }
                        setEnabled(try bool(in: items, forKey: itemKey, path: path), feature)
                    }
                default:
                    throw MarkupFeaturesError.unknownKey("\(group.rawValue).\(key.stringValue)")
                }
            }
        }
    }

    private func object(in container: KeyedDecodingContainer<Key>, forKey key: Key, path: String) throws -> KeyedDecodingContainer<Key> {
        do { return try container.nestedContainer(keyedBy: Key.self, forKey: key) } catch { throw MarkupFeaturesError.invalidValue(path) }
    }

    private func bool(in container: KeyedDecodingContainer<Key>, forKey key: Key, path: String) throws -> Bool {
        do { return try container.decode(Bool.self, forKey: key) } catch { throw MarkupFeaturesError.invalidValue(path) }
    }

    public func encode(to encoder: Encoder) throws {
        var root = encoder.container(keyedBy: Key.self)
        for group in MarkupFeatureGroup.allCases {
            var settings = root.nestedContainer(keyedBy: Key.self, forKey: Key(group.rawValue))
            try settings.encode(!disabledGroups.contains(group), forKey: Key("enabled"))
            var items = settings.nestedContainer(keyedBy: Key.self, forKey: Key("items"))
            for feature in group.features {
                try items.encode(!disabledFeatures.contains(feature), forKey: Key(feature.rawValue))
            }
        }
    }
}
