import UIKit

/// Namespace for package-level information.
public enum ImageMarkupKit {
    public static let version = "0.2.0"
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

/// Titles of the navigation bar buttons and of the alert Cancel shows when there are unsaved changes, e.g. to
/// label the finishing button "Save" or to translate them. Start from `.english` and change what you need.
public struct MarkupNavigationTexts: Equatable, Sendable {
    /// The button that exports the image and finishes (top right).
    public var done: String
    /// The button that leaves without saving (top left).
    public var cancel: String
    /// Title of the discard-changes alert.
    public var discardTitle: String
    /// Message of the discard-changes alert.
    public var discardMessage: String
    /// The alert action that throws the changes away.
    public var discard: String
    /// The alert action that returns to the editor.
    public var keepEditing: String

    public init(done: String, cancel: String, discardTitle: String, discardMessage: String, discard: String, keepEditing: String) {
        self.done = done
        self.cancel = cancel
        self.discardTitle = discardTitle
        self.discardMessage = discardMessage
        self.discard = discard
        self.keepEditing = keepEditing
    }

    /// The built-in texts: "Done", "Cancel", "Discard changes?", …
    public static let english = MarkupNavigationTexts(
        done: Strings.done,
        cancel: Strings.cancel,
        discardTitle: Strings.discardTitle,
        discardMessage: Strings.discardMessage,
        discard: Strings.discard,
        keepEditing: Strings.keepEditing
    )
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
    /// Titles of the Done and Cancel buttons and of the discard-changes alert. English by default.
    public var navigationTexts: MarkupNavigationTexts

    public init(
        title: String? = nil,
        exportOptions: MarkupExportOptions = .default,
        packageDirectory: URL? = nil,
        styleDefaults: StyleDefaults = .standard,
        features: MarkupFeatures = .all,
        navigationTexts: MarkupNavigationTexts = .english
    ) {
        self.title = title
        self.exportOptions = exportOptions
        self.packageDirectory = packageDirectory
        self.styleDefaults = styleDefaults
        self.features = features
        self.navigationTexts = navigationTexts
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
