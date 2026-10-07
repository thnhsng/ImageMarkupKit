import UIKit

/// Namespace for package-level information.
public enum ImageMarkupKit {
    public static let version = "0.3.0"
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

/// Language of the editor's built-in texts: tools, menus, panels, undo names, the header and the discard alert.
/// The raw values are the web package's locales (`"en"`, `"ja"`), and the texts are the same.
public enum MarkupLocale: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"
}

/// Titles of the navigation bar buttons and of the alert Cancel shows when there are unsaved changes, e.g. to
/// label the finishing button "Save". Start from `.english`, `.japanese` or `init(locale:)` and change what you need.
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

    /// The built-in texts of a locale.
    public init(locale: MarkupLocale) {
        let strings = Strings(locale: locale)
        self.init(
            done: strings.done,
            cancel: strings.cancel,
            discardTitle: strings.discardTitle,
            discardMessage: strings.discardMessage,
            discard: strings.discard,
            keepEditing: strings.keepEditing
        )
    }

    /// The built-in English texts: "Done", "Cancel", "Discard changes?", …
    public static let english = MarkupNavigationTexts(locale: .english)
    /// The built-in Japanese texts: 「完了」「キャンセル」「変更を破棄しますか？」…
    public static let japanese = MarkupNavigationTexts(locale: .japanese)
}

/// Editor options.
public struct MarkupEditorConfiguration {
    /// Navigation title; defaults to "Markup" / "Board" (in the locale's language).
    public var title: String?
    public var exportOptions: MarkupExportOptions
    /// When set, Done also saves an editable package (document.json + original photos + export) in this folder.
    public var packageDirectory: URL?
    public var styleDefaults: StyleDefaults
    /// Tools, style buttons, board functions and selection actions to offer (e.g. `try .fromBundle()` to read
    /// `MarkupFeatures.json` from the app). Everything by default.
    public var features: MarkupFeatures
    /// Language of the built-in texts. English by default.
    public var locale: MarkupLocale
    /// Titles of the Done and Cancel buttons and of the discard-changes alert: the locale's texts until set.
    public var navigationTexts: MarkupNavigationTexts {
        get { customNavigationTexts ?? MarkupNavigationTexts(locale: locale) }
        set { customNavigationTexts = newValue }
    }

    private var customNavigationTexts: MarkupNavigationTexts?

    public init(
        title: String? = nil,
        exportOptions: MarkupExportOptions = .default,
        packageDirectory: URL? = nil,
        styleDefaults: StyleDefaults = .standard,
        features: MarkupFeatures = .all,
        locale: MarkupLocale = .english,
        navigationTexts: MarkupNavigationTexts? = nil
    ) {
        self.title = title
        self.exportOptions = exportOptions
        self.packageDirectory = packageDirectory
        self.styleDefaults = styleDefaults
        self.features = features
        self.locale = locale
        self.customNavigationTexts = navigationTexts
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
