import UIKit
import UniformTypeIdentifiers

/// The editor's photos for one editing session.
/// Files handed in by the caller are only read; imported data (picker, camera) is copied into a session folder,
/// so cancelling an edit never touches a saved package.
@MainActor
public final class AssetStore {
    public private(set) var catalog: AssetCatalog
    /// Folder for files imported during this session.
    public let sessionDirectory: URL

    public init(catalog: AssetCatalog = AssetCatalog()) {
        self.catalog = catalog
        sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageMarkupKit", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    public func url(for assetID: String) -> URL? { catalog.url(for: assetID) }

    /// Registers a file the caller keeps alive for the whole session (not copied).
    @discardableResult
    public func register(fileAt url: URL) throws -> ImageSource {
        guard let metadata = ImagePipeline.metadata(at: url) else { throw AssetStoreError.unreadableImage(url) }
        let assetID = Self.makeAssetID(for: url)
        catalog[assetID] = url
        return ImageSource(assetID: assetID, pixelSize: metadata.pixelSize)
    }

    /// Adds an already-copied file (see `copyIntoSession`).
    func add(_ imported: ImportedAsset) -> ImageSource {
        catalog[imported.assetID] = imported.url
        return ImageSource(assetID: imported.assetID, pixelSize: imported.pixelSize)
    }

    /// Encodes an in-memory image (e.g. from the camera) as JPEG into the session folder.
    @discardableResult
    public func importImage(_ image: UIImage, compressionQuality: CGFloat = 0.9) throws -> ImageSource {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else { throw AssetStoreError.encodingFailed }
        let imported = try Self.write(data, fileExtension: "jpg", into: sessionDirectory)
        return add(imported)
    }

    /// Copies a file into the session folder. Callable from any thread (picker callbacks run in the background
    /// and their file is deleted as soon as the callback returns).
    nonisolated static func copyIntoSession(_ url: URL, directory: URL) throws -> ImportedAsset {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        let assetID = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(assetID)
        try FileManager.default.copyItem(at: url, to: destination)
        guard let metadata = ImagePipeline.metadata(at: destination) else { throw AssetStoreError.unreadableImage(url) }
        return ImportedAsset(assetID: assetID, url: destination, pixelSize: metadata.pixelSize)
    }

    nonisolated static func write(_ data: Data, fileExtension: String, into directory: URL) throws -> ImportedAsset {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let assetID = "\(UUID().uuidString).\(fileExtension)"
        let destination = directory.appendingPathComponent(assetID)
        try data.write(to: destination, options: .atomic)
        guard let metadata = ImagePipeline.metadata(at: destination) else { throw AssetStoreError.unreadableImage(destination) }
        return ImportedAsset(assetID: assetID, url: destination, pixelSize: metadata.pixelSize)
    }

    /// Deletes files imported during this session (not the caller's or a package's files).
    public func discardSessionFiles() {
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    private static func makeAssetID(for url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
        return "\(UUID().uuidString).\(ext)"
    }
}

/// A file copied into the session folder.
struct ImportedAsset: Sendable {
    var assetID: String
    var url: URL
    var pixelSize: CGSize
}

public enum AssetStoreError: Error {
    case unreadableImage(URL)
    case encodingFailed
}
