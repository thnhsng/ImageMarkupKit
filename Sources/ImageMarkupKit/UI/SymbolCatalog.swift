import UIKit

/// Single entry point for SF Symbols, so availability can be audited in one place.
///
/// Every name passed to `sf(_:)` must exist on iOS 15.0 (SF Symbols 3 or older). Newer symbols go through
/// `sfGuarded(_:iOS:fallback:)`, which falls back at runtime. `UIImage(systemName:)` returns `nil` for names
/// the running OS does not know, so fallback chains need no `#available` checks.
enum SymbolCatalog {
    static func image(_ name: String, fallbacks: [String] = [], configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
        for candidate in [name] + fallbacks {
            if let image = UIImage(systemName: candidate, withConfiguration: configuration) {
                return image
            }
        }
        return nil
    }

    /// iOS 15-safe symbol with optional fallbacks.
    static func sf(_ name: String, _ fallbacks: String..., configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
        image(name, fallbacks: fallbacks, configuration: configuration)
    }

    /// Symbol that needs a newer OS than the deployment target (e.g. `eraser`, iOS 16).
    static func sfGuarded(_ name: String, iOS version: Int, fallback: String, configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
        image(name, fallbacks: [fallback], configuration: configuration)
    }
}
