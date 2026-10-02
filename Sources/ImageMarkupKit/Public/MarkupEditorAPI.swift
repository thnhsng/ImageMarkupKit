import UIKit

/// Namespace for package-level information.
public enum ImageMarkupKit {
    public static let version = "0.1.0"
}

/// How the flattened image is produced.
public struct MarkupExportOptions: Equatable, Sendable {
    public enum Format: Equatable, Sendable {
        case jpeg(quality: CGFloat)
        case png
    }

    public var format: Format
    /// Longest side of the output, in pixels.
    public var maxPixelDimension: CGFloat
    /// Total pixel budget of the output (memory guard for large boards).
    public var maxPixelCount: CGFloat
    /// Board mode: empty margin around the content, in canvas units.
    public var boardPadding: CGFloat
    /// Board mode: minimum pixels per canvas unit, so text stays sharp even when photos are small.
    public var minimumBoardScale: CGFloat

    public init(
        format: Format = .jpeg(quality: 0.85),
        maxPixelDimension: CGFloat = 8192,
        maxPixelCount: CGFloat = 40_000_000,
        boardPadding: CGFloat = 24,
        minimumBoardScale: CGFloat = 2
    ) {
        self.format = format
        self.maxPixelDimension = maxPixelDimension
        self.maxPixelCount = maxPixelCount
        self.boardPadding = boardPadding
        self.minimumBoardScale = minimumBoardScale
    }

    public static let `default` = MarkupExportOptions()
}

/// Editor options.
public struct MarkupEditorConfiguration {
    /// Navigation title; defaults to "Markup" / "Board".
    public var title: String?
    public var exportOptions: MarkupExportOptions
    /// When set, Done also saves an editable package (document.json + original photos + export) in this folder.
    public var packageDirectory: URL?
    public var styleDefaults: StyleDefaults
    /// Tools, style buttons, board functions and selection actions to offer (e.g. `try .fromBundle()` to read
    /// `MarkupFeatures.json` from the app). Everything by default.
    public var features: MarkupFeatures

    public init(
        title: String? = nil,
        exportOptions: MarkupExportOptions = .default,
        packageDirectory: URL? = nil,
        styleDefaults: StyleDefaults = .standard,
        features: MarkupFeatures = .all
    ) {
        self.title = title
        self.exportOptions = exportOptions
        self.packageDirectory = packageDirectory
        self.styleDefaults = styleDefaults
        self.features = features
    }

    public static var `default`: MarkupEditorConfiguration { MarkupEditorConfiguration() }
}

/// What the editor hands back when the user taps Done.
public struct MarkupResult {
    /// The flattened image.
    public let image: UIImage
    /// `image` encoded per `MarkupExportOptions.format` (JPEG by default).
    public let imageData: Data
    /// Editable data: reopen with `MarkupEditorViewController(document:assets:)` or `init(packageURL:)`.
    public let document: MarkupDocument
    public let assets: AssetCatalog
    /// The saved package, when `MarkupEditorConfiguration.packageDirectory` is set.
    public let packageURL: URL?
}

@MainActor
public protocol MarkupEditorDelegate: AnyObject {
    func markupEditor(_ editor: MarkupEditorViewController, didFinishWith result: MarkupResult)
    func markupEditorDidCancel(_ editor: MarkupEditorViewController)
    func markupEditor(_ editor: MarkupEditorViewController, didFailWith error: Error)
}

public extension MarkupEditorDelegate {
    func markupEditor(_ editor: MarkupEditorViewController, didFailWith error: Error) {}
}
