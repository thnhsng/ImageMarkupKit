import Foundation

/// Maps asset IDs used in a document to the original image files on disk.
public struct AssetCatalog: Equatable, Sendable {
    public var urls: [String: URL]

    public init(urls: [String: URL] = [:]) {
        self.urls = urls
    }

    public func url(for assetID: String) -> URL? { urls[assetID] }

    public subscript(assetID: String) -> URL? {
        get { urls[assetID] }
        set { urls[assetID] = newValue }
    }
}
